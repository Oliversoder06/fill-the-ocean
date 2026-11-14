-- The one module that talks to Roblox's AnalyticsService, for both places (docs/analytics.md). Each
-- place's server/Telemetry tells it the moments; this checks every name against common/Analytics,
-- spends the rate budget, keeps each player's session record (common/AnalyticsRecord) and writes it
-- once as they leave, with the one-time funnel steps sent (PlayerData.saveFunnels).
-- Analytics never breaks the game: every public function catches its own errors and warns (never
-- silently). Studio sends nothing to Roblox: it prints each event as it would go (workspace
-- attribute StudioEcho = false turns that off) and keeps records in a separate _Studio store. On the
-- live game, admins (shared/Admins) are neither sent nor recorded, so testing never pollutes charts.
-- Server errors and warnings (LogService) are counted per message under errors_<build>, flushed every
-- ERRORS_FLUSH seconds: Roblox's Error Report never sees a warn().
local AnalyticsService = game:GetService("AnalyticsService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Analytics = require(script.Parent.Analytics)
local PlayerData = require(script.Parent.PlayerData)
local Record = require(script.Parent.AnalyticsRecord)
local Retry = require(script.Parent.Retry)

local RECORD_STORE = "AnalyticsSessions_v1"
local RECORD_BYTES = 3_500_000 -- a DataStore key holds 4 MB; shrink the record below this
local ERRORS_FLUSH = 600
local ERRORS_DISTINCT = 200 -- server messages counted per flush
local CLOSE_SECONDS = 20 -- BindToClose waits this long at most for the last records

local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

export type Options = {
	place: string, -- "Lobby" / "Run"
	config: any, -- gameplay's Config (the lists in common/Analytics are built from it)
	admins: { [number]: boolean },
	balance: () -> number, -- the team's wallet, for economy events (the lobby has none: 0)
	stageOf: (Player?) -> string, -- the Stage field for an economy event (nil: the team's)
	farewell: (Player) -> (), -- the place's own leave (it calls TelemetryCore.leave); BindToClose runs it for whoever is left
}

type Visit = {
	player: Player,
	joined: number, -- os.clock()
	session: Record.Session,
	live: boolean, -- sent to Roblox (not Studio, not an admin)
	counted: boolean, -- not an admin on the live game (whose events go nowhere): may stand in for the team
	saves: boolean, -- writes the record and the funnels (a real account; never an admin on live)
	tracked: boolean, -- in the one-time funnels (Progress.funnels)
	closed: { [string]: boolean }, -- one-time funnels Roblox has forgotten them in (Progress.expiredFunnels): no more steps
	sent: { [string]: number }, -- one-time funnel -> highest step sent
	raised: boolean, -- a one-time step went out this visit (save the funnels on leave)
	recurring: { [string]: { id: string, step: number } }, -- open recurring-funnel sessions
	journeys: { [string]: { id: string, stage: number } }, -- this visit's journey sessions
	cooldowns: { [string]: number },
	income: { [string]: number }, -- "<reason>|<stage>" -> coins not yet sent
	teleporting: boolean,
	left: boolean,
}

local TelemetryCore = {}

local options: Options
local values: { [string]: { string } } = {}
local steps: { [string]: { string } } = {} -- funnel id -> steps (Onboarding too)
local recurring: { [string]: boolean } = {}
local visits: { [Player]: Visit } = {}
local teamIncome: { [string]: number } = {} -- "<reason>|<stage>" -> coins earned by no one player (staff, buildings)
local window = { at = 0, normal = 0, protected = 0, held = 0 }
local serverErrors: { [string]: number } = {}
local serverErrorCount = 0
local pending = 0 -- record writes in flight
local store: DataStore? = nil
local build = game.PlaceVersion
local echo = RunService:IsStudio()

-- Runs fn; a failure warns and is otherwise dropped, so analytics never stops the game.
local function guard(label: string, fn: (...any) -> ...any, ...: any): ...any
	local results = table.pack(pcall(fn, ...))
	if not results[1] then
		warn(`[Telemetry] {label} failed: {results[2]}`)
		return nil
	end
	return table.unpack(results, 2, results.n)
end

local function getStore(): DataStore
	if not store then
		store = DataStoreService:GetDataStore(if RunService:IsStudio() then `{RECORD_STORE}_Studio` else RECORD_STORE)
	end
	return store :: DataStore
end

local function echoing(): boolean
	return echo and workspace:GetAttribute("StudioEcho") ~= false
end

local function describe(fields: { [string]: string }?): string
	if not fields then
		return ""
	end
	local parts = {}
	for key, value in fields do
		table.insert(parts, `{key}={value}`)
	end
	table.sort(parts)
	return " " .. table.concat(parts, " ")
end

-- Whether one more event may go out this minute (Analytics.allowed). Held-back events warn once a minute.
local function spend(isProtected: boolean): boolean
	local now = os.clock()
	if now - window.at >= 60 then
		if window.held > 0 then
			warn(`[Telemetry] held back {window.held} events last minute (rate budget)`)
		end
		window.at, window.normal, window.protected, window.held = now, 0, 0, 0
	end
	if not Analytics.allowed(window.normal, window.protected, #Players:GetPlayers(), isProtected) then
		window.held += 1
		return false
	end
	if isProtected then
		window.protected += 1
	else
		window.normal += 1
	end
	return true
end

-- Roblox's field table from field name -> value, in `wanted` order.
local function toFields(wanted: { string }?, fields: { [string]: string }?): { [string]: string }?
	if not (wanted and fields) then
		return nil
	end
	local out = {}
	for i, field in wanted do
		out[FIELD_KEYS[i]] = fields[field]
	end
	return out
end

local function seconds(visit: Visit): number
	return math.round((os.clock() - visit.joined) * 10) / 10
end

local function trail(visit: Visit, entry: Record.Entry)
	entry.t = seconds(visit)
	Record.add(visit.session, entry)
end

-- One Roblox call (or its echo in Studio). Admins on live and Studio never reach Roblox.
local function send(visit: Visit, text: string, call: () -> ())
	if echoing() then
		print(`[Telemetry] {visit.player.Name}: {text}`)
	end
	if visit.live then
		guard(text, call)
	end
end

local function sendStep(visit: Visit, funnel: string, index: number, sessionId: string?, fields: { [string]: string }?)
	local name = steps[funnel][index]
	local player = visit.player
	send(visit, `step {funnel} {index} {name}{describe(fields)}`, function()
		if funnel == "Onboarding" then
			AnalyticsService:LogOnboardingFunnelStepEvent(player, index, name)
		else
			AnalyticsService:LogFunnelStepEvent(player, funnel, sessionId, index, name, toFields(Analytics.FUNNEL_FIELDS[funnel], fields))
		end
	end)
	trail(visit, { k = "step", s = `{funnel}:{name}`, m = not recurring[funnel] }) -- recurring steps are filler: spam can't crowd out the one-time ones
end

-- Starts the analytics visit of a player who joined: `new` (their first session ever) and their
-- one-time funnel progress (`funnels` nil: never entered, so they stay out of those funnels).
function TelemetryCore.join(player: Player, new: boolean, funnels: { [string]: number }?)
	guard("join", function()
		local real = player.UserId > 0
		local admin = options.admins[player.UserId] == true
		visits[player] = {
			player = player,
			joined = os.clock(),
			session = Record.newSession({ at = os.time(), build = build, place = options.place, new = new }),
			live = not RunService:IsStudio() and not admin,
			counted = RunService:IsStudio() or not admin,
			saves = real and not (admin and not RunService:IsStudio()),
			tracked = funnels ~= nil,
			closed = {},
			sent = if funnels then table.clone(funnels) else {},
			raised = false,
			recurring = {},
			journeys = {},
			cooldowns = {},
			income = {},
			teleporting = false,
			left = false,
		}
	end)
end

-- The player's funnels became known after join (a profile that loaded late): enter them. `expired`:
-- funnels Roblox has forgotten them in (Progress.expiredFunnels), which get no more steps.
function TelemetryCore.track(player: Player, new: boolean, funnels: { [string]: number }?, expired: { [string]: boolean }?)
	guard("track", function()
		local visit = visits[player]
		if not visit then
			return
		end
		visit.session.new = new
		if funnels then
			visit.tracked = true
			for id, step in funnels do
				visit.sent[id] = math.max(visit.sent[id] or 0, step)
			end
		end
		for id in expired or {} do
			visit.closed[id] = true
		end
	end)
end

function TelemetryCore.tracked(player: Player): boolean
	local visit = visits[player]
	return visit ~= nil and visit.tracked
end

-- Whether the player's events count (never an admin on the live game): only such a member may stand
-- in for the team.
function TelemetryCore.counted(player: Player): boolean
	local visit = visits[player]
	return visit ~= nil and visit.counted and not visit.left
end

-- One-time funnel `funnel` (Onboarding or a custom one): sends every step now due, in order, never
-- skipping one (Analytics.advance). Only for tracked players. A step the budget holds back goes on
-- the next call.
function TelemetryCore.advance(player: Player, funnel: string, facts: { [string]: boolean })
	guard(`advance {funnel}`, function()
		local visit = visits[player]
		local list = steps[funnel]
		assert(list and not recurring[funnel], `unknown one-time funnel {funnel}`)
		if not (visit and visit.tracked) or visit.closed[funnel] then
			return
		end
		local from = visit.sent[funnel] or 0
		local to = Analytics.advance(list, from, facts)
		for index = from + 1, to do
			if not spend(true) then
				return
			end
			sendStep(visit, funnel, index)
			visit.sent[funnel] = index
			visit.raised = true
		end
	end)
end

-- The furthest step of one-time funnel `funnel` sent to this player (0: none).
function TelemetryCore.reached(player: Player, funnel: string): number
	local visit = visits[player]
	return if visit then visit.sent[funnel] or 0 else 0
end

-- A recurring funnel: `stepName` in the player's open session of `funnel`. Step 1 opens a new
-- session (and carries `fields`, Analytics.FUNNEL_FIELDS); a later step needs an open session and
-- sends every step between, never skipping one.
function TelemetryCore.recurring(player: Player, funnel: string, stepName: string, fields: { [string]: string }?)
	guard(`recurring {funnel}`, function()
		local visit = visits[player]
		local list = steps[funnel]
		assert(list and recurring[funnel], `unknown recurring funnel {funnel}`)
		local index = table.find(list, stepName)
		assert(index, `{funnel} has no step {stepName}`)
		if not visit then
			return
		end
		if index == 1 then
			local wanted = Analytics.FUNNEL_FIELDS[funnel]
			if wanted and not Analytics.validFields(options.config, wanted, fields or {}, values) then
				warn(`[Telemetry] {funnel} step 1 fields not listed in common/Analytics:{describe(fields)}`)
				return
			end
			local open = { id = HttpService:GenerateGUID(false), step = 0 }
			visit.recurring[funnel] = open
			if spend(false) then
				sendStep(visit, funnel, 1, open.id, fields)
				open.step = 1
			end
			return
		end
		local open = visit.recurring[funnel]
		if not open or open.step < 1 then
			return
		end
		for i = open.step + 1, index do
			if not spend(false) then
				return
			end
			sendStep(visit, funnel, i, open.id)
			open.step = i
		end
	end)
end

-- Ends the player's open session of recurring funnel `funnel` (a later step needs a new step 1).
function TelemetryCore.closeRecurring(player: Player, funnel: string)
	local visit = visits[player]
	if visit then
		visit.recurring[funnel] = nil
	end
end

-- Journey `id` (Analytics.JOURNEYS): the player reached `node`. One session per visit; a node of a
-- stage already reached is not sent again (Roblox would ignore it, but it would spend the budget).
function TelemetryCore.journey(player: Player, id: string, node: string)
	guard(`journey {id}`, function()
		local stage = Analytics.journeyStage(id, node)
		assert(stage, `{node} isn't a node of journey {id} in common/Analytics`)
		local visit = visits[player]
		if not visit then
			return
		end
		local open = visit.journeys[id]
		if not open then
			open = { id = HttpService:GenerateGUID(false), stage = 0 }
			visit.journeys[id] = open
		end
		if stage <= open.stage or not spend(true) then
			return
		end
		open.stage = stage
		local session = open.id
		send(visit, `journey {id} {stage} {node}`, function()
			AnalyticsService:LogJourneyEvent(player, id, node, session)
		end)
		trail(visit, { k = "journey", s = `{id}:{node}`, m = true })
	end)
end

-- Custom event `name` (Analytics.EVENTS) with `value` and its fields. `cooldown`: a key; the same
-- key for this player goes once per Analytics.BLOCKED_COOLDOWN. `milestone`: kept in the trail
-- whatever else it drops.
function TelemetryCore.event(player: Player, name: string, value: number, fields: { [string]: string }, cooldown: string?, milestone: boolean?): boolean
	return guard(`event {name}`, function()
		local visit = visits[player]
		if not visit then
			return false
		end
		local wanted = Analytics.EVENTS[name]
		if not (wanted and Analytics.validFields(options.config, wanted, fields, values)) then
			warn(`[Telemetry] event {name} or its fields aren't listed in common/Analytics:{describe(fields)}`)
			return false
		end
		if cooldown then
			local now = os.clock()
			if now < (visit.cooldowns[cooldown] or 0) then
				return false
			end
			visit.cooldowns[cooldown] = now + Analytics.BLOCKED_COOLDOWN
		end
		if not spend(Analytics.PROTECTED[name] == true) then
			return false
		end
		local amount = if value == value then math.clamp(value, -Analytics.AMOUNT_MAX, Analytics.AMOUNT_MAX) else 0
		send(visit, `event {name} {amount}{describe(fields)}`, function()
			AnalyticsService:LogCustomEvent(visit.player, name, amount, toFields(wanted, fields))
		end)
		trail(visit, { k = "event", s = name, v = amount, f = fields, m = milestone })
		return true
	end) == true
end

local function economy(visit: Visit, reason: string, amount: number, stage: string, sku: string?)
	local flow = Analytics.MONEY[reason]
	if not flow or not (amount > 0) then
		return
	end
	local fields = { Stage = stage }
	if not Analytics.validFields(options.config, Analytics.ECONOMY_FIELDS, fields, values) then
		warn(`[Telemetry] economy Stage {stage} isn't listed in common/Analytics`)
		return
	end
	amount = math.min(amount, Analytics.AMOUNT_MAX)
	local balance = math.clamp(guard("balance", options.balance) or 0, 0, Analytics.AMOUNT_MAX)
	if not spend(true) then
		return
	end
	local flowType = if flow == "source" then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
	send(visit, `money {flow} {reason} {amount}{if sku then ` {sku}` else ""} Stage={stage}`, function()
		AnalyticsService:LogEconomyEvent(visit.player, flowType, Analytics.CURRENCY, amount, balance, reason, sku or "", toFields(Analytics.ECONOMY_FIELDS, fields))
	end)
	trail(visit, { k = "money", s = reason, v = amount, f = if sku then { sku = sku, Stage = stage } else { Stage = stage }, m = flow == "sink" })
	Record.count(visit.session, if flow == "source" then "earned" else "spent", amount)
end

local function stageOf(player: Player?): string
	return guard("stage", options.stageOf, player) or "Loading"
end

-- Coins spent (Analytics.MONEY sink reasons) by `player`, sent at once.
function TelemetryCore.spent(player: Player, reason: string, coins: number, sku: string?)
	guard("spent", function()
		local visit = visits[player]
		if not visit then
			return
		end
		if Analytics.MONEY[reason] ~= "sink" or (sku and not table.find(values.Upgrade, sku)) then
			warn(`[Telemetry] spend reason {reason} / sku {sku} isn't listed in common/Analytics`)
			return
		end
		economy(visit, reason, coins, stageOf(player), sku)
	end)
end

-- Coins earned (a source reason): summed per reason and the Stage they were earned at, and sent every
-- Analytics.INCOME_FLUSH seconds. `player` nil: the team's (staff, buildings), sent as one present
-- member's.
function TelemetryCore.earned(player: Player?, reason: string, coins: number)
	guard("earned", function()
		if Analytics.MONEY[reason] ~= "source" then
			warn(`[Telemetry] income reason {reason} isn't listed in common/Analytics`)
			return
		elseif not (coins > 0) then
			return
		end
		local into = if player then (visits[player] and visits[player].income) else teamIncome
		if into then
			local key = `{reason}|{stageOf(player)}`
			into[key] = (into[key] or 0) + coins
		end
	end)
end

local function flushInto(visit: Visit, income: { [string]: number })
	for key, coins in income do
		income[key] = nil
		local reason, stage = key:match("^(.-)|(.*)$")
		economy(visit, reason :: string, coins, stage :: string)
	end
end

local function flushIncome(visit: Visit)
	flushInto(visit, visit.income)
end

-- The team's income goes out as one present member's whose events count: the lowest user id, so it
-- never moves around. With none (only admins here, live), it waits for one.
local function flushTeam()
	local into: Visit? = nil
	for _, visit in visits do
		if visit.counted and not visit.left and (not into or visit.player.UserId < into.player.UserId) then
			into = visit
		end
	end
	if not into then
		return
	end
	flushInto(into, teamIncome)
end

-- Record-only facts: the session's `key` set to `value` (device, fps, load...).
function TelemetryCore.note(player: Player, key: string, value: any)
	local visit = visits[player]
	if visit then
		visit.session[key] = value
	end
end

-- Record-only: adds to one of the session's counts.
function TelemetryCore.count(player: Player, name: string, by: number?)
	local visit = visits[player]
	if visit then
		Record.count(visit.session, name, by)
	end
end

-- Record-only: a row in the trail (`kind` "flag" for something worth finding later).
function TelemetryCore.flag(player: Player, what: string, fields: { [string]: string }?)
	local visit = visits[player]
	if visit then
		trail(visit, { k = "flag", s = what, f = fields, m = true })
	end
end

-- Record-only: a client's error or warning text (already cut to Analytics.TEXT_MAX).
function TelemetryCore.text(player: Player, kind: string, text: string)
	local visit = visits[player]
	if visit then
		Record.text(if kind == "error" then visit.session.errors else visit.session.warnings, text)
	end
end

-- The player is going on by teleport (into a run, or back to the lobby): their leaving isn't a quit,
-- so no SessionEnd.
function TelemetryCore.teleporting(player: Player)
	local visit = visits[player]
	if visit then
		visit.teleporting = true
	end
end

function TelemetryCore.seconds(player: Player): number
	local visit = visits[player]
	return if visit then seconds(visit) else 0
end

local function writeRecord(visit: Visit)
	local session = visit.session
	local userId = visit.player.UserId
	pending += 1
	local ok, err = Retry.run(`analytics record {userId}`, function()
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getStore():UpdateAsync(`u_{userId}`, function(old)
			local record = Record.push(old, session)
			-- too big for its key: cut the oldest trails until it fits
			repeat
				local fits = #HttpService:JSONEncode(record) <= RECORD_BYTES
			until fits or not Record.shrink(record)
			return record
		end)
	end)
	pending -= 1
	if not ok then
		warn(`[Telemetry] session record of {userId} not saved: {err}`)
	end
end

local function saveFunnels(visit: Visit)
	pending += 1
	local saved, err = PlayerData.saveFunnels(visit.player.UserId, visit.sent, os.time())
	pending -= 1
	if not saved then
		warn(`[Telemetry] funnel steps of {visit.player.UserId} not saved: {err}`)
	end
end

-- The player leaves: SessionEnd (unless teleporting; minutes this visit) with where they were, what
-- they were doing and their stage; then the record and the funnel steps are written (one write each).
-- `facts`: the place's record facts for the session (leave, progress...).
function TelemetryCore.leave(player: Player, sessionEnd: { [string]: string }?, facts: { [string]: any }?)
	guard("leave", function()
		local visit = visits[player]
		if not visit or visit.left then
			return
		end
		flushIncome(visit)
		flushTeam() -- before the last member goes, the team's income goes out as someone's
		visit.left = true
		if sessionEnd and not visit.teleporting then
			TelemetryCore.event(player, "SessionEnd", seconds(visit) / 60, sessionEnd, nil, true)
		end
		local session = visit.session
		session.seconds = seconds(visit)
		session.left = if visit.teleporting then "teleport" else "quit"
		session.onboarding = visit.sent.Onboarding
		session.tracked = visit.tracked
		for key, value in facts or {} do
			session[key] = value
		end
		visits[player] = nil
		if visit.saves then
			task.spawn(writeRecord, visit)
			if visit.tracked and visit.raised then
				task.spawn(saveFunnels, visit)
			end
		end
	end)
end

-- Server errors and warnings, counted per message; whose they are is unknown.
local function onMessage(message: string, kind: Enum.MessageType)
	if kind ~= Enum.MessageType.MessageError and kind ~= Enum.MessageType.MessageWarning then
		return
	end
	local text = `{if kind == Enum.MessageType.MessageError then "E" else "W"} {message:sub(1, Analytics.TEXT_MAX)}`
	if serverErrors[text] then
		serverErrors[text] += 1
	elseif serverErrorCount < ERRORS_DISTINCT then
		serverErrors[text] = 1
		serverErrorCount += 1
	end
end

local function flushErrors()
	if serverErrorCount == 0 or RunService:IsStudio() then
		return
	end
	local counts = serverErrors
	serverErrors, serverErrorCount = {}, 0
	local key = `errors_{options.place}_{build}`
	local ok, err = Retry.run(`analytics errors {key}`, function()
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getStore():UpdateAsync(key, function(old)
			local merged = if type(old) == "table" then old else {}
			for text, n in counts do
				merged[text] = (if type(merged[text]) == "number" then merged[text] else 0) + n
			end
			return merged
		end)
	end)
	if not ok then
		warn(`[Telemetry] server errors for {key} not saved: {err}`)
	end
end

function TelemetryCore.start(opts: Options)
	options = opts
	values = Analytics.fieldValues(opts.config)
	steps.Onboarding = Analytics.ONBOARDING
	for _, funnel in Analytics.funnels(opts.config) do
		steps[funnel.id] = funnel.steps
		recurring[funnel.id] = funnel.recurring
	end
	LogService.MessageOut:Connect(onMessage)
	task.spawn(function()
		while true do
			task.wait(Analytics.INCOME_FLUSH)
			for _, visit in visits do
				guard("income flush", flushIncome, visit)
			end
			guard("team income flush", flushTeam)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(ERRORS_FLUSH)
			guard("errors flush", flushErrors)
		end
	end)
	game:BindToClose(function()
		for player in visits do
			guard("farewell", options.farewell, player)
		end
		guard("errors flush", flushErrors)
		local deadline = os.clock() + CLOSE_SECONDS
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return TelemetryCore
