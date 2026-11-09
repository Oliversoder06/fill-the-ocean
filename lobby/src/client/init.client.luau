-- Client entry point. Fills in the lobby HUD (StarterGui.LobbyHud, built in Studio), shows admins
-- (player attribute Admin, set by the server) the Admin.ResetProfile button and starts the session
-- pad UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maps = require(ReplicatedStorage.Common.Maps)
local Session = require(script.Session)

local CONFIRM_SECONDS = 4 -- Reset my profile needs a second press within this

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("LobbyHud")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local notice = remotes:WaitForChild("Notice") :: RemoteEvent

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

-- Admins only (the server re-checks): wipes this player's own progress and solo runs. Its UI is only
-- looked up for admins, so other players never need it.
local adminReady = false
local function startAdmin()
	if adminReady or player:GetAttribute("Admin") ~= true then
		return
	end
	adminReady = true
	local adminEvent = remotes:WaitForChild("Admin") :: RemoteEvent
	local button = find("Admin.ResetProfile")
	local label = find("Admin.ResetProfile.Label")
	local idle = label.Text
	local armedAt = -math.huge
	find("Admin").Visible = true
	button.Activated:Connect(function()
		if os.clock() - armedAt < CONFIRM_SECONDS then
			armedAt = -math.huge
			label.Text = idle
			adminEvent:FireServer("resetProfile")
			return
		end
		local at = os.clock()
		armedAt = at
		label.Text = "Press again to reset"
		task.delay(CONFIRM_SECONDS, function()
			if armedAt == at then
				label.Text = idle
			end
		end)
	end)
end
player:GetAttributeChangedSignal("Admin"):Connect(startAdmin)
startAdmin()

Session.start()
