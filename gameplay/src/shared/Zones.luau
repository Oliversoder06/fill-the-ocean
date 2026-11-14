--!strict
-- Parts of the ocean and area models (the map contract in server/Map.luau), and distance checks.

local Water = require(script.Parent.Water)

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
groundParams.IgnoreWater = true -- nor the ocean (terrain water)

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
floodParams.IgnoreWater = true -- the ocean is terrain water

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

local CELL = 4 -- studs per terrain voxel; voxel regions sit on a grid of them
local PIECE = 64 -- studs a side: the sea is written a square at a time, on the grid terrain streams by
local WATER_STEP = 0.1 -- studs the surface moves at a time: each move rewrites a layer of the sea
local FRAME_BUDGET = 0.004 -- seconds of terrain work per frame: a change spreads over frames, never a hitch
local DRY = -math.huge

type Piece = { x0: number, z0: number, x1: number, z1: number }
type Row = { x0: number, z0: number, x1: number, z1: number, pieces: { Piece } } -- a Water tile's row of pieces

-- One side's share of the water: `ground` the server's (Zones.setFill), else a client's
-- (Zones.setOpenSea). `written` is the surface it last gave the sea (DRY: none; nil: not known yet),
-- `bottom` the lowest a client's sheet goes, `wanted` the fill asked for and not written yet, `mend`
-- a client's sheet to put back where it went (Zones.mendOpenSea); `refilled` the pieces the last
-- mend refilled and `land` those still dry after that (ground above the water), until the next change.
type Writer = {
	ground: boolean,
	written: number?,
	bottom: number,
	wanted: number?,
	mend: boolean,
	busy: boolean,
	refilled: { [Piece]: boolean },
	land: { [Piece]: boolean },
}

local writers: { [Model]: { [string]: Writer } } = {}
local rowsOf: { [Model]: { Row } } = {}
local groundAt: { [Piece]: boolean } = {} -- the server's: its terrain is all there and never moves

local function cellBelow(y: number): number
	return math.floor(y / CELL) * CELL
end

local function cellAbove(y: number): number
	return math.ceil(y / CELL) * CELL
end

-- A function to call between pieces of work: it waits a frame once this one's FRAME_BUDGET is used.
local function pacer(): () -> ()
	local started = os.clock()
	return function()
		if os.clock() - started >= FRAME_BUDGET then
			task.wait()
			started = os.clock()
		end
	end
end

-- The ocean's Water tiles cut along the world's PIECE grid, row by row (the tiles are unturned with
-- their edges on the terrain grid, server/Map).
local function grid(ocean: Model, parts: { BasePart }): { Row }
	local cached = rowsOf[ocean]
	if cached then
		return cached
	end
	local rows: { Row } = {}
	for _, part in parts do
		local p, size = part.Position, part.Size
		local x0, z0, x1, z1 = p.X - size.X / 2, p.Z - size.Z / 2, p.X + size.X / 2, p.Z + size.Z / 2
		local z = math.floor(z0 / PIECE) * PIECE
		while z < z1 do
			local row: Row = { x0 = x0, z0 = math.max(z, z0), x1 = x1, z1 = math.min(z + PIECE, z1), pieces = {} }
			local x = math.floor(x0 / PIECE) * PIECE
			while x < x1 do
				table.insert(row.pieces, { x0 = math.max(x, x0), z0 = row.z0, x1 = math.min(x + PIECE, x1), z1 = row.z1 })
				x += PIECE
			end
			table.insert(rows, row)
			z += PIECE
		end
	end
	rowsOf[ocean] = rows
	return rows
end

-- One channel of the voxels along a row from `bottom` up `cells` cells, between `z0` and `z1` (within
-- the row), indexed [x][y][z] from that corner. Thin reads like this cost far less than one big one.
local function readRow(row: Row, channel: string, bottom: number, cells: number, z0: number, z1: number): any
	local region = Region3.new(Vector3.new(row.x0, bottom, z0), Vector3.new(row.x1, bottom + cells * CELL, z1))
	local channels: any = workspace.Terrain:ReadVoxelChannels(region:ExpandToGrid(CELL), CELL, { channel })
	return channels[channel]
end

-- The index of a world X or Z in voxels read from `from` along that axis.
local function voxelIndex(at: number, from: number): number
	return math.floor((at - from) / CELL) + 1
