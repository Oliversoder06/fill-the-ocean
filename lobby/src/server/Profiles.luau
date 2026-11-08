-- Loads each player's saved progress when they join, keeps it for the pads, and shows it as
-- attributes: Raindrops, Runs (how many saved runs), MapsCleared, and DataReady / DataError.
-- The lobby writes only when a player leaves a run ("Leave run") or is owed a finished run's
-- Raindrops (the ending couldn't pay them); the gameplay place writes the rest.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maps = require(ReplicatedStorage.Common.Maps)
local PlayerData = require(ReplicatedStorage.Common.PlayerData)
local Progress = require(ReplicatedStorage.Common.Progress)
local RunStore = require(ReplicatedStorage.Common.RunStore)

local Profiles = {}

local loaded: { [Player]: Progress.Data } = {}

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

-- "Leave run" (owner decision D5): takes the run off this player's list; the team's save stays.
-- Returns ok plus an error.
function Profiles.leaveRun(player: Player, key: string): (boolean, string?)
	local data, err = PlayerData.removeRun(player.UserId, key)
	if not data then
		return false, err
	end
	if player.Parent then
		loaded[player] = data
		show(player, data)
	end
	return true, nil
end

function Profiles.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		loaded[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

return Profiles
