-- The run's analytics (docs/analytics.md): which funnel steps are due, the events and money moves of
-- a run, and what the client reports (Telemetry remote). common/TelemetryCore sends them and keeps the
-- session record; names come from common/Analytics. server/Run tells this the moments it already
-- decides (a scoop, a pour, a buy, a gate, a milestone...) and passes the hooks below; once a second
-- it checks each player's one-time funnel facts, where they stand and whether they idle.
-- Nothing here changes the game: delete the calls and the run plays the same.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admins = require(ReplicatedStorage.Shared.Admins)
local Config = require(ReplicatedStorage.Shared.Config)
local Analytics = require(ReplicatedStorage.Common.Analytics)
local PlayerData = require(ReplicatedStorage.Common.PlayerData)
local TelemetryCore = require(ReplicatedStorage.Common.TelemetryCore)

local POLL = 1 -- seconds between fact checks
local MOVED = 2 -- studs that count as moving (not idle)

export type Hooks = {
	states: { [Player]: any }, -- server/Run's player states (carried, hose)
	phase: () -> string,
	loaded: () -> boolean, -- the run's save is open
	started: () -> boolean, -- the run has started (the team was in)
	partyRun: () -> boolean, -- a lobby party's run (it waits for the party)
	fill: () -> number,
	teamSize: () -> number,
	wallet: () -> number,
	cheapest: () -> number?, -- the team's price of the cheapest upgrade on sale now
	boughtAny: () -> boolean, -- the team owns a bought level
	gatesOpen: () -> { number },
	milestones: () -> { number }, -- the run's reached milestones (indices)
	toolLevel: () -> number,
	playSeconds: () -> number, -- the save's time played
	whereOf: (Player) -> string, -- "Area<n>" nearest open Source, "None"
	nearSource: (Player) -> boolean, -- within reach of an open area's Source
	shortOf: (string) -> number?, -- the team's price of upgrade (or gate) id's next level while on sale
}

type Facts = {
	joined: number,
	loadSent: boolean,
	waitedOn: string,
	atWell: boolean,
	scooped: boolean,
	poured: boolean,
	canAfford: boolean,
	trip: { at: number, area: number }?,
	lastAct: string?,
	lastActAt: number,
	activeAt: number,
	lastPos: Vector3?,
	where: string, -- the nearest open area at the last poll (the character is gone by the time they leave)
	guideStep: number,
	honeycomb: boolean,
	fpsSum: number,
	fpsCount: number,
	gaps: { [string]: number },
}

local Telemetry = {}

local hooks: Hooks
local facts: { [Player]: Facts } = {}
local oneTime: { Analytics.Funnel } = {}
local introAt = 0

local function minutes(): number
	return hooks.playSeconds() / 60
end

local function stage(player: Player): string
	local f = facts[player]
	return Analytics.stage(hooks.phase(), if f then f.guideStep else 0, hooks.fill())
end

local function teamSize(): string
	return Analytics.bucket(Analytics.BANDS.teamSize, hooks.teamSize())
end

local function areaName(id: number): string
	return `Area{id}`
end

-- The present member who stands for the team (the lowest user id whose events count: never a live
-- admin), for events of the run itself.
local function teamMember(): Player?
	local best = nil
	for player in facts do
		if TelemetryCore.counted(player) and (not best or player.UserId < best.UserId) then
			best = player
		end
	end
	return best
end

local function humanoidOf(player: Player): Humanoid?
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

local function driving(player: Player): boolean
	local humanoid = humanoidOf(player)
	local seat = humanoid and humanoid.SeatPart
	return seat ~= nil and seat:IsA("VehicleSeat")
end

local function doing(player: Player): string
	local f = facts[player]
	local state = hooks.states[player]
	local now = os.clock()
	return Analytics.doing({
		phase = hooks.phase(),
		idle = if f then now - f.activeAt else 0,
		honeycomb = f ~= nil and f.honeycomb,
		driving = driving(player),
		hosing = state ~= nil and state.hose ~= nil and state.hose.spraying,
		lastAct = f and f.lastAct,
		lastActAge = if f then now - f.lastActAt else math.huge,
		carried = if state then state.carried else 0,
	})
end

