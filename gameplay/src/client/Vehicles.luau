-- The local player's own vehicle (server/Vehicles, the model workspace.Vehicle_<UserId>). While they
-- sit in its VehicleSeat they own its physics, so this sets the Drive and Turn constraints the server
-- made: the seat's throttle (W/S, gamepad triggers, touch thumbstick) speeds it up to its Speed
-- attribute and steer (A/D) turns it, like a car (no turning on the spot, reverse turns the other
-- way). The Water Bomber also climbs and dives: E / gamepad R1 / touch "Up", Q / L1 / touch "Down",
-- bound only while flying it. Action and Hotbar ask here whether the player holds their truck's hose
-- and for the tank gauge.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.Hud)

local TURN_FULL_SPEED = 8 -- studs a second at which steering turns at full rate

local player = Players.LocalPlayer
local Vehicles = {}

-- The local player's vehicle and its parts, or nil (none out, or not streamed in yet).
local function mine(): (Model?, BasePart?, VehicleSeat?)
	local model = workspace:FindFirstChild(`Vehicle_{player.UserId}`)
	local root = model and model:IsA("Model") and model.PrimaryPart
	local seat = root and model:FindFirstChild("Seat", true)
	if not (root and seat and seat:IsA("VehicleSeat")) then
		return nil, nil, nil
	end
	return model, root, seat
end

local function humanoid(): Humanoid?
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

-- Where its hose comes off (as the server measures it): its HoseReel, else its PrimaryPart.
local function reelAt(model: Model, root: BasePart): Vector3
	local reel = model:FindFirstChild("HoseReel", true)
	return if reel and reel:IsA("BasePart") then reel.Position else root.Position
end

-- Whether the local player, on foot at `position`, holds their truck's hose: it has water and they
-- stand within hoseReach of it (the server checks the same).
function Vehicles.hoseReady(position: Vector3): boolean
	local model, root, seat = mine()
	local h = humanoid()
	return model ~= nil
		and model:GetAttribute("Flies") ~= true
		and not (h and h.SeatPart == seat)
		and (player:GetAttribute("Tank") or 0) > 0
		and (position - reelAt(model, root :: BasePart)).Magnitude <= Config.vehicle.hoseReach
end

-- The tank gauge: litres in the vehicle and its size while the player drives it or stands by its
-- hose; nil otherwise.
function Vehicles.gauge(): (number?, number?)
	local model, root, seat = mine()
	local h = humanoid()
	local own = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (model and h and own and own:IsA("BasePart")) then
		return nil, nil
	end
	local driving = h.SeatPart == seat
	local byHose = model:GetAttribute("Flies") ~= true and (own.Position - reelAt(model, root :: BasePart)).Magnitude <= Config.vehicle.hoseReach
	if driving or byHose then
		return player:GetAttribute("Tank") or 0, player:GetAttribute("TankMax") or 0
	end
	return nil, nil
end

function Vehicles.start()
	local up, down = false, false
	local function climbAction(set: (boolean) -> ())
		return function(_, inputState)
			set(inputState == Enum.UserInputState.Begin)
			return Enum.ContextActionResult.Sink
		end
	end
	local function bindFlight(on: boolean)
		up, down = false, false
		if not on then
			ContextActionService:UnbindAction("VehicleUp")
			ContextActionService:UnbindAction("VehicleDown")
			return
		end
		ContextActionService:BindAction("VehicleUp", climbAction(function(v)
			up = v
		end), true, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
		ContextActionService:BindAction("VehicleDown", climbAction(function(v)
			down = v
		end), true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
		ContextActionService:SetTitle("VehicleUp", "Up")
		ContextActionService:SetTitle("VehicleDown", "Down")
	end

	local speed = 0 -- studs a second forward (negative: reversing)
	local driven: Model? = nil
	RunService.Heartbeat:Connect(function(dt)
		local model, root, seat = mine()
		local h = humanoid()
		local active = if model and h and h.SeatPart == seat then model else nil
		if active ~= driven then
			driven = active
			speed = 0
			bindFlight(active ~= nil and active:GetAttribute("Flies") == true)
		end
		if not active then
			return
		end
		local drive = (root :: BasePart):FindFirstChild("Drive")
		local turn = (root :: BasePart):FindFirstChild("Turn")
		if not (drive and drive:IsA("LinearVelocity") and turn and turn:IsA("AngularVelocity")) then
			return -- not replicated yet
		end
		local vehicleSeat = seat :: VehicleSeat
		local flies = active:GetAttribute("Flies") == true
		local top = active:GetAttribute("Speed") or 0
		local wanted = vehicleSeat.ThrottleFloat * top
		local step = Config.vehicle.accel * dt
		speed = if wanted > speed then math.min(wanted, speed + step) else math.max(wanted, speed - step)
		local grip = if flies then 1 else math.min(1, math.abs(speed) / TURN_FULL_SPEED)
		local reverse = if speed < 0 and not flies then -1 else 1
		Hud.set(turn, "AngularVelocity", Vector3.new(0, -vehicleSeat.SteerFloat * Config.vehicle.turnSpeed * grip * reverse, 0))
		local look = (root :: BasePart).CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
		if flies then
			local climb = ((if up then 1 else 0) - (if down then 1 else 0)) * Config.vehicle.climbSpeed
			Hud.set(drive, "VectorVelocity", flat * speed + Vector3.yAxis * climb)
		else
			Hud.set(drive, "PlaneVelocity", Vector2.new(flat.X, flat.Z) * speed)
		end
	end)
end

return Vehicles
