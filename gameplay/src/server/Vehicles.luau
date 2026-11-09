-- Vehicles (Config.items kind "vehicle", shared/VehicleRules): Fire Truck, Tanker, Snowcat Tanker and
-- Water Bomber. Bought at the Fire Station like a cove shop (Config.stands, server/Run onStand) and
-- levelled in TAB. The station's CallPrompt brings the player's best owned vehicle out at its
-- VehicleSpawn: a clone of ReplicatedStorage.Vehicles.<model> named Vehicle_<UserId>. One out per
-- player; it goes when they leave, call again or play ends. Only its owner gets in, through the seat's
-- DrivePrompt (touch seating is off). The driver owns its physics while seated
-- (client/Vehicles sets the Drive and Turn constraints made here); vehicles pass through characters
-- and each other (collision groups).
-- Water follows the server's clock. A truck parked by a hydrant (Map.hydrants) fills at its fillRate,
-- worth VehicleRules.payArea's pay; its owner, on foot within hoseReach of it by the water, sprays it
-- into the ocean at sprayRate while holding the act input (Vehicle remote: "spray", on); it and the
-- Garden Hose never spray at once (turning one on stops the other). The Water Bomber fills skimming
-- low over an open area's Source (not the cove's well) and drops the whole tank once over the ocean.
-- Spraying and dropping wait until the vehicle could have got there from its last fill
-- (VehicleRules.plausible), so a client that teleports its vehicle gains no water.
-- Out to clients: player attributes Vehicle (item id or ""), Tank and TankMax (whole litres), Filling
-- and VehicleSpraying; the model's Owner (UserId), ItemId, Speed and Flies.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local VehicleRules = require(ReplicatedStorage.Shared.VehicleRules)
local Water = require(ReplicatedStorage.Shared.Water)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Map = require(script.Parent.Map)

local TICK = 0.25 -- seconds between fills, sprays and attribute updates
local CALL_COOLDOWN = 2 -- seconds between accepted calls per player (exploits can fire prompts)
local MAX_VEHICLE_PER_SECOND = 10 -- spray toggles; the water follows server time, not these
local MAX_NOT_YOURS_PER_SECOND = 1 -- "not your vehicle" cards (exploits can fire prompts)
local DISTANCE_SLACK = 6 -- studs of latency allowance on the hose's reach
local VEHICLE_GROUP, CHARACTER_GROUP = "Vehicles", "Characters"
local FRICTION = 0.05 -- vehicles slide on the drive constraint, not on wheels
local DRIVE_FORCE = 400 -- the drive's strongest push, studs a second squared times the vehicle's mass
local TURN_TORQUE = 400 -- the turn's strongest twist per unit of mass (also damps rolling)
local UPRIGHT_TORQUE = 2000 -- per unit of mass: rights a tipped vehicle
local UPRIGHT_RESPONSIVENESS = 10

export type Hooks = {
	states: { [Player]: any }, -- server/Run's player states (owned, itemLevels, windows)
	playing: () -> boolean,
	openIds: () -> { number }, -- the open area ids (Areas.openIds)
	rootOf: (Player) -> BasePart?,
	inReach: (Player, ProximityPrompt) -> boolean,
	tell: (Player, string) -> (), -- a card for one player
	allow: (any, string, number) -> boolean, -- server/Run's per-player rate limit
	nearFlood: (Player) -> boolean, -- the player stands where they may pour into the ocean
	water: () -> (number, number), -- the ocean's current and target litres
	pour: (Player, number, number) -> (), -- litres worth coins land in the ocean, paid to the player
	stopHose: (Player) -> (), -- the Garden Hose stops spraying (server/Run)
	vehicle: RemoteEvent, -- ReplicatedStorage.Remotes.Vehicle
}

type Out = {
	item: any, -- its Config.items entry
	model: Model,
	root: BasePart,
	seat: VehicleSeat,
	tank: number, -- litres in it
	value: number, -- their coins (Water.mix: each fill's litres at its area's pay)
	filling: boolean,
	spraying: boolean,
	filledAt: number, -- os.clock() of the last fill (or the call)
	filledPos: Vector3, -- where the vehicle was then
}

local Vehicles = {}

local ocean: Model
local hooks: Hooks
local templates: { [string]: Model } = {} -- vehicle item id -> its template
local hydrants: { { area: any?, at: Vector3 } } = {}
local spawnPart: BasePart
local out: { [Player]: Out } = {}
local calledAt: { [Player]: number } = {}

local function stat(player: Player, v: Out, name: string): number
	return Items.stat(hooks.states[player], v.item, name)
end

