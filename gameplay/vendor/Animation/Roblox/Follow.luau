--!strict
--[[
	Follow (Roblox only): makes a model walk after a target in gameplay (a pet following its
	player), with the creature's own gait.

	It bakes two in-place cycles once (a comfortable walk and a run) and, every frame, advances
	them by the distance the model actually covered, so the feet stay planted at any speed:
	slower ground speed means slower steps, not skating. Between the two speeds the cycles blend
	(they share a phase); near standstill the pose eases back to rest.

	Two modes:
	- drive    Follow moves the model: it steers towards the target (or a point beside it),
	           speeds up and slows down at a creature-sized rate, turns at a steady rate, keeps to
	           the ground by a downward ray, and leans into acceleration.
	- observe  something else moves the model (the game's own pet mover); Follow only reads how
	           far it went each frame and animates to match.

	Joints are written in PreSimulation, after the Animator. destroy() puts them back.
]]

local RunService: RunService = game:GetService("RunService")
local Workspace: Workspace = game:GetService("Workspace")

local Rig = require("../Rig")
local Anatomy = require("../Anatomy")
local Baked = require("../Baked")
local Gait = require("../Gait")
local GaitPlan = require("../GaitPlan")
local RigReader = require("./RigReader")
local PoseWriter = require("./PoseWriter")

local Follow = {}
Follow.__index = Follow

export type Options = {
	target: any?,
	distance: number?,
	speed: number?,
	runSpeed: number?,
	mode: string?,
	offset: Vector3?,
	overrides: any?,
	turnRate: number?,
	gravity: number?,
}

local function targetPosition(target: any): Vector3?
	if typeof(target) == "function" then
		local ok, v = pcall(target)
		if ok and typeof(v) == "Vector3" then
			return v
		end
		return nil
	end
	if target ~= nil and typeof(target) == "Instance" then
		if target:IsA("BasePart") then
			return target.Position
		elseif target:IsA("Model") then
			return target:GetPivot().Position
		end
	end
	if target ~= nil and typeof(target) == "Vector3" then
		return target
	end
	return nil
end

-- out = blend of a and b (same channel layout) at t; quaternions by nlerp on the short arc.
local function blend(a: { number }, b: { number }, t: number, out: { number }, nch: number)
	local s = 1 - t
	for c = 0, nch do
		local o = c * 7
		out[o + 1] = a[o + 1] * s + b[o + 1] * t
		out[o + 2] = a[o + 2] * s + b[o + 2] * t
		out[o + 3] = a[o + 3] * s + b[o + 3] * t
		local ax, ay, az, aw = a[o + 4], a[o + 5], a[o + 6], a[o + 7]
		local bx, by, bz, bw = b[o + 4], b[o + 5], b[o + 6], b[o + 7]
		if ax * bx + ay * by + az * bz + aw * bw < 0 then
			bx, by, bz, bw = -bx, -by, -bz, -bw
		end
		local qx, qy, qz, qw = ax * s + bx * t, ay * s + by * t, az * s + bz * t, aw * s + bw * t
		local l = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
		if l > 1e-12 then
			qx, qy, qz, qw = qx / l, qy / l, qz / l, qw / l
		else
			qx, qy, qz, qw = 0, 0, 0, 1
		end
		out[o + 4], out[o + 5], out[o + 6], out[o + 7] = qx, qy, qz, qw
	end
end

function Follow.new(model: Instance, opts: Options?)
	local o: Options = opts or {}
	local read = RigReader.read(model, {})
	local rig = Rig.build(read.spec)
	local anatomy = Anatomy.classify(rig, o.overrides)
	local gravity = if type(o.gravity) == "number" then o.gravity else Workspace.Gravity
	local maxStance, crouch, comfort = GaitPlan.reach(anatomy)
	local _ = maxStance
	local _c = crouch
	local walkSpeed = if type(o.speed) == "number" and o.speed > 0 then o.speed else comfort
	local runSpeed = if type(o.runSpeed) == "number" and o.runSpeed > walkSpeed then o.runSpeed else walkSpeed * 2.2
	local walk = Gait.cycle(anatomy, { speed = walkSpeed, gravity = gravity })
	local run = Gait.cycle(anatomy, { speed = runSpeed, gravity = gravity })
	local writer = PoseWriter.new(read, rig, walk, "replace")
	local root = read.root
	local start = if root then root.CFrame else CFrame.identity
	local look = start.LookVector
	local self = setmetatable({
		model = model,
		read = read,
		rig = rig,
		anatomy = anatomy,
		walk = walk,
		run = run,
		walkSpeed = walkSpeed,
		runSpeed = runSpeed,
		walkStride = walkSpeed * walk.length,
		runStride = runSpeed * run.length,
		writer = writer,
		bufA = Baked.buffer(walk),
		bufB = Baked.buffer(run),
		bufOut = Baked.buffer(walk),
		target = o.target,
		distance = if type(o.distance) == "number" then o.distance else 4 * math.max(anatomy.hipHeight, 0.5),
		offset = o.offset,
		mode = if o.mode == "observe" then "observe" else "drive",
		turnRate = math.rad(if type(o.turnRate) == "number" then o.turnRate else 200),
		accel = 0.6 * GaitPlan.gaitGravity({ gravity = gravity }),
		phase = 0,
		speed = 0,
		moving = 0,
		position = start.Position,
		yaw = math.atan2(-look.X, -look.Z),
		lastPivot = start.Position,
		rootHeight = -rig.ground,
		alive = true,
		connection = nil :: RBXScriptConnection?,
	}, Follow)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model }
	self.params = rayParams
	self.connection = RunService.PreSimulation:Connect(function(dt: number)
		local ok, err = pcall(Follow.step :: any, self, dt)
		if not ok then
			warn("[Animation] Follow stopped: " .. tostring(err))
			self:destroy()
		end
	end)
	return self
