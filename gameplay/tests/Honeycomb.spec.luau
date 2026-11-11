local Honeycomb = require("../src/shared/Honeycomb")
local Config = require("../src/shared/Config")
local Areas = require("../../common/Areas")

local tests = {}

local CATEGORIES = { "boosts", "gear", "vehicles", "buildings", "staff", "areas" }

local function key(pos): string
	return `{pos.q},{pos.r}`
end

-- The cell mirrored about the vertical axis (flat-top axial).
local function mirror(pos)
	return { q = 0 - pos.q, r = pos.r + pos.q } -- 0 - q: no "-0" in the cell's key
end

local function upgrade(layout, id: string)
	local _, found = Honeycomb.find(layout, id)
	return found or error(`no upgrade sells {id}`)
end

local function costOf(link): number?
	if link.kind == "track" then
		return Config.track(link.id).levels[link.level].cost
	elseif link.kind == "gate" then
		return Areas.byId(Config, link.areaId).gate.price
	end
	for _, item in Config.items do
		if item.id == link.id then
			return if link.level == 1 then item.price else item.levels[link.level - 1].cost
		end
	end
	return nil
end

local function view(overrides)
	local v = {
		levels = {},
		items = {},
		openAreas = { [1] = true },
		wallet = 0,
		price = costOf,
		reachable = function()
			return true
		end,
	}
	for k, value in overrides do
		v[k] = value
	end
	return v
end

local function allOpen()
	return { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }
end

local function ids(list): string
	local out = {}
	for _, u in list do
		table.insert(out, u.id)
	end
	return table.concat(out, ",")
end

function tests.to_pixel_is_flat_top_axial(t)
	local x, y = Honeycomb.toPixel(0, 0, 10)
	t.expectEq(x, 0)
	t.expectEq(y, 0)
	x, y = Honeycomb.toPixel(1, 0, 10)
	t.expectNear(x, 15, 1e-9)
	t.expectNear(y, 10 * math.sqrt(3) / 2, 1e-9)
	x, y = Honeycomb.toPixel(0, 1, 10)
	t.expectNear(x, 0, 1e-9)
	t.expectNear(y, 10 * math.sqrt(3), 1e-9)
end

