--!strict
-- The shop's honeycomb (library ui/screens/shop.md): where every hex sits and what state it is in.
-- Pure: config is passed in, so Lune tests and Roblox load it the same way. Hexes are flat-top, in
-- axial coordinates (q, r); q is the column, r runs down it.
--
-- Category view arrangement: the category hex at (0, 0), a spine of hexes straight up and down
-- column 0 from it, and each chain as a row running right from the spine, one link per column
-- (columns 1..MAX_VISIBLE), in config order top to bottom. In flat-top "offset rows" (odd columns
-- half a hex lower) a row of hexes is a chain of neighbours, and column 0's hex in a row touches
-- column 1's hex in the same row, so each chain hangs off the spine hex beside it. Rows are spread
-- two apart (a free row between chains) when that still fits 7 rows, else packed: at most
-- 1 + MAX_VISIBLE columns by 7 rows. Longer chains show a window of their links (Honeycomb.window):
-- the i-th shown link sits in the chain's slot i.

export type Pos = { q: number, r: number }
export type Bridge = { Pos } -- two neighbouring hexes, from (nearer the category) and to
-- A link of a chain: a track level, an item link (level 1 = the buy, then its upgrades) or an area
-- gate. `key` names its hex in Honeycomb.states.
export type Link = {
	key: string,
	kind: "track" | "item" | "gate",
	id: string?, -- track or item id
	level: number?,
	areaId: number, -- the area that opens it (a gate: the area it opens)
}
export type Chain = {
	id: string, -- track id, item id, or "backpacks" (every backpack, each the next link)
	links: { Link },
	slots: { Pos }, -- min(#links, MAX_VISIBLE) places, left to right
	bridges: { Bridge }, -- bridges[i] leads into slots[i]; bridges[1] from the spine or the category
}
export type Category = {
	id: string,
	hex: Pos, -- (0, 0)
	spine: { Pos },
	bridges: { Bridge }, -- the spine's, outward from the category
	chains: { Chain },
}
export type Layout = {
	main: { centre: { id: string, q: number, r: number }, ring: { { id: string, q: number, r: number } } },
	order: { string },
	categories: { [string]: Category },
}
export type StateName = "owned" | "buy" | "short" | "future" | "locked" | "max" | "gateOpen" | "gateClosed"
-- price: buy and short; progress (wallet / price, 0..1): short only.
export type HexState = { state: StateName, price: number?, progress: number? }
-- levels: track id -> levels owned. items: item id -> links owned (0 / nil none, 1 bought, 1 + n
-- with n upgrades). price: the final price of a link now, nil when it can't be bought here.
export type View = {
	levels: { [string]: number },
	items: { [string]: number },
	openAreas: { [number]: boolean },
	wallet: number,
	price: (Link) -> number?,
	reachable: (string) -> boolean,
}

local SQRT3 = math.sqrt(3)
local MONEY_EPSILON = 1e-6 -- as Items.affords: fractional coins from pours still buy
local ROWS = 7
-- Flat-top neighbour steps, clockwise from straight up.
local STEPS = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 0, 1 }, { -1, 1 }, { -1, 0 } }
local CATEGORIES = { "tools", "boosts", "gear", "vehicles", "buildings", "staff" }

local Honeycomb = {}

Honeycomb.MAX_VISIBLE = 7

function Honeycomb.toPixel(q: number, r: number, size: number): (number, number)
	return size * 1.5 * q, size * SQRT3 * (r + q / 2)
end

-- Clockwise from straight up.
function Honeycomb.neighbours(q: number, r: number): { Pos }
	local list = {}
	for _, step in STEPS do
		table.insert(list, { q = q + step[1], r = r + step[2] })
	end
	return list
end

function Honeycomb.distance(q1: number, r1: number, q2: number, r2: number): number
	local dq, dr = q2 - q1, r2 - r1
	return (math.abs(dq) + math.abs(dr) + math.abs(dq + dr)) / 2
end

-- The hex in column `col`, offset row `row` (odd columns half a hex lower).
local function at(col: number, row: number): Pos
	return { q = col, r = row - (col - col % 2) / 2 }
end

-- Links from `entries` ({ kind, id, level, areaId }), with a gate before each one from a later
-- area than the one before it (the first is measured against the cove).
local function makeChain(id: string, entries): Chain
	local links = {}
	local area = 1
	for _, entry in entries do
		if entry.areaId > area then
			table.insert(links, { key = `gate:{id}:{entry.areaId}`, kind = "gate", areaId = entry.areaId })
		end
		area = math.max(area, entry.areaId)
		entry.key = `{entry.kind}:{entry.id}:{entry.level}`
		table.insert(links, entry)
	end
	return { id = id, links = links, slots = {}, bridges = {} }
end

local function trackChain(track): Chain
	local entries = {}
	for level, data in track.levels do
		table.insert(entries, { kind = "track", id = track.id, level = level, areaId = data.area })
	end
	return makeChain(track.id, entries)
end

local function itemEntries(item, entries)
	for level = 1, #item.levels + 1 do
		table.insert(entries, { kind = "item", id = item.id, level = level, areaId = item.area })
	end
	return entries
end

local function itemChains(config, kind: string, chains: { Chain })
	for _, item in config.items do
		if item.kind == kind then
			table.insert(chains, makeChain(item.id, itemEntries(item, {})))
		end
	end
	return chains
end

-- A category's chains, from config only (a new track or item needs no layout change).
local function chainsOf(config, catId: string): { Chain }
	local chains = {}
	if catId == "tools" or catId == "boosts" then
		for _, track in config.tracks do
			if (track.id == "tool") == (catId == "tools") then
				table.insert(chains, trackChain(track))
			end
		end
	elseif catId == "gear" then
		local packs = {}
		for _, item in config.items do
			if item.kind == "backpack" then
				itemEntries(item, packs)
			end
		end
		table.insert(chains, makeChain("backpacks", packs))
		itemChains(config, "gadget", chains)
	else
		itemChains(config, ({ vehicles = "vehicle", buildings = "building", staff = "staff" })[catId], chains)
	end
	return chains
