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

return tests
