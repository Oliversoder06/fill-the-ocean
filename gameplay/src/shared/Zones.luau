--!strict
-- Parts of the ocean and area models (the map contract in server/Map.luau), and distance checks.

local Zones = {}

-- Studs from a Source or Pour / from where the water will be within which a player scoops or pours.
-- The server (server/Run) and the client (client/Action, Guide) both use it; the server adds slack.
Zones.REACH = 12

-- An ocean child the map contract requires; a missing one is a map bug, so fail loudly.
function Zones.part(ocean: Model, name: string): BasePart
	local child = ocean:FindFirstChild(name)
	assert(child and child:IsA("BasePart"), `{ocean.Name} is missing part {name}`)
	return child
end

function Zones.near(ocean: Model, name: string, position: Vector3, radius: number): boolean
	return (position - Zones.part(ocean, name).Position).Magnitude <= radius
end

-- An area's model, workspace.Areas.<area.model> (Config.areas); the cove's (no model) is the ocean.
-- Nil when it isn't there: on a client, an area that hasn't streamed in.
function Zones.areaModel(ocean: Model, area): Instance?
	if not area.model then
		return ocean
	end
	local areas = workspace:FindFirstChild("Areas")
	return areas and areas:FindFirstChild(area.model)
end

-- An area's part by name (Source, Pour, Spawn), or nil when it isn't there (not streamed in).
-- The cove has no Pour: the sea itself is where its water goes.
function Zones.areaPart(ocean: Model, area, name: string): BasePart?
	if not area.model and name == "Pour" then
		return nil
	end
	local model = Zones.areaModel(ocean, area)
	local part = model and model:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

-- Where an area's carried water is poured: its Pour, the cove's usual pour spot (PourPoint). Nil
-- when it isn't there (not streamed in).
function Zones.pourPart(ocean: Model, area): BasePart?
	if area.model then
		return Zones.areaPart(ocean, area, "Pour")
	end
	local part = ocean:FindFirstChild("PourPoint")
	return if part and part:IsA("BasePart") then part else nil
end

-- An area's channel path (Channel.Path: parts named 1..N from its Pour down to the ocean) as points
-- in order; nil for the cove (it pours into the ocean itself) or a path not all there (not streamed in).
function Zones.channelPath(ocean: Model, area): { Vector3 }?
	local model = if area.model then Zones.areaModel(ocean, area) else nil
	local channel = model and model:FindFirstChild("Channel")
	local path = channel and channel:FindFirstChild("Path")
	if not path then
		return nil
	end
	local points: { Vector3 } = {}
	local count = 0
	for _, point in path:GetChildren() do
		local i = tonumber(point.Name)
		if i and point:IsA("BasePart") then
			points[i] = point.Position
			count += 1
		end
	end
	for i = 1, count do
		if not points[i] then
			return nil
		end
	end
	return if count >= 2 then points else nil
end

-- An area's stand: workspace.Areas.<model>.Stand, the cove's workspace.Map.Beach.BackpackStand.
-- Nil when it isn't there (not in the place yet, or not streamed in).
function Zones.stand(ocean: Model, area): Instance?
	if area.model then
		local model = Zones.areaModel(ocean, area)
		return model and model:FindFirstChild("Stand")
	end
	local scenery = workspace:FindFirstChild("Map")
	local beach = scenery and scenery:FindFirstChild("Beach")
	return beach and beach:FindFirstChild("BackpackStand")
end

-- A cove shop (Config.stands): workspace.Map.Town.<name> or workspace.Map.Beach.<name>, or nil.
function Zones.shop(name: string): Instance?
	local scenery = workspace:FindFirstChild("Map")
	local town = scenery and scenery:FindFirstChild("Town")
	local beach = scenery and scenery:FindFirstChild("Beach")
	return (town and town:FindFirstChild(name)) or (beach and beach:FindFirstChild(name))
end

-- A stand's (or shop's, or rock's) ProximityPrompt "Prompt" anywhere inside it, or nil when it has none.
function Zones.standPrompt(stand: Instance): ProximityPrompt?
	local prompt = stand:FindFirstChild("Prompt", true)
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- The first open area (`open`: Areas.open) whose `name` part lies within `radius` studs of
-- `position`, and that part; nil when none does.
function Zones.openSpot(ocean: Model, config, open: { [number]: boolean }, name: string, position: Vector3, radius: number)
	for _, area in config.areas do
		local part = if open[area.id] then Zones.areaPart(ocean, area, name) else nil
		if part and (position - part.Position).Magnitude <= radius then
			return area, part
		end
	end
	return nil, nil
end

