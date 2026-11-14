-- Session pads (workspace.Lobby.Pads.Pad1..PadN, built in Studio). Each pad Model has a "Zone" part,
-- a "Walls" model (invisible walls on all four sides, so nobody walks on or off) and a sign with
-- "Title" and "Status" labels. Touching a pad's walls from outside is asking to join: if the pad takes
-- you, you are put inside and stay in its queue whatever you do (a member who ends up outside, by a
-- fling or a respawn, is put back) until you press Leave, which puts you out in front of the pad.
-- A pad holds one session:
--   empty       the first player to touch it becomes host and gets the pad screen
--   choosing    one screen: the host either creates a new party (Create Party: a map they unlocked,
--               max players, friends-only) or loads one of their saved runs (Saved Runs); nobody else
--               can get on meanwhile
--   open        a new party: others touch the pad to join (rules in Common.SessionRules); it launches
--               when full or when the host presses Start
--   roster      a saved team run the host loaded: only its team can get on; it launches when they all
--               are (a solo run launches at once)
-- One save per map per team (RunSave.key). A new party whose final team already has a save on its map
-- asks the host at Start: Continue it, or start over (New Game). Starting over a save the host's
-- Saved Runs showed is also New Game ("open" with `replace` = its key; a save on nobody's list, every
-- member having left it, is found when the host presses Create and asked about then); it is erased at
-- launch (RunStore.erase: never while a server has it open). The host's confirm is enough; each member
-- of that save's team is told when they join (toast and HostBar). Delete on a card erases a solo run;
-- a team run only leaves the player's list (D5's Leave run), so one member can't wipe the others'
-- progress. At launch the lobby checks the run, counts the party down (SessionRules.COUNTDOWN seconds,
-- SessionState "countdown"; Leave works meanwhile and stops it, and New Game's erase waits until the
-- count is done), writes a run ticket and teleports the party into a fresh reserved
-- gameplay server behind the teleport screen (SessionState "teleporting", common/Transition: "fresh"
-- for a run that opens on the intro, else "return"); a launch that fails keeps the party on the pad
-- and the screen opens again. Each pad Model carries State (SessionRules.padState) and LaunchAt (the
-- countdown's end, server time; 0 when none) for the clients' looks (client/Pads). Clients only send
-- SessionAction("open" | "leave" | "start" | "load" | "delete" | "continue" | "restart");
-- everything is checked here.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")
local UserService = game:GetService("UserService")

local Maps = require(ReplicatedStorage.Common.Maps)
local Places = require(ReplicatedStorage.Common.Places)
local Retry = require(ReplicatedStorage.Common.Retry)
local RunSave = require(ReplicatedStorage.Common.RunSave)
local RunStore = require(ReplicatedStorage.Common.RunStore)
local RunTicket = require(ReplicatedStorage.Common.RunTicket)
local SessionRules = require(ReplicatedStorage.Common.SessionRules)
local Transition = require(ReplicatedStorage.Common.Transition)
local Config = require(ServerStorage.GameplayShared.Config)
local Water = require(ServerStorage.GameplayShared.Water)
local Profiles = require(script.Parent.Profiles)
local Telemetry = require(script.Parent.Telemetry)

local POLL = 0.25
local COOLDOWN = 4 -- after a launch, before anyone left on the pad is put out
local SCREEN_SLACK = 0.4 -- seconds past the teleport screen's out (Transition.OUT_SECONDS) for a slow client
local ACTIONS_PER_SECOND = 4
local ACTIONS = { open = true, leave = true, start = true, load = true, delete = true, continue = true, restart = true }
-- Pad space (the Zone's): half-sizes from its centre. The walls' inner faces are at INSIDE, members
-- pulled back in land within KEEP, an outsider whose root is within TOUCH is touching the walls (the
-- walls are 1 thick and a character's root sits about a stud from its front), and Leave puts you at
-- EXIT in front of the pad (+Z, toward the spawn). STAND is a standing root's height.
local INSIDE = 6.5
local KEEP = 5
local TOUCH = 9.5
local EXIT = 12
local STAND = 3.5
local LOW, HIGH = -4, 20
local SAVED_RETRY = 30 -- seconds before a saved-runs list with a failed read is read again

local Queue = {}

-- One of the host's saved runs as loaded for the Saved Runs panel.
type SavedRun = { key: string, save: RunSave.Save?, problem: string? }

-- The teleport screen a launching party leaves behind (common/Transition) and its card.
type Arrival = { look: Transition.Look, mapName: string, fill: number }

type Pad = {
	name: string,
	model: Model,
	zone: BasePart,
	title: TextLabel,
	status: TextLabel,
	host: Player?,
	settings: SessionRules.Settings?,
	roster: { key: string, mapId: string, members: { number } }?, -- a saved team run being loaded
	replaceKey: string?, -- New Game: the host's saved run this party may start over
	continueKey: string?, -- the team's save the host chose to continue at Start
	asked: { key: string, save: RunSave.Save }?, -- the team's save Start found and asked the host about
	held: boolean, -- a launch failed or asked: no launch on full until the members change or Start
	startsOver: { members: { number }, percent: number }?, -- that save's team and fill, for the notice
	checking: boolean, -- Create is looking for the team's save (openParty)
	offered: { key: string, save: RunSave.Save }?, -- a save Create found and asked the host to replace
	members: { Player }, -- join order, host included
	told: { [Player]: string },
	friends: { [number]: boolean | "pending" }, -- host-friend lookups for this session
	saved: { SavedRun }?, -- the host's saved runs; nil while they load
	savedError: string?,
	savedToken: number, -- bumped per load so a stale load is dropped
	savedLoading: boolean, -- a load for this host is running
	launching: boolean,
	counting: boolean, -- the launch countdown is running (Leave works meanwhile)
}

local remotes: { [string]: RemoteEvent } = {}
local pads: { Pad } = {}
local lastSent: { [Player]: string } = {}
local actionWindow: { [Player]: { start: number, count: number } } = {}
local deleting: { [Player]: boolean } = {} -- a Delete is running for this player
local names: { [number]: string } = {} -- display names of saved-run members, by user id
-- Each player's saved runs as last read, reused while their profile is unchanged (Profiles.revision:
-- Delete, New Game, a profile reset) and they haven't launched, or for SAVED_RETRY after a failed
-- read, so hopping between pads can't burn the lobby's DataStore read budget.
local savedCache: { [Player]: { revision: number, runs: { SavedRun }, at: number, failed: boolean } } = {}

local function tell(player: Player, text: string)
	remotes.Notice:FireClient(player, text)
end

-- Tells a player something once per stay on the pad (the key changes when the reason changes).
local function tellOnce(pad: Pad, player: Player, key: string, text: string)
	if pad.told[player] ~= key then
		pad.told[player] = key
		tell(player, text)
	end
end

local function padParts(model: Model)
	local zone = model:FindFirstChild("Zone")
	local title = model:FindFirstChild("Title", true)
	local status = model:FindFirstChild("Status", true)
	local walls = model:FindFirstChild("Walls")
	assert(zone and zone:IsA("BasePart"), `{model:GetFullName()} is missing its Zone part`)
	assert(title and title:IsA("TextLabel"), `{model:GetFullName()} is missing its Title label`)
	assert(status and status:IsA("TextLabel"), `{model:GetFullName()} is missing its Status label`)
	assert(walls, `{model:GetFullName()} is missing its Walls (four invisible walls around the Zone, built in Studio)`)
	local solid = 0
	for _, wall in walls:GetChildren() do
		if wall:IsA("BasePart") and wall.CanCollide then
			solid += 1
		end
	end
	assert(solid >= 4, `{model:GetFullName()}.Walls needs four CanCollide parts, one per side`)
	return zone, title, status
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Where a player's root is in the pad's space, or nil without a character.
local function spotOf(pad: Pad, player: Player): Vector3?
	local root = rootOf(player)
	return if root then pad.zone.CFrame:PointToObjectSpace(root.Position) else nil
end

local function within(at: Vector3, half: number): boolean
	return math.abs(at.X) <= half and math.abs(at.Z) <= half and at.Y >= LOW and at.Y <= HIGH
end

-- Moves a player's character so its root stands at `at` (pad space), facing `facing` (pad space) or
-- the way it faced.
local function place(pad: Pad, player: Player, at: Vector3, facing: Vector3?)
	local character = player.Character
	local root = rootOf(player)
	if not character or not root then
		return
	end
	local world = pad.zone.CFrame:PointToWorldSpace(at)
	local look = if facing then pad.zone.CFrame:VectorToWorldSpace(facing) else root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.01 then
		look = pad.zone.CFrame:VectorToWorldSpace(Vector3.zAxis)
	end
	character:PivotTo(CFrame.lookAt(world, world + look))
	root.AssemblyLinearVelocity = Vector3.zero
end

-- Onto the pad, as near as the walls allow to where they are.
local function pullIn(pad: Pad, player: Player)
	local at = spotOf(pad, player)
	if at then
		place(pad, player, Vector3.new(math.clamp(at.X, -KEEP, KEEP), STAND, math.clamp(at.Z, -KEEP, KEEP)))
	end
end

-- Out in front of the pad, facing away from it.
local function putOut(pad: Pad, player: Player)
	local at = spotOf(pad, player)
	if at then
		place(pad, player, Vector3.new(math.clamp(at.X, -KEEP, KEEP), STAND, EXIT), Vector3.zAxis)
	end
end

local function isMember(pad: Pad, player: Player): boolean
	return table.find(pad.members, player) ~= nil
end

local function padOf(player: Player): Pad?
	for _, pad in pads do
		if isMember(pad, player) then
			return pad
		end
	end
	return nil
end

-- What the player is doing on a pad, for lobby Telemetry's SessionEnd Doing: "Countdown" (the 3-2-1 or
-- the launch), "Choosing" (hosting, the pad screen open), "Waiting" (in a set-up party); nil off the pads.
function Queue.doingOf(player: Player): string?
	local pad = padOf(player)
	if not pad then
		return nil
	elseif pad.counting or pad.launching then
		return "Countdown"
	elseif pad.host == player and not pad.settings and not pad.roster then
		return "Choosing"
	end
	return "Waiting"
end

local function reset(pad: Pad)
	pad.host, pad.settings, pad.roster, pad.replaceKey, pad.startsOver = nil, nil, nil, nil, nil
	pad.continueKey, pad.asked, pad.held = nil, nil, false
	pad.checking, pad.offered = false, nil
	pad.members = {}
	pad.friends = {}
	pad.saved, pad.savedError = nil, nil
	pad.savedToken += 1
	pad.savedLoading = false
end

local function userIds(players: { Player }): { number }
	local ids = {}
	for _, p in players do
		table.insert(ids, p.UserId)
	end
	return ids
end

local function mapName(mapId: string): string
	local map = Maps.get(mapId)
	return if map then map.name else mapId
end


-- Fills `names` for saved-run members who aren't in this server (it yields). On failure the cards
-- fall back to "Player <id>" and the Output says why.
local function lookUpNames(ids: { number })
	local unknown = {}
	for _, id in ids do
		local p = Players:GetPlayerByUserId(id)
		if p then
			names[id] = p.DisplayName
		elseif not names[id] and not table.find(unknown, id) then
			table.insert(unknown, id)
		end
	end
	if #unknown == 0 then
		return
	end
	local ok, result = Retry.run("look up names", function()
		return UserService:GetUserInfosByUserIdsAsync(unknown)
	end, 2, 1)
	if not ok then
		warn(`[Queue] couldn't look up saved-run names: {result}`)
		return
	end
	for _, info in result do
		names[info.Id] = info.DisplayName
	end
end

local function namesOf(ids: { number }): string
	local list = {}
	for _, id in ids do
		local p = Players:GetPlayerByUserId(id)
		table.insert(list, if p then p.DisplayName else names[id] or `Player {id}`)
	end
	return table.concat(list, ", ")
end

-- Loads the host's saved runs for the Saved Runs panel, in the background (it yields), or reuses
-- their cached list (savedCache).
local function loadSaved(pad: Pad, host: Player)
	if pad.saved or pad.savedLoading then
		return
	end
	local revision = Profiles.revision(host)
	local cached = savedCache[host]
	if cached and cached.revision == revision and (not cached.failed or os.clock() - cached.at < SAVED_RETRY) then
		pad.saved, pad.savedError = cached.runs, nil
		return
	end
	pad.savedToken += 1
	local token = pad.savedToken
	pad.savedLoading = true
	task.spawn(function()
		local data = Profiles.get(host)
		local runs: { SavedRun } = {}
		local problem: string? = nil
		if not data then
			problem = "Couldn't load your saved runs. Rejoin to try again."
		else
			local ids = {}
			local failed = false
			for _, key in data.runs do
				local save, err = RunStore.load(key)
				if err then
					warn(`[Queue] couldn't load run {key} for {host.Name}: {err}`)
					failed = true
				end
				table.insert(runs, {
					key = key,
					save = save,
					problem = if err then "Couldn't load this run." elseif not save then "Not saved yet." else nil,
				})
				if save then
					table.move(save.members, 1, #save.members, #ids + 1, ids)
				end
			end
			lookUpNames(ids)
			if host.Parent and Profiles.revision(host) == revision then
				savedCache[host] = { revision = revision, runs = runs, at = os.clock(), failed = failed }
			end
		end
		if pad.savedToken == token then
			pad.saved, pad.savedError = runs, problem
			pad.savedLoading = false
		end
	end)
end

-- How full a save's ocean is: the same fill the gameplay server shows, the curve with the map's water
-- multiplier on top.
local function fillOf(save: RunSave.Save, map: Maps.Map): number
	return Water.fill(save.current / map.waterMultiplier, Config.ocean, #save.members)
end

-- The teleport screen for a run about to open (nil save: a new or erased one): "fresh" if it opens
-- on the intro (the gameplay server's rule, RunSave.wantsIntro), which ends on black; "return" with
-- the run's map and fill if it goes straight into play.
local function arrivalOf(save: RunSave.Save?, mapId: string): Arrival
	if not save or RunSave.wantsIntro(save) then
		return { look = "fresh", mapName = mapName(mapId), fill = 0 }
	end
	local map = Maps.get(save.mapId)
	return { look = "return", mapName = mapName(save.mapId), fill = if map then fillOf(save, map) else 0 }
end

-- What one Saved Runs card shows, and whether its Load button works with these players on the pad.
-- mapId and memberIds let the Create panel find the save a New Game would start over.
local function savedCard(run: SavedRun, padIds: { number }): { [string]: any }
	local save = run.save
	local card = {
		key = run.key,
		mapId = "",
		mapName = "",
		members = "",
		memberIds = {},
		teamSize = 0,
		fill = 0,
		lastPlayed = 0,
		canLoad = false,
		reason = run.problem or "",
	}
	if not save then
		return card
	end
	local map = Maps.get(save.mapId)
	card.mapId = save.mapId
	card.mapName = mapName(save.mapId)
	card.members = namesOf(save.members)
	card.memberIds = save.members
	card.teamSize = #save.members
	card.lastPlayed = save.updatedAt
	if not map then
		card.reason = "This map isn't in the game any more."
		return card
	end
	-- The same fill the gameplay server shows, the curve, with the map's water multiplier on top.
	card.fill = fillOf(save, map)
	if save.finished then
		card.reason = "This ocean is full. Run complete!"
		return card
	end
	local reason, who = SessionRules.loadError(save.members, padIds)
	if reason == "missing" then
		-- the host alone chooses; Load opens the pad to the rest of the team
		card.canLoad = table.find(save.members, padIds[1]) ~= nil
		card.reason = if card.canLoad then `Load, then {namesOf(who)} can get on` else "Only that run's team can load it."
	elseif reason == "extra" then
		card.reason = `{namesOf(who)} must leave the pad`
	else
		card.reason = "Ready to go!"
		card.canLoad = true
	end
	return card
end

-- What the host's client shows while choosing: both panels, the saved runs as cards (nil while they
-- load) and who is on the pad (padIds: the host alone; nobody else can get on while they choose).
local function hostView(pad: Pad): { [string]: any }
	local host = pad.host :: Player
	local ids = userIds(pad.members)
	local cards = nil
	if pad.saved then
		cards = {}
		for _, run in pad.saved do
			table.insert(cards, savedCard(run, ids))
		end
	end
	return { kind = "choose", unlocked = Profiles.unlockedMaps(host), padIds = ids, runs = cards, error = pad.savedError }
end

-- Friends-only: is this player friends with the host? Looked up in the background (it yields).
local function hostFriend(pad: Pad, player: Player): boolean?
	local host = pad.host
	if not host then
		return false
	end
	local cached = pad.friends[player.UserId]
	if cached == "pending" then
		return nil
	elseif cached ~= nil then
		return cached :: boolean
	end
	pad.friends[player.UserId] = "pending"
	local hostId = host.UserId
	task.spawn(function()
		local ok, result = pcall(function()
			return player:IsFriendsWith(hostId)
		end)
		if not ok then
			warn(`[Queue] friend check failed for {player.Name}: {result}`)
		end
		if pad.host and pad.host.UserId == hostId then
			pad.friends[player.UserId] = ok and result == true
		end
	end)
	return nil
end

-- What each player's client should show; sent only when it changes.
local function sendState(player: Player, state: { [string]: any })
	local key = HttpService:JSONEncode(state)
	if lastSent[player] ~= key then
		lastSent[player] = key
		remotes.SessionState:FireClient(player, state)
	end
end

-- The pad's look for every client (client/Pads): State (SessionRules.padState) and LaunchAt (the
-- countdown's end in server time, 0 when none), each written only when it changes.
local function publish(pad: Pad, launchAt: number?)
	local settings = pad.settings
	local state = SessionRules.padState({
		host = pad.host ~= nil,
		saved = pad.roster ~= nil,
		maxPlayers = if settings then settings.maxPlayers else nil,
		friendsOnly = settings ~= nil and settings.friendsOnly,
		count = #pad.members,
		counting = pad.counting,
		launching = pad.launching,
	})
	if pad.model:GetAttribute("State") ~= state then
		pad.model:SetAttribute("State", state)
	end
	local at = launchAt or 0
	if pad.model:GetAttribute("LaunchAt") ~= at then
		pad.model:SetAttribute("LaunchAt", at)
	end
end

-- Counts a checked party down on its pad before it goes (SessionRules.COUNTDOWN seconds; clients show
-- it from SessionState "countdown" and the pad's LaunchAt). Leave works meanwhile (onAction). Returns
-- false, telling whoever is left why, as soon as anyone in the party leaves the pad or the game.
local function countdown(pad: Pad, party: { Player }, title: string): boolean
	local endsAt = workspace:GetServerTimeNow() + SessionRules.COUNTDOWN
	pad.counting = true
	publish(pad, endsAt)
	Telemetry.countdown(party)
	for _, p in party do
		sendState(p, { kind = "countdown", title = title, endsAt = endsAt })
	end
	local gone: Player? = nil
	while not gone do
		for _, p in party do
			if not p.Parent or not isMember(pad, p) then
				gone = p
				break
			end
		end
		local left = endsAt - workspace:GetServerTimeNow()
		if gone or left <= 0 then
			break
		end
		pad.status.Text = `Starting in {math.ceil(left)}...`
		task.wait(0.1)
	end
	pad.counting = false
	publish(pad)
	if gone then
		Telemetry.countdownCancelled(party, gone)
		for _, p in pad.members do
			if p.Parent and p ~= gone then
				tell(p, `Countdown stopped: {gone.DisplayName} left.`)
			end
		end
		return false
	end
	pad.status.Text = "Starting..."
	return true
end

-- Sends the party to a fresh reserved gameplay server. prepare re-checks the run (it may yield) and
-- returns the ticket, its teleport screen and what can't be undone (commit: New Game's erase, run
-- after the countdown; it returns what to tell the party, or nil), or nil plus what to tell the party
-- (nil: it asked the host something instead). A checked party is counted down (countdown) first.
-- Each client covers the lobby with the screen (SessionState "teleporting")
-- before the teleport, and it rides the hop. A launch that doesn't go keeps the party on the pad,
-- held (no launch on full until the members change or the host presses Start; their next state
-- opens the screen again); one that goes puts out whoever is still here after COOLDOWN. A stopped
-- countdown isn't held: the party changed. `kind`: what the launch starts (analytics: New, Continue
-- or Restart), read once prepare has decided it.
local function launch(
	pad: Pad,
	party: { Player },
	title: string,
	prepare: () -> (RunTicket.Ticket?, string?, Arrival?, (() -> string?)?),
	kind: () -> string
)
	pad.launching = true
	publish(pad)
	pad.title.Text = title
	pad.status.Text = "Starting..."
	for _, p in party do
		sendState(p, { kind = "launching", title = title })
	end
	local ticket, problem, arrival, commit = prepare()
	local stopped = false
	if ticket then
		stopped = not countdown(pad, party, title)
		if stopped then
			ticket = nil
		elseif commit then
			problem = commit()
			if problem then
				ticket = nil
			end
		end
	end
	if ticket then
		Telemetry.partyStarted(party, kind())
		local screen = arrival :: Arrival
		for _, p in party do
			if p.Parent then
				sendState(p, { kind = "teleporting", title = title, look = screen.look, mapName = screen.mapName, fill = screen.fill })
			end
		end
		task.wait(Transition.OUT_SECONDS + SCREEN_SLACK)
	end
	-- the launch may have erased, started or forgotten a run: read their lists again next time
	for _, p in party do
		savedCache[p] = nil
	end
	local sent = false
	if not ticket then
		for _, p in party do
			if p.Parent and problem then
				tell(p, problem)
			end
		end
	elseif RunService:IsStudio() then
		for _, p in party do
			tell(p, "Teleports only work in the published game. In Studio, test runs in the gameplay place.")
		end
	else
		local serverId = HttpService:GenerateGUID(false)
		local ok, err = RunTicket.write(serverId, ticket)
		if ok then
			local options = Instance.new("TeleportOptions")
			options.ReservedServerId = serverId
			ok, err = Retry.run("teleport party", function()
				TeleportService:TeleportAsync(Places.GAMEPLAY, party, options)
			end, 3, 1)
		end
		if ok then
			Telemetry.teleported(party)
			sent = true
		else
			warn(`[Queue] launch failed on {pad.name}: {err}`)
			for _, p in party do
				tell(p, "Couldn't start the run. Press Start to try again.")
			end
		end
	end
	if sent then
		task.wait(COOLDOWN)
		for _, p in party do
			-- still here: a slow or failed teleport (TeleportInitFailed tells them)
			if p.Parent then
				putOut(pad, p)
				sendState(p, { kind = "none" })
			end
		end
		reset(pad)
	else
		pad.held = not stopped
		for _, p in party do
			lastSent[p] = nil -- update sends their pad state again
		end
	end
	pad.launching = false
	publish(pad)
end

-- Taking the lock proves no server has the run open; it is handed straight back (1 s) so the
-- gameplay server can take it when the party arrives. Returns what to tell the party, or nil.
local function probeLock(key: string): string?
	local probe = HttpService:GenerateGUID(false)
	local free, lockErr = RunStore.lock(key, probe)
	if not free then
		warn(`[Queue] run {key} can't be locked: {lockErr}`)
		return "This run is already open in another server. Try again in a minute."
	end
	local released, unlockErr = RunStore.unlock(key, probe)
	if not released then
		warn(`[Queue] couldn't release the check lock on {key}: {unlockErr}`)
		return "Couldn't start the run. Please try again in a minute."
	end
	return nil
end

-- A new party (Create Party): the same team on the same map always gets the same run key. A team that
-- already has a save there (one that was played: RunSave.isBlank) doesn't launch until the host
-- chooses (SessionState "existing"): Continue (continueKey) loads it as it is; Start over (replaceKey,
-- also New Game's confirmed save) erases it here, under its lock, and its key leaves every member's
-- list (Progress.forgetRun, so the fresh run's ending pays again), even when it is already blank (an
-- earlier try erased it); the launch stops if any member's list can't be updated, and pressing Start
-- again is safe. If the final team isn't the chosen one, its save is untouched and the host is asked
-- about the new team's.
local function launchParty(pad: Pad)
	local settings = pad.settings :: SessionRules.Settings
	local replaceKey, continueKey = pad.replaceKey, pad.continueKey
	local host = pad.host
	local party = table.clone(pad.members)
	local members = userIds(party)
	local kind = "New"
	launch(pad, party, mapName(settings.mapId), function()
		local key = RunSave.key(settings.mapId, members)
		local save, err = RunStore.load(key)
		if err then
			warn(`[Queue] couldn't check run {key} before a new party: {err}`)
			return nil, "Couldn't start the run. Please try again."
		end
		local played = save ~= nil and not RunSave.isBlank(save)
		if save and played and key ~= replaceKey and (key ~= continueKey or save.finished) then
			pad.asked = { key = key, save = save }
			local map = Maps.get(settings.mapId) :: Maps.Map
			if host and host.Parent then
				remotes.SessionState:FireClient(host, {
					kind = "existing",
					key = key,
					mapName = map.name,
					percent = math.floor(math.clamp(fillOf(save, map), 0, 1) * 100),
					finished = save.finished,
				})
			end
			return nil, nil
		end
		if played and key == continueKey then
			local problem = probeLock(key)
			if problem then
				return nil, problem
			end
		end
		-- Start over: erased after the countdown (a stopped one leaves the save as it was), so what
		-- opens is the blank it leaves
		local commit: (() -> string?)? = nil
		if key == replaceKey then
			commit = function(): string?
				if save and played then
					local erased, eraseErr, open = RunStore.erase(key)
					if not erased then
						warn(`[Queue] couldn't erase run {key} for a New Game: {eraseErr}`)
						return if open then "That run is open in another server. Try again in a minute." else "Couldn't start over. Please try again."
					end
				end
				for _, p in party do
					local forgot, forgetErr = Profiles.forgetRun(p, key)
					if not forgot then
						warn(`[Queue] erased run {key} is still listed for {p.Name}: {forgetErr}`)
						return "Couldn't start over. Please try again."
					end
				end
				return nil
			end
		end
		local opens = if key == replaceKey then nil else save
		kind = if key == replaceKey then "Restart" elseif played then "Continue" else "New"
		return { mapId = settings.mapId, key = key, members = members }, nil, arrivalOf(opens, settings.mapId), commit
	end, function()
		return kind
	end)
end

-- The saved run the host loaded, with its team on the pad. Everything the card showed is checked again
-- here: the save exists, isn't finished, is exactly this team, and no server has it open.
local function launchSaved(pad: Pad, key: string)
	local party = table.clone(pad.members)
	launch(pad, party, "Loading a run", function()
		local save, err = RunStore.load(key)
		if err then
			warn(`[Queue] couldn't load run {key} at launch: {err}`)
			return nil, "Couldn't load that run. Please try again."
		elseif not save then
			return nil, "That run has no save yet."
		elseif save.finished then
			return nil, "That ocean is already full."
		elseif not Maps.get(save.mapId) then
			return nil, "That map isn't in the game any more."
		elseif not RunSave.sameTeam(save, userIds(party)) then
			return nil, "Only that run's exact team can load it."
		end
		local problem = probeLock(key)
		if problem then
			return nil, problem
		end
		return { mapId = save.mapId, key = key, members = save.members }, nil, arrivalOf(save, save.mapId)
	end, function()
		return "Continue"
	end)
end

-- Delete on a Saved Runs card. A solo run (or a listed key with no save) is erased (RunStore.erase:
-- never while a server has it open) and forgotten; a team run only leaves this player's list (D5's
-- Leave run): the others keep it.
local function deleteRun(pad: Pad, player: Player, key: string)
	deleting[player] = true
	-- the busy flag is cleared even if the work throws; the error is raised again after
	local ran, solo, ok, err, open = pcall(function()
		local save, loadErr = RunStore.load(key)
		local isSolo = save == nil or (#save.members == 1 and save.members[1] == player.UserId)
		if loadErr then
			return isSolo, false, loadErr, false
		end
		local done, doneErr, isOpen = true, nil, false
		if save and isSolo then
			done, doneErr, isOpen = RunStore.erase(key)
		end
		if done and isSolo then
			done, doneErr = Profiles.forgetRun(player, key)
		elseif done then
			done, doneErr = Profiles.leaveRun(player, key)
		end
		return isSolo, done, doneErr, isOpen
	end)
	deleting[player] = nil
	savedCache[player] = nil
	if not ran then
		error(solo, 0)
	end
	if not ok then
		warn(`[Queue] {player.Name} couldn't delete run {key}: {err}`)
		tell(player, if open then "That run is open in a server right now. Try again in a minute." else "Couldn't delete that run. Please try again.")
		return
	end
	tell(player, if solo then "Run deleted." else "You left that run. It stays saved for the others.")
	Telemetry.runDeleted(player, solo)
	if pad.host == player and pad.saved then
		for i, run in pad.saved do
			if run.key == key then
				table.remove(pad.saved, i)
				break
			end
		end
	end
end

-- Is key one of this player's saved runs? (Load, Delete and New Game only take keys from the
-- player's own list.)
local function ownsRun(player: Player, key: unknown): boolean
	local data = Profiles.get(player)
	return type(key) == "string" and data ~= nil and table.find(data.runs, key) ~= nil
end

-- New Game: how full the save this party starts over is, for a member of its team (nil for anyone
-- else: it isn't theirs).
local function startsOverFor(pad: Pad, player: Player): number?
	local info = pad.startsOver
	return if info and table.find(info.members, player.UserId) then info.percent else nil
end

-- The host's party is set up (replace: the confirmed save it starts over, or nil).
local function openParty(pad: Pad, player: Player, settings: SessionRules.Settings, map: Maps.Map, replace: string?, replaced: RunSave.Save?)
	pad.settings = settings
	pad.replaceKey = replace
	pad.startsOver = if replaced
		then { members = replaced.members, percent = math.floor(math.clamp(fillOf(replaced, map), 0, 1) * 100) }
		else nil
	pad.offered = nil
	Telemetry.lobby(player, "NewRun")
	if settings.maxPlayers == 1 then
		tell(player, "Starting your solo run!")
	end
end

-- Create without New Game: the team on the pad may still have a save on this map that is on nobody's
-- Saved Runs (every member left it), so the client couldn't ask. It is looked up here (it yields); if
-- there is one, the host is asked to replace it (SessionState "replace") and their Yes comes back as
-- a New Game for that key (pad.offered).
local function checkAndOpen(pad: Pad, player: Player, settings: SessionRules.Settings, map: Maps.Map)
	local team = SessionRules.newTeam(settings.maxPlayers, userIds(pad.members))
	if team then
		local token = pad.savedToken
		pad.checking = true
		local key = RunSave.key(settings.mapId, team)
		local save, err = RunStore.load(key)
		if pad.savedToken ~= token then
			return -- the pad was reset meanwhile
		end
		pad.checking = false
		if pad.host ~= player or pad.settings or pad.launching then
			return
		end
		if err then
			warn(`[Queue] couldn't check run {key} before a new party: {err}`)
			tell(player, "Couldn't check for an old run. Please try again.")
			return
		end
		if save and not RunSave.isBlank(save) then
			pad.offered = { key = key, save = save }
			remotes.SessionState:FireClient(player, {
				kind = "replace",
				key = key,
				mapName = map.name,
				percent = math.floor(math.clamp(fillOf(save, map), 0, 1) * 100),
			})
			return
		end
	end
	openParty(pad, player, settings, map, nil, nil)
end

local function updateSign(pad: Pad)
	local settings, roster = pad.settings, pad.roster
	if not pad.host then
		pad.title.Text = "Open Pad"
		pad.status.Text = "Touch to host"
	elseif roster then
		pad.title.Text = mapName(roster.mapId)
		pad.status.Text = `{#pad.members}/{#roster.members} - Saved team`
	elseif not settings then
		pad.title.Text = "Setting up..."
		pad.status.Text = (pad.host :: Player).DisplayName
	else
		pad.title.Text = mapName(settings.mapId)
		pad.status.Text = `{#pad.members}/{settings.maxPlayers}{if settings.friendsOnly then " - Friends" else " - Join!"}`
	end
	publish(pad)
end

-- Takes a member off the pad (Leave, or they left the game); the earliest one left hosts.
local function drop(pad: Pad, player: Player)
	local i = table.find(pad.members, player)
	if not i then
		return
	end
	table.remove(pad.members, i)
	pad.held = false
	pad.told[player] = nil
	if player == pad.host then
		local nextId = SessionRules.nextHost(userIds(pad.members), player.UserId)
		pad.host = if nextId then Players:GetPlayerByUserId(nextId) else nil
		if pad.host and (pad.settings or pad.roster) then
			tell(pad.host, "You're the host now. Press Start when everyone's ready.")
		end
		pad.friends = {}
	end
	if #pad.members == 0 then
		reset(pad)
	end
	if player.Parent then
		sendState(player, { kind = "none" })
	end
end

-- Why the pad won't take this player now: nil (it will), "wait" (their data or a friend check is
-- still loading) or the words to tell them.
local function refusal(pad: Pad, player: Player): string?
	local host = pad.host
	if not host then
		return if player:GetAttribute("DataReady") then nil else "wait"
	end
	local roster = pad.roster
	if roster then
		return if table.find(roster.members, player.UserId) then nil else `This pad is only for {host.DisplayName}'s saved team.`
	end
	local settings = pad.settings
	if not settings then
		return `{host.DisplayName} is setting up this pad.`
	end
	local friend = if settings.friendsOnly then hostFriend(pad, player) else false
	if friend == nil then
		return "wait"
	end
	local reason = SessionRules.joinError(settings, #pad.members, friend)
	if reason == "full" then
		return "This session is full."
	elseif reason == "friends" then
		return "This session is friends only."
	end
	return nil
end

-- touching: players on no pad whose root is at this pad's walls (nearest pad only).
local function update(pad: Pad, touching: { Player })
	if pad.launching then
		for _, p in touching do
			tellOnce(pad, p, "launching", "This pad is starting a run.")
		end
		return
	end

	for i = #pad.members, 1, -1 do
		local p = pad.members[i]
		if not p.Parent then
			drop(pad, p)
		end
	end
	for p in pad.told do
		if not isMember(pad, p) and not table.find(touching, p) then
			pad.told[p] = nil
		end
	end

	-- Touching the walls asks to join: the first player on an empty pad hosts and gets the pad
	-- screen (their saved runs load); others join if the pad takes them. Whoever it takes is put on
	-- it; anyone else is told why (and put out, if they got in somehow).
	for _, p in touching do
		local why = refusal(pad, p)
		if why == nil then
			if not pad.host then
				pad.host = p
				pad.members = { p }
				pad.settings = nil
				pad.told[p] = "host"
				Telemetry.lobby(p, "Hosted")
				loadSaved(pad, p)
			else
				table.insert(pad.members, p)
				pad.held = false
				Telemetry.lobby(p, "JoinedParty")
				Telemetry.lobby(p, "InParty")
				local host = (pad.host :: Player).DisplayName
				local settings = pad.settings
				local percent = startsOverFor(pad, p)
				local note = if percent and settings
					then ` This party starts over your saved run on {mapName(settings.mapId)} ({percent}% filled).`
					else ""
				tellOnce(pad, p, "joined", if pad.roster then `Joined {host}'s saved run!` else `Joined {host}'s session!{note}`)
			end
			pullIn(pad, p)
		elseif why ~= "wait" then
			tellOnce(pad, p, why, why)
			local at = spotOf(pad, p)
			if at and within(at, INSIDE) then
				putOut(pad, p)
			end
		end
	end

	-- Members stay on the pad whatever they do (a fling, a respawn): only Leave takes them off.
	for _, p in pad.members do
		local at = spotOf(pad, p)
		if at and not within(at, INSIDE + 0.5) then
			pullIn(pad, p)
		end
	end

	-- Tell each member's client what to show.
	local settings, roster = pad.settings, pad.roster
	for _, p in pad.members do
		if p == pad.host and not settings and not roster then
			sendState(p, hostView(pad))
		elseif settings or roster then
			local waiting = ""
			if roster then
				local reason, missing = SessionRules.loadError(roster.members, userIds(pad.members))
				waiting = if reason == "missing" then namesOf(missing) else ""
			end
			sendState(p, {
				kind = if p == pad.host then "hosting" else "member",
				host = (pad.host :: Player).DisplayName,
				count = #pad.members,
				max = if roster then #roster.members else (settings :: SessionRules.Settings).maxPlayers,
				mapName = mapName(if roster then roster.mapId else (settings :: SessionRules.Settings).mapId),
				friendsOnly = settings ~= nil and settings.friendsOnly,
				startsOver = startsOverFor(pad, p),
				saved = roster ~= nil,
				waiting = waiting,
			})
		end
	end

	updateSign(pad)
	if pad.held then
		return
	elseif settings and SessionRules.isFull(settings, #pad.members) then
		task.spawn(launchParty, pad)
	elseif roster and SessionRules.loadError(roster.members, userIds(pad.members)) == nil then
		task.spawn(launchSaved, pad, roster.key)
	end
end

local function rateLimited(player: Player): boolean
	local now = os.clock()
	local w = actionWindow[player]
	if not w or now - w.start >= 1 then
		w = { start = now, count = 0 }
		actionWindow[player] = w
	end
	w.count += 1
	return w.count > ACTIONS_PER_SECOND
end

local function onAction(player: Player, action: unknown, payload: unknown)
	if type(action) ~= "string" or not ACTIONS[action] or rateLimited(player) then
		return
	end
	local pad = padOf(player)
	if not pad then
		return
	end
	if pad.launching then
		-- only Leave, and only during the countdown, which stops when it sees the party change
		if action == "leave" and pad.counting then
			drop(pad, player)
			putOut(pad, player)
		end
		return
	end
	if action == "leave" then
		drop(pad, player)
		putOut(pad, player)
		return
	end
	if pad.host ~= player then
		return
	end
	local settings, roster = pad.settings, pad.roster
	local choosing = not settings and not roster
	if action == "open" and choosing and not pad.checking then
		local chosen = SessionRules.validate(payload, Profiles.unlockedMaps(player))
		local replace = if type(payload) == "table" then (payload :: any).replace else nil
		-- New Game only starts over a save the host's Saved Runs showed, or the one Create just found
		-- for this team and asked about (pad.offered), on the party's map
		local replaced: RunSave.Save? = nil
		if replace ~= nil and pad.saved and ownsRun(player, replace) then
			for _, run in pad.saved do
				if run.key == replace then
					replaced = run.save
					break
				end
			end
		end
		local offered = pad.offered
		if replace ~= nil and not replaced and offered and offered.key == replace then
			replaced = offered.save
		end
		local map = chosen and Maps.get(chosen.mapId)
		if replace ~= nil and deleting[player] then
			tell(player, "Wait for the delete to finish.")
		elseif chosen and map and replace == nil then
			task.spawn(checkAndOpen, pad, player, chosen, map)
		elseif chosen and map and replaced and replaced.mapId == chosen.mapId then
			openParty(pad, player, chosen, map, replace, replaced)
		else
			tell(player, "Those settings aren't allowed.")
		end
	elseif action == "start" and settings then
		task.spawn(launchParty, pad)
	elseif action == "start" and roster then
		local reason, missing = SessionRules.loadError(roster.members, userIds(pad.members))
		if reason == "missing" then
			tell(player, `Waiting for {namesOf(missing)}.`)
		else
			task.spawn(launchSaved, pad, roster.key)
		end
	elseif (action == "continue" or action == "restart") and settings and pad.asked and pad.asked.key == payload then
		-- the host's answer to "existing": the team on the pad already has a save on this map
		local asked = pad.asked :: { key: string, save: RunSave.Save }
		local map = Maps.get(settings.mapId) :: Maps.Map
		local percent = math.floor(math.clamp(fillOf(asked.save, map), 0, 1) * 100)
		if action == "continue" and asked.save.finished then
			tell(player, "That ocean is already full.")
			return
		end
		pad.asked = nil
		if action == "continue" then
			pad.continueKey = asked.key
		else
			pad.replaceKey = asked.key
			pad.startsOver = { members = asked.save.members, percent = percent }
		end
		for _, p in pad.members do
			tell(p, if action == "continue"
				then `Continuing your team's run on {map.name} ({percent}% filled).`
				else `Starting over your team's run on {map.name}.`)
		end
		task.spawn(launchParty, pad)
	elseif action == "load" and choosing and not deleting[player] and ownsRun(player, payload) then
		local save: RunSave.Save? = nil
		for _, run in pad.saved or {} do
			if run.key == payload then
				save = run.save
				break
			end
		end
		if not save then
			tell(player, "That run has no save yet.")
		elseif not table.find(save.members, player.UserId) then
			tell(player, "Only that run's team can load it.")
		elseif #save.members == 1 then
			Telemetry.lobby(player, "LoadedRun")
			task.spawn(launchSaved, pad, payload :: string)
		else
			-- a team run: the pad opens to its team only, and launches once they are all on it
			Telemetry.lobby(player, "LoadedRun")
			pad.roster = { key = payload :: string, mapId = save.mapId, members = table.clone(save.members) }
			local _, missing = SessionRules.loadError(save.members, { player.UserId })
			tell(player, `Your team can get on the pad now. Waiting for {namesOf(missing)}.`)
		end
	elseif action == "delete" and choosing and not deleting[player] and ownsRun(player, payload) then
		task.spawn(deleteRun, pad, player, payload :: string)
	end
end

function Queue.start()
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	for _, name in { "Notice", "SessionState", "SessionAction" } do
		local r = folder:WaitForChild(name, 10)
		assert(r and r:IsA("RemoteEvent"), `ReplicatedStorage.Remotes is missing {name} (Rojo project; restart rojo serve)`)
		remotes[name] = r
	end
	local lobby = workspace:FindFirstChild("Lobby")
	local padsFolder = lobby and lobby:FindFirstChild("Pads")
	assert(padsFolder, "workspace.Lobby.Pads is missing (the lobby map lives in the place)")
	local models = padsFolder:GetChildren()
	table.sort(models, function(a, b)
		return a.Name < b.Name
	end)
	for _, model in models do
		if model:IsA("Model") then
			local zone, title, status = padParts(model)
			table.insert(pads, {
				name = model.Name,
				model = model,
				zone = zone,
				title = title,
				status = status,
				host = nil,
				settings = nil,
				roster = nil,
				replaceKey = nil,
				continueKey = nil,
				asked = nil,
				held = false,
				startsOver = nil,
				checking = false,
				offered = nil,
				members = {},
				told = {},
				friends = {},
				saved = nil,
				savedError = nil,
				savedToken = 0,
				savedLoading = false,
				launching = false,
				counting = false,
			})
		end
	end
	assert(#pads > 0, "workspace.Lobby.Pads has no pads")
	remotes.SessionAction.OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
		actionWindow[player] = nil
		deleting[player] = nil
		savedCache[player] = nil
	end)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(`[Queue] teleport failed for {player.Name}: {result} {message}`)
		tell(player, "Teleport failed. Touch a pad to try again.")
	end)
	task.spawn(function()
		while true do
			-- Each player on no pad touches at most one: the nearest whose walls they are at.
			local touching: { [Pad]: { Player } } = {}
			for _, pad in pads do
				touching[pad] = {}
			end
			for _, p in Players:GetPlayers() do
				if not padOf(p) then
					local best: Pad? = nil
					local bestDistance = math.huge
					for _, pad in pads do
						local at = spotOf(pad, p)
						if at and within(at, TOUCH) and at.X * at.X + at.Z * at.Z < bestDistance then
							best, bestDistance = pad, at.X * at.X + at.Z * at.Z
						end
					end
					if best then
						table.insert(touching[best], p)
					end
				end
			end
			for _, pad in pads do
				update(pad, touching[pad])
			end
			task.wait(POLL)
		end
	end)
end

return Queue
