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

return tests
