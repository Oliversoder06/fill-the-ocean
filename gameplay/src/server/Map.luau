--!strict
-- The ocean lives in the Studio place (workspace.Ocean). This module checks it and moves the water.
-- Contract, one Model workspace.Ocean holding:
--   Spawn     where players appear
--   Pad       touching it moves you to the next open area's Spawn (as in every area below)
--   Source    invisible zone over the well; players aim at it to scoop (client/Action)
--   PourPoint marks the usual pour spot at the basin rim (tripDistance from Source); pouring
--             itself works anywhere next to where the Water will be (shared/Zones.nearFlood)
--   Basin     the floor of the sunken basin; Water rises from it to ground level
--   Tap       the Garden Hose's tap by the pour spot, holding an Attachment "Hose" (the rope's end)
--   Water     with a number attribute "Depth"; rises with the fill fraction. It may hold BasePart
--             children: extra tiles for water wider than one part can be (2048 studs); every tile
--             keeps its own X and Z and rises with it
-- Areas 2-5 (Config.areas with a `model`): one Model each in workspace.Areas, named by that model:
--   Source    zone over the area's water; scooping here pays the area's rate (server/Run)
--   Pour      the channel inlet; pouring here counts as pouring into the ocean
--   Tap       the Garden Hose's tap by the Pour, holding an Attachment "Hose" (the rope's end)
--   Gate      Model: Blocker and Boards (parts, or models of parts) that close the way in, Sign
--             (a SurfaceGui with a TextLabel "Label", client/Gates) and a part Prompt holding a
--             ProximityPrompt "Prompt" (buys the gate)
--   Stand     the area's shop stand (a part or Model) holding a ProximityPrompt "Prompt" that buys
--             the area's items (server/Run); the cove's is workspace.Map.Beach.BackpackStand
--   Pad       touching it moves you to the next open area's Spawn
--   Spawn     where players appear in the area
-- Cove shops that sell their own items (Config.stands): workspace.Map.Town.<name> (a part or Model)
-- holding a ProximityPrompt "Prompt" (server/Run), e.g. Town.ToolShack sells the Water Gun.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Zones = require(ReplicatedStorage.Shared.Zones)

local REQUIRED = { "Spawn", "Source", "PourPoint", "Basin", "Water", "Pad", "Tap" }
local AREA_PARTS = { "Source", "Pour", "Pad", "Spawn", "Tap" }

local Map = {}

local baseTransparency: { [BasePart]: number } = {} -- each Water part's look in the place

-- Sets the visible water height for a fill fraction (0-1). An empty basin shows no water at all,
-- so a drained ocean looks drained.
function Map.setFill(ocean: Model, fraction: number)
	local water = Zones.part(ocean, "Water")
	local basin = Zones.part(ocean, "Basin")
	local height = math.max(0.05, (water:GetAttribute("Depth") :: number) * math.clamp(fraction, 0, 1))
	local y = basin.Position.Y + 0.5 + height / 2
	local tiles: { BasePart } = { water }
	for _, child in water:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(tiles, child)
		end
	end
	for _, tile in tiles do
		if baseTransparency[tile] == nil then
			baseTransparency[tile] = tile.Transparency
		end
		tile.Size = Vector3.new(tile.Size.X, height, tile.Size.Z)
		tile.Position = Vector3.new(tile.Position.X, y, tile.Position.Z)
		tile.Transparency = if fraction <= 0 then 1 else baseTransparency[tile]
	end
end

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

-- An area's stand: workspace.Areas.<model>.Stand, the cove's workspace.Map.Beach.BackpackStand.
-- Nil when the place doesn't have it yet.
function Map.stand(ocean: Model, area): Instance?
	if area.model then
		local model = Zones.areaModel(ocean, area)
		return model and model:FindFirstChild("Stand")
	end
	local scenery = workspace:FindFirstChild("Map")
	local beach = scenery and scenery:FindFirstChild("Beach")
	return beach and beach:FindFirstChild("BackpackStand")
end

-- A stand's ProximityPrompt "Prompt" (anywhere inside it), or nil when it has none yet.
function Map.standPrompt(stand: Instance): ProximityPrompt?
	local prompt = stand:FindFirstChild("Prompt", true)
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- A cove shop's ProximityPrompt (workspace.Map.Town.<name>, Config.stands); fails loudly when the
-- place doesn't have it.
function Map.shopPrompt(name: string): ProximityPrompt
	local scenery = workspace:FindFirstChild("Map")
	local town = scenery and scenery:FindFirstChild("Town")
	local shop = town and town:FindFirstChild(name)
	assert(shop, `workspace.Map.Town.{name} is missing (a cove shop, Config.stands)`)
	local prompt = Map.standPrompt(shop)
	assert(prompt, `{shop:GetFullName()} needs a ProximityPrompt "Prompt"`)
	return prompt
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

-- Opens a bought gate: its Boards and Blocker no longer block or show, and its prompt goes away.
function Map.openGate(ocean: Model, area)
	local gate = Map.gate(ocean, area)
	for _, name in { "Boards", "Blocker" } do
		local piece = child(gate, name)
		local parts = piece:GetDescendants()
		table.insert(parts, piece)
		for _, part in parts do
			if part:IsA("BasePart") then
				part.Transparency = 1
				part.CanCollide = false
				part.CanQuery = false -- aim rays (client/Action) see through it
				part.CanTouch = false
			end
		end
	end
	Map.gatePrompt(gate).Enabled = false
end

-- Checks one area's model against the contract above.
local function ensureArea(ocean: Model, area)
	local model = Zones.areaModel(ocean, area)
	assert(model and model:IsA("Model"), `workspace.Areas.{area.model} is missing (a Model: the areas live in the place)`)
	for _, name in AREA_PARTS do
		assert(Zones.areaPart(ocean, area, name), `{model:GetFullName()} is missing part {name}`)
	end
	Map.tapAttachment(Zones.areaPart(ocean, area, "Tap") :: BasePart)
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

	for _, area in config.areas do
		if area.model then
			ensureArea(model, area)
		end
	end
	return model
end

return Map
