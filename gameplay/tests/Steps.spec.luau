local Steps = require("../src/shared/Steps")

local tests = {}

function tests.floors_map_to_surfaces(t)
	t.expectEq(Steps.surface("Pavement"), "stone")
	t.expectEq(Steps.surface("CeramicTiles"), "stone")
	t.expectEq(Steps.surface("LeafyGrass"), "grass")
	t.expectEq(Steps.surface("Grass"), "grass")
	t.expectEq(Steps.surface("Sand"), "sand")
	t.expectEq(Steps.surface("WoodPlanks"), "wood")
	t.expectEq(Steps.surface("Wood"), "wood")
end

function tests.unknown_floors_sound_like_stone(t)
	t.expectEq(Steps.surface("Neon"), "stone")
	t.expectEq(Steps.surface("Plastic"), "stone")
end

function tests.a_step_lands_on_each_dip_of_the_bob(t)
	-- the camera bob dips at phase pi/2, 3pi/2, ...: the step count goes up exactly there
	t.expectEq(Steps.stepIndex(0), 0)
	t.expectEq(Steps.stepIndex(math.pi / 2 - 0.01), 0)
	t.expectEq(Steps.stepIndex(math.pi / 2 + 0.01), 1)
	t.expectEq(Steps.stepIndex(3 * math.pi / 2 + 0.01), 2)
end

function tests.stride_matches_the_bob(t)
	-- the bob makes 0.09 cycles per stud and steps twice per cycle
	t.expectNear(Steps.STRIDE, 1 / 0.18, 1e-9)
end

return tests
