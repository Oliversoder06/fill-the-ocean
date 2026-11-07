-- Loads each player's saved progress when they join, keeps it for the pads, and shows it as
-- attributes: Raindrops, Runs (how many saved runs), MapsCleared, and DataReady / DataError.
-- The lobby writes only when a player leaves a run ("Leave run"); the gameplay place writes the rest.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maps = require(ReplicatedStorage.Common.Maps)
local PlayerData = require(ReplicatedStorage.Common.PlayerData)
local Progress = require(ReplicatedStorage.Common.Progress)

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

local function load(player: Player)
	local data, err = PlayerData.load(player.UserId)
	if not player.Parent then
		return
	end
	if data then
		loaded[player] = data
		show(player, data)
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
