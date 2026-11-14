--!strict
-- Every analytics name, in one place (docs/analytics.md). The senders (gameplay and lobby
-- server/Telemetry) refuse any funnel, step, event, field value or money reason not listed here, so a
-- typo is a warning, never a new chart. Names are PERMANENT once live: renaming a step mixes its
-- data, renaming a funnel or event starts it empty. Change a funnel by making a new version (_v2),
-- never by editing its steps (Onboarding, which Roblox can't version, only gets steps cut from the
-- end or appended). Pure: no requires, so Lune tests it; the lists that come from the game's numbers
-- are built from a Config passed in (gameplay's shared/Config).

local Analytics = {}

-- Roblox's onboarding funnel (one-time, new players only): from the first join to the first turn of
-- the core loop, following client/Guide's steps as far as the server can confirm them. Nothing a
-- player may skip goes in it: an optional step would hold every step after it hostage.
--   Joined, LobbyLoaded: the lobby, at the first-ever profile load. PartyStarted: the lobby, as the
--   party teleports. RunLoaded: the run's save is open. IntroDone: play started with the player in
--   (watched, skipped, or a run whose intro was seen). AtWell: stood within reach of an open Source.
--   FirstScoop, FirstPour: their own. CanAfford: the team's wallet reached the cheapest upgrade.
--   FirstUpgrade: the team owns a bought level (the guide ends on the team's first buy).
Analytics.ONBOARDING = { "Joined", "LobbyLoaded", "PartyStarted", "RunLoaded", "IntroDone", "AtWell", "FirstScoop", "FirstPour", "CanAfford", "FirstUpgrade" }
-- The lobby sends the first steps; a player in a run has done them by being there.
Analytics.LOBBY_STEPS = 3
-- client/Guide's steps (its STEPS): Stage "Guide:1" ... while it shows.
Analytics.GUIDE_STEPS = 6

export type Funnel = { id: string, recurring: boolean, steps: { string } }

-- The custom funnels (Roblox allows 10; the rest are spare for new versions). One-time funnels count
-- new players only, like Onboarding. Honeycomb_v1 is recurring: one session per open of the
-- honeycomb, and only its first step carries fields (Roblox reads filters from step 1 only).
function Analytics.funnels(config: any): { Funnel }
	local progression = {}
	for _, area in config.areas do
		if area.gate then
			table.insert(progression, `Area{area.id}`)
		end
	end
	table.insert(progression, "OceanFull")
	local tool = {}
	for _, track in config.tracks do
		if track.id == "tool" then
			for level in track.levels do
				table.insert(tool, `Level{level}`)
			end
		end
	end
	local milestones = {}
	for _, milestone in config.milestones do
		table.insert(milestones, `M{math.round(milestone.fill * 100)}`)
	end
	return {
		{ id = "Progression_v1", recurring = false, steps = progression },
		{ id = "Tool_v1", recurring = false, steps = tool },
		{ id = "Milestones_v1", recurring = false, steps = milestones },
		{ id = "Honeycomb_v1", recurring = true, steps = { "Opened", "Viewed", "Bought" } },
	}
end

-- A recurring funnel's fields, on its first step only (Roblox reads filters from step 1).
Analytics.FUNNEL_FIELDS = {
	Honeycomb_v1 = { "Source", "Stage" },
}

-- Journeys (Roblox's branching funnels: a Sankey of the paths players take). Each journey must ALSO be
-- created in Creator Hub > Analytics > Journeys with exactly these stages and nodes (docs/analytics.md
-- has the config); a node Roblox doesn't know advances nothing. Stages in order, each stage's nodes are
-- alternatives meaning equal progress. One session per lobby visit; the Users view shows each player's
-- first time through.
--   Lobby_v1: where a new player gets lost between loading the lobby and starting a run.
--     LobbyLoaded -> Hosted (first on an empty pad) | JoinedParty (got on someone's party)
--     -> NewRun (the host set up a new party) | LoadedRun (the host loaded a saved run) | InParty (joined
--        a set-up party) -> CountdownStarted -> PartyStarted (the teleport goes)
Analytics.JOURNEYS = {
	Lobby_v1 = {
		{ "LobbyLoaded" },
		{ "Hosted", "JoinedParty" },
		{ "NewRun", "LoadedRun", "InParty" },
		{ "CountdownStarted" },
		{ "PartyStarted" },
	},
}

-- The stage of `node` in journey `id`, or nil when it isn't one of its nodes.
function Analytics.journeyStage(id: string, node: string): number?
	local stages = Analytics.JOURNEYS[id]
	if not stages then
		return nil
	end
	for index, nodes in stages do
		if table.find(nodes, node) then
			return index
		end
	end
	return nil
end

-- Economy events' fields: where the player was when the coins moved.
Analytics.ECONOMY_FIELDS = { "Stage" }

-- Custom events and their fields, in field order (Roblox's CustomField01..03). Every value comes from
-- fieldValues: never a name, a raw number or anything a client typed.
--   SessionEnd (minutes): once per player per place visit, unless they teleported on (not a quit).
--   TripEnd (seconds carrying): a trip is carried 0 -> water -> poured (Poured) or left (Quit).
--   IntroEnd (seconds in). GuideSkip (seconds played). GateOpened, Milestone (minutes of the run's play).
--   Blocked (1): a press that bought nothing, why. UpgradeShort (share of the price missing).
--   ItemBought, BuildingBuilt, VehicleCalled (1): automation and gear adoption.
--   LoadTime (seconds), SaveUnavailable (1; must stay 0), ClientFps (average fps).
--   PartyLaunched (1, per member as the teleport goes): the party's size and whether it starts a new
--   run, continues a saved one or starts one over. CountdownCancelled (1): someone left during the
--   3-2-1. RunDeleted (1): a Saved Runs Delete (a solo run erased, or leaving a team's).
Analytics.EVENTS = {
	SessionEnd = { "Where", "Doing", "Stage" },
	TripEnd = { "Outcome", "Area", "Stage" },
	IntroEnd = { "IntroOutcome" },
	GuideSkip = { "Stage" },
	GateOpened = { "Area", "TeamSize" },
	Milestone = { "Milestone", "TeamSize" },
	Blocked = { "Reason", "Stage" },
	UpgradeShort = { "Upgrade", "Stage" },
	ItemBought = { "Item", "Stage" },
	BuildingBuilt = { "Item", "Stage" },
	VehicleCalled = { "Item", "Stage" },
	LoadTime = { "Place", "Band", "WaitedOn" },
	SaveUnavailable = { "Place" },
	ClientFps = { "Band" },
	PartyLaunched = { "PartySize", "RunKind" },
	CountdownCancelled = { "PartySize", "CancelWhy" },
	RunDeleted = { "RunTeam" },
}

-- Events that may never be crowded out by a flood of others (Rules.allowed).
Analytics.PROTECTED = { SessionEnd = true, SaveUnavailable = true }

-- Number bands: `edges` ascending; a value below edges[1] is labels[1], at or above edges[i] labels[i + 1].
export type Bands = { edges: { number }, labels: { string } }
Analytics.BANDS = {
	fps = { edges = { 15, 25, 40, 55 }, labels = { "0-15", "15-25", "25-40", "40-55", "55+" } } :: Bands,
	load = { edges = { 5, 10, 20, 40 }, labels = { "0-5s", "5-10s", "10-20s", "20-40s", "40s+" } } :: Bands,
	teamSize = { edges = { 2, 3, 4 }, labels = { "1", "2", "3", "4+" } } :: Bands,
}

-- What a player was doing. In the lobby: Roaming (on no pad), Choosing (hosting, the pad screen open),
-- Waiting (in a party not yet going), Countdown (the 3-2-1 or the launch), Loading (no profile yet).
-- "Party" is the lobby's value before those (2026-11-13), kept so old SessionEnds still read.
Analytics.DOING = { "Loading", "Intro", "Ending", "Idle", "Honeycomb", "Driving", "Hosing", "Scooping", "Pouring", "Carrying", "Roaming", "Party", "Choosing", "Waiting", "Countdown" }
Analytics.SOURCES = { "Key", "Button", "Goal" } -- how the honeycomb was opened (Honeycomb_v1 step 1)
Analytics.REASONS = { "CantAfford", "Locked", "GateLocked", "NotBuilt" } -- Blocked
Analytics.WAITED_ON = { "Data", "Party", "Save", "None" } -- LoadTime: what the join waited on

-- Every field's allowed values.
function Analytics.fieldValues(config: any): { [string]: { string } }
	local areas = {}
	for _, area in config.areas do
		table.insert(areas, `Area{area.id}`)
	end
	local stages = { "Lobby", "Loading", "Intro" }
	for step = 1, Analytics.GUIDE_STEPS do
		table.insert(stages, `Guide:{step}`)
	end
	for percent = 0, 100, 5 do
		table.insert(stages, `F{percent}`)
	end
	local where = table.clone(areas)
	table.insert(where, 1, "Lobby")
	table.insert(where, "None")
	local milestones = {}
	for _, milestone in config.milestones do
		table.insert(milestones, `M{math.round(milestone.fill * 100)}`)
	end
	local items = {}
	for _, item in config.items do
		table.insert(items, item.id)
	end
	local bands = {}
	for _, band in Analytics.BANDS do
		for _, label in band.labels do
			if not table.find(bands, label) then
				table.insert(bands, label)
			end
		end
	end
	return {
		Where = where,
		Doing = Analytics.DOING,
		Stage = stages,
		Outcome = { "Poured", "Quit" },
		Area = areas,
		IntroOutcome = { "Watched", "Skipped" },
		TeamSize = Analytics.BANDS.teamSize.labels,
		Milestone = milestones,
		Reason = Analytics.REASONS,
		Upgrade = Analytics.skus(config),
		Item = items,
		Place = { "Lobby", "Run" },
		Band = bands,
		WaitedOn = Analytics.WAITED_ON,
		Source = Analytics.SOURCES,
		PartySize = Analytics.BANDS.teamSize.labels,
		RunKind = { "New", "Continue", "Restart" },
		CancelWhy = { "LeftPad", "LeftGame" },
		RunTeam = { "Solo", "Team" },
	}
end

-- Whether `fields` (field name -> value) are exactly the `wanted` fields, each a listed value.
-- `values`: fieldValues(config), when the caller keeps it (it is rebuilt otherwise).
function Analytics.validFields(config: any, wanted: { string }, fields: { [string]: string }, values: { [string]: { string } }?): boolean
	local listed = values or Analytics.fieldValues(config)
	local count = 0
	for _ in fields do
		count += 1
	end
	if count ~= #wanted then
		return false
	end
	for _, field in wanted do
		local value = fields[field]
		if type(value) ~= "string" or not listed[field] or not table.find(listed[field], value) then
			return false
		end
	end
	return true
end

-- Whether event `name` with exactly these fields may go out.
function Analytics.valid(config: any, name: string, fields: { [string]: string }): boolean
	local wanted = Analytics.EVENTS[name]
	return wanted ~= nil and Analytics.validFields(config, wanted, fields)
end

-- The economy (one currency: the team's coins; Robux is counted by Roblox's Monetization pages). A
-- money move is reported only when the code names one of these reasons, so Studio and admin coins
-- never count as income. The reason is the transaction type (Roblox allows 20, custom names allowed).
Analytics.CURRENCY = "Coins"
Analytics.MONEY = {
	Pour = "source", -- a player's own pour (tool or Water Gun)
	Hose = "source", -- the Garden Hose
	Vehicle = "source", -- a vehicle's hose or drop
	Staff = "source", -- the team's staff (no player: flushed to one present member)
	Buildings = "source", -- the team's buildings (same)
	Upgrade = "sink", -- a TAB level of a track or an owned item
	Item = "sink", -- a stand's item
	Gate = "sink", -- an area's gate
	Build = "sink", -- a building on a plot
	BuildingLevel = "sink", -- a TAB level of a building
}
-- Income is summed per player and reason and sent every this many seconds (and on leave): a pour
-- every few seconds would spend the whole budget.
Analytics.INCOME_FLUSH = 300
-- Above this, an amount would arrive as infinity (Roblox stores floats).
Analytics.AMOUNT_MAX = 3.4e38

-- The item SKUs a sink names (Roblox allows 100): track ids, item ids and gate ids.
function Analytics.skus(config: any): { string }
	local list = {}
	for _, track in config.tracks do
		table.insert(list, track.id)
	end
	for _, item in config.items do
		table.insert(list, item.id)
	end
	for _, area in config.areas do
		if area.gate then
			table.insert(list, `gate:{area.id}`)
		end
	end
	return list
end

-- Roblox allows 120 + 20 x players events a minute per server and silently drops the rest. Spend at
-- most `share` of it and keep `protectedShare` of that for funnel steps, purchases and SessionEnd.
Analytics.BUDGET = { share = 0.6, protectedShare = 0.3 }
Analytics.BLOCKED_COOLDOWN = 30 -- seconds: one wall is counted once, not ten times
Analytics.IDLE_AFTER = 60 -- seconds without moving or acting
Analytics.ACT_RECENT = 5 -- seconds a scoop or pour counts as what the player is doing
Analytics.TEXT_MAX = 160 -- characters of a client error or warning kept (the record only)
Analytics.ERRORS_MAX = 5 -- distinct client errors and warnings kept per session, each

-- What a client may report (Telemetry remote): `gap` seconds between accepted reports of a name,
-- `kind` how its one argument is checked (Rules.checkReport). The client decides nothing: the server
-- turns these into events itself.
Analytics.CLIENT = {
	fps = { gap = 50, kind = "fps" }, -- average fps over the last minute of play
	hcOpen = { gap = 0.5, kind = "source" }, -- the honeycomb opened (how)
	hcView = { gap = 0.5, kind = "none" }, -- an upgrade's card showed
	hcClose = { gap = 0.5, kind = "none" },
	short = { gap = 1, kind = "upgrade" }, -- pressed an upgrade the wallet can't pay
	guide = { gap = 0.25, kind = "guideStep" }, -- client/Guide's step (0: hidden)
	guideSkip = { gap = 5, kind = "none" },
	warn = { gap = 2, kind = "text" },
	error = { gap = 2, kind = "text" },
	device = { gap = 5, kind = "device" }, -- how they play (the record only; Roblox breaks down by platform itself)
}
Analytics.DEVICES = { "Touch", "Gamepad", "Mouse" }

-- The rules: decisions over plain values. A wrong answer here doesn't throw, it silently makes a
-- chart lie, so each is spec'd (tests/Analytics.spec).

-- The highest step of `steps` that may be sent now, `sent` already sent: every step up to it is
-- true in `facts`, in order. A false step holds the ones after it (never skipped); never goes back.
function Analytics.advance(steps: { string }, sent: number, facts: { [string]: boolean }): number
	local reached = sent
	for i = sent + 1, #steps do
		if not facts[steps[i]] then
			break
		end
		reached = i
	end
	return reached
end

-- The band label `value` falls in (Analytics.BANDS). NaN lands in the first band.
function Analytics.bucket(bands: Bands, value: number): string
	for i, edge in bands.edges do
		if not (value >= edge) then
			return bands.labels[i]
		end
	end
	return bands.labels[#bands.labels]
end

-- The universal third field: where in the game the player is. The intro, the guide's step while it
-- shows (0: hidden), else the ocean's fill in 5% bands.
function Analytics.stage(phase: string, guideStep: number, fill: number): string
	if phase == "loading" then
		return "Loading"
	elseif phase == "intro" then
		return "Intro"
	elseif guideStep >= 1 and guideStep <= Analytics.GUIDE_STEPS and guideStep % 1 == 0 then
		return `Guide:{guideStep}`
	end
	local percent = math.clamp(math.floor(fill * 20 + 1e-9) * 5, 0, 100)
	return `F{if percent == percent then percent else 0}`
end

export type DoingFacts = {
	phase: string,
	idle: number, -- seconds without moving or acting
	honeycomb: boolean,
	driving: boolean,
	hosing: boolean,
	lastAct: string?, -- "scoop" / "pour"
	lastActAge: number, -- seconds since it
	carried: number,
}

-- What the player was doing (SessionEnd's Doing): the most specific thing that is true.
function Analytics.doing(f: DoingFacts): string
	if f.phase == "loading" then
		return "Loading"
	elseif f.phase == "intro" then
		return "Intro"
	elseif f.phase == "ending" or f.phase == "done" then
		return "Ending"
	elseif f.idle >= Analytics.IDLE_AFTER then
		return "Idle"
	elseif f.honeycomb then
		return "Honeycomb"
	elseif f.driving then
		return "Driving"
	elseif f.hosing then
		return "Hosing"
	elseif f.lastAct == "scoop" and f.lastActAge < Analytics.ACT_RECENT then
		return "Scooping"
	elseif f.lastAct == "pour" and f.lastActAge < Analytics.ACT_RECENT then
		return "Pouring"
	elseif f.carried > 0 then
		return "Carrying"
	end
	return "Roaming"
end

-- Whether one more event may go out this minute, `normal` and `protected` already sent in it, with
-- `players` in the server. Normal events stop at the protected reserve; nothing passes the share.
function Analytics.allowed(normal: number, protected: number, players: number, isProtected: boolean): boolean
	local limit = math.floor((120 + 20 * players) * Analytics.BUDGET.share)
	local reserve = math.ceil(limit * Analytics.BUDGET.protectedShare)
	if normal + protected >= limit then
		return false
	end
	return isProtected or normal < limit - reserve
end

-- A client report's argument, checked (Analytics.CLIENT): the value to use, or nil to drop it. Never
-- trusts the client: numbers are clamped, names must be listed, text is cut and only ever stored in
-- the record (never a Roblox field). Reports without an argument return true.
function Analytics.checkReport(config: any, name: string, arg: any): any
	local rule = Analytics.CLIENT[name]
	if not rule then
		return nil
	end
	local kind = rule.kind
	if kind == "none" then
		return true
	elseif kind == "fps" then
		if type(arg) ~= "number" or arg ~= arg then
			return nil
		end
		return math.clamp(arg, 0, 1000)
	elseif kind == "guideStep" then
		if type(arg) ~= "number" or arg % 1 ~= 0 or arg < 0 or arg > Analytics.GUIDE_STEPS then
			return nil
		end
		return arg
	elseif kind == "source" then
		return if type(arg) == "string" and table.find(Analytics.SOURCES, arg) then arg else nil
	elseif kind == "device" then
		return if type(arg) == "string" and table.find(Analytics.DEVICES, arg) then arg else nil
	elseif kind == "upgrade" then
		return if type(arg) == "string" and table.find(Analytics.skus(config), arg) then arg else nil
	elseif kind == "text" then
		return if type(arg) == "string" then arg:sub(1, Analytics.TEXT_MAX) else nil
	end
	return nil
end

return Analytics