-- The one-time funnels' facts for this player now. The lobby's steps are done by being here.
local function check(player: Player, f: Facts)
	local phase = hooks.phase()
	local playing = phase == "playing" or phase == "ending" or phase == "done"
	if playing and not f.atWell and hooks.nearSource(player) then
		f.atWell = true
	end
	local bought = hooks.boughtAny()
	if playing and not f.canAfford then
		local cheapest = hooks.cheapest()
		f.canAfford = bought or (cheapest ~= nil and hooks.wallet() >= cheapest)
	end
	if not TelemetryCore.tracked(player) then
		return
	end
	TelemetryCore.advance(player, "Onboarding", {
		Joined = true,
		LobbyLoaded = true,
		PartyStarted = true,
		RunLoaded = hooks.loaded(),
		IntroDone = playing,
		AtWell = f.atWell,
		FirstScoop = f.scooped,
		FirstPour = f.poured,
		CanAfford = f.canAfford,
		FirstUpgrade = bought,
	})
	if not hooks.loaded() then
		return
	end
	local open = hooks.gatesOpen()
	local reached = hooks.milestones()
	local tool = hooks.toolLevel()
	local full = hooks.fill() >= 1
	for _, funnel in oneTime do
		local due = {}
		for i, name in funnel.steps do
			if funnel.id == "Progression_v1" then
				local id = tonumber(name:match("^Area(%d+)$"))
				due[name] = if id then table.find(open, id) ~= nil else full
			elseif funnel.id == "Tool_v1" then
				due[name] = tool >= i
			elseif funnel.id == "Milestones_v1" then
				due[name] = table.find(reached, i) ~= nil
			end
		end
		TelemetryCore.advance(player, funnel.id, due)
	end
end

local function poll()
	local now = os.clock()
	local loading = hooks.phase() == "loading"
	for player, f in facts do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = if root and root:IsA("BasePart") then root.Position else nil
		if at and (not f.lastPos or (at - f.lastPos).Magnitude >= MOVED) then
			f.lastPos, f.activeAt = at, now
		end
		if at then
			f.where = hooks.whereOf(player)
		end
		if not f.loadSent and not loading then
			f.loadSent = true
			local seconds = now - f.joined
			TelemetryCore.event(player, "LoadTime", seconds, { Place = "Run", Band = Analytics.bucket(Analytics.BANDS.load, seconds), WaitedOn = f.waitedOn })
			TelemetryCore.note(player, "load", math.round(seconds * 10) / 10)
		end
		check(player, f)
	end
end