end

function Follow.step(self: any, dt: number)
	if not self.alive or dt <= 0 then
		return
	end
	local model: Instance = self.model
	if not model.Parent then
		self:destroy()
		return
	end
	local speed: number
	if self.mode == "drive" then
		local goal = targetPosition(self.target)
		local want = 0
		local dir = Vector3.zero
		if goal then
			if self.offset and typeof(self.target) == "Instance" then
				local cf = if self.target:IsA("Model") then self.target:GetPivot() else (self.target :: any).CFrame
				goal = (cf * CFrame.new(self.offset)).Position
			end
			local d = Vector3.new((goal :: Vector3).X - self.position.X, 0, (goal :: Vector3).Z - self.position.Z)
			local dist = d.Magnitude
			if dist > 1e-4 then
				dir = d / dist
			end
			-- arrive: full pace when far, easing to a stop at the follow distance
			local gap = dist - self.distance
			if gap > 0 then
				want = math.min(self.runSpeed, math.sqrt(2 * self.accel * gap), self.walkSpeed * (1 + gap / (4 * self.distance)))
			end
		end
		-- steady acceleration, no jumps in speed
		local dv = math.clamp(want - self.speed, -self.accel * dt, self.accel * dt)
		self.speed = math.max(0, self.speed + dv)
		if dir.Magnitude > 0 and self.speed > 1e-3 then
			local wantYaw = math.atan2(-dir.X, -dir.Z)
			local diff = (wantYaw - self.yaw + math.pi) % (2 * math.pi) - math.pi
			local turn = math.clamp(diff, -self.turnRate * dt, self.turnRate * dt)
			self.yaw += turn
		end
		local fwd = Vector3.new(-math.sin(self.yaw), 0, -math.cos(self.yaw))
		self.position += fwd * self.speed * dt
		-- keep to the ground under the model
		local hit = Workspace:Raycast(self.position + Vector3.new(0, 10 * self.rootHeight + 5, 0), Vector3.new(0, -(20 * self.rootHeight + 50), 0), self.params)
		local y = if hit then hit.Position.Y + self.rootHeight else self.position.Y
		self.position = Vector3.new(self.position.X, y, self.position.Z)
		speed = self.speed
	else
		local pivot = (if model:IsA("Model") then model:GetPivot() else (model :: any).CFrame) :: CFrame
		local p = pivot.Position
		local moved = Vector3.new(p.X - self.lastPivot.X, 0, p.Z - self.lastPivot.Z).Magnitude
		self.lastPivot = p
		-- smoothed, so a jittery mover does not make jittery legs
		local raw = moved / dt
		self.speed += (raw - self.speed) * math.min(1, dt * 10)
		speed = self.speed
		self.position = p
	end
	-- phase by distance: a stride per cycle, whichever blend of walk and run is showing
	local mix = math.clamp((speed - self.walkSpeed) / math.max(self.runSpeed - self.walkSpeed, 1e-3), 0, 1)
	mix = mix * mix * (3 - 2 * mix)
	local stride = self.walkStride * (1 - mix) + self.runStride * mix
	if stride > 1e-6 then
		self.phase = (self.phase + speed * dt / stride) % 1
	end
	local target = math.clamp(speed / math.max(0.15 * self.walkSpeed, 1e-3), 0, 1)
	self.moving += (target - self.moving) * math.min(1, dt * 6)
	Baked.sample(self.walk, self.phase * self.walk.length, self.bufA)
	Baked.sample(self.run, self.phase * self.run.length, self.bufB)
	blend(self.bufA, self.bufB, mix, self.bufOut, self.walk.nch)
	PoseWriter.write(self.writer, self.bufOut, self.moving)
	if self.mode == "drive" then
		local base = CFrame.new(self.position) * CFrame.Angles(0, self.yaw - self.rig.facing, 0)
		local b = self.bufOut
		local offset = CFrame.new(b[1], b[2], b[3], b[4], b[5], b[6], b[7])
		local blended = CFrame.identity:Lerp(offset, self.moving)
		PoseWriter.place(self.writer, base * blended)
	end
end

function Follow.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	PoseWriter.restore(self.writer)
end

return Follow
