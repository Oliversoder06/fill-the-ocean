-- Third-person bodies: how every character (other players, and your own for its shadow) carries
-- its tool and moves. Each frame, after the default animations, it adjusts their joints:
--   carry: the arms reach for the tool by two-bone IK, in a pose per tool (shared/BodyPose), and
--     the tool turns in the hand through the HeldGrip motor (server/HeldTools);
--   actions: scoops and pours on the first-person pose curves (shared/ToolView), from ActKind and
--     ActAt (server/Run) for others and from client/Action for you;
--   walk: a bounce and twist in time with the animated legs, a lean into speed and turns, a
--     lean-back and waddle under a heavy load, and a crouch with dust on landing;
--   look: the head and chest follow where the player looks (the Look attribute; yours from the
--     camera, sent through the Look remote);
--   drips: other players' full tools drip (Cues.carry).
-- Joints follow child = Attachment0.WorldCFrame * Transform * Attachment1.CFrame:Inverse(). Poses
-- are worked out in root-part space, so they don't depend on where the character stands.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BodyPose = require(ReplicatedStorage.Shared.BodyPose)
local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Ease = require(ReplicatedStorage.Shared.Ease)
local ToolView = require(ReplicatedStorage.Shared.ToolView)
local Action = require(script.Parent.Action)
local Footsteps = require(script.Parent.Footsteps)

local RANGE = 200 -- studs; farther bodies keep the default animations
local REBUILD_SECONDS = 1 -- how often to retry a character whose rig isn't ready
local ARM_EASE = 8 -- how quickly the arms take hold of or let go of the tool
local LEAN_EASE = 6
local LOOK_EASE = 10
local INTENSITY_EASE = 8
local VELOCITY_EASE = 12 -- smooths others' replicated movement before it drives the lean
local SWING_DECAY = 0.6 -- per second, how fast the widest remembered leg swing shrinks
local MOVING_SPEED = 1 -- studs/s below which a body counts as standing
local BLEND_SECONDS = 0.08 -- eases into each new action's pose (as client/Viewmodel)
local LOOK_SEND_INTERVAL = 0.15 -- seconds between Look sends (the server accepts one per 0.1 s)
local LOOK_SEND_STEP = 2 -- degrees of change worth sending

local JOINT_NAMES = {
	"Root",
	"Waist",
	"Neck",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightHip",
	"RightKnee",
	"RightAnkle",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
}
local JOINT_SET = {}
for _, name in JOINT_NAMES do
	JOINT_SET[name] = true
end

local player = Players.LocalPlayer
local Bodies = {}

type Joint = { instance: any, base: CFrame, written: CFrame? }
type Arm = { shoulder: Joint, elbow: Joint, wrist: Joint }
type Body = {
	owner: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	joints: { [string]: Joint },
	right: Arm,
	left: Arm,
	lastPos: Vector3?,
	lastYaw: number?,
	velocity: Vector3,
	intensity: number,
	maxSwing: number,
	pitch: number,
	roll: number,
	look: number,
	dip: number,
	dipVelocity: number,
	airSpeed: number,
	armWeight: number,
	pose: { number }, -- action (down, tilt), as client/Viewmodel
	from: { number },
	changedAt: number,
	actionId: any,
	grip: Motor6D?,
	drips: { ParticleEmitter },
	dripsOn: BasePart?,
	active: boolean,
}

-- A joint's two frames, in its parent part's and child part's space.
local function frames(j: Joint): (CFrame, CFrame)
	local inst = j.instance
	if inst:IsA("Motor6D") then
		return inst.C0, inst.C1
	end
	return inst.Attachment0.CFrame, inst.Attachment1.CFrame
end

local function childPart(j: Joint): BasePart
	local inst = j.instance
	return if inst:IsA("Motor6D") then inst.Part1 else inst.Attachment1.Parent
end

-- Length of the part between two joints: from where `from` enters it to where `to` leaves it.
local function boneLength(from: Joint, to: Joint): number
	local _, enter = frames(from)
	local leave = frames(to)
	return (leave.Position - enter.Position).Magnitude
end

local function intact(j: Joint): boolean
	local inst = j.instance
	if inst.Parent == nil then
		return false
	end
	if inst:IsA("Motor6D") then
		return inst.Part0 ~= nil and inst.Part1 ~= nil
	end
	return inst.Attachment0 ~= nil and inst.Attachment1 ~= nil
