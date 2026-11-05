--!strict
-- Footstep maths: which surface a floor sounds like, and when a step lands. Pure, Lune-tested.

local Steps = {}

-- Matches client/CameraFeel: the bob runs 0.09 cycles per stud and dips twice per cycle.
Steps.BOB_CYCLES_PER_STUD = 0.09
Steps.STRIDE = 1 / (2 * Steps.BOB_CYCLES_PER_STUD) -- studs between steps (other players)

local SURFACES = {
	Grass = "grass",
	LeafyGrass = "grass",
	Ground = "grass",
	Mud = "grass",
	Sand = "sand",
	Snow = "sand",
	Salt = "sand",
	Wood = "wood",
	WoodPlanks = "wood",
}

-- The surface a floor material sounds like (by Enum.Material name). Anything hard is stone.
function Steps.surface(materialName: string): string
	return SURFACES[materialName] or "stone"
end

-- How many steps the bob has made by this phase: one more at each dip (phase pi/2, 3pi/2, ...).
function Steps.stepIndex(phase: number): number
	return math.floor(phase / math.pi + 0.5)
end

return Steps