function tests.neighbours_are_six_at_distance_one(t)
	local seen = {}
	for _, n in Honeycomb.neighbours(2, -1) do
		t.expectEq(Honeycomb.distance(2, -1, n.q, n.r), 1, "neighbour distance")
		t.expectEq(seen[key(n)], nil, "neighbours distinct")
		seen[key(n)] = true
		local x, y = Honeycomb.toPixel(n.q - 2, n.r + 1, 1)
		t.expectNear(math.sqrt(x * x + y * y), math.sqrt(3), 1e-9, "neighbour centres one hex apart")
	end
	t.expectEq(#Honeycomb.neighbours(0, 0), 6)
	t.expectEq(Honeycomb.distance(0, 0, 2, -1), 2)
	t.expectEq(Honeycomb.distance(0, 0, 3, 3), 6)
	t.expectEq(Honeycomb.distance(-1, 2, -1, 2), 0)
end

function tests.main_is_the_tool_and_a_ring_of_categories(t)
	local layout = Honeycomb.layout(Config)
	t.expectEq(layout.tool.id, "tool")
	t.expectEq(#layout.tool.links, #Config.track("tool").levels, "one hex for every tool level")
	t.expectEq(#layout.ring, 6)
	local seen = {}
	for i, hex in layout.ring do
		t.expectEq(hex.id, CATEGORIES[i], "ring order")
		t.expectEq(layout.order[i], CATEGORIES[i])
		t.expectEq(Honeycomb.distance(0, 0, hex.q, hex.r), 1, "ring touches the centre")
		t.expectEq(seen[key(hex)], nil, "ring hexes distinct")
		seen[key(hex)] = true
	end
end

function tests.ring_slots_fill_ring_one_then_ring_two_without_overlaps(t)
	for count = 0, 18 do
		local slots = Honeycomb.ringSlots(count)
		t.expectEq(#slots, count, `{count} slots`)
		local used, inner = {}, 0
		for _, pos in slots do
			local d = Honeycomb.distance(0, 0, pos.q, pos.r)
			if d < 1 or d > 2 then
				error(`{count}: {key(pos)} is not in ring 1 or 2`)
			elseif used[key(pos)] then
				error(`{count}: {key(pos)} used twice`)
			end
			used[key(pos)] = true
			inner += if d == 1 then 1 else 0
		end
		t.expectEq(inner, math.min(count, 6), `{count}: ring 1 fills first`)
	end
	t.expectEq((pcall(Honeycomb.ringSlots, 19)), false, "past ring 2 there is no room")
end

function tests.ring_slots_are_mirror_symmetric(t)
	-- the mirror helper is right: same height, x flipped
	local x, y = Honeycomb.toPixel(2, -1, 1)
	local mx, my = Honeycomb.toPixel(mirror({ q = 2, r = -1 }).q, mirror({ q = 2, r = -1 }).r, 1)
	t.expectNear(mx, -x, 1e-9)
	t.expectNear(my, y, 1e-9)
	for count = 0, 18 do
		local used = {}
		for _, pos in Honeycomb.ringSlots(count) do
			used[key(pos)] = true
		end
		for _, pos in Honeycomb.ringSlots(count) do
			t.expectEq(used[key(mirror(pos))], true, `{count}: the mirror of {key(pos)}`)
		end
	end
end

-- Empty hexes complete every ring the upgrades reach (style clear-tide), never on an upgrade's cell.
function tests.empty_slots_complete_the_rings_the_upgrades_reach(t)
	for count = 0, 18 do
		local used = {}
		for _, pos in Honeycomb.ringSlots(count) do
			used[key(pos)] = true
		end
		local empty = Honeycomb.emptySlots(count)
		for _, pos in empty do
			if used[key(pos)] then
				error(`{count}: empty {key(pos)} sits on an upgrade`)
			end
			used[key(pos)] = true
		end
		t.expectEq(count + #empty, if count <= 6 then 6 else 18, `{count}: the rings reached are full`)
		for _, pos in empty do
			t.expectEq(used[key(mirror(pos))], true, `{count}: the mirror of empty {key(pos)}`)
		end
	end
	local layout = Honeycomb.layout(Config)
	for _, catId in layout.order do
		local cat = layout.categories[catId]
		t.expectEq(#cat.empty, #Honeycomb.emptySlots(#cat.upgrades), `{catId}: its empty hexes`)
	end
end

-- Slots read top to bottom, left to right, so the earliest upgrades sit nearest the top; the same
-- count always gives the same slots.
function tests.ring_slots_read_top_to_bottom_and_are_deterministic(t)
	for count = 0, 18 do
		local slots, again = Honeycomb.ringSlots(count), Honeycomb.ringSlots(count)
		for i, pos in slots do
			t.expectEq(key(again[i]), key(pos), `{count} slot {i}`)
			if i > 1 then
				local px, py = Honeycomb.toPixel(slots[i - 1].q, slots[i - 1].r, 1)
				local x, y = Honeycomb.toPixel(pos.q, pos.r, 1)
				if not (y > py + 1e-9 or (math.abs(y - py) < 1e-9 and x > px)) then
					error(`{count}: slot {i} ({key(pos)}) reads before slot {i - 1}`)
				end
			end
		end
	end
	t.expectEq(key(Honeycomb.ringSlots(1)[1]), "0,-1", "one: straight up")
	local two = Honeycomb.ringSlots(2)
	t.expectEq(`{key(two[1])} {key(two[2])}`, "-1,0 1,-1", "two: upper left and right")
	t.expectEq(key(Honeycomb.ringSlots(7)[1]), "0,-2", "seven: ring 1 and the top of ring 2")
end

function tests.each_category_sits_in_ring_slots(t)
	local layout = Honeycomb.layout(Config)
	for _, catId in CATEGORIES do
		local cat = layout.categories[catId]
		local want = Honeycomb.ringSlots(#cat.upgrades)
		t.expectEq(#cat.slots, #want, `{catId} slot count`)
		for i, pos in want do
			t.expectEq(key(cat.slots[i]), key(pos), `{catId} slot {i}`)
		end
	end
end

function tests.upgrades_land_in_their_categories_by_area(t)
	local layout = Honeycomb.layout(Config)
	local function list(catId)
		return ids(layout.categories[catId].upgrades)
	end
	t.expectEq(list("boosts"), "pickup,hold,quick,walk,tip")
	t.expectEq(list("gear"), "backpacks,waterGun,gardenHose,heatGloves,icePick,jetpackTank,cloudNet")
	t.expectEq(list("vehicles"), "fireTruck,tanker,snowcatTanker,waterBomber")
	t.expectEq(list("buildings"), "pump,waterTower,pipeline,rainMachine")
	t.expectEq(list("staff"), "helper,lifeguard,firefighter,plumber")
	t.expectEq(list("areas"), "gate:2,gate:3,gate:4,gate:5")
	for _, catId in CATEGORIES do
		local last = 0
		for _, u in layout.categories[catId].upgrades do
			t.expectEq(u.areaId >= last, true, `{catId}: {u.id} after an earlier area`)
			last = u.areaId
		end
	end
end

-- One hex per upgrade: every track level, item link and gate is sold by exactly one hex.
function tests.every_level_is_sold_by_one_hex(t)
	local layout = Honeycomb.layout(Config)
	local count, hexes = {}, 1
	local function add(u)
		for _, link in u.links do
			local k = `{link.kind}:{link.id}:{link.level}`
			count[k] = (count[k] or 0) + 1
		end
	end
	add(layout.tool)
	for _, catId in CATEGORIES do
		for _, u in layout.categories[catId].upgrades do
			add(u)
			hexes += 1
		end
	end
	local packs, gates = 0, 0
	for _, track in Config.tracks do
		for level in track.levels do
			t.expectEq(count[`track:{track.id}:{level}`], 1, `track {track.id} level {level}`)
		end
	end
	for _, item in Config.items do
		packs += if item.kind == "backpack" then 1 else 0
		for level = 1, #item.levels + 1 do
			t.expectEq(count[`item:{item.id}:{level}`], 1, `item {item.id} link {level}`)
		end
	end
	for _, area in Config.areas do
		if area.gate then
			gates += 1
			t.expectEq(count[`gate:{Areas.gateId(area.id)}:1`], 1, `gate {area.id}`)
		end
	end
	t.expectEq(hexes, #Config.tracks + #Config.items - packs + 1 + gates, "one hex per track, item and gate; one for the backpacks")
end

function tests.upgrades_hold_their_levels_in_order(t)
	local layout = Honeycomb.layout(Config)
	local function links(id)
		local out = {}
		for _, link in upgrade(layout, id).links do
			table.insert(out, `{link.id}:{link.level}@{link.areaId}`)
		end
		return table.concat(out, ",")
	end
	t.expectEq(links("pickup"), "pickup:1@1,pickup:2@2,pickup:3@2,pickup:4@3")
	t.expectEq(links("waterGun"), "waterGun:1@1,waterGun:2@1,waterGun:3@1,waterGun:4@1,waterGun:5@1,waterGun:6@1")
	local packs = {}
	for area, id in { "backpackTank", "bigTank", "twinTanks", "insulatedTank", "cloudBag" } do
		for level = 1, 6 do
			table.insert(packs, `{id}:{level}@{area}`)
		end
	end
	t.expectEq(links("backpacks"), table.concat(packs, ","))
	local gate = upgrade(layout, "gate:4")
	t.expectEq(gate.kind, "gate")
	t.expectEq(links("gate:4"), "gate:4:1@4")
	t.expectEq(gate.links[1].kind, "gate")
end

function tests.owned_count_is_the_furthest_level_owned(t)
	local layout = Honeycomb.layout(Config)
	t.expectEq(Honeycomb.ownedCount(layout.tool, view({ levels = { tool = 7 } })), 7)
	local backpacks = upgrade(layout, "backpacks")
	t.expectEq(Honeycomb.ownedCount(backpacks, view({})), 0)
	t.expectEq(Honeycomb.ownedCount(backpacks, view({ items = { backpackTank = 2 } })), 2)
	t.expectEq(Honeycomb.ownedCount(backpacks, view({ items = { backpackTank = 1, bigTank = 1 } })), 7, "a bigger pack passes the earlier links")
	t.expectEq(Honeycomb.ownedCount(upgrade(layout, "gate:2"), view({})), 0)
	t.expectEq(Honeycomb.ownedCount(upgrade(layout, "gate:2"), view({ openAreas = { [1] = true, [2] = true } })), 1)
end

function tests.states_count_levels_owned_of_all(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ levels = { pickup = 1, quick = 3 } }))
	t.expectEq(s.pickup.owned, 1)
	t.expectEq(s.pickup.total, 4)
	t.expectEq(s.quick.owned, 3)
	t.expectEq(s.quick.total, 10)
	t.expectEq(s.hold.owned, 0)
	local main = Honeycomb.states(layout, "main", view({ levels = { tool = 2 } }))
	t.expectEq(main.tool.owned, 2)
	t.expectEq(main.tool.total, 24)
end

function tests.states_next_affordable_is_buy(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ levels = { pickup = 1 }, openAreas = { [1] = true, [2] = true }, wallet = 4e6 }))
	t.expectEq(s.pickup.state, "buy")
	t.expectEq(s.pickup.price, 3.2e6, "the next level's price")
	s = Honeycomb.states(layout, "boosts", view({ wallet = 39.9999999 }))
	t.expectEq(s.hold.state, "buy", "fractional coins still buy")
	t.expectEq(Honeycomb.states(layout, "main", view({ wallet = 20 })).tool.state, "buy", "Cup (20)")
end

function tests.states_short_shows_progress(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ levels = { pickup = 1 }, openAreas = { [1] = true, [2] = true }, wallet = 1.6e6 }))
	t.expectEq(s.pickup.state, "short")
	t.expectEq(s.pickup.price, 3.2e6)
	t.expectNear(s.pickup.progress, 0.5, 1e-9)
	s = Honeycomb.states(layout, "boosts", view({ wallet = -5 }))
	t.expectEq(s.hold.state, "short")
	t.expectEq(s.hold.progress, 0, "progress clamps at 0")
end

function tests.states_max_when_every_level_is_owned(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ levels = { pickup = 4, hold = 1 }, openAreas = allOpen() }))
	t.expectEq(s.pickup.state, "max")
	t.expectEq(s.pickup.owned, 4)
	t.expectEq(s.pickup.price, nil)
	t.expectEq(s.hold.state, "max")
end

function tests.states_locked_behind_a_closed_area(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ levels = { pickup = 1 }, wallet = 1e12 }))
	t.expectEq(s.pickup.state, "locked", "pickup 2 opens with Mountain Spring")
	s = Honeycomb.states(layout, "vehicles", view({ wallet = 1e12 }))
	t.expectEq(s.fireTruck.state, "locked")
