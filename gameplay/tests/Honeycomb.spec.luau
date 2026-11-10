local Honeycomb = require("../src/shared/Honeycomb")
local Config = require("../src/shared/Config")

local tests = {}

local CATEGORIES = { "tools", "boosts", "gear", "vehicles", "buildings", "staff" }

local function key(pos): string
	return `{pos.q},{pos.r}`
end

local function chain(layout, catId: string, id: string)
	for _, c in layout.categories[catId].chains do
		if c.id == id then
			return c
		end
	end
	error(`no chain {id} in {catId}`)
end

local function linkName(link): string
	return if link.kind == "gate" then `gate{link.areaId}` else `{link.id}:{link.level}`
end

local function costOf(link): number?
	if link.kind == "track" then
		return Config.track(link.id).levels[link.level].cost
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
	local main = Honeycomb.layout(Config).main
	t.expectEq(main.centre.id, "tool")
	t.expectEq(main.centre.q, 0)
	t.expectEq(main.centre.r, 0)
	t.expectEq(#main.ring, 6)
	local seen = {}
	for i, hex in main.ring do
		t.expectEq(hex.id, CATEGORIES[i], "ring order")
		t.expectEq(Honeycomb.distance(0, 0, hex.q, hex.r), 1, "ring touches the centre")
		t.expectEq(seen[key(hex)], nil, "ring hexes distinct")
		seen[key(hex)] = true
	end
end

function tests.no_overlaps_in_any_category(t)
	local layout = Honeycomb.layout(Config)
	for _, catId in CATEGORIES do
		local cat = layout.categories[catId]
		t.expectEq(cat.hex.q, 0)
		t.expectEq(cat.hex.r, 0)
		local used = { [key(cat.hex)] = "category" }
		local function take(pos, what)
			if used[key(pos)] then
				error(`{catId}: {what} overlaps {used[key(pos)]} at {key(pos)}`)
			end
			used[key(pos)] = what
		end
		for i, pos in cat.spine do
			take(pos, `spine {i}`)
		end
		for _, c in cat.chains do
			t.expectEq(#c.slots, math.min(#c.links, Honeycomb.MAX_VISIBLE), `{c.id} slot count`)
			for i, pos in c.slots do
				take(pos, `{c.id} slot {i}`)
			end
		end
	end
end

function tests.chains_are_connected_by_bridges_between_neighbours(t)
	local layout = Honeycomb.layout(Config)
	for _, catId in CATEGORIES do
		local cat = layout.categories[catId]
		local reached = { [key(cat.hex)] = true }
		for _, bridge in cat.bridges do
			t.expectEq(Honeycomb.distance(bridge[1].q, bridge[1].r, bridge[2].q, bridge[2].r), 1, `{catId} spine bridge`)
			t.expectEq(reached[key(bridge[1])], true, `{catId} spine grows from the category`)
			reached[key(bridge[2])] = true
		end
		for _, pos in cat.spine do
			t.expectEq(reached[key(pos)], true, `{catId} spine hex {key(pos)} joined`)
		end
		for _, c in cat.chains do
			t.expectEq(#c.bridges, #c.slots, `{c.id} one bridge per slot`)
			t.expectEq(reached[key(c.bridges[1][1])], true, `{c.id} starts at the category or the spine`)
			for i, bridge in c.bridges do
				t.expectEq(key(bridge[2]), key(c.slots[i]), `{c.id} bridge {i} ends at slot {i}`)
				if i > 1 then
					t.expectEq(key(bridge[1]), key(c.slots[i - 1]), `{c.id} bridge {i} starts at slot {i - 1}`)
				end
				t.expectEq(Honeycomb.distance(bridge[1].q, bridge[1].r, bridge[2].q, bridge[2].r), 1, `{c.id} bridge {i} joins neighbours`)
			end
		end
	end
end

function tests.every_track_level_and_item_level_appears_once(t)
	local layout = Honeycomb.layout(Config)
	local count = {}
	local total = 0
	for _, catId in CATEGORIES do
		for _, c in layout.categories[catId].chains do
			for _, link in c.links do
				if link.kind ~= "gate" then
					local k = `{link.kind}:{link.id}:{link.level}`
					count[k] = (count[k] or 0) + 1
					total += 1
				end
			end
		end
	end
	local expected = 0
	for _, track in Config.tracks do
		for level in track.levels do
			t.expectEq(count[`track:{track.id}:{level}`], 1, `track {track.id} level {level}`)
			expected += 1
		end
	end
	for _, item in Config.items do
		for level = 1, #item.levels + 1 do
			t.expectEq(count[`item:{item.id}:{level}`], 1, `item {item.id} link {level}`)
			expected += 1
		end
	end
	t.expectEq(total, expected, "nothing extra")
end

function tests.chains_land_in_their_categories(t)
	local layout = Honeycomb.layout(Config)
	local function ids(catId)
		local list = {}
		for _, c in layout.categories[catId].chains do
			table.insert(list, c.id)
		end
		return table.concat(list, ",")
	end
	t.expectEq(ids("tools"), "tool")
	t.expectEq(ids("boosts"), "pickup,hold,quick,walk,tip")
	t.expectEq(ids("gear"), "backpacks,waterGun,gardenHose,heatGloves,icePick,jetpackTank,cloudNet")
	t.expectEq(ids("vehicles"), "fireTruck,tanker,snowcatTanker,waterBomber")
	t.expectEq(ids("buildings"), "pump,waterTower,pipeline,rainMachine")
	t.expectEq(ids("staff"), "helper,lifeguard,firefighter,plumber")
end

function tests.gates_sit_before_the_first_link_of_a_later_area(t)
	local layout = Honeycomb.layout(Config)
	local function names(c)
		local list = {}
		for _, link in c.links do
			table.insert(list, linkName(link))
		end
		return table.concat(list, ",")
	end
	t.expectEq(names(chain(layout, "boosts", "pickup")), "pickup:1,gate2,pickup:2,pickup:3,gate3,pickup:4")
	t.expectEq(names(chain(layout, "boosts", "hold")), "hold:1")
	t.expectEq(names(chain(layout, "gear", "waterGun")), "waterGun:1,waterGun:2,waterGun:3", "an area-1 item has no gate")
	t.expectEq(names(chain(layout, "gear", "gardenHose")), "gate2,gardenHose:1,gardenHose:2,gardenHose:3")
	t.expectEq(names(chain(layout, "staff", "plumber")), "gate5,plumber:1,plumber:2,plumber:3")
	t.expectEq(
		names(chain(layout, "gear", "backpacks")),
		"backpackTank:1,backpackTank:2,backpackTank:3,gate2,bigTank:1,bigTank:2,bigTank:3,gate3,twinTanks:1,twinTanks:2,twinTanks:3,gate4,insulatedTank:1,insulatedTank:2,insulatedTank:3,gate5,cloudBag:1,cloudBag:2,cloudBag:3"
	)
	local tool = chain(layout, "tools", "tool")
	t.expectEq(#tool.links, 21)
	t.expectEq(linkName(tool.links[4]), "tool:4")
	t.expectEq(linkName(tool.links[5]), "gate2")
	t.expectEq(linkName(tool.links[6]), "tool:5")
	t.expectEq(linkName(tool.links[11]), "gate3")
	t.expectEq(linkName(tool.links[12]), "tool:10")
	t.expectEq(linkName(tool.links[21]), "tool:19")
end

function tests.window_keeps_last_owned_next_and_max(t)
	local layout = Honeycomb.layout(Config)
	local tool = chain(layout, "tools", "tool")
	local function shown(owned, max)
		return table.concat(Honeycomb.window(tool, owned, max), ",")
	end
	t.expectEq(shown(0), "1,2,3,4,5,6,21", "start: the first links and the max end")
	t.expectEq(shown(4), "4,5,6,7,8,9,21", "last owned, the gate, next, following, max")
	t.expectEq(shown(18), "15,16,17,18,19,20,21", "near the end it runs into the max")
	t.expectEq(shown(19), "15,16,17,18,19,20,21", "all owned")
	t.expectEq(shown(9, 4), "10,11,12,21", "a smaller window still keeps last owned, next and max")
	local short = chain(layout, "boosts", "pickup")
	t.expectEq(table.concat(Honeycomb.window(short, 2), ","), "1,2,3,4,5,6", "a short chain shows everything")
	for owned = 0, 19 do
		local list = Honeycomb.window(tool, owned)
		t.expectEq(#list, Honeycomb.MAX_VISIBLE)
		t.expectEq(list[#list], 21, "max end shown")
		for i = 2, #list do
			if list[i] <= list[i - 1] then
				error(`window {owned} not increasing`)
			end
		end
	end
end

function tests.moves_say_which_old_slot_each_shown_link_came_from(t)
	local moves = Honeycomb.moves({ 1, 2, 3, 4, 5, 6, 21 }, { 2, 3, 4, 5, 6, 7, 21 })
	t.expectEq(moves[1], 2)
	t.expectEq(moves[5], 6)
	t.expectEq(moves[6], nil, "a link new to the window")
	t.expectEq(moves[7], 7, "the max end stays")
	moves = Honeycomb.moves({ 4, 5, 6, 7, 8, 9, 21 }, { 6, 7, 8, 9, 10, 11, 21 })
	t.expectEq(moves[1], 3, "a gate passed: two slots")
	t.expectEq(moves[5], nil)
end

function tests.owned_count_counts_links_up_to_the_furthest_owned(t)
	local layout = Honeycomb.layout(Config)
	t.expectEq(Honeycomb.ownedCount(chain(layout, "tools", "tool"), view({ levels = { tool = 7 } })), 7)
	local backpacks = chain(layout, "gear", "backpacks")
	t.expectEq(Honeycomb.ownedCount(backpacks, view({})), 0)
	t.expectEq(Honeycomb.ownedCount(backpacks, view({ items = { backpackTank = 2 } })), 2)
	t.expectEq(Honeycomb.ownedCount(backpacks, view({ items = { backpackTank = 1, bigTank = 1 } })), 4, "a bigger pack passes the earlier links")
end

function tests.states_owned_gate_closed_and_locked(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ levels = { pickup = 1 }, wallet = 1e12 }))
	t.expectEq(s["track:pickup:1"].state, "owned")
	t.expectEq(s["gate:pickup:2"].state, "gateClosed")
	t.expectEq(s["track:pickup:2"].state, "locked", "the next link behind a closed gate")
	t.expectEq(s["track:pickup:3"].state, "locked")
	t.expectEq(s["gate:pickup:3"].state, "gateClosed")
	t.expectEq(s["track:pickup:4"].state, "locked")
end

function tests.states_next_affordable_is_buy_then_future(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ levels = { pickup = 1 }, openAreas = { [1] = true, [2] = true }, wallet = 20000 }))
	t.expectEq(s["gate:pickup:2"].state, "gateOpen")
	t.expectEq(s["track:pickup:2"].state, "buy")
	t.expectEq(s["track:pickup:2"].price, 14062)
	t.expectEq(s["track:pickup:3"].state, "future", "only the next link can be bought")
	t.expectEq(s["gate:pickup:3"].state, "gateClosed")
	t.expectEq(s["track:pickup:4"].state, "locked")
	s = Honeycomb.states(layout, "boosts", view({ wallet = 39.9999999 }))
	t.expectEq(s["track:hold:1"].state, "buy", "fractional coins still buy")
end

function tests.states_next_short_shows_progress(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ levels = { pickup = 1 }, openAreas = { [1] = true, [2] = true }, wallet = 7031 }))
	t.expectEq(s["track:pickup:2"].state, "short")
	t.expectEq(s["track:pickup:2"].price, 14062)
	t.expectNear(s["track:pickup:2"].progress, 0.5, 1e-9)
	s = Honeycomb.states(layout, "boosts", view({ wallet = -5 }))
	t.expectEq(s["track:hold:1"].state, "short")
	t.expectEq(s["track:hold:1"].progress, 0, "progress clamps at 0")
end

function tests.states_last_owned_link_is_max(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ levels = { pickup = 4, hold = 1 }, openAreas = allOpen() }))
	t.expectEq(s["track:pickup:3"].state, "owned")
	t.expectEq(s["track:pickup:4"].state, "max")
	t.expectEq(s["track:hold:1"].state, "max")
	t.expectEq(s["gate:pickup:3"].state, "gateOpen")
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
	t.expectEq(s["item:cloudNet:1"].state, "locked", "unreachable")
	t.expectEq(s["item:cloudNet:2"].state, "locked")
	t.expectEq(s["item:icePick:1"].state, "buy")
	t.expectEq(s["item:icePick:2"].state, "future")
	s = Honeycomb.states(layout, "gear", view({
		openAreas = allOpen(),
		wallet = 1e12,
		price = function(link)
			return if link.id == "waterGun" then nil else costOf(link)
		end,
	}))
	t.expectEq(s["item:waterGun:1"].state, "locked", "no price: can't be bought here")
	t.expectEq(s["item:waterGun:2"].state, "future")