end

-- Finds the server's pieces (once): those with solid terrain, the seabed or the shore, at the floor.
local function findGround(rows: { Row }, floor: number, pace: () -> ())
	local bottom = cellBelow(floor) - CELL
	for _, row in rows do
		if groundAt[row.pieces[1]] ~= nil then
			continue
		end
		local solid = readRow(row, "SolidOccupancy", bottom, 2, row.z0, row.z1)
		local depth = voxelIndex(row.z1, row.z0) - 1
		for _, piece in row.pieces do
			local found = false
			for x = voxelIndex(piece.x0, row.x0), voxelIndex(piece.x1, row.x0) - 1 do
				for z = 1, depth do
					if solid[x][1][z] > 0 or solid[x][2][z] > 0 then
						found = true
						break
					end
				end
				if found then
					break
				end
			end
			groundAt[piece] = found
		end
		pace()
	end
end

local function fillPiece(piece: Piece, from: number, to: number)
	local centre = Vector3.new((piece.x0 + piece.x1) / 2, (from + to) / 2, (piece.z0 + piece.z1) / 2)
	workspace.Terrain:FillBlock(CFrame.new(centre), Vector3.new(piece.x1 - piece.x0, to - from, piece.z1 - piece.z0), Enum.Material.Water)
end

-- The ocean's surface height for a fill fraction (0-1), on the step it is drawn at; the floor when dry.
function Zones.level(ocean: Model, fraction: number): number
	local _, fullY = waterTiles(ocean)
	local depth = Zones.part(ocean, "Water"):GetAttribute("Depth") :: number
	return fullY - depth + (Water.surface(fraction, depth, WATER_STEP) or 0)
end

-- Writes one change to the writer's pieces, a frame's budget at a time: the server's are those with
-- ground, its water reaching down to the floor; a client's are all of them, nearest first, a sheet a
-- cell or two deep (where the server's water has streamed in, the same cells come out the same).
-- Lowering (or, for the server, not knowing what is there) clears from the cell holding the new
-- surface up; rising fills from the cell holding the old one.
local function write(ocean: Model, w: Writer, fraction: number)
	local parts, fullY = waterTiles(ocean)
	local depth = Zones.part(ocean, "Water"):GetAttribute("Depth") :: number
	local floor = fullY - depth
	local height = Water.surface(fraction, depth, WATER_STEP)
	local now = if height then floor + height else DRY
	local was = w.written
	if was == now then
		return
	end
	local base = if w.ground or now == DRY then floor else math.max(floor, cellBelow(now) - CELL)
	local clearFrom: number?, clearTo: number? = nil, nil
	local fillFrom = base
	if was == nil then
		if w.ground then
			clearFrom, clearTo = floor, fullY
		end
	elseif now < was then
		clearFrom, clearTo = if now ~= DRY then now elseif w.ground then floor else w.bottom, was
		fillFrom = if w.ground then math.max(floor, cellBelow(now)) else base
	elseif was ~= DRY then
		fillFrom = math.max(floor, cellBelow(was))
	end
	local clearBottom = if clearFrom then cellBelow(clearFrom) else 0
	local clearTop = if clearTo then cellAbove(clearTo) else 0
	for _, part in parts do
		if part.Transparency ~= 1 then
			part.Transparency = 1
		end
	end
	local pace = pacer()
	local rows = grid(ocean, parts)
	local list: { Piece } = {}
	if w.ground then
		findGround(rows, floor, pace)
		for _, row in rows do
			for _, piece in row.pieces do
				if groundAt[piece] then
					table.insert(list, piece)
				end
			end
		end
	else
		local eye = workspace.CurrentCamera.CFrame.Position
		local away: { [Piece]: number } = {}
		for _, row in rows do
			for _, piece in row.pieces do
				away[piece] = ((piece.x0 + piece.x1) / 2 - eye.X) ^ 2 + ((piece.z0 + piece.z1) / 2 - eye.Z) ^ 2
				table.insert(list, piece)
			end
		end
		table.sort(list, function(a, b)
			return away[a] < away[b]
		end)
	end
	local terrain = workspace.Terrain
	for _, piece in list do
		if clearTop > clearBottom then
			local region = Region3.new(Vector3.new(piece.x0, clearBottom, piece.z0), Vector3.new(piece.x1, clearTop, piece.z1))
			terrain:ReplaceMaterial(region:ExpandToGrid(CELL), CELL, Enum.Material.Water, Enum.Material.Air)
		end
		if now > fillFrom then
			fillPiece(piece, fillFrom, now)
		end
		pace()
	end
	w.written = now
	w.bottom = if now == DRY then math.huge else math.min(w.bottom, fillFrom)
	table.clear(w.refilled)
	table.clear(w.land)
end

-- Puts a client's sheet back wherever it went (terrain streaming out takes this client's water with
-- it): in every piece dry at its middle just under the surface. A piece still dry after that is
-- ground above the water and left alone until the next change.
local function mend(ocean: Model, w: Writer)
	local now = w.written
	if now == nil or now == DRY then
		return
	end
	local parts, fullY = waterTiles(ocean)
	local floor = fullY - (Zones.part(ocean, "Water"):GetAttribute("Depth") :: number)
	local base = math.max(floor, cellBelow(now) - CELL)
	local probe = cellBelow(math.max(floor, now - 0.05)) -- the cell holding the surface
	local pace = pacer()
	for _, row in grid(ocean, parts) do
		local line = cellBelow((row.z0 + row.z1) / 2)
		local liquid = readRow(row, "LiquidOccupancy", probe, 1, line, line + CELL)
		for _, piece in row.pieces do
			if liquid[voxelIndex((piece.x0 + piece.x1) / 2, row.x0)][1][1] > 0 then
				w.refilled[piece] = nil
			elseif w.refilled[piece] then
				w.refilled[piece] = nil
				w.land[piece] = true
			elseif not w.land[piece] then
				fillPiece(piece, base, now)
				w.refilled[piece] = true
				w.bottom = math.min(w.bottom, base)
			end
		end
		pace()
	end
