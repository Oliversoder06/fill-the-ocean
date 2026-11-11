-- The Upgrades button (StarterGui.Hud.UpgradesButton, right edge) that opens the honeycomb
-- (client/Honeycomb, which shows its Badge). Holding Tab / Y / the mouse / a finger squishes it down;
-- letting go springs it back up. Tab and Y toggle as they go down, so a release that never arrives
-- (focus moving) can't swallow the press; the mouse and a finger toggle on release, like a button.
-- Its key tag tells keyboard and gamepad players which key does it.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Cues = require(ReplicatedStorage.Shared.Cues)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["clear-tide"])
local Hud = require(script.Parent.Hud)

local motion = Theme.motion
local set = Hud.set
local CUE = Cues.honeycomb

local QUICK = TweenInfo.new(CUE.quickSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOLD_DOWN = TweenInfo.new(CUE.holdDownSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOLD_UP = TweenInfo.new(CUE.holdUpSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local HoneycombButton = {}

function HoneycombButton.start(upgrades: GuiButton, toggle: () -> ())
	local press = Hud.find(upgrades, "Press") :: UIScale
	local key = Hud.find(upgrades, "Key")
	local keyText = Hud.find(key, "Text")
	local held = false
	local hovered = false
	local function hold()
		held = true
		TweenService:Create(press, HOLD_DOWN, { Scale = CUE.holdScale }):Play()
	end
	local function release(fire: boolean)
		if not held then
			return
		end
		held = false
		TweenService:Create(press, HOLD_UP, { Scale = if hovered then motion.hoverScale else 1 }):Play()
		if fire then
			toggle()
		end
	end
	ContextActionService:BindAction("ToggleUpgrades", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			hold()
			toggle()
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			release(false)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Tab, Enum.KeyCode.ButtonY)
	upgrades.MouseEnter:Connect(function()
		hovered = true
		if not held then
			TweenService:Create(press, QUICK, { Scale = motion.hoverScale }):Play()
		end
	end)
	upgrades.MouseLeave:Connect(function()
		hovered = false
		if held then
			release(false) -- dragged off the button: cancel, like a normal button
		else
			TweenService:Create(press, QUICK, { Scale = 1 }):Play()
		end
	end)
	upgrades.MouseButton1Down:Connect(hold) -- touch fires these too
	upgrades.MouseButton1Up:Connect(function()
		release(true)
	end)

	local function onInputType(kind: Enum.UserInputType)
		set(key, "Visible", kind ~= Enum.UserInputType.Touch)
		set(keyText, "Text", if kind.Name:sub(1, 7) == "Gamepad" then "Y" else "TAB")
	end
	UserInputService.LastInputTypeChanged:Connect(onInputType)
	onInputType(UserInputService:GetLastInputType())
end

return HoneycombButton
