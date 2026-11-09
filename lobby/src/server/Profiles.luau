-- Loads each player's saved progress when they join, keeps it for the pads, and shows it as
-- attributes: Raindrops, Runs (how many saved runs), MapsCleared, DataReady / DataError, and Admin
-- (shared Admins, mapped from gameplay as ServerStorage.GameplayShared.Admins).
-- The lobby writes only when a player leaves or deletes a run, starts one over (New Game), is owed a
-- finished run's Raindrops (the ending couldn't pay them), or an admin resets their own profile
-- (Admin("resetProfile"): their solo runs erased, then their progress back to the start). The
-- gameplay place writes the rest.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Maps = require(ReplicatedStorage.Common.Maps)
local PlayerData = require(ReplicatedStorage.Common.PlayerData)
local Progress = require(ReplicatedStorage.Common.Progress)
local RunSave = require(ReplicatedStorage.Common.RunSave)
local RunStore = require(ReplicatedStorage.Common.RunStore)
local Admins = require(ServerStorage.GameplayShared.Admins)

local ADMIN_COOLDOWN = 5 -- seconds between an admin's profile resets

local Profiles = {}

local loaded: { [Player]: Progress.Data } = {}
local adminAt: { [Player]: number } = {} -- os.clock() of the last reset; math.huge while one runs
local revisions: { [Player]: number } = {} -- bumped on every write to a player's progress or runs

local function show(player: Player, data: Progress.Data)
	local cleared = 0
	for _ in data.mapsCleared do
		cleared += 1
	end
	player:SetAttribute("Raindrops", data.raindrops)
	player:SetAttribute("Runs", #data.runs)
	player:SetAttribute("MapsCleared", cleared)
end

-- Pays the player for each of their saved runs that is finished but hasn't paid them yet (the
-- ending's payment failed). Progress.clearMap pays a run once, so this can't pay twice.
local function payOwed(player: Player, data: Progress.Data)
	for _, key in data.runs do
		if Progress.isPaid(data, key) then
			continue
		end
		local save, loadErr = RunStore.load(key)
		if loadErr then
			warn(`[Profiles] couldn't check run {key} for {player.Name}'s Raindrops: {loadErr}`)
			continue
		end
		local map = save and Maps.get(save.mapId)
		if not (save and map and save.finished and table.find(save.members, player.UserId)) then
			continue
		end
		local paid, payErr = PlayerData.clearMap(player.UserId, map.id, map.rewardRaindrops, key)
		if not paid then
			warn(`[Profiles] couldn't pay {player.Name} for run {key}: {payErr}; tried again next join`)
		elseif player.Parent then
			loaded[player] = paid
			show(player, paid)
		end
	end
end

local function load(player: Player)
	player:SetAttribute("Admin", Admins[player.UserId] == true)
	local data, err = PlayerData.load(player.UserId)
	if not player.Parent then
		return
	end
	if data then
		loaded[player] = data
		show(player, data)
		task.spawn(payOwed, player, data)
	else
		-- Can't reach saves: only maps that need nothing cleared are open, and the HUD says so.
		warn(`[Profiles] couldn't load {player.Name}: {err}`)
		player:SetAttribute("DataError", true)
	end
	player:SetAttribute("DataReady", true)
end

-- The player's progress, or nil until it has loaded or if loading failed.
function Profiles.get(player: Player): Progress.Data?
	return loaded[player]
end

-- Changes whenever the lobby writes this player's progress or erases their runs (Queue's saved-runs
-- cache keys on it).
function Profiles.revision(player: Player): number
	return revisions[player] or 0
end

local function bump(player: Player)
	if player.Parent then
		revisions[player] = (revisions[player] or 0) + 1
	end
end

-- The map ids this player may start a party on (Common.Maps.unlocked).
function Profiles.unlockedMaps(player: Player): { [string]: boolean }
	local data = loaded[player]
	local cleared = if data then data.mapsCleared else {}
	local open = {}
	for _, map in Maps.list do
		if Maps.unlocked(cleared, map.id) then
			open[map.id] = true
		end
	end
	return open
end

-- Keeps a player's freshly written progress (while they're here). Returns ok plus an error.
local function keep(player: Player, data: Progress.Data?, err: string?): (boolean, string?)
	bump(player)
	if not data then
		return false, err
	end
	if player.Parent then
		loaded[player] = data
		show(player, data)
	end
	return true, nil
end

-- "Leave run" (owner decision D5): takes the run off this player's list; the team's save stays.
-- Returns ok plus an error.
function Profiles.leaveRun(player: Player, key: string): (boolean, string?)
	return keep(player, PlayerData.removeRun(player.UserId, key))
end

-- The run was erased (New Game, Delete): off this player's list, and its ending may pay again.
function Profiles.forgetRun(player: Player, key: string): (boolean, string?)
	return keep(player, PlayerData.forgetRun(player.UserId, key))
end

-- Erases the player's solo run on every map (one key per map, so runs that fell off the list go
-- too), then resets their progress. It stops before the progress at the first run it can't erase
-- (open in a server, or the stores failed); a run erased before that still lists, as a fresh one.
-- Their team runs only leave the list; the teams keep them. Returns ok, an error, and whether a run
-- was open in a server.
function Profiles.resetProfile(player: Player): (boolean, string?, boolean)
	bump(player)
	for _, map in Maps.list do
		local ok, err, open = RunStore.erase(RunSave.key(map.id, { player.UserId }))
		if not ok then
			return false, err, open
		end
	end
	local ok, err = keep(player, PlayerData.reset(player.UserId))
	return ok, err, false
end

-- Admin("resetProfile") from the lobby HUD's Admin button: admins only, one at a time, at most one
-- per ADMIN_COOLDOWN.
local function onAdmin(notice: RemoteEvent, player: Player, action: unknown)
	if action ~= "resetProfile" or not Admins[player.UserId] then
		return
	end
	local now = os.clock()
	if now - (adminAt[player] or -math.huge) < ADMIN_COOLDOWN then
		return
	end
	adminAt[player] = math.huge
	-- the busy flag is cleared even if the reset throws; the error is raised again after
	local ran, ok, err, open = pcall(Profiles.resetProfile, player)
	if player.Parent then
		adminAt[player] = os.clock()
	end
	if not ran then
		error(ok, 0)
	end
	if not player.Parent then
		return
	end
	if not ok then
		warn(`[Profiles] couldn't reset {player.Name}'s profile: {err}`)
		notice:FireClient(player, if open then "A solo run of yours is open in a server. Try again in a minute." else "Couldn't reset your profile. Please try again.")
		return
	end
	notice:FireClient(player, "Profile reset: no Raindrops, cleared maps or saved runs. Step off and on a pad to see it.")
end

function Profiles.start()
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local remotes = {}
	for _, name in { "Notice", "Admin" } do
		local r = folder:WaitForChild(name, 10)
		assert(r and r:IsA("RemoteEvent"), `ReplicatedStorage.Remotes is missing {name} (Rojo project; restart rojo serve)`)
		remotes[name] = r
	end
	remotes.Admin.OnServerEvent:Connect(function(player, action)
		onAdmin(remotes.Notice, player, action)
	end)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		loaded[player] = nil
		adminAt[player] = nil
		revisions[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

return Profiles