end

function tests.states_a_bigger_backpack_passes_the_earlier_links(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "gear", view({ items = { backpackTank = 1, bigTank = 1 }, openAreas = { [1] = true, [2] = true }, wallet = 1e12 }))
	t.expectEq(s["item:backpackTank:2"].state, "owned")
	t.expectEq(s["item:backpackTank:3"].state, "owned")
	t.expectEq(s["item:bigTank:1"].state, "owned")
	t.expectEq(s["item:bigTank:2"].state, "buy")
	t.expectEq(s["item:bigTank:3"].state, "future")
	t.expectEq(s["gate:backpacks:3"].state, "gateClosed")
	t.expectEq(s["item:twinTanks:1"].state, "locked")
end

function tests.at_most_one_buy_or_short_per_chain(t)
	local layout = Honeycomb.layout(Config)
	for _, wallet in { 0, 1e12 } do
		local v = view({ openAreas = allOpen(), wallet = wallet, levels = { tool = 3 }, items = { helper = 2 } })
		for _, catId in CATEGORIES do
			local s = Honeycomb.states(layout, catId, v)
			for _, c in layout.categories[catId].chains do
				local next = 0
				for _, link in c.links do
					local state = s[link.key].state
					if state == "buy" or state == "short" then
						next += 1
					end
				end
				t.expectEq(next, 1, `{c.id} has exactly one next link`)
			end
		end
	end