-- Where a player at `position` scoops, among the `open` areas (Areas.open): an area's Source within
-- `reach` studs, else a DeepPool behind a broken rock (`broken`: area ids) within `reach`, else the
-- drifting cloud (the Source of a "cloud" area) within `netReach` (the Cloud Net's; nil without it).
-- Returns the area, the part and whether it is a deep pool; nil when there is nowhere to scoop.
function Zones.scoopSpot(ocean: Model, config, open: { [number]: boolean }, broken: { number }, position: Vector3, reach: number, netReach: number?)
	local area, part = Zones.openSpot(ocean, config, open, "Source", position, reach)
	if area then
		return area, part, false
	end
	local deep = {}
	for _, id in broken do
		deep[id] = open[id]
	end
	area, part = Zones.openSpot(ocean, config, deep, "DeepPool", position, reach)
	if area then
		return area, part, true
	end
	if netReach then
		local clouds = {}
		for _, a in config.areas do
			clouds[a.id] = open[a.id] and a.mechanic == "cloud"
		end
		area, part = Zones.openSpot(ocean, config, clouds, "Source", position, netReach)
		if area then
			return area, part, false
		end
	end
	return nil, nil, false
end

local GROUND_PROBE = 1.5 -- studs below the feet that still count as standing
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true -- the ground, not invisible zones

-- What `character` stands on (the jetpack refuels there, snow slows walking): the hit of a ray from
-- `root` down past its feet, or nil in the air.
function Zones.ground(character: Model, root: BasePart): RaycastResult?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local down = root.Size.Y / 2 + (if humanoid then humanoid.HipHeight else 2) + GROUND_PROBE
	groundParams.FilterDescendantsInstances = { character }
	return workspace:Raycast(root.Position, Vector3.new(0, -down, 0), groundParams)
end

-- Where the water will be once the ocean is full: inside a Water tile's footprint (server/Map), on
-- ground lower than the full water line. Anywhere there is a place to pour.
local LOOK_ABOVE = 30 -- studs above the full line that the ground probe starts
local LOOK_DOWN = 300
local MAX_DROP = 30 -- studs the spot may lie below the player (no pouring from a cliff top)
local RINGS = { 0.5, 1 } -- fractions of the radius sampled around the player
local SPOKES = 8

local floodParams = RaycastParams.new()
floodParams.FilterType = Enum.RaycastFilterType.Exclude
floodParams.RespectCanCollide = true -- the ground, not invisible zones, leaves or the water itself

local function waterTiles(ocean: Model): ({ BasePart }, number)
	local water = Zones.part(ocean, "Water")
	local basin = Zones.part(ocean, "Basin")
	local tiles: { BasePart } = { water }
	for _, child in water:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(tiles, child)
		end
	end
	return tiles, basin.Position.Y + 0.5 + (water:GetAttribute("Depth") :: number)
end

local function inFootprint(tiles: { BasePart }, point: Vector3): boolean
	for _, tile in tiles do
		local p = tile.CFrame:PointToObjectSpace(point)
		if math.abs(p.X) <= tile.Size.X / 2 and math.abs(p.Z) <= tile.Size.Z / 2 then
			return true
		end
	end
	return false
end

-- Whether `point` (a surface you look at) will be under water when the ocean is full.
function Zones.willFlood(ocean: Model, point: Vector3): boolean
	local tiles, fullY = waterTiles(ocean)
	return point.Y <= fullY + 0.05 and inFootprint(tiles, point)
end

-- Whether `position` lies over the ocean's water (a Water tile's footprint), at any height: the Water
-- Bomber drops its load there (server/Vehicles).
function Zones.overWater(ocean: Model, position: Vector3): boolean
	return inFootprint((waterTiles(ocean)), position)
end

-- Whether some ground within `radius` studs (across) of `position` will be under water when the
-- ocean is full. `ignore` lists what may stand on that ground (characters).
function Zones.nearFlood(ocean: Model, position: Vector3, radius: number, ignore: { Instance }): boolean
	return Zones.floodPoint(ocean, position, radius, ignore, nil) ~= nil
end

-- A ground point within `radius` studs of `position` that will be under water when the ocean is
-- full, nil for none: with `toward` (a direction), the one most in that direction (the spot a pour
-- lands when the player looks out, not down); without, the first found.
function Zones.floodPoint(ocean: Model, position: Vector3, radius: number, ignore: { Instance }, toward: Vector3?): Vector3?
	local tiles, fullY = waterTiles(ocean)
	floodParams.FilterDescendantsInstances = ignore
	local function floods(x: number, z: number): Vector3?
		if not inFootprint(tiles, Vector3.new(x, fullY, z)) then
			return nil
		end
		local hit = workspace:Raycast(Vector3.new(x, fullY + LOOK_ABOVE, z), Vector3.new(0, -LOOK_DOWN, 0), floodParams)
		return if hit and hit.Position.Y <= fullY and hit.Position.Y >= position.Y - MAX_DROP then hit.Position else nil
	end
	local under = floods(position.X, position.Z)
	if under and not toward then
		return under
	end
	local flat = if toward then Vector3.new(toward.X, 0, toward.Z) else Vector3.zero
	flat = if flat.Magnitude > 1e-6 then flat.Unit else flat
	local best, bestScore = under, -math.huge
	for _, ring in RINGS do
		for i = 1, SPOKES do
			local angle = (i / SPOKES) * 2 * math.pi
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local point = floods(position.X + offset.X * radius * ring, position.Z + offset.Z * radius * ring)
			if point then
				if not toward then
					return point
				end
				local score = offset:Dot(flat)
				if score > bestScore then
					best, bestScore = point, score
				end
			end
		end
	end
	return best
end

return Zones
