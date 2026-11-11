-- Session pads (workspace.Lobby.Pads.Pad1..PadN, built in Studio). Each pad Model has a "Zone" part
-- and a sign with "Title" and "Status" labels. A pad holds one session:
--   empty       the first player to step on becomes host and gets the pad screen
--   choosing    one screen: the host either creates a new party (Create Party: a map they unlocked,
--               max players, friends-only) or loads one of their saved runs (Saved Runs)
--   open        a new party: others step on to join (rules in Common.SessionRules); it launches when
--               full or when the host presses Start
-- A saved run loads only with exactly its team standing on the pad (SessionRules.loadError for the
-- card, RunSave.sameTeam again at launch). One save per map per team (RunSave.key): a new party whose
-- team already has a save on its map starts over it only if the host confirmed that save (New Game:
-- "open" with `replace` = its key; a save on nobody's list, every member having left it, is found
-- when the host presses Create and asked about then); it is erased at launch (RunStore.erase: never while a server has it
-- open). The host's confirm is enough; each member of that save's team is told when they join (toast
-- and HostBar). Delete on a card erases a solo run; a team run only leaves the player's list (D5's
-- Leave run), so one member can't wipe the others' progress. At launch the lobby writes a run ticket
-- and teleports the party into a fresh reserved gameplay server. Clients only send
-- SessionAction("open" | "cancel" | "start" | "load" | "delete"); everything is checked here.
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
local Config = require(ServerStorage.GameplayShared.Config)
local Water = require(ServerStorage.GameplayShared.Water)
local Profiles = require(script.Parent.Profiles)

local POLL = 0.25
local COOLDOWN = 4 -- after a launch or a failed launch
local ZONE_HEIGHT = 10
local ACTIONS_PER_SECOND = 4
local ACTIONS = { open = true, cancel = true, start = true, load = true, delete = true }
local SAVED_RETRY = 30 -- seconds before a saved-runs list with a failed read is read again

local Queue = {}

-- One of the host's saved runs as loaded for the Saved Runs panel.
type SavedRun = { key: string, save: RunSave.Save?, problem: string? }

type Pad = {
	name: string,
	zone: BasePart,
	title: TextLabel,
	status: TextLabel,
	host: Player?,
	settings: SessionRules.Settings?,
	replaceKey: string?, -- New Game: the host's saved run this party may start over
	startsOver: { members: { number }, percent: number }?, -- that save's team and fill, for the notice
	checking: boolean, -- Create is looking for the team's save (openParty)
	offered: { key: string, save: RunSave.Save }?, -- a save Create found and asked the host to replace
	members: { Player }, -- join order, host included
	declined: { [Player]: boolean }, -- must step off before they can host again
	told: { [Player]: string },
	friends: { [number]: boolean | "pending" }, -- host-friend lookups for this session
	saved: { SavedRun }?, -- the host's saved runs; nil while they load
	savedError: string?,
	savedToken: number, -- bumped per load so a stale load is dropped
	savedLoading: boolean, -- a load for this host is running
	launching: boolean,
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
	assert(zone and zone:IsA("BasePart"), `{model:GetFullName()} is missing its Zone part`)
	assert(title and title:IsA("TextLabel"), `{model:GetFullName()} is missing its Title label`)
	assert(status and status:IsA("TextLabel"), `{model:GetFullName()} is missing its Status label`)
	return zone, title, status
end

-- Players whose character root is inside the pad's zone box.
local function occupants(zone: BasePart): { [Player]: boolean }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local characters = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(characters, p.Character)
		end
	end
	params.FilterDescendantsInstances = characters
	local found = {}
	local cf = zone.CFrame * CFrame.new(0, ZONE_HEIGHT / 2, 0)
	for _, part in workspace:GetPartBoundsInBox(cf, zone.Size + Vector3.new(0, ZONE_HEIGHT, 0), params) do
		local player = Players:GetPlayerFromCharacter(part.Parent)
		if player and part.Name == "HumanoidRootPart" then
			found[player] = true
		end
	end
	return found
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

local function reset(pad: Pad)
	pad.host, pad.settings, pad.replaceKey, pad.startsOver = nil, nil, nil, nil
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

-- Who would load a saved run: the host, then everyone else standing on the pad (by user id, so the
-- card text stays the same from poll to poll).
local function loaders(pad: Pad, here: { [Player]: boolean }): { Player }
	local others = {}
	for p in here do
		if p ~= pad.host and not padOf(p) then
			table.insert(others, p)
		end
	end
	table.sort(others, function(a, b)
		return a.UserId < b.UserId
	end)
	table.insert(others, 1, pad.host :: Player)
	return others
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
		card.reason = `Waiting for {namesOf(who)}`
	elseif reason == "extra" then
		card.reason = `{namesOf(who)} must step off the pad`
	else
		card.reason = "Everyone's here!"
		card.canLoad = true
	end
	return card
end

-- What the host's client shows while choosing: both panels, the saved runs as cards (nil while they
-- load) and who stands on the pad (padIds, the host first: the team a New Game would be for).
local function hostView(pad: Pad, here: { [Player]: boolean }): { [string]: any }
	local host = pad.host :: Player
	local ids = userIds(loaders(pad, here))
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

