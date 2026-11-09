-- Staff bodies (3f), client only: every present player's hires walk their loop as local NPCs, so 30
-- staff cost the server nothing (server/Staff works out their water from rates). Read from each
-- player's Staff attribute (StaffRules.decode: id:hires@post; post 0 = nowhere to work, no body).
-- Each hire is a clone of ReplicatedStorage.Staff.<item.model> (an R15 rig) in a client folder
-- workspace.StaffBodies: its root part is anchored and moved here by PivotTo; its joints are written
-- by the roblox-animation runtime (ReplicatedStorage.Animation: AnimPlayer, in PreSimulation) from
-- shared/StaffClips, baked once per model on the first body (no animation assets to upload).
-- Loops by job: "area": scoop twice at the post's Source, carry to its Pour (the cove's: Ocean
-- PourPoint), pour, now and then their own move (StaffClips.signature) or a cheer, walk back.
-- "truck": the Fire Station's VehicleSpawn to a refill bay (Map.Roads.TruckRefillBay1), hose spray,
-- back. "plots": plot to plot (Map.Plots.PlotN.Base), the wrench at each.
-- At most MAX_BODIES, the nearest first; a body whose loop starts beyond RANGE studs of the camera
-- is removed and comes back when near. A loop whose parts haven't streamed in waits.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local StaffClips = require(ReplicatedStorage.Shared.StaffClips)
local StaffRules = require(ReplicatedStorage.Shared.StaffRules)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Hud = require(script.Parent.Hud)

local MAX_BODIES = 30
local RANGE = 250 -- studs from the camera to a loop's first stop
local REFRESH_SECONDS = 0.5 -- how often the wanted bodies are worked out
local FADE = 0.2 -- seconds each clip fades in over the last
local TURN_RATE = 8 -- how quickly a body turns to where it walks or works
local STAND_BACK = 7 -- studs a carrier stands back from a Source toward its Pour (and from a Pour)
local LANE = 3 -- studs between bodies working the same spot side by side
local LANES = 5
local PLOT_GAP = 3 -- studs a Plumber stands in front of a plot's edge
local GROUND_UP, GROUND_DOWN = 30, 120 -- studs above / below a point the ground is looked for
local START_GAP = 1.3 -- seconds between the first steps of bodies on the same spot
local SIGNATURE_EVERY, CHEER_EVERY = 3, 5 -- loops between a body's own move, and between cheers

type Kind = { template: Model, baked: { [string]: any }?, baking: boolean, rootHeight: number, pivotOffset: CFrame }
type Step = { clip: string, to: Vector3?, carry: boolean?, face: Vector3?, seconds: number? }
type Body = {
	key: string,
	model: Model,
	anim: any, -- AnimPlayer
	kind: Kind,
	item: any,
	post: number,
	lane: number,
	plan: { Step },
	step: number,
	from: Vector3,
	at: Vector3, -- ground point it stands on now
	yaw: number,
	startedAt: number,
	duration: number,
	loops: number,
	clip: string?,
	handle: any?,
}

local Staff = {}

-- the animation runtime's modules (ReplicatedStorage.Animation), required in Staff.start
local AnimPlayer: any, Baked: any, Gait: any, Performance: any

local kinds: { [string]: Kind } = {} -- staff item id -> its model and bakes
local bodies: { [string]: Body } = {}
local folder: Folder
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true -- the ground, not invisible zones
groundParams.IgnoreWater = true

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The ground under `point`, or nil (nothing there, or not streamed in). Skips the bodies and the
-- characters (refresh keeps that list).
local function ground(point: Vector3): Vector3?
	local hit = workspace:Raycast(point + Vector3.new(0, GROUND_UP, 0), Vector3.new(0, -(GROUND_UP + GROUND_DOWN), 0), groundParams)
	return hit and hit.Position
end

-- `point` moved `lane` places sideways across `along` (bodies on one spot stand side by side).
local function sideways(point: Vector3, along: Vector3, lane: number): Vector3
	local dir = if flat(along).Magnitude > 1e-3 then flat(along).Unit else Vector3.zAxis
	return point + dir:Cross(Vector3.yAxis) * ((lane - 1) % LANES - (LANES - 1) / 2) * LANE
end

local function partIn(parent: Instance?, name: string): BasePart?
	local part = parent and parent:FindFirstChild(name, true)
	return if part and part:IsA("BasePart") then part else nil
end

