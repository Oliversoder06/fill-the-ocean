--!strict
-- The ocean lives in the Studio place (workspace.Ocean). This module checks it and moves the water.
-- Contract, one Model workspace.Ocean holding:
--   Spawn     where players appear (the furthest open area's Spawn, server/Run)
--   Source    invisible zone over the well; players aim at it to scoop (client/Action)
--   PourPoint marks the usual pour spot at the basin rim (tripDistance from Source); pouring
--             itself works anywhere next to where the Water will be (shared/Zones.nearFlood)
--   Basin     the floor of the sunken basin; Water rises from it to ground level
--   Tap       the Garden Hose's tap by the pour spot, holding an Attachment "Hose" (the rope's end)
--   Water     with a number attribute "Depth"; rises with the fill fraction. It may hold BasePart
--             children: extra tiles for water wider than one part can be (2048 studs); every tile
--             keeps its own X and Z and rises with it
--   PourDecal a flat part on the seabed by PourPoint holding a Decal ("POUR HERE"), shown while the
--             ocean is nearly empty (client/Channels fades it out as it fills)
-- Areas 2-5 (Config.areas with a `model`): one Model each in workspace.Areas, named by that model:
--   Source    zone over the area's water; scooping here pays the area's rate (server/Run)
--   Pour      the channel inlet; pouring here counts as pouring into the ocean
--   Channel   the channel from the Pour down to the ocean (client/Channels): Path, a Folder of parts
--             named 1..N (N >= 2) from the Pour to where it meets the ocean, that a wave follows after
--             every pour; Water, a part or a Folder/Model of parts whose Textures trickle downstream
--   Tap       the Garden Hose's tap by the Pour, holding an Attachment "Hose" (the rope's end)
--   Gate      Model: Blocker and Boards (parts, or models of parts) that close the way in, Sign
--             (a SurfaceGui with a TextLabel "Label", client/Gates) and a part Prompt holding a
--             ProximityPrompt "Prompt" (buys the gate)
--   Stand     the area's shop stand (a part or Model) holding a ProximityPrompt "Prompt" that buys
--             the area's items (server/Run); the cove's is workspace.Map.Beach.BackpackStand
--   Spawn     where players appear in the area
-- Every area, the cove (in workspace.Ocean) included, also holds its deeper pool (server/Mechanics):
--   DeepPool  zone over the deeper pool's water; scooping here brings Config.deepPool.sweepScale
--             sweeps once its rock is broken
--   Rock      the rock in front of it (a part or Model of parts) holding a ProximityPrompt "Prompt";
--             the area's top tool breaks it (shared/AreaRules.rockTool)
-- and its mechanic's parts (Config.areas `mechanic`):
--   steam     Vents: a Folder or Model of vent parts (each bursts steam, client/Mechanics)
--   cloud     CloudPath: a Folder or Model of 3-4 parts Point1..PointN the anchored Source drifts
--             between (its visible cloud is welded to it, unanchored)
-- Cove shops that sell their own items (Config.stands): workspace.Map.Town.<name> or
-- workspace.Map.Beach.<name> (a part or Model) holding a ProximityPrompt "Prompt" (server/Run), e.g.
-- Town.ToolShack sells the Water Gun and Beach.Stage_Ocean_LifeguardTower hires the staff.
-- Vehicles (server/Vehicles): Town.FireStation also holds a ProximityPrompt "CallPrompt" (brings the
-- player's vehicle out) and a part "VehicleSpawn" (where it appears, facing the part's front).
-- Vehicles fill at hydrants: workspace.Map.Roads.TruckRefillBay1 and TruckRefillBay2 (the cove's) and
-- a "Hydrant" (a part or Model) in every area model 2-5.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Zones = require(ReplicatedStorage.Shared.Zones)

local REQUIRED = { "Spawn", "Source", "PourPoint", "Basin", "Water", "Tap", "PourDecal" }
local AREA_PARTS = { "Source", "Pour", "Spawn", "Tap" }

local Map = {}

-- How each part clear() hid looked and collided in the place, so show() can put it back.
local hidden: { [BasePart]: { transparency: number, canCollide: boolean, canQuery: boolean, canTouch: boolean } } = {}

local function child(parent: Instance, name: string): Instance
	local found = parent:FindFirstChild(name)
	assert(found, `{parent:GetFullName()} is missing {name}`)
	return found
end

-- A gate's ProximityPrompt (Gate.Prompt.Prompt).
function Map.gatePrompt(gate: Instance): ProximityPrompt
	local prompt = child(child(gate, "Prompt"), "Prompt")
	assert(prompt:IsA("ProximityPrompt"), `{prompt:GetFullName()} must be a ProximityPrompt`)
	return prompt
end

-- An area's stand (Zones.stand), nil when the place doesn't have it yet.
Map.stand = Zones.stand

-- A stand's ProximityPrompt "Prompt" (anywhere inside it), or nil when it has none yet.
Map.standPrompt = Zones.standPrompt

-- A cove shop's ProximityPrompt (workspace.Map.Town.<name> or Map.Beach.<name>, Config.stands); fails
-- loudly when the place doesn't have it.
function Map.shopPrompt(name: string): ProximityPrompt
	local shop = Zones.shop(name)
	assert(shop, `workspace.Map.Town.{name} or workspace.Map.Beach.{name} is missing (a cove shop, Config.stands)`)
	local prompt = Map.standPrompt(shop)
	assert(prompt, `{shop:GetFullName()} needs a ProximityPrompt "Prompt"`)
	return prompt
end

-- The Fire Station's ProximityPrompt "CallPrompt" and its part "VehicleSpawn" (anywhere inside it).
function Map.fireStation(): (ProximityPrompt, BasePart)
	local station = child(child(child(workspace, "Map"), "Town"), "FireStation")
	local prompt = station:FindFirstChild("CallPrompt", true)
	assert(prompt and prompt:IsA("ProximityPrompt"), `{station:GetFullName()} needs a ProximityPrompt "CallPrompt"`)
	local spawn = station:FindFirstChild("VehicleSpawn", true)
	assert(spawn and spawn:IsA("BasePart"), `{station:GetFullName()} needs a part "VehicleSpawn"`)
	assert(prompt.Parent and (prompt.Parent:IsA("BasePart") or prompt.Parent:IsA("Attachment")), `{prompt:GetFullName()} must sit in a part or an Attachment (its reach is checked from there)`)
	return prompt, spawn
end

-- Where vehicles fill: the cove's refill bays (area nil) and each area model's Hydrant (area 2-5).
function Map.hydrants(ocean: Model, config): { { area: any?, at: Vector3 } }
	local roads = child(child(workspace, "Map"), "Roads")
	local hydrants = {}
	for _, name in { "TruckRefillBay1", "TruckRefillBay2" } do
		local bay = child(roads, name)
		assert(bay:IsA("PVInstance"), `{bay:GetFullName()} must be a part or Model`)
		table.insert(hydrants, { area = nil, at = bay:GetPivot().Position })
	end
	for _, area in config.areas do
		if area.model then
			local hydrant = child(Zones.areaModel(ocean, area) :: Instance, "Hydrant")
			assert(hydrant:IsA("PVInstance"), `{hydrant:GetFullName()} must be a part or Model`)
			table.insert(hydrants, { area = area, at = hydrant:GetPivot().Position })
		end
	end
	return hydrants
end

-- A Tap's Attachment "Hose", where the Garden Hose's rope starts (server/HeldTools).
function Map.tapAttachment(tap: BasePart): Attachment
	local attachment = child(tap, "Hose")
	assert(attachment:IsA("Attachment"), `{attachment:GetFullName()} must be an Attachment`)
	return attachment
end

-- An area's Gate model (checked by Map.ensure).
function Map.gate(ocean: Model, area): Instance
	return child(Zones.areaModel(ocean, area) :: Instance, "Gate")
end

-- Makes `piece` (a part or a model of parts) stop blocking and showing.
local function clear(piece: Instance)
	local parts = piece:GetDescendants()
	table.insert(parts, piece)
	for _, part in parts do
		if part:IsA("BasePart") then
			if not hidden[part] then
				hidden[part] = { transparency = part.Transparency, canCollide = part.CanCollide, canQuery = part.CanQuery, canTouch = part.CanTouch }
			end
			part.Transparency = 1
			part.CanCollide = false
			part.CanQuery = false -- aim rays (client/Action) see through it
			part.CanTouch = false
		end
	end
end

-- Undoes clear(): `piece` blocks and shows as it did in the place.
local function show(piece: Instance)
	local parts = piece:GetDescendants()
	table.insert(parts, piece)
	for _, part in parts do
		if part:IsA("BasePart") and hidden[part] then
			local was = hidden[part]
			part.Transparency = was.transparency
			part.CanCollide = was.canCollide
			part.CanQuery = was.canQuery
			part.CanTouch = was.canTouch
			hidden[part] = nil
		end
	end
end

-- Opens a bought gate: its Boards and Blocker no longer block or show, and its prompt goes away.
function Map.openGate(ocean: Model, area)
	local gate = Map.gate(ocean, area)
	for _, name in { "Boards", "Blocker" } do
		clear(child(gate, name))
	end
	Map.gatePrompt(gate).Enabled = false
end

-- Shuts a gate again (admin run reset): Boards and Blocker as in the place, its prompt back.
function Map.closeGate(ocean: Model, area)
	local gate = Map.gate(ocean, area)
	for _, name in { "Boards", "Blocker" } do
		show(child(gate, name))
	end
	Map.gatePrompt(gate).Enabled = true
end

-- An area's Rock in front of its deeper pool (checked by Map.ensure), and its prompt.
function Map.rock(ocean: Model, area): Instance
	return child(Zones.areaModel(ocean, area) :: Instance, "Rock")
end

function Map.rockPrompt(rock: Instance): ProximityPrompt
	local prompt = Map.standPrompt(rock)
	assert(prompt, `{rock:GetFullName()} needs a ProximityPrompt "Prompt"`)
	return prompt
end

-- Breaks an area's rock: it no longer blocks or shows, and its prompt goes away.
function Map.breakRock(ocean: Model, area)
	local rock = Map.rock(ocean, area)
	clear(rock)
	Map.rockPrompt(rock).Enabled = false
end

-- Puts a broken rock back (admin run reset); an unbroken one is left as it is.
function Map.mendRock(ocean: Model, area)
	local rock = Map.rock(ocean, area)
	show(rock)
	Map.rockPrompt(rock).Enabled = true
end

-- The parts of an area's `folder` (Vents, CloudPath) in name order (Point1, Point2, ...).
local function partsIn(ocean: Model, area, folder: string): { BasePart }
	local parts = {}
	for _, part in child(Zones.areaModel(ocean, area) :: Instance, folder):GetChildren() do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)
	return parts
