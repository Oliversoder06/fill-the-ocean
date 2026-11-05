-- Admin window (F2), only for the user ids in shared/Admins: jump the run to any stage. Built in
-- Studio as StarterGui.Hud.Admin. The server re-checks the id and only jumps mid-stage.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admins = require(ReplicatedStorage.Shared.Admins)
local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.Hud)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local Admin = {}

function Admin.start()
	if not Admins[player.UserId] then
		return
	end
	local adminEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin") :: RemoteEvent
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local root = Hud.find(gui, "Admin")
	local status = Hud.find(root, "Body.Status")
	local window = Window.new(root, Hud.find(root, "Scale"))

	local open = false
	local function setOpen(value: boolean)
		if value == open then
			return
		end
		open = value
		if value then
			window.open(1)
		else
			window.close(1)
		end
	end

	for i, stage in Config.stages do
		local button = Hud.find(root, `Body.Stages.Stage{i}`)
		Hud.find(button, "Label").Text = string.upper(stage.name)
		button.Activated:Connect(function()
			adminEvent:FireServer(i)
			setOpen(false)
		end)
	end
	Hud.find(root, "CloseButton").Activated:Connect(function()
		setOpen(false)
	end)

	local function refresh()
		local index = ReplicatedStorage:GetAttribute("Stage")
		local stage = type(index) == "number" and Config.stages[index]
		local phase = ReplicatedStorage:GetAttribute("Phase")
		status.Text = if phase == "playing"
			then `Now: {if stage then stage.name else "-"}`
			else `Now: {if stage then stage.name else "-"} ({phase}). Jumps work while playing.`
	end
	ReplicatedStorage:GetAttributeChangedSignal("Stage"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(refresh)
	refresh()

	ContextActionService:BindAction("ToggleAdmin", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			setOpen(not open)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F2)
end

return Admin
