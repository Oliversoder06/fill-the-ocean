-- Admin window (F2), only for the user ids in shared/Admins: jump the ocean's fill (0%, 50%, 95%,
-- 100%), Reset run (Body.ResetRun, pressed twice within CONFIRM_SECONDS: the run starts over for
-- the same team and map), or Preview intro (Body.PreviewIntro: the intro cutscene on this client
-- only, client/Intro). Built in Studio as StarterGui.Hud.Admin. The server re-checks the id and
-- only acts while playing.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admins = require(ReplicatedStorage.Shared.Admins)
local Hud = require(script.Parent.Hud)
local Intro = require(script.Parent.Intro)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local Admin = {}

local FILLS = { 0, 50, 95, 100 } -- percent; button Body.Fills.Fill<percent>
local CONFIRM_SECONDS = 4 -- Reset run needs a second press within this

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

	local armedAt = -math.huge -- os.clock() of the first Reset run press
	local function refresh()
		if os.clock() - armedAt < CONFIRM_SECONDS then
			status.Text = "Press Reset run again to wipe this run for the whole team."
			return
		end
		local fill = ReplicatedStorage:GetAttribute("Fill")
		local now = if type(fill) == "number" then string.format("%.1f%%", math.floor(fill * 1000) / 10) else "-"
		local phase = ReplicatedStorage:GetAttribute("Phase")
		status.Text = if phase == "playing" then `Now: {now}` else `Now: {now} ({phase}). Jumps work while playing.`
	end
	Hud.find(root, "Body.ResetRun").Activated:Connect(function()
		if os.clock() - armedAt < CONFIRM_SECONDS then
			armedAt = -math.huge
			adminEvent:FireServer("reset")
			setOpen(false)
		else
			armedAt = os.clock()
			task.delay(CONFIRM_SECONDS, refresh)
		end
		refresh()
	end)
	Hud.find(root, "Body.PreviewIntro").Activated:Connect(function()
		local problem = Intro.preview()
		if problem then
			status.Text = problem
		else
			setOpen(false)
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal("Fill"):Connect(refresh)
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(refresh)
	refresh()

	ContextActionService:BindAction("ToggleAdmin", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not Hud.cutscene then
			setOpen(not open)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F2)
end

return Admin