end

-- Smallest rotation that turns unit vector a onto unit vector b.
local function turnTo(a: Vector3, b: Vector3): CFrame
	local dot = math.clamp(a:Dot(b), -1, 1)
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-5 then
		if dot > 0 then
			return CFrame.identity
		end
		local other = if math.abs(a.X) < 0.9 then Vector3.xAxis else Vector3.yAxis
		return CFrame.fromAxisAngle(a:Cross(other).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function ease(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function yawOf(cframe: CFrame): number
	local look = cframe.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- Two-bone IK: the shoulder, elbow and wrist transforms that put the hand at `hand` (root space)
-- with the elbow toward `pole`. Out of reach, the arm straightens and the hand stops short.
local function solveArm(arm: Arm, torso: CFrame, hand: CFrame, pole: Vector3): (CFrame, CFrame, CFrame)
	local s0, s1 = frames(arm.shoulder)
	local e0, e1 = frames(arm.elbow)
	local w0, w1 = frames(arm.wrist)
	local upperBone = e0.Position - s1.Position
	local lowerBone = w0.Position - e1.Position
	local shoulder = (torso * s0).Position
	local toWrist = (hand * w1).Position - shoulder
	local distance = toWrist.Magnitude
	local dir = if distance > 1e-4 then toWrist / distance else -torso.UpVector
	local along, out, reach = BodyPose.elbow(upperBone.Magnitude, lowerBone.Magnitude, distance)
	local side = pole - dir * pole:Dot(dir)
	side = if side.Magnitude > 1e-4 then side.Unit else torso.RightVector
	local elbowAt = shoulder + dir * along + side * out

	local upperRest = (torso * s0 * s1:Inverse()).Rotation
	local upperRot = turnTo(upperRest * upperBone.Unit, (elbowAt - shoulder).Unit) * upperRest
	local upper = CFrame.new(shoulder) * upperRot * CFrame.new(-s1.Position)
	local elbowReal = (upper * e0).Position
	local lowerRest = (upper * e0 * e1:Inverse()).Rotation
	local lowerRot = turnTo(lowerRest * lowerBone.Unit, (shoulder + dir * reach - elbowReal).Unit) * lowerRest
	local lower = CFrame.new(elbowReal) * lowerRot * CFrame.new(-e1.Position)
	local handReal = CFrame.new((lower * w0).Position) * hand.Rotation * CFrame.new(-w1.Position)
	return (torso * s0):Inverse() * (upper * s1), (upper * e0):Inverse() * (lower * e1), (lower * w0):Inverse() * (handReal * w1)
end

local function build(owner: Player, character: Model): Body?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not (humanoid and root) then
		return nil
	end
	local joints: { [string]: Joint } = {}
	for _, d in character:GetDescendants() do
		if JOINT_SET[d.Name] and not joints[d.Name] and (d:IsA("AnimationConstraint") or d:IsA("Motor6D")) then
			joints[d.Name] = { instance = d, base = d.Transform, written = nil }
		end
	end
	for _, name in JOINT_NAMES do
		local j = joints[name]
		if not (j and intact(j)) then
			return nil -- still loading, or not an R15 rig (left to the default animations)
		end
	end
	return {
		owner = owner,
		character = character,
		humanoid = humanoid,
		root = root,
		joints = joints,
		right = { shoulder = joints.RightShoulder, elbow = joints.RightElbow, wrist = joints.RightWrist },
		left = { shoulder = joints.LeftShoulder, elbow = joints.LeftElbow, wrist = joints.LeftWrist },
		lastPos = nil,
		lastYaw = nil,
		velocity = Vector3.zero,
		intensity = 0,
		maxSwing = 0,
		pitch = 0,
		roll = 0,
		look = 0,
		dip = 0,
		dipVelocity = 0,
		airSpeed = 0,
		armWeight = 0,
		pose = { 0, 0 },
		from = { 0, 0 },
		changedAt = -math.huge,
		actionId = nil,
		grip = nil,
		drips = {},
		dripsOn = nil,
		active = false,
	}
end

local function setDrips(body: Body, water: BasePart?, template: Instance)
	if body.dripsOn == water then
		return
	end
	for _, emitter in body.drips do
		emitter:Destroy()
	end
	table.clear(body.drips)
	body.dripsOn = water
	if water then
		for _, emitter in template:GetChildren() do
			if emitter:IsA("ParticleEmitter") then
				local copy = emitter:Clone()
				copy.Enabled = true
				copy.Parent = water
				table.insert(body.drips, copy)
			end
		end
	end
end

-- Hands every joint back to the default animations (out of range, dead, or leaving).
local function release(body: Body, dripsTemplate: Instance)
	if not body.active then
		return
	end
	body.active = false
	for _, j in body.joints do
		if j.written and j.instance.Transform == j.written then
			j.instance.Transform = j.base
		end
		j.written = nil
	end
	if body.grip then
		body.grip.Transform = CFrame.identity
	end
	setDrips(body, nil, dripsTemplate)
	body.armWeight, body.lastPos, body.lastYaw = 0, nil, nil
end

-- The current action as (kind, progress, id), or nil.
local function currentAction(body: Body): (string?, number, any)
	if body.owner == player then
		local action = Action.current()
		if action then
			return action.kind, (os.clock() - action.started) / action.duration, action.id
		end
		return nil, 0, nil
	end
	local kind, at = body.owner:GetAttribute("ActKind"), body.owner:GetAttribute("ActAt")
	if (kind ~= "scoop" and kind ~= "pour") or type(at) ~= "number" then
		return nil, 0, nil
	end
	local duration = if kind == "pour" then Config.pourSeconds else body.owner:GetAttribute("ActSeconds") or Config.start.actSeconds
	local progress = (workspace:GetServerTimeNow() - at) / duration
	if progress < 0 or progress >= 1 then
		return nil, 0, nil
	end
	return kind, progress, at
end

-- The action pose (down, tilt): eases into each new action, springs back after (as client/Viewmodel).
local function updateAction(body: Body, now: number)
	local kind, progress, id = currentAction(body)
	if kind then
		if id ~= body.actionId then
			body.actionId, body.from, body.changedAt = id, table.clone(body.pose), now
		end
		local down, _, tilt = (if kind == "scoop" then ToolView.scoopPose else ToolView.pourPose)(progress)
		local b = math.clamp((now - body.changedAt) / BLEND_SECONDS, 0, 1)
		b = b * b * (3 - 2 * b)
		body.pose[1] = body.from[1] + (down - body.from[1]) * b
		body.pose[2] = body.from[2] + (tilt - body.from[2]) * b
	else
		if body.actionId then
			body.actionId, body.from, body.changedAt = nil, table.clone(body.pose), now
		end
		body.pose[1] = Ease.pop(body.from[1], 0, now - body.changedAt)
		body.pose[2] = Ease.pop(body.from[2], 0, now - body.changedAt)
	end
end

local function waterOf(held: Instance): BasePart?
	for _, d in held:GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(-6) == "_Water" then
			return d
		end
	end
	return nil
end

local function pose(body: Body, dt: number, now: number, dripsTemplate: Instance)
	local joints = body.joints
	local root, humanoid = body.root, body.humanoid
	body.active = true

	-- What the default animations want this frame (unchanged if they didn't touch a joint).
	for _, j in joints do
		local current = j.instance.Transform
		if current ~= j.written then
			j.base = current
		end
	end

	-- Movement, from the root's motion (works the same for replicated characters).
	local pos = root.Position
	local velocity = Vector3.zero
	if body.lastPos then
		velocity = (pos - body.lastPos) / dt
	end
	body.lastPos = pos
	body.velocity += (velocity - body.velocity) * ease(VELOCITY_EASE, dt)
	local v = body.velocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local forward = v:Dot(root.CFrame.LookVector)
	local yaw = yawOf(root.CFrame)
	local turnRate = if body.lastYaw then ((yaw - body.lastYaw + math.pi) % (2 * math.pi) - math.pi) / dt else 0
	body.lastYaw = yaw
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

	-- Landing: remember the fall speed, kick the dip spring (and some dust) on touchdown.
	if not grounded then
		body.airSpeed = math.max(body.airSpeed, -velocity.Y)
	elseif body.airSpeed > 0 then
		local dip = BodyPose.landDip(body.airSpeed)
		if dip > 0 then
			body.dipVelocity += dip * math.sqrt(BodyPose.DIP_SPRING)
			Footsteps.dust(humanoid, Cues.steps.landDust)
		end
		body.airSpeed = 0
	end
	local spring = BodyPose.DIP_SPRING
	body.dipVelocity += (-spring * body.dip - 2 * BodyPose.DIP_DAMPING * math.sqrt(spring) * body.dipVelocity) * dt
	body.dip = math.max(body.dip + body.dipVelocity * dt, 0)

	-- The tool and how it is carried.
	local held = body.character:FindFirstChild("HeldTool")
	local modelName = held and held:GetAttribute("ModelName")
	local found = held and held:FindFirstChild("HeldGrip", true)
	local grip: Motor6D? = if found and found:IsA("Motor6D") and type(modelName) == "string" then found else nil
	if body.grip and body.grip ~= grip and body.grip.Parent then
		body.grip.Transform = CFrame.identity
	end
	body.grip = grip
	local style, turn = BodyPose.carry(if type(modelName) == "string" then modelName else "")
	local carrying = (body.owner:GetAttribute("Carried") or 0) > 0
	local heavy = grip ~= nil and carrying and style.heavy
	body.armWeight += ((if grip then 1 else 0) - body.armWeight) * ease(ARM_EASE, dt)
	if body.owner ~= player then
		setDrips(body, if grip and carrying and held then waterOf(held) else nil, dripsTemplate)
	end

	-- Walk: bounce and twist in time with the animated legs.
	local swing = joints.RightHip.base:ToEulerAnglesXYZ()
	body.maxSwing = math.max(math.abs(swing), body.maxSwing * math.exp(-SWING_DECAY * dt))
	local wanted = if speed > MOVING_SPEED and grounded then math.min(speed / BodyPose.WALK_SPEED, 1.5) else 0
	body.intensity += (wanted - body.intensity) * ease(INTENSITY_EASE, dt)
	local bounce, twist, waddle = BodyPose.stride(swing, body.maxSwing, body.intensity, heavy)

	local leanPitch, leanRoll = BodyPose.lean(forward, speed, turnRate, heavy)
	body.pitch += (leanPitch - body.pitch) * ease(LEAN_EASE, dt)
	body.roll += (leanRoll - body.roll) * ease(LEAN_EASE, dt)

	local lookTarget = 0
	if body.owner == player then
		lookTarget = math.deg(math.asin(math.clamp(workspace.CurrentCamera.CFrame.LookVector.Y, -1, 1)))
	else
		local look = body.owner:GetAttribute("Look")
		lookTarget = if type(look) == "number" then look else 0
	end
	body.look += (lookTarget - body.look) * ease(LOOK_EASE, dt)
	local neckLook, waistLook = BodyPose.look(body.look)

	updateAction(body, now)
	local gripDown, gripForward, tilt, bend = BodyPose.fromView(body.pose[1], body.pose[2])

	-- Torso and legs.
	local rootT = joints.Root.base * CFrame.new(0, bounce - body.dip, 0) * CFrame.Angles(0, 0, body.roll + waddle)
	local waistT = joints.Waist.base * CFrame.Angles(body.pitch - bend + waistLook, twist, 0)
	local out: { [string]: CFrame } = {
		Root = rootT,
		Waist = waistT,
		Neck = joints.Neck.base * CFrame.Angles(neckLook, 0, 0),
	}
	local crouch = BodyPose.crouch(body.dip, boneLength(joints.RightHip, joints.RightKnee))
	if crouch > 0 then
		for _, side in { "Right", "Left" } do
			out[side .. "Hip"] = joints[side .. "Hip"].base * CFrame.Angles(crouch, 0, 0)
			out[side .. "Knee"] = joints[side .. "Knee"].base * CFrame.Angles(-2 * crouch, 0, 0)
			out[side .. "Ankle"] = joints[side .. "Ankle"].base * CFrame.Angles(crouch, 0, 0)
		end
	end

	-- Arms: reach for the tool's grip, placed in torso space by the carry style.
	local w = body.armWeight
	if grip and w > 1e-3 then
		local root0, root1 = frames(joints.Root)
		local waist0, waist1 = frames(joints.Waist)
		local torso = root0 * rootT * root1:Inverse() * waist0 * waistT * waist1:Inverse()
		local armLength = boneLength(joints.RightShoulder, joints.RightElbow) + boneLength(joints.RightElbow, joints.RightWrist)
		local reach = Vector3.new(style.reach[1], style.reach[2], style.reach[3]) * armLength
			+ Vector3.new(0, -gripDown, -gripForward)
		local pole = Vector3.new(style.pole[1], style.pole[2], style.pole[3])
		local handTurn = CFrame.Angles(tilt, 0, 0) * CFrame.Angles(style.hand, 0, 0)
		local toolInHand = CFrame.Angles(-style.hand, 0, 0) * CFrame.Angles(0, turn, 0)

		local rightShoulder = frames(joints.RightShoulder).Position
		local toolAt = torso * CFrame.new(rightShoulder + reach) * CFrame.Angles(tilt, 0, 0) * CFrame.Angles(0, turn, 0)
		local hand = toolAt * toolInHand:Inverse() * grip.C0:Inverse()
		local s, e, wr = solveArm(body.right, torso, hand, torso:VectorToWorldSpace(pole))
		out.RightShoulder = joints.RightShoulder.base:Lerp(s, w)
		out.RightElbow = joints.RightElbow.base:Lerp(e, w)
		out.RightWrist = joints.RightWrist.base:Lerp(wr, w)
		grip.Transform = CFrame.new():Lerp(toolInHand, w)

		if style.twoHanded then
			local leftShoulder = frames(joints.LeftShoulder).Position
			local mirrored = Vector3.new(-reach.X, reach.Y, reach.Z)
			local leftHand = childPart(joints.LeftWrist)
			local leftAt = torso * CFrame.new(leftShoulder + mirrored) * handTurn * CFrame.new(0, leftHand.Size.Y / 2, 0)
			local ls, le, lw = solveArm(body.left, torso, leftAt, torso:VectorToWorldSpace(Vector3.new(-pole.X, pole.Y, pole.Z)))
			out.LeftShoulder = joints.LeftShoulder.base:Lerp(ls, w)
			out.LeftElbow = joints.LeftElbow.base:Lerp(le, w)
			out.LeftWrist = joints.LeftWrist.base:Lerp(lw, w)
		end
	end

	for _, name in JOINT_NAMES do
		local j = joints[name]
		local value = out[name] or j.base
		j.instance.Transform = value
		j.written = value
	end
end

function Bodies.start()
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local dripsTemplate = vfx:WaitForChild(Cues.carry.drips, 10)
	assert(dripsTemplate and dripsTemplate:IsA("Attachment"), `Vfx is missing {Cues.carry.drips} (an Attachment)`)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local lookRemote = remotes and remotes:WaitForChild("Look", 10)
	assert(lookRemote and lookRemote:IsA("RemoteEvent"), "ReplicatedStorage.Remotes is missing Look (Rojo project)")

	local bodies: { [Model]: Body } = {}
	local retryAt: { [Model]: number } = {}
	local lastSent, lastSentAt = math.huge, -math.huge

	RunService.PreSimulation:Connect(function(dt: number)
		if dt <= 0 then
			return
		end
		local now = os.clock()
		local camera = workspace.CurrentCamera

		-- Where you look, for everyone else's copy of your head.
		local pitch = math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)))
		if math.abs(pitch - lastSent) >= LOOK_SEND_STEP and now - lastSentAt >= LOOK_SEND_INTERVAL then
			lastSent, lastSentAt = pitch, now
			lookRemote:FireServer(pitch)
		end

		local seen: { [Model]: boolean } = {}
		for _, owner in Players:GetPlayers() do
			local character = owner.Character
			if not character then
				continue
			end
			seen[character] = true
			local body = bodies[character]
			if body then
				for _, j in body.joints do
					if not intact(j) then
						release(body, dripsTemplate)
						bodies[character], body = nil, nil
						break
					end
				end
			end
			if not body then
				if now < (retryAt[character] or 0) then
					continue
				end
				body = build(owner, character)
				if not body then
					retryAt[character] = now + REBUILD_SECONDS
					continue
				end
				bodies[character] = body
			end
			local b = body :: Body
			local near = (b.root.Position - camera.CFrame.Position).Magnitude <= RANGE
			if near and b.humanoid.Health > 0 then
				pose(b, dt, now, dripsTemplate)
			else
				release(b, dripsTemplate)
			end
		end
		for character, body in bodies do
			if not seen[character] then
				release(body, dripsTemplate)
				bodies[character] = nil
			end
		end
		for character in retryAt do
			if not seen[character] then
				retryAt[character] = nil
			end
		end
	end)
end

return Bodies