local function pivotOf(parent: Instance?, name: string): Vector3?
	local found = parent and parent:FindFirstChild(name)
	return if found and found:IsA("PVInstance") then found:GetPivot().Position else nil
end

-- The stops a job's loop works between ({ where, faces }), or nil while its parts aren't streamed in.
local function stops(item, post: number, lane: number): { { at: Vector3, face: Vector3 } }?
	local ocean = Hud.ocean()
	local scenery = workspace:FindFirstChild("Map")
	if item.job == "area" then
		local area = Areas.byId(Config, post)
		local source = ocean and Zones.areaPart(ocean, area, "Source")
		local pour = ocean and Zones.pourPart(ocean, area)
		if not (source and pour) then
			return nil
		end
		local way = flat(pour.Position - source.Position)
		local back = if way.Magnitude > 1e-3 then way.Unit else Vector3.zAxis
		return {
			{ at = sideways(source.Position + back * STAND_BACK, back, lane), face = source.Position },
			{ at = sideways(pour.Position - back * STAND_BACK, back, lane), face = pour.Position },
		}
	elseif item.job == "truck" then
		local town = scenery and scenery:FindFirstChild("Town")
		local spawn = partIn(town and town:FindFirstChild("FireStation"), "VehicleSpawn")
		local bay = pivotOf(scenery and scenery:FindFirstChild("Roads"), "TruckRefillBay1")
		if not (spawn and bay) then
			return nil
		end
		local way = bay - spawn.Position
		return {
			{ at = sideways(spawn.Position, way, lane), face = bay },
			{ at = sideways(bay - flat(way).Unit * STAND_BACK, way, lane), face = bay },
		}
	end
	local plots = scenery and scenery:FindFirstChild("Plots")
	local list = {}
	for index = 1, math.huge do
		local plot = plots and plots:FindFirstChild(`Plot{index}`)
		if not plot then
			break
		end
		local base = partIn(plot, "Base")
		if base then
			local front = flat(base.CFrame.LookVector).Unit
			local at = base.Position - front * (base.Size.Z / 2 + PLOT_GAP)
			table.insert(list, { at = sideways(at, front, lane), face = base.Position })
		end
	end
	return if #list > 0 then list else nil
end

