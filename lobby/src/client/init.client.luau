-- Client entry point. Fills in the lobby HUD (StarterGui.LobbyHud, built in Studio) and starts
-- the session pad UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maps = require(ReplicatedStorage.Common.Maps)
local Session = require(script.Session)

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("LobbyHud")
local notice = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notice") :: RemoteEvent

local function find(path: string): any
	local node: Instance = gui
	for name in path:gmatch("[^%.]+") do
		local child = node:FindFirstChild(name)
		assert(child, `LobbyHud is missing {path}`)
		node = child
	end
	return node
end

local raindrops = find("Stats.Raindrops")
local maps = find("Stats.Maps")
local toast = find("Toast")
local toastText = find("Toast.Text")

local function refresh()
	if player:GetAttribute("DataError") then
		raindrops.Text = "Raindrops: couldn't load"
		maps.Text = "Maps: couldn't load"
	else
		raindrops.Text = `{player:GetAttribute("Raindrops") or 0} Raindrops`
		maps.Text = `{player:GetAttribute("MapsCleared") or 0}/{#Maps.list} maps cleared`
	end
end

for _, name in { "Raindrops", "MapsCleared", "DataError" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
refresh()

local token = 0
notice.OnClientEvent:Connect(function(text: string)
	token += 1
	local mine = token
	toastText.Text = text
	toast.Visible = true
	task.delay(4, function()
		if mine == token then
			toast.Visible = false
		end
	end)
end)

Session.start()
