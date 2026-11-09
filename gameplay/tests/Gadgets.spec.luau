local Gadgets = require("../src/shared/Gadgets")

local tests = {}

function tests.fuel_burns_while_flying(t)
	t.expectNear(Gadgets.fuel(3, 3, 0.5, true, false, 4), 2.5, 1e-9)
	t.expectNear(Gadgets.fuel(3, 3, 0.5, true, true, 4), 2.5, 1e-9, "taking off from the ground still burns")
	t.expectEq(Gadgets.fuel(0.2, 3, 0.5, true, false, 4), 0, "never below empty")
end

-- Fuel refills only on the ground, from empty to full in rechargeSeconds.
function tests.fuel_refills_on_the_ground(t)
	t.expectNear(Gadgets.fuel(0, 4, 1, false, true, 4), 1, 1e-9)
	t.expectNear(Gadgets.fuel(0, 8, 1, false, true, 4), 2, 1e-9, "a bigger tank refills in the same time")
	t.expectEq(Gadgets.fuel(3.9, 4, 1, false, true, 4), 4, "never above full")
	t.expectEq(Gadgets.fuel(1, 4, 1, false, false, 4), 1, "falling keeps what is left")
end

-- A tank levelled down (or a fresh one) never holds more than its max.
function tests.fuel_clamped_to_max(t)
	t.expectEq(Gadgets.fuel(10, 3, 0, false, false, 4), 3)
end

return tests
