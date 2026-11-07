--!strict
-- Parts of the ocean model (the map contract in server/Map.luau), and distance checks.

local Zones = {}

-- Studs from Source / from where the water will be within which a player scoops or pours (client
-- Action and Guide; server/Run adds latency slack).
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