end

local function writer(ocean: Model, ground: boolean): Writer
	local mine = writers[ocean]
	if not mine then
		mine = {}
		writers[ocean] = mine
	end
	local key = if ground then "ground" else "open"
	local w = mine[key]
	if not w then
		w = { ground = ground, written = nil, bottom = math.huge, wanted = nil, mend = false, busy = false, refilled = {}, land = {} }
		mine[key] = w
	end
	return w
end

-- Runs `w`'s asks over the next frames, without yielding here: the latest fill asked for (asks
-- made meanwhile are written next), then a mend if one was asked for.
local function work(ocean: Model, w: Writer)
	if w.busy then
		return
	end
	w.busy = true
	task.spawn(function()
		local ok, err = xpcall(function()
			while w.wanted ~= nil or w.mend do
				local fill = w.wanted
				if fill ~= nil then
					w.wanted = nil
					write(ocean, w, fill)
				else
					w.mend = false
					mend(ocean, w)
				end
			end
		end, debug.traceback)
		w.busy = false
		if not ok then
			error(`[Zones] writing the ocean's water failed: {err}`, 0)
		end
	end)
end

-- Sets the ocean's water for a fill fraction (0-1) where there is ground under the sea: Roblox
-- terrain water in the Water tiles' footprint from the floor (the Basin's top) up to Zones.level, none
-- at all when dry, around the seabed and the shore (they keep their ground). The server's
-- (server/Run): it streams in to each player near it, with the seabed. The tiles only mark where
-- the water goes and stay hidden. Only what moved since the last change is rewritten.
function Zones.setFill(ocean: Model, fraction: number)
	local w = writer(ocean, true)
	w.wanted = fraction
	work(ocean, w)
end

-- A client's own sea (client/Sea): a sheet at Zones.setFill's surface over the whole footprint, out
-- to the horizon. Past the seabed the server puts no terrain, so streaming never takes it away; over
-- the seabed the server's water streams in on top of it, and streaming out takes both
-- (Zones.mendOpenSea puts the sheet back).
function Zones.setOpenSea(ocean: Model, fraction: number)
	local w = writer(ocean, false)
	w.wanted = fraction
	work(ocean, w)
end

-- Puts this client's open sea back where seabed it covered has streamed in and out again since.
function Zones.mendOpenSea(ocean: Model)
	local w = writer(ocean, false)
	w.mend = true
	work(ocean, w)
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