end

function tests.states_locked_when_unreachable_or_unpriced(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "gear", view({
		openAreas = allOpen(),
		wallet = 1e12,
		reachable = function(id)
			return id ~= "cloudNet"
		end,
	}))
	t.expectEq(s.cloudNet.state, "locked", "unreachable")
	t.expectEq(s.icePick.state, "buy")
	s = Honeycomb.states(layout, "gear", view({
		openAreas = allOpen(),
		wallet = 1e12,
		price = function(link)
			return if link.id == "waterGun" then nil else costOf(link)
		end,
	}))
	t.expectEq(s.waterGun.state, "locked", "no price: can't be bought here")
end

function tests.states_a_bigger_backpack_passes_the_earlier_links(t)
	local layout = Honeycomb.layout(Config)
	local v = view({ items = { backpackTank = 1, bigTank = 1 }, openAreas = { [1] = true, [2] = true }, wallet = 1e12 })
	local st = Honeycomb.states(layout, "gear", v).backpacks
	t.expectEq(st.state, "buy")
	t.expectEq(st.owned, 7)
	t.expectEq(st.total, 30)
	local link = Honeycomb.link(upgrade(layout, "backpacks"), st.owned)
	t.expectEq(`{link.id}:{link.level}`, "bigTank:2", "the worn pack's next upgrade")
	st = Honeycomb.states(layout, "gear", view({ items = { backpackTank = 6, bigTank = 6 }, openAreas = { [1] = true, [2] = true }, wallet = 1e12 })).backpacks
	t.expectEq(st.state, "locked", "the next pack's area is closed")
