-- Loads each player's saved progress when they join and shows it as attributes:
-- Raindrops, Unlocked (highest difficulty), Runs, and DataReady / DataError.
-- The lobby only reads; the gameplay place writes at the end of a run.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(ReplicatedStorage.Common.PlayerData)

local Profiles = {}

local function load(player: Player)
	local data, err = PlayerData.load(player.UserId)
	if not player.Parent then
		return
	end
	if data then
		player:SetAttribute("Raindrops", data.raindrops)
		player:SetAttribute("Unlocked", data.unlocked)
		player:SetAttribute("Runs", data.runs)
		player:SetAttribute("DataReady", true)
	else
		-- Can't reach saves: allow Difficulty 1 only, and say so in the HUD.
		warn(`[Profiles] couldn't load {player.Name}: {err}`)
		player:SetAttribute("Unlocked", 1)
		player:SetAttribute("DataError", true)
		player:SetAttribute("DataReady", true)
	end
end

-- Highest difficulty this player may queue for (1 until their data has loaded or if it failed).
function Profiles.unlocked(player: Player): number
	local unlocked = player:GetAttribute("Unlocked")
	return if type(unlocked) == "number" then unlocked else 1
end

function Profiles.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

return Profiles
