-- First-person copy of what the player holds, lower right of the view, held by a copy of the
-- player's own right hand and forearm: the hotbar gadget out (ToolModels.Gadgets.<model>), else the
-- tool while it is out, as server/HeldTools puts in the character's hand. The tool grows a little
-- with each tier. It shows its water while carrying, sweeps through the water on each scoop, tips
-- over on a pour (poses from shared/ToolView, timing from client/Action) and springs back up after.
-- The hand wobbles with each step (walk cycle from client/CameraFeel) and trails a little behind
-- camera turns. Nothing shows while driving (client/Vehicles: the camera is third person then).
-- A newly bought tool waits below the screen while the shop is open, then swings up into the hand.
-- Runs after CameraFeel, so it follows the camera's bob and tilt.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ease = require(ReplicatedStorage.Shared.Ease)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local ToolView = require(ReplicatedStorage.Shared.ToolView)
local Items = require(ReplicatedStorage.Common.Items)
local Action = require(script.Parent.Action)
local CameraFeel = require(script.Parent.CameraFeel)
local Vehicles = require(script.Parent.Vehicles)

local BLEND_SECONDS = 0.08 -- eases into each new action's pose, so back-to-back sweeps don't snap

local ARM_HAND_SIZE = 0.4 -- studs, longest side of the hand on screen, whatever the tool's size
local ARM_SHOULDER = Vector3.new(1.7, -1.5, -1) -- camera space, just off the lower right of the view
local ARM_LENGTH = 3 -- studs, forearm stretched so it always runs from the wrist off the screen
local ARM_KEEP = { Attachment = true, SurfaceAppearance = true } -- what a copied body part keeps

local SWAY_PER_RATE = 0.03 -- studs the hand trails per radian/s of camera turn
local SWAY_MAX = 0.15
local SWAY_EASE = 12

local player = Players.LocalPlayer
local Viewmodel = {}

local revealListeners: { (Model) -> () } = {}

type Arm = {
	model: Model,
	hand: BasePart,
	lower: BasePart,
	grip: CFrame, -- the hand's grip attachment, in hand space
	wrist: CFrame, -- the hand's wrist attachment, in hand space
	source: BasePart, -- the character's RightHand it was copied from
	color: Color3,
	shirt: string,
}

-- Called with the viewmodel when a new tool starts swinging into the hand (client/Purchase).
function Viewmodel.onReveal(fn: (Model) -> ())
	table.insert(revealListeners, fn)
end

local function shirtOf(character: Model): string
	local shirt = character:FindFirstChildOfClass("Shirt")
	return if shirt then shirt.ShirtTemplate else ""
end

local function copyPart(part: BasePart): BasePart
	local copy = part:Clone()
	assert(copy, `Viewmodel can't copy {part:GetFullName()} (Archivable is off)`)
	for _, child in copy:GetChildren() do
		if not ARM_KEEP[child.ClassName] then
			child:Destroy()
		end
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.CastShadow = false
	copy.Massless = true
	return copy
end

-- A copy of the player's own right hand and forearm (mesh, skin and shirt sleeve) at viewmodel
-- scale. Nil for avatars without R15 wrist and grip attachments.
local function buildArm(character: Model, hand: BasePart, lower: BasePart): Arm?
	local wrist = hand:FindFirstChild("RightWristRigAttachment")
	local grip = hand:FindFirstChild("RightGripAttachment")
	if not (wrist and wrist:IsA("Attachment") and grip and grip:IsA("Attachment")) then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "ViewArm"
	local h, l = copyPart(hand), copyPart(lower)
	h.Parent, l.Parent = model, model
	model.PrimaryPart = h
	-- A Humanoid makes Roblox draw the classic shirt onto the copied forearm.
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	local shirt = character:FindFirstChildOfClass("Shirt")
	if shirt then
		shirt:Clone().Parent = model
	end
	model:ScaleTo(ARM_HAND_SIZE / math.max(hand.Size.X, hand.Size.Y, hand.Size.Z))
	l.Size = Vector3.new(l.Size.X, ARM_LENGTH, l.Size.Z)
	return {
		model = model,
		hand = h,
		lower = l,
		grip = (h:FindFirstChild("RightGripAttachment") :: Attachment).CFrame,
		wrist = (h:FindFirstChild("RightWristRigAttachment") :: Attachment).CFrame,
		source = hand,
		color = hand.Color,
		shirt = shirtOf(character),
	}
end

-- Smallest rotation that turns unit vector a onto unit vector b.
local function turnTo(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-5 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(a:Dot(b), -1, 1)))
end

-- The hand grips the tool, turned so that at rest it points at the shoulder, and then moves rigidly
-- with the tool; the forearm runs from the wrist to the shoulder, so the wrist bends on a pour.
local function placeArm(arm: Arm, grip: CFrame, restGrip: CFrame, shoulder: Vector3)
	local handUp = arm.grip:VectorToObjectSpace(Vector3.yAxis) -- the hand's wrist direction, in grip space
	local hand = grip * turnTo(handUp, restGrip:PointToObjectSpace(shoulder).Unit) * arm.grip:Inverse()
	local wrist = (hand * arm.wrist).Position
	local along = (shoulder - wrist).Unit
	local right = hand.RightVector - along * hand.RightVector:Dot(along)
	if right.Magnitude < 1e-3 then
		right = along:Cross(hand.LookVector)
	end
	arm.hand.CFrame = hand
	arm.lower.CFrame = CFrame.fromMatrix(wrist + along * (ARM_LENGTH / 2 - 0.05), right.Unit, along)
end

local function shopOpen(): boolean
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("Hud")
	local shop = hud and hud:FindFirstChild("Shop")
	return shop ~= nil and shop:IsA("GuiObject") and shop.Visible
