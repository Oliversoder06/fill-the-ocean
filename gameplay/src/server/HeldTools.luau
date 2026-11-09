-- Puts each player's current tool in their character's right hand so other players see it.
-- Follows the player attributes ToolModel, Carried and Equipped that Run publishes. The tool hangs
-- from a Motor6D (HeldGrip) at the bottom of the hand; client/Bodies turns it in the hand to suit
-- how the tool is carried.
-- The worn backpack (player attribute Backpack, a model name or "") goes on the back: a clone of the
-- Accessory ReplicatedStorage.ToolModels.Backpacks.<name>, whose Handle holds an Attachment
-- "BodyBackAttachment" so Humanoid:AddAccessory welds it to the back.
-- A hotbar gadget out (player attribute Gadget, an item id) is held instead of the tool: a clone of
-- ReplicatedStorage.ToolModels.Gadgets.<item.model>. Run also drives two gadget pieces directly
-- (setHose, setLift): the Garden Hose's rope from its tap to the hand, and the Jetpack Tank's lift,
-- which exists only while the server lets the player fly.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local ToolView = require(ReplicatedStorage.Shared.ToolView)

local HELD_NAME = "HeldTool"
local GRIP_NAME = "HeldGrip"
local PACK_NAME = "WornBackpack"
local ROPE_NAME = "HoseRope"
local LIFT_NAME = "JetpackLift"
local LIFT_FORCE = 2 -- the lift's strongest push, in body weights (climbs at riseSpeed, then holds it)

local HeldTools = {}

local gadgetModels: { [string]: string } = {} -- gadget item id -> its model in ToolModels.Gadgets

local function hand(character: Model): BasePart?
	local h = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if h and h:IsA("BasePart") then h else nil
end

-- The tool's main part (named like the model, per shared/ToolModels); the rest is welded to it.
local function bodyOf(model: Model, modelName: string): BasePart
	local named = model:FindFirstChild(modelName)
	if named and named:IsA("BasePart") then
		return named
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(-6) ~= "_Water" then
			return d
		end
	end
	error(`ToolModels.{modelName} has no part to hold`)
end

local function refresh(player: Player)
	local character = player.Character
	local toolName = player:GetAttribute("ToolModel")
	local h = character and hand(character)
	if not (character and h and type(toolName) == "string") then
		return
	end
	local held = character:FindFirstChild(HELD_NAME)
	-- In hand: the hotbar gadget, else the tool while it is out, else nothing.
	local gadgetId = player:GetAttribute("Gadget")
	local gadget = if type(gadgetId) == "string" then gadgetModels[gadgetId] else nil
	local modelName = gadget or toolName
	if not gadget and player:GetAttribute("Equipped") == false then
		if held then
			held:Destroy()
		end
		return
	end
	if not held or held:GetAttribute("ModelName") ~= modelName then
		if held then
			held:Destroy()
		end
		local model = ToolModels.get(modelName, if gadget then "Gadgets" else nil):Clone()
		local extents = model:GetExtentsSize()
		local scale = ToolView.heldScale(math.max(extents.X, extents.Y, extents.Z))
		if scale < 1 then
			model:ScaleTo(scale)
		end
		model.Name = HELD_NAME
		model:SetAttribute("ModelName", modelName)
		local gripAt = CFrame.new(0, -h.Size.Y / 2, 0)
		model:PivotTo(h.CFrame * gripAt)
		local body = bodyOf(model, modelName)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				if d ~= body then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = body
					weld.Part1 = d
					weld.Parent = d
				end
			end
		end
		local grip = Instance.new("Motor6D")
		grip.Name = GRIP_NAME
		grip.Part0 = h
		grip.Part1 = body
		grip.C0 = gripAt
		grip.C1 = body.CFrame:ToObjectSpace(model:GetPivot())
		grip.Parent = body
		model.Parent = character
		held = model
	end
	ToolModels.setWater(held :: Model, (player:GetAttribute("Carried") or 0) > 0)
