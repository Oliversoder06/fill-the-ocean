local Water = require("../src/shared/Water")

local tests = {}

function tests.target_scales_with_players(t)
	t.expectEq(Water.target(972, 2, 1), 1944)
	t.expectEq(Water.target(972, 0, 1), 972)
	t.expectEq(Water.target(1000, 3, 0.5), 1500)
end

function tests.rescale_keeps_percent(t)
	t.expectEq(Water.rescale(400, 1000, 500), 200)
end

function tests.rescale_up_keeps_percent(t)
	t.expectEq(Water.rescale(300, 1000, 2000), 600)
end

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

return tests