-- The steps of one loop for a body, from its stops (see the header).
local function planOf(body: Body, places): { Step }
	local item = body.item
	local loop = body.loops
	local signature = StaffClips.signature[item.id]
	local extra = if loop % CHEER_EVERY == CHEER_EVERY - 1 then "cheer" elseif loop % SIGNATURE_EVERY == SIGNATURE_EVERY - 1 then signature else nil
	local plan: { Step } = {}
	if item.job == "area" then
		local source, pour = places[1], places[2]
		table.insert(plan, { clip = "scoop", face = source.face })
		table.insert(plan, { clip = "scoop", face = source.face })
		table.insert(plan, { clip = "walkCarry", to = pour.at, carry = true })
		table.insert(plan, { clip = "pour", face = pour.face })
		if extra then
			table.insert(plan, { clip = extra, face = pour.face })
		end
		table.insert(plan, { clip = "walk", to = source.at })
	elseif item.job == "truck" then
		local station, bay = places[1], places[2]
		table.insert(plan, { clip = "walk", to = bay.at })
		table.insert(plan, { clip = "hoseSpray", face = bay.face })
		table.insert(plan, { clip = "walk", to = station.at })
		table.insert(plan, { clip = extra or "idle", face = station.face, seconds = if extra then nil else 3 })
	else
		for _, place in places do
			table.insert(plan, { clip = "walk", to = place.at })
			table.insert(plan, { clip = "wrench", face = place.face })
		end
		if extra then
			table.insert(plan, { clip = extra, face = places[#places].face })
		end
	end
	return plan
end

-- Plays `name` on the body, fading over the clip before. The newest handle goes first in the
-- player's list: AnimPlayer steps its handles from the back, so the newest writes last each frame
-- and a faded-out clip putting its joints back (when it ends) never shows for a frame.
local function play(body: Body, name: string, loop: boolean)
	if body.clip == name and body.handle and loop then
		return
	end
	local old = body.handle
	local handle = body.anim:play((body.kind.baked :: any)[name], { loop = loop, fadeIn = FADE, fadeOut = FADE })
	local handles = body.anim.handles
	table.remove(handles, table.find(handles, handle) :: number)
	table.insert(handles, 1, handle)
	if old then
		old:stop(FADE)
	end
	body.clip, body.handle = name, handle
end

local function place(body: Body, at: Vector3)
	local kind = body.kind
	local root = CFrame.new(at + Vector3.new(0, kind.rootHeight, 0)) * CFrame.Angles(0, body.yaw, 0)
	body.model:PivotTo(root * kind.pivotOffset)
end

local function yawTo(direction: Vector3): number?
	local d = flat(direction)
	return if d.Magnitude > 1e-3 then math.atan2(-d.X, -d.Z) else nil
end

-- Starts step `index` of the body's plan (a new loop past its end) at `now`.
local function begin(body: Body, index: number, now: number)
	if index > #body.plan then
		body.loops += 1
		local places = stops(body.item, body.post, body.lane)
		if places then -- else keep the last loop's stops until they stream back in
			body.plan = planOf(body, places)
		end
		index = 1
	end
	local step = body.plan[index]
	body.step, body.startedAt, body.from = index, now, body.at
	local baked = (body.kind.baked :: any)[step.clip]
	if step.to then
		local speed = if step.carry then StaffClips.gaits.walkCarry.speed else StaffClips.gaits.walk.speed
		body.duration = flat(step.to - body.at).Magnitude / speed
		play(body, step.clip, true)
	else
		body.duration = step.seconds or math.max(baked.length - FADE, FADE)
		play(body, step.clip, step.seconds ~= nil)
	end
end

local function update(body: Body, now: number, dt: number)
	if now - body.startedAt >= body.duration then
		local step = body.plan[body.step]
		if step.to then
			body.at = step.to
		end
		begin(body, body.step + 1, now)
	end
	local step = body.plan[body.step]
	local wanted: number? = nil
	local moved = step.to ~= nil
	if step.to then
		local t = math.clamp((now - body.startedAt) / math.max(body.duration, 1e-3), 0, 1)
		local point = body.from:Lerp(step.to, t)
		body.at = ground(point) or point
		wanted = yawTo(step.to - body.from)
	elseif step.face then
		wanted = yawTo(step.face - body.at)
	end
	if wanted then
		local turn = (wanted - body.yaw + math.pi) % (2 * math.pi) - math.pi
		if math.abs(turn) > 1e-3 then
			body.yaw += turn * (1 - math.exp(-TURN_RATE * dt))
			moved = true
		end
	end
	if moved then
		place(body, body.at)
	end
end

local function remove(key: string)
	local body = bodies[key]
	bodies[key] = nil
	body.anim:destroy()
	body.model:Destroy()
end

-- Outfit pieces (sleeves, props) hang on plain welds; read as joints they'd turn into extra limbs.
local function outfit(model: Instance): { Instance }
	local rigParts: { [Instance]: boolean } = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("Motor6D") then
			if inst.Part0 then
				rigParts[inst.Part0] = true
			end
			if inst.Part1 then
				rigParts[inst.Part1] = true
			end
		end
	end
	local list = {}
	for _, inst in model:GetDescendants() do
		if (inst:IsA("JointInstance") and not inst:IsA("Motor6D")) or inst:IsA("WeldConstraint") then
			local a, b = (inst :: any).Part0, (inst :: any).Part1
			table.insert(list, inst)
			for _, part in { a, b } do
				if part and not rigParts[part] then
					table.insert(list, part)
				end
			end
		end
	end
	return list
end

-- A clone of the kind's rig, ready to be moved and posed: anchored root, nothing to collide with,
-- touch or aim at, no name tag.
local function spawnBody(key: string, kind: Kind, item, post: number, lane: number, places)
	local model = kind.template:Clone()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = part == model.PrimaryPart
			part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
		elseif part:IsA("Humanoid") then
			part.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	model.Parent = folder
	local body: Body = {
		key = key,
		model = model,
		anim = AnimPlayer.new(model, { ignore = outfit(model) }),
		kind = kind,
		item = item,
		post = post,
		lane = lane,
		plan = {},
		step = 0,
		from = places[1].at,
		at = places[1].at,
		yaw = yawTo(places[1].face - places[1].at) or 0,
		startedAt = 0,
		duration = 0,
		loops = 0,
		clip = nil,
		handle = nil,
	}
	body.plan = planOf(body, places)
	-- bodies on one spot start a little apart, so they don't move as one
	table.insert(body.plan, 1, { clip = "idle", face = places[1].face, seconds = 0.2 + (lane - 1) * START_GAP })
	bodies[key] = body
	body.at = ground(body.at) or body.at
	place(body, body.at)
	begin(body, 1, os.clock())
end

-- Bakes a kind's clips once, on its first body's rig (a yielding task, a clip at a time).
local function bake(kind: Kind)
	kind.baking = true
	local probe = AnimPlayer.new(kind.template, { ignore = outfit(kind.template) })
	local a = probe.anatomy
	probe:destroy()
	local baked = {}
	for name, clip in StaffClips.clips do
		if name ~= "carry" then
			baked[name] = Performance.bake(a, clip)
			task.wait()
		end
	end
	baked.walk = Gait.cycle(a, StaffClips.gaits.walk)
	task.wait()
	local hold = Baked.compact(Performance.bake(a, StaffClips.clips.carry))
	baked.walkCarry = StaffClips.overlay(Gait.cycle(a, StaffClips.gaits.walkCarry), hold)
	kind.baked = baked
end

-- Works out the wanted bodies (nearest first, at most MAX_BODIES) and spawns or removes the rest.
local function refresh()
	local ignore: { Instance } = { folder }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
	local wanted = {}
	local camera = workspace.CurrentCamera
	if ReplicatedStorage:GetAttribute("Phase") == "playing" and camera then
		local lanes: { [string]: number } = {}
		for _, owner in Players:GetPlayers() do
			for _, entry in StaffRules.decode(owner:GetAttribute("Staff")) do
				local item = Items.get(Config, entry.id)
				if not (item and kinds[item.id] and entry.post > 0) then
					continue
				end
				for i = 1, math.min(entry.hires, 3) do
					-- every truck loop walks the same path, whatever vehicle it runs
					local spot = if item.job == "truck" then "truck" else `{item.job}@{entry.post}`
					lanes[spot] = (lanes[spot] or 0) + 1
					local lane = lanes[spot]
					local places = stops(item, entry.post, lane)
					local distance = if places then (places[1].at - camera.CFrame.Position).Magnitude else math.huge
					if distance <= RANGE then
						local key = `{owner.UserId}:{item.id}:{i}@{entry.post}#{lane}` -- a new lane respawns the body there
						table.insert(wanted, { key = key, item = item, post = entry.post, lane = lane, places = places, distance = distance })
					end
				end
			end
		end
		table.sort(wanted, function(a, b)
			return a.distance < b.distance
		end)
	end
	local keep = {}
	for i = 1, math.min(#wanted, MAX_BODIES) do
		keep[wanted[i].key] = wanted[i]
	end
	for key in table.clone(bodies) do
		if not keep[key] then
			remove(key)
		end
	end
	for key, want in keep do
		local kind = kinds[want.item.id]
		if bodies[key] then
			continue
		elseif not kind.baked then
			if not kind.baking then
				task.spawn(bake, kind)
			end
			continue
		end
		spawnBody(key, kind, want.item, want.post, want.lane, want.places)
	end
end

function Staff.start()
	local animation = ReplicatedStorage:WaitForChild("Animation", 10)
	assert(animation, "ReplicatedStorage.Animation is missing (the animation runtime, Rojo project)")
	AnimPlayer = require(animation:WaitForChild("Roblox"):WaitForChild("AnimPlayer")) :: any
	Baked = require(animation:WaitForChild("Baked")) :: any
	Gait = require(animation:WaitForChild("Gait")) :: any
	Performance = require(animation:WaitForChild("Performance")) :: any
	local templates = ReplicatedStorage:WaitForChild("Staff", 10)
	assert(templates, "ReplicatedStorage.Staff is missing (the staff rigs live in the place)")
	for _, item in Config.items do
		if item.kind == "staff" then
			local template = templates:WaitForChild(item.model, 10)
			assert(template and template:IsA("Model") and template.PrimaryPart, `ReplicatedStorage.Staff.{item.model} must be a Model with a PrimaryPart (its HumanoidRootPart)`)
			local box, size = template:GetBoundingBox()
			local root = template.PrimaryPart :: BasePart
			kinds[item.id] = {
				template = template,
				baked = nil,
				baking = false,
				rootHeight = root.Position.Y - (box.Position.Y - size.Y / 2),
				pivotOffset = root.CFrame:Inverse() * template:GetPivot(),
			}
		end
	end
	folder = Instance.new("Folder")
	folder.Name = "StaffBodies"
	folder.Parent = workspace

	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
	RunService.PreRender:Connect(function(dt: number)
		local now = os.clock()
		for _, body in bodies do
			update(body, now, dt)
		end
	end)
end

return Staff