local function publish(player: Player)
	local v = out[player]
	local state = hooks.states[player]
	local has = v ~= nil and state ~= nil
	player:SetAttribute("Vehicle", if has then v.item.id else "")
	player:SetAttribute("Tank", if has then math.floor(v.tank) else 0)
	player:SetAttribute("TankMax", if has then stat(player, v, "tank") else 0)
	player:SetAttribute("Filling", has and v.filling)
	player:SetAttribute("VehicleSpraying", has and v.spraying)
end

-- Where the hose comes off: the model's HoseReel, else its PrimaryPart.
local function reelOf(v: Out): BasePart
	local reel = v.model:FindFirstChild("HoseReel", true)
	return if reel and reel:IsA("BasePart") then reel else v.root
end

-- The hose's optional look: the HoseReel's Beam "HoseBeam" runs to the owner's hand while it sprays.
local function showSpray(player: Player, v: Out)
	local beam = reelOf(v):FindFirstChild("HoseBeam")
	if not (beam and beam:IsA("Beam")) then
		return
	end
	local hand = player.Character and player.Character:FindFirstChild("RightHand")
	local grip = hand and hand:FindFirstChild("RightGripAttachment")
	beam.Attachment1 = if v.spraying and grip and grip:IsA("Attachment") then grip else nil
end

local function remove(player: Player)
	local v = out[player]
	if not v then
		return
	end
	out[player] = nil
	v.model:Destroy()
	publish(player)
end

-- The driver owns the physics; an empty vehicle stays with the server, so nobody nearby picks it up
-- and flings it. Only the owner gets in (DrivePrompt); anyone else who ends up seated is put out.
local function watchSeat(player: Player, model: Model, seat: VehicleSeat)
	local prompt = seat:FindFirstChild("DrivePrompt") :: ProximityPrompt
	prompt.Triggered:Connect(function(who)
		local h = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
		if who ~= player then
			local state = hooks.states[who]
			if state and hooks.allow(state, "notYours", MAX_NOT_YOURS_PER_SECOND) then
				hooks.tell(who, `This is {player.DisplayName}'s vehicle`)
			end
		elseif h and h.Health > 0 and not seat.Occupant and hooks.playing() and hooks.inReach(who, prompt) then
			seat:Sit(h)
		end
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not model:IsDescendantOf(workspace) then
			return
		end
		local humanoid = seat.Occupant
		prompt.Enabled = humanoid == nil
		local rider = humanoid and Players:GetPlayerFromCharacter(humanoid.Parent)
		if humanoid and rider ~= player then
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
			return
		end
		local ok, reason = seat:CanSetNetworkOwnership()
		if not ok then
			warn(`[Vehicles] {model:GetFullName()}: {reason}`)
			return
		end
		seat:SetNetworkOwner(rider)
	end)
end

-- The drive the client sets (client/Vehicles): Drive (a LinearVelocity, horizontal for trucks so
-- gravity keeps them on the road, full for the bomber so it hovers), Turn (an AngularVelocity) and
-- Upright (keeps the top up, free to turn). All start still, which also brakes a parked vehicle.
local function addDrive(root: BasePart, mass: number, flies: boolean)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	-- Its X axis (an attachment's primary axis) points up, for Upright.
	attachment.CFrame = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis)
	attachment.Parent = root
	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	if flies then
		drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		drive.VectorVelocity = Vector3.zero
	else
		drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		drive.PrimaryTangentAxis = Vector3.xAxis
		drive.SecondaryTangentAxis = Vector3.zAxis
		drive.PlaneVelocity = Vector2.zero
	end
	drive.ForceLimitsEnabled = true
	drive.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	drive.MaxForce = mass * DRIVE_FORCE
	drive.Parent = root
	local turn = Instance.new("AngularVelocity")
	turn.Name = "Turn"
	turn.Attachment0 = attachment
	turn.RelativeTo = Enum.ActuatorRelativeTo.World
	turn.AngularVelocity = Vector3.zero
	turn.MaxTorque = mass * TURN_TORQUE
	turn.Parent = root
	local upright = Instance.new("AlignOrientation")
	upright.Name = "Upright"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = attachment
	upright.AlignType = Enum.AlignType.PrimaryAxisParallel
	upright.PrimaryAxis = Vector3.yAxis
	upright.MaxTorque = mass * UPRIGHT_TORQUE
	upright.Responsiveness = UPRIGHT_RESPONSIVENESS
	upright.Parent = root
end