end

-- What is in hand: its model name, its ToolModels subfolder ("Gadgets" or nil) and its tier (a
-- gadget shows at the first tool's size); nil when nothing is.
local function inHand(): (string?, string?, number)
	local gadgetId = player:GetAttribute("Gadget")
	local gadget = if type(gadgetId) == "string" and gadgetId ~= "" then Items.get(Config, gadgetId) else nil
	if gadget then
		return gadget.model, "Gadgets", 1
	end
	local modelName, tier = player:GetAttribute("ToolModel"), player:GetAttribute("ToolTier")
	if player:GetAttribute("Equipped") == false or type(modelName) ~= "string" or type(tier) ~= "number" then
		return nil, nil, 0
	end
	return modelName, nil, tier
end

function Viewmodel.start()
	local current: Model? = nil
	local currentKey: string? = nil -- "<sub>.<model>" of what shows
	local currentTier = 0
	local toolTier = 0 -- the last tool tier held, so a bought tool swings in
	local viewSize = ToolView.VIEW_START
	local centerOffset = Vector3.zero -- bounding-box centre seen from the grip (pivot), after scaling
	local shownWater: boolean? = nil
	local pose = { 0, 0, 0 } -- down, side, tilt (see ToolView)
	local from = { 0, 0, 0 } -- pose when the last action started or ended
	local changedAt = -math.huge
	local actionId: number? = nil
	local revealPending = false
	local revealAt = -math.huge
	local arm: Arm? = nil
	local sway = Vector2.zero -- (side, down) the hand trails behind camera turns
	local lastLook: CFrame? = nil

	local function load(modelName: string, sub: string?, tier: number): boolean
		local template = ToolModels.find(modelName, sub)
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
		local scale = viewSize / math.max(longest, 0.01)
		model:ScaleTo(scale)
		local center = template:GetBoundingBox()
		centerOffset = template:GetPivot():PointToObjectSpace(center.Position) * scale
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
		current, currentKey, currentTier = model, `{sub}.{modelName}`, tier
		shownWater = nil
		return true
	end

	RunService:BindToRenderStep("Viewmodel", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		local camera = workspace.CurrentCamera
		local modelName, sub, tier = inHand()
		local character = player.Character
		local alive = character and character:FindFirstChildOfClass("Humanoid")
		if not modelName or not alive or camera.CameraType ~= Enum.CameraType.Custom or Vehicles.driving() then
			if current then
				current:Destroy()
				current, currentKey = nil, nil
			end
			if arm and arm.model.Parent then
				arm.model.Parent = nil
			end
			lastLook = nil
			return
		end
		local changed = `{sub}.{modelName}` ~= currentKey or tier ~= currentTier
		if not sub then
			if toolTier > 0 and tier > toolTier then
				revealPending = true -- a bought tool: swing it in once the shop is closed
			end
			toolTier = tier
		end
		if (changed or not current or current.Parent ~= camera) and not load(modelName, sub, tier) then
			return
		end
		local model = current :: Model

		-- Rebuild the arm when the avatar changes (respawn, new body colours or shirt).
		local hand = (character :: Model):FindFirstChild("RightHand")
		local lower = (character :: Model):FindFirstChild("RightLowerArm")
		if hand and lower and hand:IsA("BasePart") and lower:IsA("BasePart") then
			if not arm or arm.source ~= hand or arm.color ~= hand.Color or arm.shirt ~= shirtOf(character :: Model) then
				if arm then
					arm.model:Destroy()
				end
				arm = buildArm(character :: Model, hand, lower)
			end
		elseif arm then
			arm.model:Destroy()
			arm = nil
		end
		if arm and arm.model.Parent ~= camera then
			arm.model.Parent = camera
		end
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
		local walkDown, walkSide, walkRoll = ToolView.walkBob(CameraFeel.walk())

		-- Turn sway: the hand drifts against the turn for a moment, as if it lags behind the view.
		local look = camera.CFrame.Rotation
		local swayTarget = Vector2.zero
		if lastLook and dt > 0 then
			local pitchTurn, yawTurn = lastLook:ToObjectSpace(look):ToEulerAnglesYXZ()
			swayTarget = Vector2.new(
				math.clamp(yawTurn / dt * SWAY_PER_RATE, -SWAY_MAX, SWAY_MAX),
				math.clamp(pitchTurn / dt * SWAY_PER_RATE, -SWAY_MAX, SWAY_MAX)
			)
		end
		lastLook = look
		sway += (swayTarget - sway) * (1 - math.exp(-SWAY_EASE * dt))

		local down = pose[1] + revealDown + walkDown + sway.Y
		local side = pose[2] + walkSide + sway.X
		local tilt = pose[3] + revealTilt
		-- Frame the tool by its centre (grips sit anywhere: a bucket's bail, a tub's rim), but tilt it
		-- from the grip. The centre lands where the old box placeholders' centres sat.
		local yaw = CFrame.Angles(0, math.rad(-8), 0)
		local centre = Vector3.new(0.9 + viewSize * 0.25 + side, -0.9 - viewSize * 0.09 - down, -1.8 - viewSize * 0.72)
		local base = camera.CFrame * CFrame.new(centre - yaw:VectorToWorldSpace(centerOffset))
		local grip = base * CFrame.Angles(tilt, math.rad(-8), walkRoll)
		model:PivotTo(grip)
		if arm then
			local restGrip = base * CFrame.Angles(0, math.rad(-8), walkRoll)
			placeArm(arm, grip, restGrip, camera.CFrame * ARM_SHOULDER)
		end
		local water = (player:GetAttribute("Carried") or 0) > 0
		if water ~= shownWater then
			shownWater = water
			ToolModels.setWater(model, water)
		end
	end)
end

return Viewmodel
