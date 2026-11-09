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

-- An area's part by name (Source, Pour, Pad, Spawn), or nil when it isn't there (not streamed in).
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
	local tiles, fullY = waterTiles(ocean)
	floodParams.FilterDescendantsInstances = ignore
	local function floods(x: number, z: number): boolean
		if not inFootprint(tiles, Vector3.new(x, fullY, z)) then
			return false
		end
		local hit = workspace:Raycast(Vector3.new(x, fullY + LOOK_ABOVE, z), Vector3.new(0, -LOOK_DOWN, 0), floodParams)
		return hit ~= nil and hit.Position.Y <= fullY and hit.Position.Y >= position.Y - MAX_DROP
	end
	if floods(position.X, position.Z) then
		return true
	end
	for _, ring in RINGS do
		for i = 1, SPOKES do
			local angle = (i / SPOKES) * 2 * math.pi
			if floods(position.X + math.cos(angle) * radius * ring, position.Z + math.sin(angle) * radius * ring) then
				return true
			end
		end
	end
	return false
end

return Zones
