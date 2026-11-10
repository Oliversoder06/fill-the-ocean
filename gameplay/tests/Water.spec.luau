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

-- A stretch grows by its own growth up to its last percent `to`; `growth` takes over after the last.
-- Percents: 10, 30, 90 (x3 up to percent 2), then 180, 360 (x2).
local STRETCHED = { firstPercent = 10, growth = 2, stretches = { { to = 2, growth = 3 } } }

function tests.stretches_grow_at_their_own_pace(t)
	t.expectEq(Water.litresAt(0.01, STRETCHED, 1), 10)
	t.expectEq(Water.litresAt(0.02, STRETCHED, 1), 40)
	t.expectEq(Water.litresAt(0.03, STRETCHED, 1), 130)
	t.expectEq(Water.litresAt(0.04, STRETCHED, 1), 310)
	t.expectEq(Water.litresAt(0.05, STRETCHED, 1), 670)
	t.expectEq(Water.fill(130, STRETCHED, 1), 0.03)
	t.expectEq(Water.fill(220, STRETCHED, 1), 0.035, "straight between whole percents")
	for _, fraction in { 0, 0.015, 0.03, 0.42, 1 } do
		t.expectNear(Water.fill(Water.litresAt(fraction, STRETCHED, 2), STRETCHED, 2), fraction, 1e-9, `fraction {fraction}`)
	end
end

-- A tool keeps the coin value of what it holds, so water scooped in two areas pays each one's rate.
function tests.mix_pays_each_area(t)
	t.expectEq(Water.mix(0, 10, 10), 100, "an empty tool takes the new water's value")
	local value = Water.mix(0, 4, 10) -- 4 L of cove water at 10 a litre
	value = Water.mix(value, 6, 50) -- topped up with 6 L of spring water at 50
	t.expectEq(value, 40 + 300)
	t.expectEq(Water.mix(value, 0, 50), value, "no new water keeps the value")
end

-- Pouring part of what a tool or tank holds takes that share of its value.
function tests.share_of_value(t)
	t.expectEq(Water.share(340, 10, 10), 340, "all of it")
	t.expectEq(Water.share(340, 10, 5), 170, "half")
	t.expectEq(Water.share(340, 10, 0), 0, "none")
end

function tests.fill_scales_with_players(t)
	t.expectEq(Water.fill(20, OCEAN, 2), 0.01)
	t.expectEq(Water.fill(140, OCEAN, 2), 0.03)
	t.expectEq(Water.litresAt(0.03, OCEAN, 4), 280)
	t.expectEq(Water.fill(10, OCEAN, 0), 0.01, "no players counts as one")
end

-- teamStep: a team of n needs 1 + teamStep * (n - 1) times the water (Config.ocean.teamStep).
function tests.team_step_scales_the_ocean(t)
	local ocean = { firstPercent = 10, growth = 2, teamStep = 0.5 }
	t.expectEq(Water.litresAt(0.01, ocean, 1), 10)
	t.expectEq(Water.litresAt(0.01, ocean, 2), 15)
	t.expectEq(Water.litresAt(0.03, ocean, 3), 140)
	t.expectEq(Water.fill(45, ocean, 2), 0.02)
end

return tests
