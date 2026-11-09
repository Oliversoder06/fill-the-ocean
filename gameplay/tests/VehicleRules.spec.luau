local VehicleRules = require("../src/shared/VehicleRules")
local Items = require("../../common/Items")
local Config = require("../src/shared/Config")

local tests = {}

local function fresh()
	return { owned = {}, itemLevels = {} }
end

local function own(state, id: string)
	table.insert(state.owned, id)
	state.itemLevels[id] = 0
end

-- The vehicles by area, one each in areas 2-5.
local function vehicles()
	local list = {}
	for _, item in Config.items do
		if item.kind == "vehicle" then
			list[item.area] = item
		end
	end
	return list
end

-- 3d: Fire Truck, Tanker, Snowcat Tanker and Water Bomber, sold at the Fire Station.
function tests.four_vehicles_at_the_fire_station(t)
	local want = {
		fireTruck = { "Fire Truck", 2 },
		tanker = { "Tanker", 3 },
		snowcatTanker = { "Snowcat Tanker", 4 },
		waterBomber = { "Water Bomber", 5 },
	}
	local count = 0
	for _, item in Config.items do
		if item.kind == "vehicle" then
			count += 1
			local w = want[item.id]
			t.expectEq(w ~= nil, true, `unexpected vehicle {item.id}`)
			t.expectEq(item.name, w[1])
			t.expectEq(item.area, w[2], `{item.id}'s area`)
			t.expectEq(item.stand, "FireStation", `{item.id} is sold at the Fire Station`)
			t.expectEq(type(item.model), "string", `{item.id} has a model`)
		end
	end
	t.expectEq(count, 4)
	t.expectEq(Config.stands.FireStation, "Fire Station", "its name for the shop")
	t.expectEq(Items.get(Config, "waterBomber").flies, true, "the bomber flies")
	t.expectEq(Items.get(Config, "fireTruck").flies, nil, "trucks drive")
end

