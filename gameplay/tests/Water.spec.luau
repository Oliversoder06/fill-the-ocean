local Water = require("../src/shared/Water")

local tests = {}

function tests.pour_empties_whole_tool(t)
	t.expectEq(Water.pourAmount(60, 0, 1000), 60)
end

function tests.pour_stops_at_target(t)
	t.expectEq(Water.pourAmount(60, 990, 1000), 10)
end

function tests.pour_needs_carried(t)
	t.expectEq(Water.pourAmount(0, 0, 1000), 0)
end

function tests.pour_never_negative_when_full(t)
	t.expectEq(Water.pourAmount(10, 1001, 1000), 0)
end

function tests.scoop_one_sweep_fills(t)
	t.expectEq(Water.scoopAmount(0, 10, 1), 10)
end

function tests.scoop_splits_into_sweeps(t)
	t.expectEq(Water.scoopAmount(0, 10, 4), 2.5)
	t.expectEq(Water.scoopAmount(5, 10, 4), 2.5)
end

function tests.scoop_last_sweep_tops_up(t)
	t.expectEq(Water.scoopAmount(9, 10, 4), 1)
	local carried = 0
	for _ = 1, 3 do
		carried += Water.scoopAmount(carried, 1, 3)
	end
	t.expectEq(carried, 1, "three thirds fill exactly")
end

function tests.scoop_full_is_zero(t)
	t.expectEq(Water.scoopAmount(10, 10, 3), 0)
	t.expectEq(Water.scoopAmount(11, 10, 3), 0)
end

function tests.scoop_zero_sweeps_counts_as_one(t)
	t.expectEq(Water.scoopAmount(0, 10, 0), 10)
end

-- Percent k needs firstPercent * growth^(k-1) litres: 10, 20, 40, 80, ...
local OCEAN = { firstPercent = 10, growth = 2 }

function tests.fill_is_exact_at_whole_percents(t)
	t.expectEq(Water.fill(0, OCEAN, 1), 0)
	t.expectEq(Water.fill(10, OCEAN, 1), 0.01)
	t.expectEq(Water.fill(30, OCEAN, 1), 0.02)
	t.expectEq(Water.fill(70, OCEAN, 1), 0.03)
	t.expectEq(Water.fill(50, OCEAN, 1), 0.025, "straight between whole percents")
	t.expectEq(Water.fill(Water.litresAt(1, OCEAN, 1), OCEAN, 1), 1)
	t.expectEq(Water.fill(Water.litresAt(1, OCEAN, 1) * 2, OCEAN, 1), 1, "never past full")
	t.expectEq(Water.fill(-5, OCEAN, 1), 0, "never below empty")
end

function tests.fill_and_litresAt_round_trip(t)
	t.expectEq(Water.litresAt(0, OCEAN, 1), 0)
	t.expectEq(Water.litresAt(0.03, OCEAN, 1), 70)
	t.expectNear(Water.litresAt(1, OCEAN, 1), 10 * (2 ^ 100 - 1), 10 * 2 ^ 100 * 1e-12)
	for _, fraction in { 0, 0.004, 0.01, 0.37, 0.5, 0.955, 0.99, 1 } do
		t.expectNear(Water.fill(Water.litresAt(fraction, OCEAN, 3), OCEAN, 3), fraction, 1e-9, `fraction {fraction}`)
	end
	for _, litres in { 0, 5, 10, 55, 1234567 } do
		t.expectNear(Water.litresAt(Water.fill(litres, OCEAN, 2), OCEAN, 2), litres, litres * 1e-9, `litres {litres}`)
	end
end

function tests.fill_scales_with_players(t)
	t.expectEq(Water.fill(20, OCEAN, 2), 0.01)
	t.expectEq(Water.fill(140, OCEAN, 2), 0.03)
	t.expectEq(Water.litresAt(0.03, OCEAN, 4), 280)
	t.expectEq(Water.fill(10, OCEAN, 0), 0.01, "no players counts as one")
end

return tests
