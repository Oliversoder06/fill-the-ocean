-- The hotbar (StarterGui.Hud.Hotbar, built in Studio): one slot showing the current tool. Press 1,
-- gamepad X or click the slot to put the tool away or take it out (the server decides). The fill
-- bar above the slot shows the tool at its left end and "carried / capacity" litres, only while
-- the tool is out.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Ease = require(ReplicatedStorage.Shared.Ease)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local Hud = require(script.Parent.Hud)

local player = Players.LocalPlayer
local colors, motion = Theme.colors, Theme.motion
local set = Hud.set

local QUICK = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FILL_POP = TweenInfo.new(Ease.POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FILL_POP_SCALE = 1.08 -- the bar swells a little each time water lands (shows even at 100%)

local Hotbar = {}

-- Litres for the fill label: whole numbers when whole (sweeps can leave thirds), 1.2K above 1000.
local function litres(n: number): string
	if n >= 1000 then
		return Hud.short(n)
	end
	local rounded = math.floor(n * 10 + 0.5) / 10
	return if rounded % 1 == 0 then tostring(math.floor(rounded)) else string.format("%.1f", rounded)
end

function Hotbar.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local equipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Equip") :: RemoteEvent
	local bar = Hud.find(gui, "Hotbar")
	local fillBar = Hud.find(bar, "FillBar")
	local fill = Hud.find(fillBar, "Fill")
	local fillLabel = Hud.find(fillBar, "Label")
	local fillPop = Hud.find(fillBar, "Pop")
	local fillTool = Hud.find(fillBar, "Tool") -- the tool's model at the bar's left end
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
	-- The bar springs to each new fill (Ease.pop) instead of jumping.
	local shown, from, to, changedAt = 0, 0, 0, -math.huge
	RunService.RenderStepped:Connect(function()
		local modelName = player:GetAttribute("ToolModel")
		set(bar, "Visible", type(modelName) == "string")
		if type(modelName) ~= "string" then
			return
		end
		if modelName ~= shownModel then
			local template = ToolModels.find(modelName)
			if template then -- nil until replicated; try again next frame
				ToolModels.showIn(view, template)
				ToolModels.showIn(fillTool, template)
				shownModel = modelName
			end
		end

		local equipped = player:GetAttribute("Equipped") ~= false
		set(slot, "ImageColor3", if equipped then colors.toolTag else colors.locked)
		set(ring, "Visible", equipped)
		set(fillBar, "Visible", equipped)
		if equipped then
			local carried = player:GetAttribute("Carried") or 0
			local capacity = player:GetAttribute("Capacity") or 0
			local ratio = if capacity > 0 then math.clamp(carried / capacity, 0, 1) else 0
			local now = os.clock()
			if ratio ~= to then
				if ratio > to then
					fillPop.Scale = FILL_POP_SCALE
					TweenService:Create(fillPop, FILL_POP, { Scale = 1 }):Play()
				end
				from, to, changedAt = shown, ratio, now
			end
			shown = math.clamp(Ease.pop(from, to, now - changedAt), 0, 1)
			set(fill, "Size", UDim2.fromScale(shown, 1))
			set(fill, "Visible", shown > 0)
			set(fillLabel, "Text", `{litres(carried)} / {litres(capacity)}`)
		end
	end)
end

return Hotbar
