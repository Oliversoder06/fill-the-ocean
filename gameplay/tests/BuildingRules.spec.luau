local BuildingRules = require("../src/shared/BuildingRules")
local Config = require("../src/shared/Config")
local Items = require("../../common/Items")

local tests = {}

-- 3e: Pump, Water Tower, Pipeline, Rain Machine, one per area from Mountain Spring on.
function tests.four_buildings_by_area(t)
	local want = {
		pump = { "Pump", 2, "Pump" },
		waterTower = { "Water Tower", 3, "WaterTower" },
		pipeline = { "Pipeline", 4, "Pipeline" },
		rainMachine = { "Rain Machine", 5, "RainMachine" },
	}
	local count = 0
	for _, item in Config.items do
		if item.kind == "building" then
			count += 1
			local w = want[item.id]
			t.expectEq(w ~= nil, true, `unexpected building {item.id}`)
			t.expectEq(item.name, w[1])
			t.expectEq(item.area, w[2], `{item.id}'s area`)
			t.expectEq(item.model, w[3], `{item.id}'s model`)
			t.expectEq(item.stand, nil, `{item.id} is built on a plot, not sold at a stand`)
		end
	end
	t.expectEq(count, 4)
end

-- Every level costs more and makes more; each later building makes more than a maxed earlier one.
function tests.building_levels_improve(t)
	local last = nil
	for _, item in Config.items do
		if item.kind == "building" then
			t.expectEq(#item.levels >= 2, true, `{item.id} has levels`)
			local rate, cost = item.rate, item.price
			for i, level in item.levels do
				t.expectEq(level.rate > rate, true, `{item.id} level {i} makes more`)
				t.expectEq(level.cost > cost, true, `{item.id} level {i} costs more`)
				rate, cost = level.rate, level.cost
			end
			if last then
				t.expectEq(item.rate > last.levels[#last.levels].rate, true, `{item.id} beats a maxed {last.id}`)
				t.expectEq(item.price > last.price, true, `{item.id} costs more than {last.id}`)
			end
			last = item
		end
	end
end

-- A building litre pays half the hand pay of the best open area, whatever order the ids come in.
function tests.pay_is_half_the_best_open_area(t)
	t.expectEq(Config.buildings.payShare, 0.5)
	t.expectEq(BuildingRules.payPerLitre(Config, { 1 }), 5)
	t.expectEq(BuildingRules.payPerLitre(Config, { 3, 1, 2 }), 125)
	t.expectEq(BuildingRules.payPerLitre(Config, { 1, 2, 3, 4, 5 }), 3125)
end

function tests.clogged_makes_half(t)
	t.expectEq(Config.buildings.clog.factor, 0.5)
	t.expectNear(BuildingRules.litres(Config, 10, 2, false, 1), 20, 1e-9)
	t.expectNear(BuildingRules.litres(Config, 10, 2, true, 1), 10, 1e-9)
	t.expectNear(BuildingRules.litres(Config, 10, 2, false, 1.1), 22, 1e-9, "the Plumber's scale (3f)")
end

function tests.clogs_every_4_to_7_minutes(t)
	t.expectEq(BuildingRules.clogDelay(Config, 0), 240)
	t.expectNear(BuildingRules.clogDelay(Config, 0.5), 330, 1e-9)
	t.expectEq(BuildingRules.clogDelay(Config, 0.999999) <= 420, true)
end

function tests.build_checks_plot_area_and_money(t)
	local pump = Items.get(Config, "pump")
	local plots = { ["2"] = "pump" }
	local function check(index, item, openAreas, money)
		local ok, reason = BuildingRules.canBuild(plots, 6, index, item, openAreas, money)
		return if ok then "ok" else reason
	end
	t.expectEq(check(1, pump, 2, pump.price), "ok")
	t.expectEq(check(3, pump, 2, pump.price - 1e-9), "ok", "pour rounding still buys it")
	t.expectEq(check(2, pump, 2, 1e12), "taken", "one building per plot")
	t.expectEq(check(0, pump, 2, 1e12), "plot")
	t.expectEq(check(7, pump, 2, 1e12), "plot")
	t.expectEq(check(1.5, pump, 2, 1e12), "plot")
	t.expectEq(check(0 / 0, pump, 2, 1e12), "plot")
	t.expectEq(check("1", pump, 2, 1e12), "plot")
	t.expectEq(check(1, nil, 2, 1e12), "unknown")
	t.expectEq(check(1, Items.get(Config, "waterGun"), 2, 1e12), "unknown", "only buildings go on plots")
	t.expectEq(check(1, pump, 1, 1e12), "locked", "on sale once its area is open")
	t.expectEq(check(1, pump, 2, pump.price - 1), "money")
	t.expectEq(check(5, pump, 5, 1e12), "ok", "the same building on several plots")
end

-- One money tolerance for every building price (build, TAB level, the picker).
function tests.affords_tolerates_pour_rounding(t)
	t.expectEq(BuildingRules.affords(150000 - 1e-9, 150000), true, "pour rounding still buys it")
	t.expectEq(BuildingRules.affords(150000, 150000), true)
	t.expectEq(BuildingRules.affords(149999, 150000), false)
end

-- The picker's offer: on sale once its area is open, buildable when the money covers it too.
function tests.buildable_checks_area_and_money(t)
	local pump = Items.get(Config, "pump")
	local function check(openAreas, money)
		local ok, reason = BuildingRules.buildable(pump, openAreas, money)
		return if ok then "ok" else reason
	end
	t.expectEq(check(2, pump.price), "ok")
	t.expectEq(check(2, pump.price - 1e-9), "ok", "pour rounding still builds it")
	t.expectEq(check(1, 1e12), "locked")
	t.expectEq(check(2, pump.price - 1), "money")
	t.expectEq(check(1, 0), "locked", "a closed area shows as locked, not as too dear")
end

-- A team pays its own price (priceOf: common/Items.price for the team's size).
function tests.build_charges_the_team_price(t)
	local pump = Items.get(Config, "pump")
	local function duo(cost: number): number
		return Items.price(Config, cost, 2)
	end
	local ok, reason = BuildingRules.canBuild({}, 6, 1, pump, 2, pump.price, duo)
	t.expectEq(ok, false, "the solo price isn't enough for two")
	t.expectEq(reason, "money")
	t.expectEq((BuildingRules.canBuild({}, 6, 1, pump, 2, duo(pump.price), duo)), true)
	t.expectEq(select(2, BuildingRules.buildable(pump, 2, pump.price, duo)), "money")
	t.expectEq((BuildingRules.buildable(pump, 2, duo(pump.price) - 1e-9, duo)), true, "pour rounding still builds it")
end

-- The shop side is +X, the staff side -X (the plots sit at x +-62).
function tests.aqueduct_side_by_x(t)
	t.expectEq(BuildingRules.side(62), "ShopSide")
	t.expectEq(BuildingRules.side(-62), "StaffSide")
end

-- Economy rule: bought as its area opens, a building pays itself back in 8 to 12 minutes.
function tests.buildings_pay_back_in_about_ten_minutes(t)
	for _, item in Config.items do
		if item.kind == "building" then
			local open = {}
			for id = 1, item.area do
				table.insert(open, id)
			end
			local seconds = item.price / (item.rate * BuildingRules.payPerLitre(Config, open))
			t.expectEq(seconds >= 480 and seconds <= 720, true, `{item.id} pays back in {seconds} s`)
		end
	end
end

return tests
