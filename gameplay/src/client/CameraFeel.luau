-- First person only, with a soft head bob, a landing dip and a small tilt that reacts to movement.
-- The tilt never delays the aim: before Roblox's default camera runs we hand it back the untilted
-- camera, and after it runs we add the tilt on top for this frame only.
-- Bob and landing dip go through Humanoid.CameraOffset.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BOB_UP = 0.18 -- studs of vertical sway at full intensity
local BOB_SIDE = 0.1 -- studs of sideways sway at full intensity
local STEPS_PER_STUD = 0.09 -- bob cycles per stud walked, so faster walking bobs faster
local BOB_EASE = 8 -- how quickly the bob fades in and out
local MOVING_SPEED = 1 -- studs/s below which the player counts as standing
local LAND_DIP_PER_SPEED = 0.012 -- studs of dip per stud/s of fall speed
local LAND_DIP_MAX = 0.6
local SPRING = 140 -- landing spring stiffness
local DAMPING = 0.75 -- landing spring damping ratio (1 = no bounce)

local ROLL_PER_STRAFE = 1.2 -- degrees of roll at 16 studs/s sideways
local ROLL_PER_TURN = 0.006 -- degrees of roll per degree/s of turning
local PITCH_PER_RISE = 0.04 -- degrees of pitch per stud/s of vertical speed
local PITCH_PER_DIP = 5 -- degrees of forward pitch per stud of landing dip
local TILT_MAX = 2 -- degrees, clamp for roll and pitch
local TILT_EASE = 10 -- how quickly the tilt follows (the aim itself is never delayed)

local player = Players.LocalPlayer
local CameraFeel = {}

local function ease(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function yawOf(cframe: CFrame): number
	local look = cframe.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

function CameraFeel.start()
	player.CameraMode = Enum.CameraMode.LockFirstPerson

	local untilted: CFrame? = nil
	local lastYaw: number? = nil
	local roll, pitch = 0, 0
	local phase, intensity = 0, 0
	local dip, dipVelocity = 0, 0
	local airSpeed = 0 -- fastest downward speed during the current fall

	local function usable(): boolean
		return workspace.CurrentCamera.CameraType == Enum.CameraType.Custom
	end

	-- Before the default camera: remove last frame's tilt so input applies to the real aim.
	RunService:BindToRenderStep("CameraFeelRestore", Enum.RenderPriority.Camera.Value - 1, function()
		if untilted and usable() then
			workspace.CurrentCamera.CFrame = untilted
		end
	end)

	-- After the default camera: update bob, dip and tilt, then show the tilted view.
	RunService:BindToRenderStep("CameraFeelApply", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = workspace.CurrentCamera
		if not usable() then
			untilted, lastYaw = nil, nil
			return
		end
		local aim = camera.CFrame
		untilted = aim

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- lihfolk-ignore: findfirstchild-chain (root is nil-checked on the next line before use)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (humanoid and root) or dt <= 0 then
			return
		end
		local velocity = root.AssemblyLinearVelocity
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

		-- Landing dip: remember the fall speed, kick the spring when we touch down.
		if not grounded then
			airSpeed = math.max(airSpeed, -velocity.Y)
		elseif airSpeed > 0 then
			dipVelocity -= math.min(airSpeed * LAND_DIP_PER_SPEED, LAND_DIP_MAX) * math.sqrt(SPRING)
			airSpeed = 0
		end
		local accel = -SPRING * dip - 2 * DAMPING * math.sqrt(SPRING) * dipVelocity
		dipVelocity += accel * dt
		dip += dipVelocity * dt

		-- Head bob
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local wanted = if speed > MOVING_SPEED and grounded then math.min(speed / 16, 1.5) else 0
		intensity += (wanted - intensity) * ease(BOB_EASE, dt)
		phase += speed * STEPS_PER_STUD * dt * 2 * math.pi
		humanoid.CameraOffset = Vector3.new(
			math.sin(phase) * BOB_SIDE * intensity,
			math.abs(math.cos(phase)) * BOB_UP * intensity - BOB_UP * intensity * 0.5 + dip,
			0
		)

		-- Tilt: roll into strafes and turns, pitch with vertical speed and the landing dip.
		local yaw = yawOf(aim)
		local turnRate = 0
		if lastYaw then
			turnRate = ((yaw - lastYaw + 180) % 360 - 180) / dt
		end
		lastYaw = yaw
		local strafe = aim.Rotation:VectorToObjectSpace(velocity).X
		local rollTarget = math.clamp(-strafe / 16 * ROLL_PER_STRAFE - turnRate * ROLL_PER_TURN, -TILT_MAX, TILT_MAX)
		local pitchTarget = math.clamp(velocity.Y * PITCH_PER_RISE + dip * PITCH_PER_DIP, -TILT_MAX, TILT_MAX)
		roll += (rollTarget - roll) * ease(TILT_EASE, dt)
		pitch += (pitchTarget - pitch) * ease(TILT_EASE, dt)
		camera.CFrame = aim * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
	end)
end

return CameraFeel
