local NextGoal = require("../src/shared/NextGoal")
local Format = require("../src/shared/Format")

local tests = {}

local format = { money = Format.money, fill = Format.fill, percent = Format.percent }

local function gate(onSale: boolean, affordable: boolean)
	return { name = "Mountain Spring", fill = 0.07, price = 16000, onSale = onSale, affordable = affordable, target = "gate" }
end

local sneakers = { name = "Sneakers 3", cost = 1637, place = "in UPGRADES", affordable = true, target = "walk" }
local pack = { name = "Backpack Tank", cost = 1200, place = "at the Cove Well Stand", affordable = true, target = "stand" }
local bucket = { name = "Bucket", cost = 692, place = "in UPGRADES", affordable = false, target = "tool" }
local tip = { name = "Tip Jar 2", cost = 30000, place = "in UPGRADES", affordable = false, target = "tip" }

function tests.the_dearest_thing_you_can_afford_first(t)
	local text, target = NextGoal.pick({ bucket, pack, { name = "Sneakers 1", cost = 69, place = "in UPGRADES", affordable = true, target = "walk" } }, gate(false, false), 1300, 0.01, format)
	t.expectEq(text, "Buy Backpack Tank at the Cove Well Stand · 1,200")
	t.expectEq(target, "stand")
end

function tests.an_affordable_gate_beats_a_cheaper_upgrade(t)
	local text, target = NextGoal.pick({ sneakers }, gate(true, true), 20000, 0.08, format)
	t.expectEq(text, "Open the Mountain Spring gate · 16,000")
	t.expectEq(target, "gate")
end

function tests.a_gate_on_sale_comes_before_saving_for_upgrades(t)
	local text, target = NextGoal.pick({ tip }, gate(true, false), 3000, 0.08, format)
	t.expectEq(text, "Open the Mountain Spring gate · 16,000 (you have 3,000)")
	t.expectEq(target, "gate")
end

function tests.else_the_cheapest_next_thing_with_your_money(t)
	local text, target = NextGoal.pick({ tip, bucket }, gate(false, false), 300, 0.01, format)
	t.expectEq(text, "Next: Bucket in UPGRADES · 692 (you have 300)")
	t.expectEq(target, "tool")
end

function tests.else_the_fill_the_next_gate_waits_for(t)
	local text, target = NextGoal.pick({}, gate(false, false), 300, 0.0231, format)
	t.expectEq(text, "Fill the ocean to 7% to reach Mountain Spring (2.31%)")
	t.expectEq(target, "gate")
end

function tests.nothing_left_but_filling(t)
	local text, target = NextGoal.pick({}, nil, 0, 0.5, format)
	t.expectEq(text, "Fill the ocean!")
	t.expectEq(target, nil)
end

function tests.offers_may_say_their_own_verb(t)
	local pump = { verb = "Build", name = "Pump", cost = 50000, place = "on a town plot", affordable = true, target = "plots" }
	local text = NextGoal.pick({ pump }, nil, 60000, 0.3, format)
	t.expectEq(text, "Build Pump on a town plot · 50,000")
end

return tests