end

function tests.gate_states_follow_the_gates_price(t)
	local layout = Honeycomb.layout(Config)
	local function onSale(id)
		return function(link)
			return if link.id == id then costOf(link) else nil
		end
	end
	local s = Honeycomb.states(layout, "areas", view({ price = onSale("gate:2"), wallet = 46500 }))
	t.expectEq(s["gate:2"].state, "short", "on sale, not enough yet")
	t.expectNear(s["gate:2"].progress, 0.5, 1e-9)
	t.expectEq(s["gate:3"].state, "locked", "not on sale")
	s = Honeycomb.states(layout, "areas", view({ price = onSale("gate:2"), wallet = 93000 }))
	t.expectEq(s["gate:2"].state, "buy")
	s = Honeycomb.states(layout, "areas", view({ price = onSale("gate:3"), openAreas = { [1] = true, [2] = true } }))
	t.expectEq(s["gate:2"].state, "max", "open")
	t.expectEq(s["gate:2"].owned, 1)
	t.expectEq(s["gate:2"].total, 1)
	t.expectEq(s["gate:3"].state, "short")
end

function tests.badges_count_buy_hexes(t)
	local layout = Honeycomb.layout(Config)
	local rich = Honeycomb.badges(layout, view({ openAreas = allOpen(), wallet = 1e15 }))
	local sum = rich.main
	t.expectEq(rich.main, 1, "the tool")
	for _, catId in CATEGORIES do
		local want = if catId == "areas" then 0 else #layout.categories[catId].upgrades
		t.expectEq(rich[catId], want, `{catId}: every upgrade (every gate open)`)
		sum += rich[catId]
	end
	t.expectEq(rich.total, sum)
	local poor = Honeycomb.badges(layout, view({ wallet = 0 }))
	t.expectEq(poor.total, 0)
	t.expectEq(poor.boosts, 0)
	local start = Honeycomb.badges(layout, view({ wallet = 100 }))
	t.expectEq(start.main, 1, "Cup (20)")
	t.expectEq(start.boosts, 3, "Hold (40), Quick (35), Sneakers (69), not Pickup (192) or Tip (300)")
	t.expectEq(start.gear, 0)
	t.expectEq(start.areas, 0)
	t.expectEq(start.total, 4)
	local gates = Honeycomb.badges(layout, view({ wallet = 1e15, levels = { tool = 24, pickup = 4, hold = 1, quick = 10, walk = 10, tip = 9 } }))
	t.expectEq(gates.areas, 4, "every gate priced here and paid for")
