-- The hotbar (StarterGui.Hud.Hotbar, built in Studio): one slot showing the current tool. Press 1,
-- gamepad X or click the slot to put the tool away or take it out (the server decides). The fill
-- bar above the slot shows how full the tool is, only while it is out.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local Hud = require(script.Parent.Hud)

local player = Players.LocalPlayer
local colors, motion = Theme.colors, Theme.motion
local set = Hud.set

local QUICK = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local Hotbar = {}

-- Puts a copy of the tool model in the slot's ViewportFrame, framed to fit.
local function showModel(view: ViewportFrame, template: Model)
	view:ClearAllChildren()
	local model = template:Clone()
	model:PivotTo(CFrame.new())
	model.Parent = view
	ToolModels.setWater(model, false)
	local camera = Instance.new("Camera")
	local center, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local direction = Vector3.new(1, 0.6, 1).Unit
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(center.Position + direction * radius / math.tan(math.rad(20)) * 1.05, center.Position)
	camera.Parent = view
	view.CurrentCamera = camera
end

function Hotbar.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local equipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Equip") :: RemoteEvent
	local bar = Hud.find(gui, "Hotbar")
	local fillBar = Hud.find(bar, "FillBar")
	local fill = Hud.find(fillBar, "Fill")
	local fillLabel = Hud.find(fillBar, "Label")
	local slot = Hud.find(bar, "Slot")
	local ring = Hud.find(slot, "Ring")
	local view = Hud.find(slot, "View")
	local press = Hud.find(slot, "Press")

	local function toggle()
		equipRemote:FireServer(player:GetAttribute("Equipped") == false)
		press.Scale = motion.pressScale
		TweenService:Create(press, POP, { Scale = 1 }):Play()
	end

	ContextActionService:BindAction("ToggleEquip", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.One, Enum.KeyCode.ButtonX)
	slot.Activated:Connect(toggle)
	slot.MouseEnter:Connect(function()
		TweenService:Create(press, QUICK, { Scale = motion.hoverScale }):Play()
	end)
	slot.MouseLeave:Connect(function()
		TweenService:Create(press, QUICK, { Scale = 1 }):Play()
	end)

	local shownModel: string? = nil
	RunService.RenderStepped:Connect(function()
		local modelName = player:GetAttribute("ToolModel")
		set(bar, "Visible", type(modelName) == "string")
		if type(modelName) ~= "string" then
			return
		end
		if modelName ~= shownModel then
			local template = ToolModels.find(modelName)
			if template then -- nil until replicated; try again next frame
				showModel(view, template)
				shownModel = modelName
			end
		end

		local equipped = player:GetAttribute("Equipped") ~= false
		set(slot, "ImageColor3", if equipped then colors.shallowWater else colors.locked)
		set(ring, "Visible", equipped)
		set(fillBar, "Visible", equipped)
		if equipped then
			local carried = player:GetAttribute("Carried") or 0
			local capacity = player:GetAttribute("Capacity") or 0
			local ratio = if capacity > 0 then math.clamp(carried / capacity, 0, 1) else 0
			set(fill, "Size", UDim2.fromScale(ratio, 1))
			set(fill, "Visible", ratio > 0)
			set(fillLabel, "Text", `{math.floor(ratio * 100 + 0.5)}% Full`)
		end
	end)
end

return Hotbar