end

-- The Garden Hose's rope: from `tap`'s Attachment "Hose" to the right hand, `length` studs long, so
-- it also keeps the player within reach. Nil `tap` takes it off. Called on every publish (server/Run).
function HeldTools.setHose(player: Player, tap: BasePart?, length: number)
	local character = player.Character
	local rope = character and character:FindFirstChild(ROPE_NAME)
	local h = character and hand(character)
	local grip = h and h:FindFirstChild("RightGripAttachment")
	if not (tap and character and grip and grip:IsA("Attachment")) then
		if rope then
			rope:Destroy()
		end
		return
	end
	local from = tap:FindFirstChild("Hose") :: Attachment -- checked by server/Map.ensure
	if rope and rope:IsA("RopeConstraint") and rope.Attachment0 == from and rope.Attachment1 == grip then
		rope.Length = length
		return
	end
	if rope then
		rope:Destroy()
	end
	local new = Instance.new("RopeConstraint")
	new.Name = ROPE_NAME
	new.Attachment0 = from
	new.Attachment1 = grip
	new.Length = length
	new.Visible = true
	new.Parent = character
end

-- The Jetpack Tank's lift: a vertical-only LinearVelocity on the root that climbs at `riseSpeed`
-- studs a second (walking still steers sideways). Nil turns it off. Called on every publish
-- (server/Run), which turns it off the moment the fuel runs out.
function HeldTools.setLift(player: Player, riseSpeed: number?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local lift = root:FindFirstChild(LIFT_NAME)
	if not riseSpeed then
		if lift and lift:IsA("LinearVelocity") then
			lift.Enabled = false
		end
		return
	end
	if not lift then
		local attachment = Instance.new("Attachment")
		attachment.Name = `{LIFT_NAME}Attachment`
		attachment.Parent = root
		local velocity = Instance.new("LinearVelocity")
		velocity.Name = LIFT_NAME
		velocity.Attachment0 = attachment
		velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		velocity.LineDirection = Vector3.yAxis
		velocity.Enabled = false
		velocity.Parent = root
		lift = velocity
	end
	local velocity = lift :: LinearVelocity
	velocity.LineVelocity = riseSpeed
	velocity.MaxForce = root.AssemblyMass * workspace.Gravity * LIFT_FORCE
	velocity.Enabled = true
end

-- Puts the worn backpack on the character's back, swapping it when a bigger one is bought.
local function refreshPack(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local modelName = player:GetAttribute("Backpack")
	if not (character and humanoid and type(modelName) == "string") then
		return
	end
	local worn = character:FindFirstChild(PACK_NAME)
	if worn and worn:GetAttribute("ModelName") == modelName then
		return
	end
	if worn then
		worn:Destroy()
	end
	if modelName == "" then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild("ToolModels")
	local packs = folder and folder:FindFirstChild("Backpacks")
	local template = packs and packs:FindFirstChild(modelName)
	if not (template and template:IsA("Accessory")) then
		warn(`[HeldTools] ReplicatedStorage.ToolModels.Backpacks.{modelName} is missing (an Accessory); {player.Name}'s backpack isn't shown`)
		return
	end
	local pack = template:Clone()
	pack.Name = PACK_NAME
	pack:SetAttribute("ModelName", modelName)
	for _, d in pack:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	humanoid:AddAccessory(pack)
end

local function track(player: Player)
	player:GetAttributeChangedSignal("ToolModel"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("Carried"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("Equipped"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("Gadget"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("Backpack"):Connect(function()
		refreshPack(player)
	end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("RightHand", 5)
		refresh(player)
		character:WaitForChild("Humanoid", 5)
		refreshPack(player)
	end)
	refresh(player)
	refreshPack(player)
end

function HeldTools.start(config)
	ToolModels.check(config)
	for _, item in config.items do
		if item.kind == "gadget" then
			gadgetModels[item.id] = item.model
		end
	end

	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
end

return HeldTools
