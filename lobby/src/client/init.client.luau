-- Client entry point. Fills in the lobby HUD (StarterGui.LobbyHud, built in Studio) and starts
-- the session pad UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local unlocked = find("Stats.Unlocked")
local toast = find("Toast")
local toastText = find("Toast.Text")

local function refresh()
	if player:GetAttribute("DataError") then
		raindrops.Text = "Raindrops: couldn't load"
	else
		raindrops.Text = `{player:GetAttribute("Raindrops") or 0} Raindrops`
	end
	unlocked.Text = `Unlocked: Difficulty {player:GetAttribute("Unlocked") or 1}`
end

for _, name in { "Raindrops", "Unlocked", "DataError" } do
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