-- Sends the party to a fresh reserved gameplay server. prepare re-checks the run (it may yield) and
-- returns the ticket, or nil plus what to tell the party.
local function launch(pad: Pad, party: { Player }, title: string, prepare: () -> (RunTicket.Ticket?, string?))
	pad.launching = true
	pad.title.Text = title
	pad.status.Text = "Starting..."
	for _, p in party do
		sendState(p, { kind = "launching", title = title })
	end
	local ticket, problem = prepare()
	-- the launch may have erased, started or forgotten a run: read their lists again next time
	for _, p in party do
		savedCache[p] = nil
	end
	if not ticket then
		for _, p in party do
			if p.Parent then
				tell(p, problem :: string)
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
		if not ok then
			warn(`[Queue] launch failed on {pad.name}: {err}`)
			for _, p in party do
				tell(p, "Couldn't start the run. Please try again.")
			end
		end
	end
	task.wait(COOLDOWN)
	-- whoever is still standing here (Studio, failed teleport) must step off before hosting again
	for p in occupants(pad.zone) do
		pad.declined[p] = true
	end
	for _, p in party do
		if p.Parent then
			sendState(p, { kind = "none" })
		end
	end
	reset(pad)
	pad.launching = false
end

-- A new party (Create Party): the same team on the same map always gets the same run key. A team that
-- already has a save there (one that was played: RunSave.isBlank) is sent to Saved Runs instead of
-- launching, unless the host confirmed starting over exactly that save (New Game): then it is erased
-- here, under its lock, and its key leaves every member's list (Progress.forgetRun, so the fresh run's
-- ending pays again), even when it is already blank (an earlier try erased it); the launch stops if
-- any member's list can't be updated, and pressing Start again is safe. If the final team isn't the
-- confirmed one, the confirmed save is untouched.
local function launchParty(pad: Pad)
	local settings = pad.settings :: SessionRules.Settings
	local replaceKey = pad.replaceKey
	local party = table.clone(pad.members)
	local members = userIds(party)
	launch(pad, party, mapName(settings.mapId), function()
		local key = RunSave.key(settings.mapId, members)
		local save, err = RunStore.load(key)
		if err then
			warn(`[Queue] couldn't check run {key} before a new party: {err}`)
			return nil, "Couldn't start the run. Please try again."
		elseif save and not RunSave.isBlank(save) and key ~= replaceKey then
			return nil,
				if save.finished
					then "Your team already filled this ocean. Press New Game to play it again."
					else "Your team already has a run on this map. Load it from Saved Runs, or create the party again with the whole team on the pad to replace it."
		end
		if key == replaceKey then
			if save and not RunSave.isBlank(save) then
				local erased, eraseErr, open = RunStore.erase(key)
				if not erased then
					warn(`[Queue] couldn't erase run {key} for a New Game: {eraseErr}`)
					return nil, if open then "That run is open in another server. Try again in a minute." else "Couldn't start over. Please try again."
				end
			end
			for _, p in party do
				local forgot, forgetErr = Profiles.forgetRun(p, key)
				if not forgot then
					warn(`[Queue] erased run {key} is still listed for {p.Name}: {forgetErr}`)
					return nil, "Couldn't start over. Please try again."
				end
			end
		end
		return { mapId = settings.mapId, key = key, members = members }, nil
	end)
