local Items = require("../../common/Items")
local Config = require("../src/shared/Config")

local tests = {}

local function fresh()
	return { owned = {}, itemLevels = {} }
end

local function own(state, id: string, level: number?)
	table.insert(state.owned, id)
	state.itemLevels[id] = level or 0
end

-- Backpacks by area: the shop sells one per area, each bigger than the last.
local function backpacks()
	local list = {}
	for _, item in Config.items do
		if item.kind == "backpack" then
			list[item.area] = item
		end
	end
	return list
end

function tests.five_backpacks_one_per_area(t)
	local list = backpacks()
	for area = 1, 5 do
		t.expectEq(list[area] ~= nil, true, `a backpack in area {area}`)
	end
	t.expectEq(list[1].name, "Backpack Tank")
	t.expectEq(list[5].name, "Cloud Bag")
end

-- A new backpack never holds less than a fully levelled earlier one, so buying one is always an upgrade.
function tests.backpacks_grow(t)
	local list = backpacks()
	for area = 2, 5 do
		local last = list[area - 1]
		local top = last.levels[#last.levels].capacity
		t.expectEq(list[area].capacity > top, true, `{list[area].name} holds more than a maxed {last.name}`)
		t.expectEq(list[area].price > last.price, true, `{list[area].name} costs more than {last.name}`)
	end
	for _, item in list do
		local capacity, cost = item.capacity, 0
		for i, level in item.levels do
			t.expectEq(level.capacity > capacity, true, `{item.id} level {i} adds capacity`)
			t.expectEq(level.cost > cost, true, `{item.id} level {i} costs more`)
			capacity, cost = level.capacity, level.cost
		end
	end
end

function tests.buy_needs_area_open(t)
	local ok, reason = Items.canBuy(Config, fresh(), "bigTank", 1, 1e12)
	t.expectEq(ok, false)
	t.expectEq(reason, "locked")
	t.expectEq((Items.canBuy(Config, fresh(), "bigTank", 2, 1e12)), true, "open once area 2 is")
	t.expectEq((Items.canBuy(Config, fresh(), "backpackTank", 1, 1e12)), true, "the cove's is open from the start")
end

function tests.buy_needs_money(t)
	local price = Items.get(Config, "backpackTank").price
	local ok, reason = Items.canBuy(Config, fresh(), "backpackTank", 1, price - 1)
	t.expectEq(ok, false)
	t.expectEq(reason, "money")
	t.expectEq((Items.canBuy(Config, fresh(), "backpackTank", 1, price)), true, "exactly the price buys it")
	t.expectEq((Items.canBuy(Config, fresh(), "backpackTank", 1, price - 1e-9)), true, "pour rounding still buys it")
end

function tests.cannot_buy_twice(t)
	local state = fresh()
	own(state, "backpackTank")
	t.expectEq(Items.owned(state, "backpackTank"), true)
	local ok, reason = Items.canBuy(Config, state, "backpackTank", 5, 1e12)
	t.expectEq(ok, false)
	t.expectEq(reason, "owned")
	local unknown, why = Items.canBuy(Config, state, "nope", 5, 1e12)
	t.expectEq(unknown, false)
	t.expectEq(why, "unknown")
end

-- A bigger backpack takes over from a smaller one: the smaller can't be bought or levelled after it.
function tests.backpack_replaces_smaller(t)
	local state = fresh()
	own(state, "bigTank")
	local ok, reason = Items.canBuy(Config, state, "backpackTank", 5, 1e12)
	t.expectEq(ok, false, "no going back to a smaller pack")
	t.expectEq(reason, "replaced")
	t.expectEq((Items.canBuy(Config, state, "twinTanks", 3, 1e12)), true, "a bigger one still sells")
	own(state, "backpackTank")
	own(state, "twinTanks")
	t.expectEq(Items.backpack(Config, state).id, "twinTanks", "the newest pack is worn")
	local _, status = Items.nextLevel(Config, state, "bigTank")
	t.expectEq(status, "replaced")
	local level, wornStatus = Items.nextLevel(Config, state, "twinTanks")
	t.expectEq(wornStatus, "buy")
	t.expectEq(level, Items.get(Config, "twinTanks").levels[1])
end

function tests.next_level_until_max(t)
	local state = fresh()
	local item = Items.get(Config, "backpackTank")
	local none, unowned = Items.nextLevel(Config, state, item.id)
	t.expectEq(none, nil)
	t.expectEq(unowned, "unowned")
	own(state, item.id, #item.levels - 1)
	local last, status = Items.nextLevel(Config, state, item.id)
	t.expectEq(last, item.levels[#item.levels])
	t.expectEq(status, "buy")
	state.itemLevels[item.id] = #item.levels
	local _, maxed = Items.nextLevel(Config, state, item.id)
	t.expectEq(maxed, "max")
	local _, unknown = Items.nextLevel(Config, state, "nope")
	t.expectEq(unknown, nil)
end

function tests.capacity_bonus_from_best_backpack(t)
	local state = fresh()
	t.expectEq(Items.capacityBonus(Config, state), 0, "no pack, no bonus")
	own(state, "backpackTank", 2)
	local small = Items.get(Config, "backpackTank")
	t.expectEq(Items.capacityBonus(Config, state), small.levels[2].capacity, "its level's capacity")
	own(state, "bigTank")
	t.expectEq(Items.capacityBonus(Config, state), Items.get(Config, "bigTank").capacity, "the bigger pack only, not both")
end

-- The pack fills after the tool at the tool's pace: the same litres per sweep, more sweeps.
function tests.pack_fills_at_the_tool_pace(t)
	local state = fresh()
	local stats = { capacity = 60, sweeps = 3 }
	local same = Items.withGear(Config, state, stats)
	t.expectEq(same.capacity, 60)
	t.expectEq(same.sweeps, 3)
	own(state, "backpackTank")
	local bonus = Items.get(Config, "backpackTank").capacity
	local geared = Items.withGear(Config, state, stats)
	t.expectEq(geared.capacity, 60 + bonus)
	t.expectNear(geared.capacity / geared.sweeps, 20, 1e-9, "litres per sweep")
	t.expectEq(stats.capacity, 60, "the tool's stats are left as they were")
end

-- A stand sells the cheapest thing of its area you can buy now.
function tests.stand_picks_cheapest_affordable(t)
	local state = fresh()
	local item = Items.get(Config, "backpackTank")
	t.expectEq(Items.standPick(Config, state, 1, 1, item.price - 1), nil, "nothing affordable")
	t.expectEq(Items.standPick(Config, state, 1, 1, item.price), item)
	t.expectEq(Items.standPick(Config, state, 2, 1, 1e12), nil, "a closed area's stand sells nothing")
	own(state, item.id)
	t.expectEq(Items.standPick(Config, state, 1, 1, 1e12), nil, "nothing left at the cove")
end

function tests.team_owned_buildings(t)
	t.expectEq(Items.teamOwned({}, "pump"), false)
	t.expectEq(Items.teamOwned({ pump = 0 }, "pump"), true, "level 0 is bought")
end

-- 3b: one gadget per area, each with one mechanic (Phase 3 outline).
function tests.six_gadgets_by_area(t)
	local want = {
		waterGun = { "Water Gun", 1 },
		gardenHose = { "Garden Hose", 2 },
		heatGloves = { "Heat Gloves", 3 },
		icePick = { "Ice Pick", 4 },
		jetpackTank = { "Jetpack Tank", 4 },
		cloudNet = { "Cloud Net", 5 },
	}
	local count = 0
	for _, item in Config.items do
		if item.kind == "gadget" then
			count += 1
			local w = want[item.id]
			t.expectEq(w ~= nil, true, `unexpected gadget {item.id}`)
			t.expectEq(item.name, w[1])
			t.expectEq(item.area, w[2], `{item.id}'s area`)
			t.expectEq(type(item.model), "string", `{item.id} has a model`)
		end
	end
	t.expectEq(count, 6)
	t.expectEq(Items.get(Config, "waterGun").range, 30, "the Water Gun pours from 30 studs")
end

-- Every gadget level costs more and makes each of its stats better (Ice Pick: fewer hits).
function tests.gadget_levels_improve(t)
	local better = { range = 1, rate = 1, reach = 1, flightSeconds = 1, capacity = 1, hotFill = 1, hits = -1 }
	for _, item in Config.items do
		if item.kind == "gadget" then
			t.expectEq(#item.levels >= 2, true, `{item.id} has levels`)
			local last, cost = item, item.price
			for i, level in item.levels do
				t.expectEq(level.cost > cost, true, `{item.id} level {i} costs more`)
				local any = false
				for stat, sign in better do
					if last[stat] ~= nil then
						t.expectEq(level[stat] ~= nil, true, `{item.id} level {i} keeps {stat}`)
						t.expectEq((level[stat] - last[stat]) * sign > 0, true, `{item.id} level {i} improves {stat}`)
						any = true
					end
				end
				t.expectEq(any, true, `{item.id} level {i} changes a stat`)
				last, cost = level, level.cost
			end
		end
	end
end

function tests.gadget_stat_only_when_owned(t)
	local state = fresh()
	t.expectEq(Items.gadgetStat(Config, state, "waterGun", "range"), nil, "unowned")
	own(state, "waterGun")
	t.expectEq(Items.gadgetStat(Config, state, "waterGun", "range"), 30)
	state.itemLevels.waterGun = 1
	t.expectEq(Items.gadgetStat(Config, state, "waterGun", "range"), Items.get(Config, "waterGun").levels[1].range)
	t.expectEq(Items.gadgetStat(Config, state, "nope", "range"), nil, "unknown id")
end

-- The Jetpack Tank holds water too, on top of the worn backpack.
function tests.jetpack_holds_water(t)
	local state = fresh()
	own(state, "jetpackTank")
	local jet = Items.get(Config, "jetpackTank")
	t.expectEq(Items.capacityBonus(Config, state), jet.capacity)
	own(state, "backpackTank")
	t.expectEq(Items.capacityBonus(Config, state), jet.capacity + Items.get(Config, "backpackTank").capacity, "both count")
	state.itemLevels.jetpackTank = 2
	t.expectEq(Items.capacityBonus(Config, state), jet.levels[2].capacity + Items.get(Config, "backpackTank").capacity)
end

-- Hotbar slots: owned gadgets you use by hand, in config order; passive ones (gloves, pick) have none.
function tests.hotbar_slots(t)
	local state = fresh()
	t.expectEq(#Items.slots(Config, state), 0)
	own(state, "jetpackTank")
	own(state, "heatGloves")
	own(state, "waterGun")
	own(state, "icePick")
	local slots = Items.slots(Config, state)
	t.expectEq(#slots, 2)
	t.expectEq(slots[1].id, "waterGun")
	t.expectEq(slots[2].id, "jetpackTank")
end

-- Cloud Catcher is up in the clouds: only players with a Jetpack Tank reach it.
function tests.cloud_catcher_needs_jetpack(t)
	local state = fresh()
	local ids = Items.reachable(Config, state, { 1, 2, 3, 4, 5 })
	t.expectEq(table.concat(ids, ","), "1,2,3,4")
	own(state, "jetpackTank")
	t.expectEq(table.concat(Items.reachable(Config, state, { 1, 2, 3, 4, 5 }), ","), "1,2,3,4,5")
	t.expectEq(table.concat(Items.reachable(Config, fresh(), { 1, 3 }), ","), "1,3", "other areas need nothing")
end

-- The jetpack opens area 5, so it must cost less than the Cloud Catcher gate.
function tests.jetpack_affordable_before_cloud_gate(t)
	local cloud = Config.areas[5]
	t.expectEq(Items.get(Config, "jetpackTank").price < (cloud.gate :: any).price, true)
end

-- The cove's Tool Shack sells the Water Gun; the cove's stand keeps selling only its backpack.
function tests.tool_shack_sells_water_gun(t)
	local state = fresh()
	t.expectEq(Items.standPick(Config, state, 1, 1, 1e12, "ToolShack"), Items.get(Config, "waterGun"))
	t.expectEq(Items.standPick(Config, state, 1, 1, 1e12), Items.get(Config, "backpackTank"))
	own(state, "waterGun")
	t.expectEq(Items.standPick(Config, state, 1, 1, 1e12, "ToolShack"), nil)
	t.expectEq(Items.standPick(Config, state, 2, 2, 1e12, "ToolShack"), nil, "the shack sells only cove items")
	t.expectEq(Config.stands.ToolShack, "Tool Shack", "its name for the shop")
end

return tests
