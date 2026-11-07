-- Admin window (F2), only for the user ids in shared/Admins: jump the ocean's fill (0%, 50%, 95%,
-- 100%). Built in Studio as StarterGui.Hud.Admin. The server re-checks the id and only jumps while
-- playing.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admins = require(ReplicatedStorage.Shared.Admins)
local Hud = require(script.Parent.Hud)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local Admin = {}

local FILLS = { 0, 50, 95, 100 } -- percent; button Body.Fills.Fill<percent>

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

	for _, percent in FILLS do
		Hud.find(root, `Body.Fills.Fill{percent}`).Activated:Connect(function()
			adminEvent:FireServer(percent / 100)
			setOpen(false)
		end)
	end
	Hud.find(root, "CloseButton").Activated:Connect(function()
		setOpen(false)
	end)

	local function refresh()
		local fill = ReplicatedStorage:GetAttribute("Fill")
		local now = if type(fill) == "number" then string.format("%.1f%%", math.floor(fill * 1000) / 10) else "-"
		local phase = ReplicatedStorage:GetAttribute("Phase")
		status.Text = if phase == "playing" then `Now: {now}` else `Now: {now} ({phase}). Jumps work while playing.`
	end
	ReplicatedStorage:GetAttributeChangedSignal("Fill"):Connect(refresh)
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