-- A player of the run joined (server/Run's onPlayerAdded): their visit starts at once; their funnel
-- progress loads alongside (a profile that can't load keeps them out of the one-time funnels).
function Telemetry.playerIn(player: Player)
	local now = os.clock()
	facts[player] = {
		joined = now,
		loadSent = false,
		waitedOn = if hooks.started() then "None" elseif hooks.partyRun() then "Party" else "Save",
		atWell = false,
		scooped = false,
		poured = false,
		canAfford = false,
		trip = nil,
		lastAct = nil,
		lastActAt = -math.huge,
		activeAt = now,
		lastPos = nil,
		where = "None",
		guideStep = 0,
		honeycomb = false,
		fpsSum = 0,
		fpsCount = 0,
		gaps = {},
	}
	TelemetryCore.join(player, false, nil)
	if player.UserId <= 0 then
		return -- Studio's test accounts have no profile
	end
	task.spawn(function()
		local data, err, isNew = PlayerData.load(player.UserId)
		if not data then
			warn(`[Telemetry] couldn't load {player.Name}'s funnel steps: {err}; not in the one-time funnels this visit`)
			return
		end
		if player.Parent then
			TelemetryCore.track(player, isNew, data.funnels)
		end
	end)
end

-- An accepted scoop sweep was credited (server/Run's onAct): a trip starts with the first water.
function Telemetry.scooped(player: Player, areaId: number)
	local f = facts[player]
	if not f then
		return
	end
	f.scooped = true
	f.lastAct, f.lastActAt, f.activeAt = "scoop", os.clock(), os.clock()
	f.trip = f.trip or { at = os.clock(), area = areaId }
	TelemetryCore.count(player, "scoops")
end

-- An accepted pour (tool or Water Gun): the trip ends Poured.
function Telemetry.poured(player: Player)
	local f = facts[player]
	if not f then
		return
	end
	f.poured = true
	f.lastAct, f.lastActAt, f.activeAt = "pour", os.clock(), os.clock()
	TelemetryCore.count(player, "pours")
	local trip = f.trip
	if trip then
		f.trip = nil
		TelemetryCore.event(player, "TripEnd", os.clock() - trip.at, { Outcome = "Poured", Area = areaName(trip.area), Stage = stage(player) })
	end
end

-- Coins into the team's wallet for a listed reason (Analytics.MONEY); player nil: the team's.
function Telemetry.earned(player: Player?, coins: number, reason: string)
	if player and not facts[player] then
		return
	end
	TelemetryCore.earned(player, reason, coins)
end

-- Coins out of the team's wallet, bought by `player`; `sku` the track, item or gate id.
function Telemetry.spent(player: Player, coins: number, reason: string, sku: string)
	TelemetryCore.spent(player, reason, coins, sku)
	TelemetryCore.count(player, "buys")
end

-- A buy from the honeycomb landed (server/Run's onBuy): its funnel session ends Bought.
function Telemetry.boughtInHoneycomb(player: Player)
	TelemetryCore.recurring(player, "Honeycomb_v1", "Bought")
end

-- A stand's item bought (staff, vehicles, gadgets, backpacks).
function Telemetry.itemBought(player: Player, itemId: string)
	TelemetryCore.event(player, "ItemBought", 1, { Item = itemId, Stage = stage(player) }, nil, true)
end

function Telemetry.buildingBuilt(player: Player, itemId: string)
	TelemetryCore.event(player, "BuildingBuilt", 1, { Item = itemId, Stage = stage(player) }, nil, true)
end

function Telemetry.vehicleCalled(player: Player, itemId: string)
	TelemetryCore.event(player, "VehicleCalled", 1, { Item = itemId, Stage = stage(player) })
end

-- A press that bought nothing (Analytics.REASONS). `sku`: what was pressed; with CantAfford it also
-- sends UpgradeShort, the share of its price the wallet lacked.
function Telemetry.blocked(player: Player, reason: string, sku: string?)
	if not facts[player] then
		return
	end
	local key = `{reason}:{sku or ""}`
	TelemetryCore.event(player, "Blocked", 1, { Reason = reason, Stage = stage(player) }, key)
	local cost = if reason == "CantAfford" and sku then hooks.shortOf(sku) else nil
	if cost and cost > 0 then
		local missing = math.clamp(1 - hooks.wallet() / cost, 0, 1)
		TelemetryCore.event(player, "UpgradeShort", missing, { Upgrade = sku :: string, Stage = stage(player) }, `short:{sku}`)
	end
end

-- `buyer` opened area `areaId`'s gate (minutes of the run's play: the real pace against tools/simulate).
function Telemetry.gateOpened(buyer: Player, areaId: number)
	TelemetryCore.event(buyer, "GateOpened", minutes(), { Area = areaName(areaId), TeamSize = teamSize() }, nil, true)
end

-- The run reached milestone `index` (Config.milestones), sent once for the team.
function Telemetry.milestone(index: number)
	local member = teamMember()
	if member then
		TelemetryCore.event(member, "Milestone", minutes(), { Milestone = `M{math.round(Config.milestones[index].fill * 100)}`, TeamSize = teamSize() }, nil, true)
	end
end

function Telemetry.introStarted(at: number)
	introAt = at
end

-- The intro ended for everyone here: watched to the end (or its time ran out) or skipped.
function Telemetry.introEnded(skipped: boolean)
	local seconds = math.max(0, workspace:GetServerTimeNow() - introAt)
	for player in facts do
		TelemetryCore.event(player, "IntroEnd", seconds, { IntroOutcome = if skipped then "Skipped" else "Watched" })
	end
end

-- The run's save couldn't be loaded: these players can't play (must stay 0).
function Telemetry.saveUnavailable()
	for player in facts do
		TelemetryCore.event(player, "SaveUnavailable", 1, { Place = "Run" })
	end
end

-- These players are teleported to the lobby: their leaving isn't a quit.
function Telemetry.teleporting(players: { Player })
	for _, player in players do
		TelemetryCore.teleporting(player)
	end
end

-- The player leaves (or the server closes): a trip still carrying ends Quit, ClientFps, SessionEnd
-- and the record.
function Telemetry.playerOut(player: Player)
	local f = facts[player]
	if not f then
		return
	end
	local state = hooks.states[player]
	local here = hooks.whereOf(player)
	local where = if here ~= "None" then here else f.where
	local what = doing(player)
	local now = stage(player)
	facts[player] = nil -- after doing and stage, which read it
	if f.trip and state and state.carried > 0 then
		TelemetryCore.event(player, "TripEnd", os.clock() - f.trip.at, { Outcome = "Quit", Area = areaName(f.trip.area), Stage = now })
	end
	local fps = if f.fpsCount > 0 then f.fpsSum / f.fpsCount else nil
	if fps then
		TelemetryCore.event(player, "ClientFps", fps, { Band = Analytics.bucket(Analytics.BANDS.fps, fps) })
	end
	TelemetryCore.leave(player, { Where = where, Doing = what, Stage = now }, {
		leave = { where = where, doing = what, stage = now },
		fps = fps and math.round(fps),
		progress = {
			fill = math.round(hooks.fill() * 1000) / 1000,
			wallet = math.floor(hooks.wallet()),
			gates = #hooks.gatesOpen(),
			tool = hooks.toolLevel(),
			teamSize = hooks.teamSize(),
			minutes = math.round(minutes()),
		},
	})
end

-- Telemetry(name, arg) from client/Telemetry: only listed names, one per Analytics.CLIENT gap, the
-- argument checked (Analytics.checkReport); the server turns them into events itself.
local function onReport(player: Player, name: unknown, arg: unknown)
	local f = facts[player]
	if not f or type(name) ~= "string" then
		return
	end
	local rule = Analytics.CLIENT[name]
	if not rule then
		return
	end
	local now = os.clock()
	if now < (f.gaps[name] or 0) then
		return
	end
	f.gaps[name] = now + rule.gap
	local value = Analytics.checkReport(Config, name, arg)
	if value == nil then
		return
	end
	if name == "fps" then
		f.fpsSum += value
		f.fpsCount += 1
	elseif name == "hcOpen" then
		f.honeycomb, f.activeAt = true, now
		TelemetryCore.recurring(player, "Honeycomb_v1", "Opened", { Source = value, Stage = stage(player) })
	elseif name == "hcView" then
		f.activeAt = now
		TelemetryCore.recurring(player, "Honeycomb_v1", "Viewed")
	elseif name == "hcClose" then
		f.honeycomb = false
		TelemetryCore.closeRecurring(player, "Honeycomb_v1")
	elseif name == "short" then
		f.activeAt = now
		Telemetry.blocked(player, "CantAfford", value)
	elseif name == "guide" then
		f.guideStep = value
	elseif name == "guideSkip" then
		TelemetryCore.event(player, "GuideSkip", TelemetryCore.seconds(player), { Stage = stage(player) })
	elseif name == "warn" or name == "error" then
		TelemetryCore.text(player, name, value)
	elseif name == "device" then
		TelemetryCore.note(player, "device", value)
	end
end

function Telemetry.start(runHooks: Hooks, remote: RemoteEvent)
	hooks = runHooks
	for _, funnel in Analytics.funnels(Config) do
		if not funnel.recurring then
			table.insert(oneTime, funnel)
		end
	end
	TelemetryCore.start({
		place = "Run",
		config = Config,
		admins = Admins,
		balance = hooks.wallet,
		farewell = Telemetry.playerOut,
	})
	remote.OnServerEvent:Connect(onReport)
	task.spawn(function()
		while true do
			task.wait(POLL)
			local ok, err = pcall(poll)
			if not ok then
				warn(`[Telemetry] poll failed: {err}`)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- server/Run calls playerOut first (it still has the player's state); this catches the rest
		Telemetry.playerOut(player)
	end)
end

-- Analytics never breaks the run: every call from server/Run catches its own errors and warns.
for name, fn in Telemetry do
	if name ~= "start" then
		Telemetry[name] = function(...)
			local ok, err = pcall(fn, ...)
			if not ok then
				warn(`[Telemetry] {name} failed: {err}`)
			end
		end
	end
end

return Telemetry