-- Brings `item` out at the Fire Station for `player`, replacing the one they had out (and its water).
local function spawn(player: Player, item)
	remove(player)
	local model = templates[item.id]:Clone()
	model.Name = `Vehicle_{player.UserId}`
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("ItemId", item.id)
	model:SetAttribute("Flies", item.flies == true)
	model:SetAttribute("Speed", Items.stat(hooks.states[player], item, "speed"))
	local root = model.PrimaryPart :: BasePart
	local seat = model:FindFirstChild("Seat", true) :: VehicleSeat
	seat.HeadsUpDisplay = false
	seat.CanTouch = false -- in through the DrivePrompt only
	local mass = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CollisionGroup = VEHICLE_GROUP
			local base = PhysicalProperties.new(part.Material)
			part.CustomPhysicalProperties = PhysicalProperties.new(base.Density, FRICTION, base.Elasticity, 100, base.ElasticityWeight)
			mass += part:GetMass()
			if part ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
	addDrive(root, mass, item.flies == true)
	local _, size = model:GetBoundingBox()
	model:PivotTo(spawnPart.CFrame * CFrame.new(0, spawnPart.Size.Y / 2 + size.Y / 2 + 0.5, 0))
	model.Parent = workspace
	seat:SetNetworkOwner(nil)
	watchSeat(player, model, seat)
	out[player] = {
		item = item,
		model = model,
		root = root,
		seat = seat,
		tank = 0,
		value = 0,
		filling = false,
		spraying = false,
		filledAt = os.clock(),
		filledPos = root.Position,
	}
	publish(player)
end

-- The CallPrompt: brings out the player's best owned vehicle (the furthest area's, Items.furthest).
local function onCall(player: Player, prompt: ProximityPrompt)
	local state = hooks.states[player]
	local now = os.clock()
	if not state or not hooks.playing() or now - (calledAt[player] or 0) < CALL_COOLDOWN then
		return
	end
	calledAt[player] = now
	if not hooks.inReach(player, prompt) then
		return
	end
	local item = Items.furthest(Config, state, "vehicle")
	if not item then
		hooks.tell(player, "Buy a vehicle here at the Fire Station first")
		return
	end
	spawn(player, item)
	hooks.tell(player, `Your {item.name} is out front!`)
end

local function setSpray(player: Player, v: Out, on: boolean)
	v.spraying = on
	showSpray(player, v)
	publish(player)
end

-- Vehicle remote: "spray", on: the truck's hose sprays (credited in tick) while the act input is held.
local function onVehicle(player: Player, action: unknown, on: unknown)
	local state = hooks.states[player]
	local v = out[player]
	if not state or not v or not hooks.playing() or not hooks.allow(state, "vehicle", MAX_VEHICLE_PER_SECOND) then
		return
	end
	if action == "spray" and type(on) == "boolean" and not v.item.flies and v.spraying ~= on then
		if on then
			hooks.stopHose(player)
		end
		setSpray(player, v, on)
	end
end

-- The truck's hose stops spraying (the Garden Hose turned on: server/Run).
function Vehicles.stopSpray(player: Player)
	local v = out[player]
	if v and v.spraying then
		setSpray(player, v, false)
	end
end

-- The area whose pay a parked truck's hydrant gives (VehicleRules.payArea), or nil away from one. An
-- area's hydrant counts only while its area is open.
local function hydrantArea(v: Out, position: Vector3)
	if v.root.AssemblyLinearVelocity.Magnitude > Config.vehicle.parkedSpeed then
		return nil
	end
	local open = Areas.open(hooks.openIds())
	for _, hydrant in hydrants do
		local area = hydrant.area
		if (hydrant.at - position).Magnitude <= Config.vehicle.hydrantReach and (not area or open[area.id]) then
			return Areas.byId(Config, VehicleRules.payArea(v.item.area, area and area.id))
		end
	end
	return nil
end

-- The open area whose Source the bomber skims (VehicleRules.skims, VehicleRules.skimmable), or nil.
local function skimArea(position: Vector3)
	for _, id in hooks.openIds() do
		local area = Areas.byId(Config, id)
		local source = VehicleRules.skimmable(id) and Zones.areaPart(ocean, area, "Source")
		if source then
			local offset = position - source.Position
			if VehicleRules.skims(Config.vehicle, Vector3.new(offset.X, 0, offset.Z).Magnitude, offset.Y) then
				return area
			end
		end
	end
	return nil
end