end

-- A "steam" area's vent parts.
function Map.vents(ocean: Model, area): { BasePart }
	return partsIn(ocean, area, "Vents")
end

-- A "cloud" area's drift points, in order.
function Map.cloudPath(ocean: Model, area): { BasePart }
	return partsIn(ocean, area, "CloudPath")
end

-- Checks an area's deeper pool, rock and mechanic parts (the cove's live in workspace.Ocean).
local function ensureMechanics(ocean: Model, area)
	local where = (Zones.areaModel(ocean, area) :: Instance):GetFullName()
	assert(Zones.areaPart(ocean, area, "DeepPool"), `{where} is missing part DeepPool (the deeper pool, server/Mechanics)`)
	local holder = Map.rockPrompt(Map.rock(ocean, area)).Parent
	assert(holder and (holder:IsA("BasePart") or holder:IsA("Attachment")), `{where}.Rock's Prompt must sit in a part or an Attachment (its reach is checked from there)`)
	if area.mechanic == "steam" then
		assert(#Map.vents(ocean, area) > 0, `{where}.Vents needs vent parts`)
	elseif area.mechanic == "cloud" then
		local path = #Map.cloudPath(ocean, area)
		assert(path >= 3 and path <= 4, `{where}.CloudPath needs 3-4 parts Point1..PointN, has {path}`)
		assert((Zones.areaPart(ocean, area, "Source") :: BasePart).Anchored, `{where}.Source must be Anchored (it drifts by tween)`)
	end
end

-- Checks one area's model against the contract above.
local function ensureArea(ocean: Model, area)
	local model = Zones.areaModel(ocean, area)
	assert(model and model:IsA("Model"), `workspace.Areas.{area.model} is missing (a Model: the areas live in the place)`)
	for _, name in AREA_PARTS do
		assert(Zones.areaPart(ocean, area, name), `{model:GetFullName()} is missing part {name}`)
	end
	Map.tapAttachment(Zones.areaPart(ocean, area, "Tap") :: BasePart)
	local channel = child(model, "Channel")
	child(channel, "Water")
	assert(Zones.channelPath(ocean, area), `{channel:GetFullName()}.Path needs parts named 1..N (N >= 2, no gaps) from the Pour to the ocean`)
	child(model, "Stand")
	local gate = child(model, "Gate")
	assert(gate:IsA("Model"), `{gate:GetFullName()} must be a Model`)
	child(gate, "Blocker")
	child(gate, "Boards")
	local label = child(gate, "Sign"):FindFirstChild("Label", true)
	assert(label and label:IsA("TextLabel") and label:FindFirstAncestorWhichIsA("SurfaceGui"), `{gate:GetFullName()}.Sign needs a SurfaceGui with a TextLabel "Label"`)
	assert(child(gate, "Prompt"):IsA("BasePart"), `{gate:GetFullName()}.Prompt must be a part`)
	Map.gatePrompt(gate)
end

function Map.ensure(config): Model
	local model = workspace:FindFirstChild("Ocean")
	assert(model and model:IsA("Model"), "workspace.Ocean is missing: the ocean lives in the place")
	for _, partName in REQUIRED do
		Zones.part(model, partName) -- asserts with the part name
	end
	assert(type(Zones.part(model, "Water"):GetAttribute("Depth")) == "number", `Ocean: Water needs a number attribute "Depth"`)
	Map.tapAttachment(Zones.part(model, "Tap"))
	assert(Zones.part(model, "PourDecal"):FindFirstChildWhichIsA("Decal"), "Ocean: PourDecal needs a Decal")

	for _, area in config.areas do
		if area.model then
			ensureArea(model, area)
		end
		ensureMechanics(model, area)
	end
	return model
end

return Map