end

function tests.badges_say_which_wallets_keep_them(t)
	local layout = Honeycomb.layout(Config)
	local start, low, high = Honeycomb.badges(layout, view({ wallet = 100 }))
	t.expectEq(low <= 100 and 100 < high, true, "the wallet itself is in range")
	t.expectNear(low, 69, 1e-5, "Sneakers (69): the dearest buy")
	t.expectNear(high, 192, 1e-5, "Pickup (192): the cheapest short")
	for _, wallet in { low, 150, high - 0.01 } do
		t.expectEq(Honeycomb.badges(layout, view({ wallet = wallet })).total, start.total, `same badges at {wallet}`)
	end
	t.expectEq(Honeycomb.badges(layout, view({ wallet = low - 0.01 })).total < start.total, true, "under the dearest buy")
	t.expectEq(Honeycomb.badges(layout, view({ wallet = high })).total > start.total, true, "at the cheapest short")
	local _, noneLow, noneHigh = Honeycomb.badges(layout, view({ openAreas = allOpen(), wallet = 1e300 }))
	t.expectEq(noneHigh, math.huge, "nothing short: no ceiling")
	t.expectEq(noneLow < 1e300, true)
	local _, poorLow = Honeycomb.badges(layout, view({ wallet = 0 }))
	t.expectEq(poorLow, -math.huge, "nothing buys: no floor")