end

local function place(catId: string, chains: { Chain }): Category
	local count = #chains
	assert(count <= ROWS, `honeycomb: {catId} has {count} chains, more than {ROWS} rows`)
	local gap = if count > 1 then math.min(2, (ROWS - 1) // (count - 1)) else 0
	local top = -((count - 1) * gap) // 2
	local cat: Category = { id = catId, hex = at(0, 0), spine = {}, bridges = {}, chains = chains }
	local lowest, highest = 0, 0
	for i, chain in chains do
		local row = top + (i - 1) * gap
		lowest, highest = math.min(lowest, row), math.max(highest, row)
		local from = at(0, row)
		for col = 1, math.min(#chain.links, Honeycomb.MAX_VISIBLE) do
			local pos = at(col, row)
			table.insert(chain.slots, pos)
			table.insert(chain.bridges, { from, pos })
			from = pos
		end
	end
	for _, dir in { -1, 1 } do
		local from = cat.hex
		for row = dir, if dir < 0 then lowest else highest, dir do
			local pos = at(0, row)
			table.insert(cat.spine, pos)
			table.insert(cat.bridges, { from, pos })
			from = pos
		end
	end
	return cat
end

function Honeycomb.layout(config): Layout
	local layout: Layout = { main = { centre = { id = "tool", q = 0, r = 0 }, ring = {} }, order = CATEGORIES, categories = {} }
	for i, catId in CATEGORIES do
		table.insert(layout.main.ring, { id = catId, q = STEPS[i][1], r = STEPS[i][2] })
		layout.categories[catId] = place(catId, chainsOf(config, catId))
	end
	return layout
end

local function linkOwned(view: View, link: Link): boolean
	if link.kind == "track" then
		return (view.levels[link.id :: string] or 0) >= (link.level :: number)
	elseif link.kind == "item" then
		return (view.items[link.id :: string] or 0) >= (link.level :: number)
	end
	return false
end

-- Index of the furthest owned link (0 for none): links before it count as owned too (a bigger
-- backpack passes the earlier ones' upgrades).
local function furthest(chain: Chain, view: View): number
	local last = 0
	for i, link in chain.links do
		if linkOwned(view, link) then
			last = i
		end
	end
	return last
end

-- How many of the chain's links (gates not counted) are owned, for Honeycomb.window.
function Honeycomb.ownedCount(chain: Chain, view: View): number
	local count = 0
	for i = 1, furthest(chain, view) do
		if chain.links[i].kind ~= "gate" then
			count += 1
		end
	end
	return count
end

-- Which link indices to show, in order (the i-th sits in chain.slots[i]): all of a short chain;
-- else from the last owned link (so its gate and the next link follow) onward, ending with the
-- chain's last link, the max end.
function Honeycomb.window(chain: Chain, ownedCount: number, maxVisible: number?): { number }
	local visible = maxVisible or Honeycomb.MAX_VISIBLE
	local n = #chain.links
	local shown = {}
	if n <= visible then
		for i = 1, n do
			table.insert(shown, i)
		end
		return shown
	end
	local lastOwned, seen = 0, 0
	for i, link in chain.links do
		if seen == ownedCount then
			break
		elseif link.kind ~= "gate" then
			seen += 1
			lastOwned = i
		end
	end
	local start = math.min(math.max(1, lastOwned), n - visible + 1)
	for i = start, start + visible - 2 do
		table.insert(shown, i)
	end
	table.insert(shown, n)
	return shown
end

local function chainStates(chain: Chain, view: View, out: { [string]: HexState })
	local ownedTo = furthest(chain, view)
	local blocked, nextSeen = false, false
	for i, link in chain.links do
		local state: HexState
		if link.kind == "gate" then
			local open = view.openAreas[link.areaId] == true
			blocked = blocked or (not open and i > ownedTo)
			state = { state = if open then "gateOpen" else "gateClosed" }
		elseif i <= ownedTo then
			state = { state = if i == #chain.links then "max" else "owned" }
		else
			local first = not nextSeen
			nextSeen = true
			local price = if first then view.price(link) else nil
			local shut = blocked or not view.openAreas[link.areaId] or (link.kind == "item" and not view.reachable(link.id :: string))
			if shut or (first and not price) then
				state = { state = "locked" }
			elseif not first or not price then
				state = { state = "future" }
			elseif view.wallet + MONEY_EPSILON >= price then
				state = { state = "buy", price = price }
			else
				state = { state = "short", price = price, progress = math.clamp(view.wallet / price, 0, 1) }
			end
		end
		out[link.key] = state
	end
end

-- Every link's state in category `catId` (all links, shown or not), by Link.key. Only a chain's
-- first link not owned can be "buy" or "short"; links past a closed gate, in a closed area, of an
-- unreachable item or without a price are "locked".
function Honeycomb.states(layout: Layout, catId: string, view: View): { [string]: HexState }
	local out = {}
	for _, chain in layout.categories[catId].chains do
		chainStates(chain, view, out)
	end
	return out
end

-- The red balls: "buy" hexes per category id, and `total`.
function Honeycomb.badges(layout: Layout, view: View): { [string]: number }
	local counts = { total = 0 }
	for _, catId in layout.order do
		local n = 0
		for _, state in Honeycomb.states(layout, catId, view) do
			if state.state == "buy" then
				n += 1
			end
		end
		counts[catId] = n
		counts.total += n
	end
	return counts
end

return Honeycomb