end

function tests.badges_count_buy_hexes(t)
	local layout = Honeycomb.layout(Config)
	local rich = Honeycomb.badges(layout, view({ openAreas = allOpen(), wallet = 1e12 }))
	local sum = 0
	for _, catId in CATEGORIES do
		t.expectEq(rich[catId], #layout.categories[catId].chains, `{catId}: every chain's first link`)
		sum += rich[catId]
	end
	t.expectEq(rich.total, sum)
	local poor = Honeycomb.badges(layout, view({ wallet = 0 }))
	t.expectEq(poor.total, 0)
	t.expectEq(poor.boosts, 0)
	local start = Honeycomb.badges(layout, view({ wallet = 100 }))
	t.expectEq(start.tools, 1, "Cup (20)")
	t.expectEq(start.boosts, 3, "Hold (40), Quick (35), Sneakers (69), not Pickup (192) or Tip (300)")
	t.expectEq(start.gear, 0)
	t.expectEq(start.total, 4)
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
	local gun = chain(layout, "gear", "waterGun")
	local locked = { state = "locked" }
	t.expectEq(Honeycomb.elsewhere(gun.links[1], locked, view({})), true)
	t.expectEq(Honeycomb.elsewhere(gun.links[2], locked, view({})), false, "an upgrade is bought here")
	t.expectEq(Honeycomb.elsewhere(gun.links[1], { state = "future" }, view({})), false)
	local unreachable = view({ reachable = function()
		return false
	end })
	t.expectEq(Honeycomb.elsewhere(gun.links[1], locked, unreachable), false)
	local hose = chain(layout, "gear", "gardenHose")
	t.expectEq(hose.links[2].level, 1, "after its area's gate")
	t.expectEq(Honeycomb.elsewhere(hose.links[2], locked, view({})), false, "closed area")
	t.expectEq(Honeycomb.elsewhere(hose.links[2], locked, view({ openAreas = allOpen() })), true)
	t.expectEq(Honeycomb.elsewhere(chain(layout, "tools", "tool").links[1], locked, view({})), false, "a track")
end

function tests.model_keys_keep_few_models_per_chain(t)
	local layout = Honeycomb.layout(Config)
	local function keys(catId, id, v)
		local list = {}
		for key in Honeycomb.modelKeys(chain(layout, catId, id), Honeycomb.states(layout, catId, v)) do
			table.insert(list, key)
		end
		table.sort(list)
		return table.concat(list, ",")
	end
	local tool = chain(layout, "tools", "tool")
	local maxKey = tool.links[#tool.links].key
	t.expectEq(keys("tools", "tool", view({ levels = { tool = 4 } })), `{maxKey},track:tool:4,track:tool:5`, "last owned, next, max")
	t.expectEq(keys("tools", "tool", view({})), `track:tool:1,{maxKey}`, "none owned: next and max")
	t.expectEq(keys("gear", "waterGun", view({})), "item:waterGun:1", "one model per item: its next link")
	t.expectEq(keys("gear", "waterGun", view({ items = { waterGun = 1 } })), "item:waterGun:2")
	local gun = chain(layout, "gear", "waterGun")
	t.expectEq(keys("gear", "waterGun", view({ items = { waterGun = #gun.links } })), gun.links[#gun.links].key, "maxed: its last link")
	t.expectEq(keys("gear", "backpacks", view({ items = { backpackTank = 2 } })) ~= "", true)
	for _, catId in CATEGORIES do
		local v = view({ levels = { tool = 4 }, items = { backpackTank = 2 } })
		local s = Honeycomb.states(layout, catId, v)
		local n = 1 -- the category hex
		for _, c in layout.categories[catId].chains do
			for _ in Honeycomb.modelKeys(c, s) do
				n += 1
			end
		end
		t.expectEq(n <= 12, true, `{catId}: {n} models at most 12`)
	end
end

function tests.last_buy_round_trips(t)
	local text = Honeycomb.encodeBuy("waterGun", 3, 1234.5)
	t.expectEq(text, "waterGun@3@1234.5")
	local buy = Honeycomb.decodeBuy(text) :: any
	t.expectEq(buy.id, "waterGun")
	t.expectEq(buy.level, 3)
	t.expectEq(buy.at, 1234.5)
	t.expectEq(Honeycomb.decodeBuy(nil), nil)
	t.expectEq(Honeycomb.decodeBuy(""), nil)
	t.expectEq(Honeycomb.decodeBuy("tool@x@1"), nil)
end

function tests.every_category_fits_11_columns_by_7_rows(t)
	local layout = Honeycomb.layout(Config)
	for _, catId in CATEGORIES do
		local cat = layout.categories[catId]
		local minC, maxC, minR, maxR = math.huge, -math.huge, math.huge, -math.huge
		local function grow(pos)
			-- flat-top offset rows: odd columns sit half a hex lower
			local row = pos.r + (pos.q - pos.q % 2) / 2
			minC, maxC = math.min(minC, pos.q), math.max(maxC, pos.q)
			minR, maxR = math.min(minR, row), math.max(maxR, row)
		end
		grow(cat.hex)
		for _, pos in cat.spine do
			grow(pos)
		end
		for _, c in cat.chains do
			for _, pos in c.slots do
				grow(pos)
			end
		end
		if maxC - minC + 1 > 11 or maxR - minR + 1 > 7 then
			error(`{catId} is {maxC - minC + 1} x {maxR - minR + 1}`)
		end
	end
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

function tests.clamp_pan_keeps_the_content_over_the_board(t)
	local x, y = Honeycomb.clampPan(100, -100, 300, 300, 400, 400)
	t.expectEq(x, 0, "content smaller than the board: no pan")
	t.expectEq(y, 0)
	x, y = Honeycomb.clampPan(150, -100, 600, 500, 400, 400)
	t.expectEq(x, 100)
	t.expectEq(y, -50)
	x, y = Honeycomb.clampPan(-20, 20, 600, 500, 400, 400)
	t.expectEq(x, -20)
	t.expectEq(y, 20)
end

function tests.find_names_the_category_and_chain_of_an_id(t)
	local layout = Honeycomb.layout(Config)
	local catId, c = Honeycomb.find(layout, "tool")
	t.expectEq(catId, "tools")
	t.expectEq((c :: any).id, "tool")
	catId, c = Honeycomb.find(layout, "quick")
	t.expectEq(catId, "boosts")
	t.expectEq((c :: any).id, "quick")
	catId, c = Honeycomb.find(layout, "bigTank")
	t.expectEq(catId, "gear")
	t.expectEq((c :: any).id, "backpacks", "a backpack's links sit in the backpacks chain")
	t.expectEq((Honeycomb.find(layout, "pump")), "buildings")
	t.expectEq((Honeycomb.find(layout, "nope")), nil)
end

function tests.pick_selects_an_ids_next_link_else_the_first_buy_else_short(t)
	local layout = Honeycomb.layout(Config)
	local s = Honeycomb.states(layout, "boosts", view({ wallet = 100 }))
	t.expectEq(Honeycomb.pick(layout, "boosts", s), "track:hold:1", "Pickup (192) is short, Hold (40) buys")
	t.expectEq(Honeycomb.pick(layout, "boosts", s, "tip"), "track:tip:1")
	s = Honeycomb.states(layout, "boosts", view({ wallet = 0 }))
	t.expectEq(Honeycomb.pick(layout, "boosts", s), "track:pickup:1", "nothing buys: the first short")
	local maxed = { pickup = 4, hold = 1, quick = 7, walk = 7, tip = 4 }
	s = Honeycomb.states(layout, "boosts", view({ levels = maxed, openAreas = allOpen() }))
	t.expectEq(Honeycomb.pick(layout, "boosts", s, "pickup"), "track:pickup:4", "a maxed id: its max end")
	t.expectEq(Honeycomb.pick(layout, "boosts", s), nil, "nothing to buy or save for")
end

function tests.owned_share_counts_links_not_gates(t)
	local layout = Honeycomb.layout(Config)
	local owned, total = Honeycomb.ownedShare(layout, "boosts", view({ levels = { pickup = 2, quick = 1 } }))
	t.expectEq(owned, 3)
	t.expectEq(total, 4 + 1 + 7 + 7 + 4)
end

function tests.bought_is_what_the_buy_remote_compares(t)
	local layout = Honeycomb.layout(Config)
	local tool = chain(layout, "tools", "tool").links[1]
	t.expectEq(Honeycomb.bought(tool, view({ levels = { tool = 3 } })), 3)
	t.expectEq(Honeycomb.bought(tool, view({})), 0)
	local gun = chain(layout, "gear", "waterGun").links[2]
	t.expectEq(Honeycomb.bought(gun, view({})), -1, "not owned")
	t.expectEq(Honeycomb.bought(gun, view({ items = { waterGun = 1 } })), 0, "just bought")
	t.expectEq(Honeycomb.bought(gun, view({ items = { waterGun = 3 } })), 2)
end

function tests.level_text_reads_the_step_a_link_buys(t)
	local layout = Honeycomb.layout(Config)
	local tool = chain(layout, "tools", "tool")
	t.expectEq(Honeycomb.levelText(tool.links[1], "buy"), "Buy")
	t.expectEq(Honeycomb.levelText(tool.links[3], "short"), "Lv 2 → Lv 3")
	t.expectEq(Honeycomb.levelText(tool.links[3], "owned"), "Lv 3")
	t.expectEq(Honeycomb.levelText(tool.links[21], "max"), "MAX")
	t.expectEq(Honeycomb.levelText(tool.links[5], "gateClosed"), "")
	local gun = chain(layout, "gear", "waterGun")
	t.expectEq(Honeycomb.levelText(gun.links[1], "locked"), "Buy")
	t.expectEq(Honeycomb.levelText(gun.links[2], "future"), "Lv 1 → Lv 2")
end

function tests.enter_delay_grows_with_distance_and_caps(t)
	t.expectEq(Honeycomb.enterDelay(0, 0, 0.03, 0.1), 0)
	t.expectNear(Honeycomb.enterDelay(1, 0, 0.03, 0.1), 0.03, 1e-9)
	t.expectNear(Honeycomb.enterDelay(2, -1, 0.03, 0.1), 0.06, 1e-9)
	t.expectEq(Honeycomb.enterDelay(7, 0, 0.03, 0.1), 0.1)
end

return tests