end

function tests.elsewhere_is_an_open_items_first_link_bought_at_its_stand(t)
	local layout = Honeycomb.layout(Config)
	local gun = upgrade(layout, "waterGun")
	local locked = { state = "locked", owned = 0, total = 3 }
	t.expectEq(Honeycomb.elsewhere(gun.links[1], locked, view({})), true)
	t.expectEq(Honeycomb.elsewhere(gun.links[2], locked, view({})), false, "an upgrade is bought here")
	t.expectEq(Honeycomb.elsewhere(gun.links[1], { state = "short", owned = 0, total = 3 }, view({})), false)
	local unreachable = view({ reachable = function()
		return false
	end })
	t.expectEq(Honeycomb.elsewhere(gun.links[1], locked, unreachable), false)
	local hose = upgrade(layout, "gardenHose")
	t.expectEq(Honeycomb.elsewhere(hose.links[1], locked, view({})), false, "closed area")
	t.expectEq(Honeycomb.elsewhere(hose.links[1], locked, view({ openAreas = allOpen() })), true)
	t.expectEq(Honeycomb.elsewhere(layout.tool.links[1], locked, view({})), false, "a track")
	t.expectEq(Honeycomb.elsewhere(upgrade(layout, "gate:2").links[1], locked, view({})), false, "a gate")
end

function tests.last_buy_round_trips(t)
	local text = Honeycomb.encodeBuy("waterGun", 3, 1234.5)
	t.expectEq(text, "waterGun@3@1234.5")
	local buy = Honeycomb.decodeBuy(text) :: any
	t.expectEq(buy.id, "waterGun")
	t.expectEq(buy.level, 3)
	t.expectEq(buy.at, 1234.5)
	t.expectEq((Honeycomb.decodeBuy(Honeycomb.encodeBuy(Areas.gateId(2), 1, 5)) :: any).id, "gate:2", "a gate's buy")
	t.expectEq(Honeycomb.decodeBuy(nil), nil)
	t.expectEq(Honeycomb.decodeBuy(""), nil)
	t.expectEq(Honeycomb.decodeBuy("tool@x@1"), nil)
end

-- Every hex of a view, the centre first.
local function viewHexes(layout, viewId: string)
	local list = { { q = 0, r = 0 } }
	local cells = if viewId == "main" then layout.ring else layout.categories[viewId].slots
	for _, pos in cells do
		table.insert(list, { q = pos.q, r = pos.r })
	end
	return list
end

-- A 1366 x 768 screen's board (between the title and the close button, about 1366 x 540 px; hexes
-- 110 x 96 at zoom 1, SPACING apart): every view fits with hexes at least 80 px tall.
function tests.every_view_fits_a_small_laptop_with_big_hexes(t)
	local layout = Honeycomb.layout(Config)
	for _, viewId in { "main", table.unpack(CATEGORIES) } do
		local _, _, w, h = Honeycomb.bounds(viewHexes(layout, viewId), 55, Honeycomb.SPACING)
		local zoom, pans = Honeycomb.zoom(w, h, 1366, 540, 96, 64, 1.6)
		t.expectEq(pans, false, `{viewId} fits`)
		t.expectEq(zoom * 96 >= 80, true, `{viewId}: hexes {zoom * 96} px tall`)
	end
	t.expectEq(Honeycomb.SPACING > 1 and Honeycomb.SPACING <= 1.15, true, "a small even gap")
end