-- Whether the owner may spray now: on foot, within the hose's reach, by the water, with water left.
local function canSpray(player: Player, v: Out): boolean
	local root = hooks.rootOf(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return root ~= nil
		and v.tank > 0
		and not (humanoid and humanoid.SeatPart == v.seat)
		and (root.Position - reelOf(v).Position).Magnitude <= Config.vehicle.hoseReach + DISTANCE_SLACK
		and hooks.nearFlood(player)
end

-- `want` litres leave the tank into the ocean (never past full), with their share of its value.
local function empty(player: Player, v: Out, want: number)
	local current, target = hooks.water()
	local litres = Water.pourAmount(want, current, target)
	if litres <= 0 then
		return
	end
	local value = Water.share(v.value, v.tank, litres)
	v.tank -= litres
	v.value -= value
	if v.tank <= 1e-9 then
		v.tank, v.value = 0, 0
	end
	hooks.pour(player, litres, value)
end

local function tick(player: Player, v: Out, step: number)
	if not hooks.states[player] or not v.root:IsDescendantOf(workspace) then
		remove(player) -- fell out of the world, or its owner is gone
		return
	end
	local now = os.clock()
	local position = v.root.Position
	local max = stat(player, v, "tank")
	local area = if v.item.flies then skimArea(position) else hydrantArea(v, position)
	v.filling = area ~= nil and v.tank < max
	if v.filling then
		local litres = VehicleRules.fill(v.tank, max, stat(player, v, "fillRate"), step) - v.tank
		v.value = Water.mix(v.value, litres, Config.ocean.coinsPerLitre * area.payMultiplier)
		v.tank += litres
	end
	if area then
		v.filledAt, v.filledPos = now, position
	end
	local speed = stat(player, v, "speed")
	if v.model:GetAttribute("Speed") ~= speed then
		v.model:SetAttribute("Speed", speed) -- levelled up while it is out
	end
	local travelled = VehicleRules.plausible(Config.vehicle, (position - v.filledPos).Magnitude, now - v.filledAt, speed)
	if v.item.flies then
		if VehicleRules.drops(v.tank, area ~= nil, travelled, Zones.overWater(ocean, position)) then
			empty(player, v, v.tank)
		end
	elseif v.spraying then
		if not canSpray(player, v) then
			v.spraying = false
			showSpray(player, v)
		elseif travelled then
			empty(player, v, VehicleRules.spray(v.tank, stat(player, v, "sprayRate"), step))
		end
	end
	if out[player] == v then -- a pour that filled the ocean ends play, which removes every vehicle
		publish(player)
	end
end

-- The player left: their vehicle goes.
function Vehicles.leave(player: Player)
	remove(player)
	calledAt[player] = nil
end

-- Play ended: every vehicle goes.
function Vehicles.stop()
	for player in table.clone(out) do
		remove(player)
	end
end

-- Characters walk through vehicles: every character part goes in the Characters group.
local function groupCharacter(character: Model)
	local function group(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = CHARACTER_GROUP
		end
	end
	for _, part in character:GetDescendants() do
		group(part)
	end
	character.DescendantAdded:Connect(group)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(groupCharacter)
	if player.Character then
		groupCharacter(player.Character)
	end
end

function Vehicles.start(oceanModel: Model, runHooks: Hooks)
	ocean, hooks = oceanModel, runHooks
	local folder = ReplicatedStorage:FindFirstChild("Vehicles")
	assert(folder, "ReplicatedStorage.Vehicles is missing: the vehicle templates live in the place")
	for _, item in Config.items do
		if item.kind == "vehicle" then
			local model = folder:FindFirstChild(item.model)
			assert(model and model:IsA("Model") and model.PrimaryPart, `ReplicatedStorage.Vehicles.{item.model} must be a Model with a PrimaryPart`)
			local seat = model:FindFirstChild("Seat", true)
			assert(seat and seat:IsA("VehicleSeat"), `ReplicatedStorage.Vehicles.{item.model} needs a VehicleSeat "Seat"`)
			local drivePrompt = seat:FindFirstChild("DrivePrompt")
			assert(drivePrompt and drivePrompt:IsA("ProximityPrompt"), `{seat:GetFullName()} needs a ProximityPrompt "DrivePrompt"`)
			templates[item.id] = model
		end
	end
	hydrants = Map.hydrants(ocean, Config)
	local prompt
	prompt, spawnPart = Map.fireStation()
	prompt.Triggered:Connect(function(player)
		onCall(player, prompt)
	end)
	hooks.vehicle.OnServerEvent:Connect(onVehicle)

	for _, name in { VEHICLE_GROUP, CHARACTER_GROUP } do
		if not workspace:IsCollisionGroupRegistered(name) then
			workspace:RegisterCollisionGroup(name)
		end
	end
	workspace:CollisionGroupSetCollidable(VEHICLE_GROUP, CHARACTER_GROUP, false)
	workspace:CollisionGroupSetCollidable(VEHICLE_GROUP, VEHICLE_GROUP, false)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		if not hooks.playing() then
			since = 0
			return
		end
		since += dt
		if since < TICK then
			return
		end
		local step = since
		since = 0
		for player, v in table.clone(out) do
			if out[player] == v then
				tick(player, v, step)
			end
		end
	end)
end

return Vehicles
