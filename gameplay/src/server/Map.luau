--!strict
-- Stages live in the Studio place (workspace.Stages). This module checks them and moves the water.
-- Contract, one Model per stage named after config.stages[i].name:
--   Spawn     where players are moved at stage start
--   Source    invisible zone over the well; players aim at it to scoop (client/Action)
--   PourPoint at the basin rim; players stand near it and aim at it or the Water to pour;
--             tripDistance from Source
--   Basin     the floor of the sunken basin; Water rises from it to ground level
--   Water     with a number attribute "Depth"; rises with the fill fraction

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Zones = require(ReplicatedStorage.Shared.Zones)

local REQUIRED = { "Spawn", "Source", "PourPoint", "Basin", "Water" }

local Map = {}

local baseTransparency: { [BasePart]: number } = {} -- each Water part's look in the place

-- Sets the visible water height for a fill fraction (0-1). An empty basin shows no water at all,
-- so a drained stage looks drained.
function Map.setFill(stage: Model, fraction: number)
	local water = Zones.part(stage, "Water")
	local basin = Zones.part(stage, "Basin")
	if baseTransparency[water] == nil then
		baseTransparency[water] = water.Transparency
	end
	local height = math.max(0.05, (water:GetAttribute("Depth") :: number) * math.clamp(fraction, 0, 1))
	water.Size = Vector3.new(water.Size.X, height, water.Size.Z)
	water.Position = Vector3.new(basin.Position.X, basin.Position.Y + 0.5 + height / 2, basin.Position.Z)
	water.Transparency = if fraction <= 0 then 1 else baseTransparency[water]
end

function Map.ensure(config): Folder
	local folder = workspace:FindFirstChild("Stages")
	assert(folder and folder:IsA("Folder"), "workspace.Stages is missing: the stages live in the place")
	for _, stage in config.stages do
		local model = folder:FindFirstChild(stage.name)
		assert(model and model:IsA("Model"), `workspace.Stages is missing stage {stage.name}`)
		for _, partName in REQUIRED do
			Zones.part(model, partName) -- asserts with the stage and part name
		end
		assert(
			type(Zones.part(model, "Water"):GetAttribute("Depth")) == "number",
			`Stage {stage.name}: Water needs a number attribute "Depth"`
		)
	end
	return folder
end

return Map