end

-- One of the host's saved runs, with whoever stands on the pad. Everything the card showed is
-- checked again here: the save exists, isn't finished, is exactly this team, and no server has it open.
local function launchSaved(pad: Pad, key: string)
	local party = loaders(pad, occupants(pad.zone))
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
		-- Taking the lock proves no server has the run open; it is handed straight back (1 s) so the
		-- gameplay server can take it when the party arrives.
		local probe = HttpService:GenerateGUID(false)
		local free, lockErr = RunStore.lock(key, probe)
		if not free then
			warn(`[Queue] run {key} can't be locked: {lockErr}`)
			return nil, "This run is already open in another server. Try again in a minute."
		end
		local released, unlockErr = RunStore.unlock(key, probe)
		if not released then
			warn(`[Queue] couldn't release the check lock on {key}: {unlockErr}`)
			return nil, "Couldn't start the run. Please try again in a minute."
		end
		return { mapId = save.mapId, key = key, members = save.members }, nil
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
	if settings.maxPlayers == 1 then
		tell(player, "Starting your solo run!")
	end
end

-- Create without New Game: the team on the pad may still have a save on this map that is on nobody's
-- Saved Runs (every member left it), so the client couldn't ask. It is looked up here (it yields); if
-- there is one, the host is asked to replace it (SessionState "replace") and their Yes comes back as
-- a New Game for that key (pad.offered).
local function checkAndOpen(pad: Pad, player: Player, settings: SessionRules.Settings, map: Maps.Map)
	local team = SessionRules.newTeam(settings.maxPlayers, userIds(loaders(pad, occupants(pad.zone))))
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
	local settings = pad.settings
	if not pad.host then
		pad.title.Text = "Open Pad"
		pad.status.Text = "Step on to host"
	elseif not settings then
		pad.title.Text = "Setting up..."
		pad.status.Text = (pad.host :: Player).DisplayName
	else
		pad.title.Text = mapName(settings.mapId)
		pad.status.Text = `{#pad.members}/{settings.maxPlayers}{if settings.friendsOnly then " - Friends" else " - Join!"}`
	end
end

