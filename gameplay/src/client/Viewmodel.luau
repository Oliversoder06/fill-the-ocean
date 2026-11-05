-- First-person copy of the player's current tool, lower right of the view. It grows a little with
-- each tool tier, shows its water while carrying, sweeps through the water on each scoop, tips
-- over on a pour (poses from shared/ToolView, timing from client/Action) and springs back up after.
-- A newly bought tool waits below the screen while the shop is open, then swings up into the hand.
-- Runs after CameraFeel, so it follows the camera's bob and tilt.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ease = require(ReplicatedStorage.Shared.Ease)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local ToolView = require(ReplicatedStorage.Shared.ToolView)
local Action = require(script.Parent.Action)

local BLEND_SECONDS = 0.08 -- eases into each new action's pose, so back-to-back sweeps don't snap

local player = Players.LocalPlayer
local Viewmodel = {}

local revealListeners: { (Model) -> () } = {}

-- Called with the viewmodel when a new tool starts swinging into the hand (client/Purchase).
function Viewmodel.onReveal(fn: (Model) -> ())
	table.insert(revealListeners, fn)
end

local function shopOpen(): boolean
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("Hud")
	local shop = hud and hud:FindFirstChild("Shop")
	return shop ~= nil and shop:IsA("GuiObject") and shop.Visible
end

function Viewmodel.start()
	local current: Model? = nil
	local currentName: string? = nil
	local currentTier = 0
	local viewSize = ToolView.VIEW_START
	local shownWater: boolean? = nil
	local pose = { 0, 0, 0 } -- down, side, tilt (see ToolView)
	local from = { 0, 0, 0 } -- pose when the last action started or ended
	local changedAt = -math.huge
	local actionId: number? = nil
	local revealPending = false
	local revealAt = -math.huge

	local function load(modelName: string, tier: number): boolean
		local template = ToolModels.find(modelName)
		if not template then
			return false -- not replicated yet; try again next frame
		end
		if current then
			current:Destroy()
		end
		local model = template:Clone()
		local extents = template:GetExtentsSize()
		local longest = math.max(extents.X, extents.Y, extents.Z)
		viewSize = ToolView.viewSize(tier) -- every rung (levels too) shows a slightly bigger tool
		model:ScaleTo(viewSize / math.max(longest, 0.01))
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			end
		end
		model.Name = "Viewmodel"
		model.Parent = workspace.CurrentCamera
		current, currentName, currentTier = model, modelName, tier
		shownWater = nil
		return true
	end

	RunService:BindToRenderStep("Viewmodel", Enum.RenderPriority.Camera.Value + 2, function()
		local camera = workspace.CurrentCamera
		local modelName = player:GetAttribute("ToolModel")
		local tier = player:GetAttribute("ToolTier")
		local alive = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local equipped = player:GetAttribute("Equipped") ~= false
		if type(modelName) ~= "string" or type(tier) ~= "number" or not alive or not equipped or camera.CameraType ~= Enum.CameraType.Custom then
			if current then
				current:Destroy()
				current, currentName = nil, nil
			end
			return
		end
		local changed = modelName ~= currentName or tier ~= currentTier
		if changed and currentTier > 0 and tier > currentTier then
			revealPending = true -- a bought tool: swing it in once the shop is closed
		end
		if (changed or not current or current.Parent ~= camera) and not load(modelName, tier) then
			return
		end
		local model = current :: Model

		local now = os.clock()
		if revealPending and not shopOpen() then
			revealPending, revealAt = false, now
			for _, fn in revealListeners do
				fn(model)
			end
		end
		local action = Action.current()
		if action then
			if action.id ~= actionId then
				actionId, from, changedAt = action.id, table.clone(pose), now
			end
			local poseOf = if action.kind == "scoop" then ToolView.scoopPose else ToolView.pourPose
			local down, side, tilt = poseOf((now - action.started) / action.duration)
			local b = math.clamp((now - changedAt) / BLEND_SECONDS, 0, 1)
			b = b * b * (3 - 2 * b)
			pose[1] = from[1] + (down - from[1]) * b
			pose[2] = from[2] + (side - from[2]) * b
			pose[3] = from[3] + (tilt - from[3]) * b
		else
			if actionId then -- just finished: spring back up from wherever the action left the tool
				actionId, from, changedAt = nil, table.clone(pose), now
			end
			for i = 1, 3 do
				pose[i] = Ease.pop(from[i], 0, now - changedAt)
			end
		end

		local revealDown, revealTilt = ToolView.revealPose(if revealPending then 0 else (now - revealAt) / ToolView.REVEAL_SECONDS)
		local offset = CFrame.new(0.9 + viewSize * 0.25 + pose[2], -0.9 - viewSize * 0.35 - pose[1] - revealDown, -1.8 - viewSize * 0.6)
		model:PivotTo(camera.CFrame * offset * CFrame.Angles(pose[3] + revealTilt, math.rad(-8), 0))
		local water = (player:GetAttribute("Carried") or 0) > 0
		if water ~= shownWater then
			shownWater = water
			ToolModels.setWater(model, water)
		end
	end)
end

return Viewmodel