function tests.bounds_cover_every_hex(t)
	local cx, cy, w, h = Honeycomb.bounds({ { q = 0, r = 0 } }, 10)
	t.expectEq(cx, 0)
	t.expectEq(cy, 0)
	t.expectEq(w, 20)
	t.expectNear(h, 10 * math.sqrt(3), 1e-9)
	cx, cy, w, h = Honeycomb.bounds({ { q = 0, r = 0 }, { q = 2, r = 0 } }, 10)
	t.expectNear(cx, 15, 1e-9)
	t.expectNear(cy, 10 * math.sqrt(3) / 2, 1e-9)
	t.expectNear(w, 50, 1e-9)
	t.expectNear(h, 20 * math.sqrt(3), 1e-9)
	_, _, w, h = Honeycomb.bounds({ { q = 0, r = 0 }, { q = 2, r = 0 } }, 10, 1.1)
	t.expectNear(w, 30 * 1.1 + 20, 1e-9, "spaced centres, hexes their own size")
	t.expectNear(h, 10 * math.sqrt(3) * 1.1 + 10 * math.sqrt(3), 1e-9)
end

function tests.zoom_fits_the_board_and_pans_below_the_smallest_hex(t)
	local zoom, pans = Honeycomb.zoom(200, 100, 400, 400, 96, 64, 1.5)
	t.expectEq(zoom, 1.5, "a small view grows, up to the cap")
	t.expectEq(pans, false)
	zoom, pans = Honeycomb.zoom(500, 400, 400, 400, 96, 64, 1.5)
	t.expectNear(zoom, 0.8, 1e-9, "shrinks to fit")
	t.expectEq(pans, false)
	zoom, pans = Honeycomb.zoom(800, 400, 400, 400, 96, 64, 1.5)
	t.expectNear(zoom, 64 / 96, 1e-9, "never below the smallest hex")
	t.expectEq(pans, true)
end

function tests.find_names_the_view_and_upgrade_of_an_id(t)
	local layout = Honeycomb.layout(Config)
	local viewId, u = Honeycomb.find(layout, "tool")
	t.expectEq(viewId, "main")
	t.expectEq((u :: any).id, "tool")
	viewId, u = Honeycomb.find(layout, "quick")
	t.expectEq(viewId, "boosts")
	t.expectEq((u :: any).id, "quick")
	viewId, u = Honeycomb.find(layout, "bigTank")
	t.expectEq(viewId, "gear")
	t.expectEq((u :: any).id, "backpacks", "a backpack sits in the backpacks hex")
	t.expectEq((Honeycomb.find(layout, "pump")), "buildings")
	t.expectEq((Honeycomb.find(layout, "gate:3")), "areas")
	t.expectEq((Honeycomb.find(layout, "nope")), nil)
end

function tests.pick_selects_an_ids_hex_else_the_first_buy_else_short(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ wallet = 100 }))
	t.expectEq(Honeycomb.pick(layout, "boosts", s), "hold", "Pickup (192) is short, Hold (40) buys")
	t.expectEq(Honeycomb.pick(layout, "boosts", s, "tip"), "tip")
	s = Honeycomb.states(layout, "boosts", view({ wallet = 0 }))
	t.expectEq(Honeycomb.pick(layout, "boosts", s), "pickup", "nothing buys: the first short")
	local maxed = { pickup = 4, hold = 1, quick = 10, walk = 10, tip = 9 }
	s = Honeycomb.states(layout, "boosts", view({ levels = maxed, openAreas = allOpen() }))
	t.expectEq(Honeycomb.pick(layout, "boosts", s, "pickup"), "pickup", "a maxed id: still its hex")
	t.expectEq(Honeycomb.pick(layout, "boosts", s), nil, "nothing to buy or save for")
	s = Honeycomb.states(layout, "gear", view({}))
	t.expectEq(Honeycomb.pick(layout, "gear", s, "bigTank"), "backpacks")
end