-- Every level costs more and raises tank, speed, fill rate and spray rate; each vehicle costs more
-- and holds more than a fully levelled earlier one.
function tests.vehicle_levels_improve(t)
	local list = vehicles()
	for area = 2, 5 do
		local item = list[area]
		t.expectEq(#item.levels >= 2, true, `{item.id} has levels`)
		local last, cost = item, item.price
		for i, level in item.levels do
			t.expectEq(level.cost > cost, true, `{item.id} level {i} costs more`)
			for _, stat in { "tank", "speed", "fillRate", "sprayRate" } do
				if item[stat] ~= nil then
					t.expectEq(level[stat] ~= nil and level[stat] > last[stat], true, `{item.id} level {i} raises {stat}`)
				end
			end
			last, cost = level, level.cost
		end
		if area > 2 then
			local before = list[area - 1]
			t.expectEq(item.price > before.price, true, `{item.id} costs more than {before.id}`)
			t.expectEq(item.tank > before.levels[#before.levels].tank, true, `{item.id} holds more than a maxed {before.id}`)
		end
	end
end

-- About 30 s at a hydrant (or skimming) fills an empty tank at every level.
function tests.fills_in_about_30_seconds(t)
	for _, item in vehicles() do
		for i, level in { item, table.unpack(item.levels) } do
			local seconds = level.tank / level.fillRate
			t.expectEq(seconds >= 20 and seconds <= 30, true, `{item.id} level {i - 1} fills in {seconds} s`)
		end
	end
end

-- Trucks spray from their hose; the bomber drops its whole load at once instead.
function tests.trucks_spray_the_bomber_drops(t)
	for _, item in vehicles() do
		for _, level in { item, table.unpack(item.levels) } do
			t.expectEq(level.sprayRate ~= nil, not item.flies, `{item.id} sprayRate`)
		end
	end
end

-- The Fire Station sells the cheapest vehicle whose area is open; the other stands keep their own.
function tests.fire_station_sells_open_vehicles(t)
	local truck = Items.get(Config, "fireTruck")
	t.expectEq(Items.standPick(Config, fresh(), 1, 1, 1e12, "FireStation"), nil, "nothing before Mountain Spring opens")
	t.expectEq(Items.standPick(Config, fresh(), 1, 2, 1e12, "FireStation"), truck)
	t.expectEq(Items.standPick(Config, fresh(), 1, 2, truck.price - 1, "FireStation"), nil, "not affordable")
	local state = fresh()
	own(state, "fireTruck")
	t.expectEq(Items.standPick(Config, state, 1, 2, 1e12, "FireStation"), nil, "nothing more until Hot Springs")
	t.expectEq(Items.standPick(Config, state, 1, 3, 1e12, "FireStation"), Items.get(Config, "tanker"))
	t.expectEq(Items.standPick(Config, fresh(), 1, 5, 1e12), Items.get(Config, "backpackTank"), "the cove's stand sells no vehicles")
	t.expectEq(Items.standPick(Config, fresh(), 1, 5, 1e12, "ToolShack"), Items.get(Config, "waterGun"), "nor the Tool Shack")
end

-- A call brings the owned vehicle of the furthest area.
function tests.best_vehicle(t)
	local state = fresh()
	t.expectEq(VehicleRules.best(Config, state.owned), nil, "none owned")
	own(state, "waterGun")
	t.expectEq(VehicleRules.best(Config, state.owned), nil, "gadgets aren't vehicles")
	own(state, "fireTruck")
	t.expectEq(VehicleRules.best(Config, state.owned), Items.get(Config, "fireTruck"))
	own(state, "snowcatTanker")
	own(state, "tanker")
	t.expectEq(VehicleRules.best(Config, state.owned), Items.get(Config, "snowcatTanker"))
end

function tests.fill_until_full(t)
	t.expectEq(VehicleRules.fill(0, 100, 10, 1), 10)
	t.expectEq(VehicleRules.fill(95, 100, 10, 1), 100, "never above the tank")
	t.expectEq(VehicleRules.fill(100, 100, 10, 1), 100)
end

function tests.spray_never_more_than_the_tank(t)
	t.expectEq(VehicleRules.spray(50, 100, 0.25), 25)
	t.expectEq(VehicleRules.spray(10, 100, 1), 10)
	t.expectEq(VehicleRules.spray(0, 100, 1), 0)
end

-- Spraying or dropping waits until the vehicle could have got there from its last fill.
function tests.plausible_trip(t)
	local rules = Config.vehicle
	t.expectEq(VehicleRules.plausible(rules, 260, 260 / 40, 40), true, "Main Street at full speed")
	t.expectEq(VehicleRules.plausible(rules, 260, 1, 40), false, "too fast: a teleport")
	t.expectEq(VehicleRules.plausible(rules, 0, 0, 40), true, "still by the hydrant")
	t.expectEq(VehicleRules.plausible(rules, rules.tripMargin, 0, 40), true, "within the margin")
end

-- The bomber fills only low over a pool.
function tests.skims_low_over_a_pool(t)
	local rules = Config.vehicle
	t.expectEq(VehicleRules.skims(rules, 10, 5), true)
	t.expectEq(VehicleRules.skims(rules, rules.skimRadius + 1, 5), false, "beside the pool")
	t.expectEq(VehicleRules.skims(rules, 10, rules.skimHeight + 1), false, "too high")
	t.expectEq(VehicleRules.skims(rules, 10, -rules.skimHeight - 1), false, "far below it")
end

-- A refill bay (no area: the cove) pays the vehicle's own area; an area's hydrant pays that area.
function tests.hydrant_pay_area(t)
	t.expectEq(VehicleRules.payArea(2, nil), 2)
	t.expectEq(VehicleRules.payArea(3, nil), 3)
	t.expectEq(VehicleRules.payArea(3, 2), 2)
	t.expectEq(VehicleRules.payArea(2, 4), 4)
end

return tests