local function update(pad: Pad)
	if pad.launching then
		return
	end
	local here = occupants(pad.zone)

	-- People who stepped off or left: drop them; pass host on if needed.
	for i = #pad.members, 1, -1 do
		local p = pad.members[i]
		if not here[p] or not p.Parent then
			table.remove(pad.members, i)
			if p == pad.host then
				local ids = {}
				for _, m in pad.members do
					table.insert(ids, m.UserId)
				end
				local nextId = SessionRules.nextHost(ids, p.UserId)
				pad.host = if nextId then Players:GetPlayerByUserId(nextId) else nil
				if pad.host and pad.settings then
					tell(pad.host, "You're the host now. Press Start when everyone's ready.")
				end
				pad.friends = {}
			end
			if p.Parent then
				sendState(p, { kind = "none" })
			end
		end
	end
	if #pad.members == 0 then
		reset(pad)
	end
	for p in pad.declined do
		if not here[p] then
			pad.declined[p] = nil
		end
	end
	for p in pad.told do
		if not here[p] then
			pad.told[p] = nil
		end
	end

	-- Empty pad: the first eligible player on it hosts and gets the pad screen; their saved runs load.
	if not pad.host then
		for p in here do
			if not pad.declined[p] and not padOf(p) and p:GetAttribute("DataReady") then
				pad.host = p
				pad.members = { p }
				pad.settings = nil
				pad.told[p] = "host"
				loadSaved(pad, p)
				break
			end
		end
	end

	-- Everyone else on the pad: wait while the host chooses, then join if allowed. A saved run's
	-- team just stays on the pad: the host's Load takes everyone standing on it.
	local settings = pad.settings
	for p in here do
		if not isMember(pad, p) and not padOf(p) and not pad.declined[p] then
			if not settings then
				local host = (pad.host :: Player).DisplayName
				tellOnce(pad, p, "setup", `{host} is setting up. Stay on the pad if you're in their saved run.`)
			else
				local friend = if settings.friendsOnly then hostFriend(pad, p) else false
				if friend ~= nil then
					local reason = SessionRules.joinError(settings, #pad.members, friend)
					if reason == "full" then
						tellOnce(pad, p, "full", "This session is full.")
					elseif reason == "friends" then
						tellOnce(pad, p, "friends", "This session is friends only.")
					else
						table.insert(pad.members, p)
						local percent = startsOverFor(pad, p)
						local note = if percent
							then ` This party starts over your saved run on {mapName(settings.mapId)} ({percent}% filled).`
							else ""
						tellOnce(pad, p, "joined", `Joined {(pad.host :: Player).DisplayName}'s session!{note}`)
					end
				end
			end
		end
	end

	-- Tell each member's client what to show.
	for _, p in pad.members do
		if p == pad.host and not settings then
			sendState(p, hostView(pad, here))
		elseif settings then
			sendState(p, {
				kind = if p == pad.host then "hosting" else "member",
				host = (pad.host :: Player).DisplayName,
				count = #pad.members,
				max = settings.maxPlayers,
				mapName = mapName(settings.mapId),
				friendsOnly = settings.friendsOnly,
				startsOver = startsOverFor(pad, p),
			})
		end
	end

	updateSign(pad)
	if settings and SessionRules.isFull(settings, #pad.members) then
		task.spawn(launchParty, pad)
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
	if not pad or pad.host ~= player or pad.launching then
		return
	end
	if action == "open" and not pad.settings and not pad.checking then
		local settings = SessionRules.validate(payload, Profiles.unlockedMaps(player))
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
		local map = settings and Maps.get(settings.mapId)
		if replace ~= nil and deleting[player] then
			tell(player, "Wait for the delete to finish.")
		elseif settings and map and replace == nil then
			task.spawn(checkAndOpen, pad, player, settings, map)
		elseif settings and map and replaced and replaced.mapId == settings.mapId then
			openParty(pad, player, settings, map, replace, replaced)
		else
			tell(player, "Those settings aren't allowed.")
		end
	elseif action == "cancel" and not pad.settings then
		pad.declined[player] = true
		sendState(player, { kind = "none" })
		reset(pad)
	elseif action == "start" and pad.settings then
		task.spawn(launchParty, pad)
	elseif action == "load" and not pad.settings and not deleting[player] and ownsRun(player, payload) then
		task.spawn(launchSaved, pad, payload :: string)
	elseif action == "delete" and not pad.settings and not deleting[player] and ownsRun(player, payload) then
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
				zone = zone,
				title = title,
				status = status,
				host = nil,
				settings = nil,
				replaceKey = nil,
				startsOver = nil,
				checking = false,
				offered = nil,
				members = {},
				declined = {},
				told = {},
				friends = {},
				saved = nil,
				savedError = nil,
				savedToken = 0,
				savedLoading = false,
				launching = false,
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
		tell(player, "Teleport failed. Step on a pad again to retry.")
	end)
	task.spawn(function()
		while true do
			for _, pad in pads do
				update(pad)
			end
			task.wait(POLL)
		end
	end)
end

return Queue