function tests.owned_share_counts_levels(t)
	local layout = Honeycomb.layout(Config)
	local owned, total = Honeycomb.ownedShare(layout, "boosts", view({ levels = { pickup = 2, quick = 1 } }))
	t.expectEq(owned, 3)
	t.expectEq(total, 4 + 1 + 10 + 10 + 9)
	owned, total = Honeycomb.ownedShare(layout, "areas", view({ openAreas = { [1] = true, [2] = true } }))
	t.expectEq(owned, 1)
	t.expectEq(total, 4)
end

function tests.bought_is_what_the_buy_remote_compares(t)
	local layout = Honeycomb.layout(Config)
	local tool = layout.tool.links[1]
	t.expectEq(Honeycomb.bought(tool, view({ levels = { tool = 3 } })), 3)
	t.expectEq(Honeycomb.bought(tool, view({})), 0)
	local gun = upgrade(layout, "waterGun").links[2]
	t.expectEq(Honeycomb.bought(gun, view({})), -1, "not owned")
	t.expectEq(Honeycomb.bought(gun, view({ items = { waterGun = 1 } })), 0, "just bought")
	t.expectEq(Honeycomb.bought(gun, view({ items = { waterGun = 3 } })), 2)
	local gate = upgrade(layout, "gate:2").links[1]
	t.expectEq(Honeycomb.bought(gate, view({})), 0, "closed")
	t.expectEq(Honeycomb.bought(gate, view({ openAreas = { [1] = true, [2] = true } })), 1, "open")
end

function tests.link_is_the_next_level_else_the_last(t)
	local layout = Honeycomb.layout(Config)
	local pickup = upgrade(layout, "pickup")
	t.expectEq(Honeycomb.link(pickup, 0).level, 1)
	t.expectEq(Honeycomb.link(pickup, 2).level, 3)
	t.expectEq(Honeycomb.link(pickup, 4).level, 4, "maxed: the last")
end

function tests.level_text_reads_the_step_a_link_buys(t)
	local layout = Honeycomb.layout(Config)
	local tool = layout.tool
	t.expectEq(Honeycomb.levelText(tool.links[1], "buy"), "Buy")
	t.expectEq(Honeycomb.levelText(tool.links[3], "short"), "Lv 2 → Lv 3")
	t.expectEq(Honeycomb.levelText(tool.links[19], "max"), "MAX")
	t.expectEq(Honeycomb.levelText(upgrade(layout, "gate:2").links[1], "buy"), "")
	local gun = upgrade(layout, "waterGun")
	t.expectEq(Honeycomb.levelText(gun.links[1], "locked"), "Buy")
	t.expectEq(Honeycomb.levelText(gun.links[2], "short"), "Lv 1 → Lv 2")
end

function tests.enter_delay_grows_with_distance_and_caps(t)
	t.expectEq(Honeycomb.enterDelay(0, 0, 0.03, 0.1), 0)
	t.expectNear(Honeycomb.enterDelay(1, 0, 0.03, 0.1), 0.03, 1e-9)
	t.expectNear(Honeycomb.enterDelay(2, -1, 0.03, 0.1), 0.06, 1e-9)
	t.expectEq(Honeycomb.enterDelay(7, 0, 0.03, 0.1), 0.1)
end

function tests.step_goes_to_the_nearest_point_in_the_pushed_direction(t)
	local points = { { x = 0, y = 0 }, { x = 10, y = 0 }, { x = 10, y = -10 }, { x = 30, y = 0 }, { x = -10, y = 5 } }
	t.expectEq(Honeycomb.step(points, 1, 1, 0), 2, "right: the nearest, not the far one")
	t.expectEq(Honeycomb.step(points, 1, 0, -1), 3, "up: within 60 degrees")
	t.expectEq(Honeycomb.step(points, 1, -1, 0), 5, "left")
	t.expectEq(Honeycomb.step(points, 1, 0, 1), nil, "nothing below")
	t.expectEq(Honeycomb.step(points, 2, 1, 0), 4, "from another point")
	t.expectEq(Honeycomb.step(points, 3, 0, -1), nil, "past the edge")
end

return tests
