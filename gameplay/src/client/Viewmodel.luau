-- First-person copy of the player's current tool, lower right of the view. It grows a little with
-- each tool tier, shows its water while carrying, dips while scooping and tips while pouring.
-- Runs after CameraFeel, so it follows the camera's bob and tilt.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local ToolView = require(ReplicatedStorage.Shared.ToolView)

local POSE_EASE = 12
local POUR_TILT = math.rad(-65) -- tip forward
local SCOOP_DIP = 0.35 -- studs down while scooping
local SCOOP_TILT = math.rad(-20)

local player = Players.LocalPlayer
local Viewmodel = {}

local function ease(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

function Viewmodel.start()
	local current: Model? = nil
	local currentName: string? = nil
	local currentTier = 0
	local viewSize = ToolView.VIEW_START
	local holding: string? = nil -- "ScoopPrompt" or "PourPrompt" while the hold button is down
	local tilt, dip = 0, 0
	local shownWater: boolean? = nil

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		holding = prompt.Name
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function()
		holding = nil
	end)

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

	RunService:BindToRenderStep("Viewmodel", Enum.RenderPriority.Camera.Value + 2, function(dt)
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
		if (changed or not current or current.Parent ~= camera) and not load(modelName, tier) then
			return
		end
		local model = current :: Model

		local tiltTarget = if holding == "PourPrompt" then POUR_TILT elseif holding == "ScoopPrompt" then SCOOP_TILT else 0
		local dipTarget = if holding == "ScoopPrompt" then SCOOP_DIP else 0
		tilt += (tiltTarget - tilt) * ease(POSE_EASE, dt)
		dip += (dipTarget - dip) * ease(POSE_EASE, dt)

		local offset = CFrame.new(0.9 + viewSize * 0.25, -0.9 - viewSize * 0.35 - dip, -1.8 - viewSize * 0.6)
		model:PivotTo(camera.CFrame * offset * CFrame.Angles(tilt, math.rad(-8), 0))
		local water = (player:GetAttribute("Carried") or 0) > 0
		if water ~= shownWater then
			shownWater = water
			ToolModels.setWater(model, water)
		end
	end)
end

return Viewmodel
