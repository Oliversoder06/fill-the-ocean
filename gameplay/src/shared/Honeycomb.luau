--!strict
-- The shop's honeycomb (library ui/screens/shop.md): where every hex sits and what state it is in.
-- Pure: config is passed in, so Lune tests and Roblox load it the same way. Hexes are flat-top, in
-- axial coordinates (q, r); q is the column, r runs down it.
--
-- One hex per upgrade: a track, an item, the backpacks (every pack, each the next level) or an
-- area's gate; a click buys its next level. The main view: the tool at (0, 0) and a ring of
-- categories. A category view: its Back hex at (0, 0) and its upgrades, earlier areas first, in
-- Honeycomb.ringSlots, SPACING apart so a small even gap shows between them.

export type Pos = { q: number, r: number }
-- A level an upgrade's hex sells: a track level, an item link (level 1 = the buy, then its
-- upgrades) or a gate (level 1 opens it; id "gate:<areaId>", common/Areas.gateId).
export type Link = { kind: "track" | "item" | "gate", id: string, level: number, areaId: number }
export type Upgrade = {
	id: string, -- track id, item id, "backpacks" or the gate's id
	kind: "track" | "item" | "backpacks" | "gate",
	areaId: number, -- its first level's area
	links: { Link },
}
export type Category = { id: string, upgrades: { Upgrade }, slots: { Pos } }
export type Layout = {
	tool: Upgrade, -- the main view's centre
	ring: { { id: string, q: number, r: number } },
	order: { string },
	categories: { [string]: Category },
}
export type StateName = "buy" | "short" | "max" | "locked"
-- owned of total levels; price: buy and short; progress (wallet / price, 0..1): short only.
export type HexState = { state: StateName, owned: number, total: number, price: number?, progress: number? }
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
-- Flat-top neighbour steps, clockwise from straight up.
local STEPS = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 0, 1 }, { -1, 1 }, { -1, 0 } }
local STEP_CONE = 0.5 -- cos 60 degrees: how far off its direction a gamepad step may land
local CATEGORIES = { "boosts", "gear", "vehicles", "buildings", "staff", "areas" }
local ITEM_KINDS = { vehicles = "vehicle", buildings = "building", staff = "staff" }
-- Rings 1 and 2: the cells on the vertical axis (top, bottom), then mirror pairs (left, right),
-- the widest first.
local RINGS = {
	{ axis = { { 0, -1 }, { 0, 1 } }, pairs = { { { -1, 0 }, { 1, -1 } }, { { -1, 1 }, { 1, 0 } } } },
	{
		axis = { { 0, -2 }, { 0, 2 } },
		pairs = { { { -2, 1 }, { 2, -1 } }, { { -2, 0 }, { 2, -2 } }, { { -2, 2 }, { 2, 0 } }, { { -1, -1 }, { 1, -2 } }, { { -1, 2 }, { 1, 1 } } },
	},
}

local Honeycomb = {}

Honeycomb.SPACING = 1.1 -- hex centres this many hex sizes apart: a small even gap

function Honeycomb.toPixel(q: number, r: number, size: number): (number, number)
	return size * 1.5 * q, size * SQRT3 * (r + q / 2)
end

-- The box around `hexes` (flat-top, `size` from centre to corner, centres `spacing` sizes apart,
-- 1 by default): its centre and size in pixels.
function Honeycomb.bounds(hexes: { Pos }, size: number, spacing: number?): (number, number, number, number)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local halfH = size * SQRT3 / 2
	for _, pos in hexes do
		local x, y = Honeycomb.toPixel(pos.q, pos.r, size * (spacing or 1))
		minX, maxX = math.min(minX, x - size), math.max(maxX, x + size)
		minY, maxY = math.min(minY, y - halfH), math.max(maxY, y + halfH)
	end
	return (minX + maxX) / 2, (minY + maxY) / 2, maxX - minX, maxY - minY
end

-- The zoom that fits content (w x h) on a board, at most `maxZoom`, but never so small that a hex
-- (`hexPixels` tall on screen at zoom 1) drops under `minPixels` (then it overflows: true).
function Honeycomb.zoom(contentW: number, contentH: number, boardW: number, boardH: number, hexPixels: number, minPixels: number, maxZoom: number): (number, boolean)
	local fit = math.min(boardW / contentW, boardH / contentH, maxZoom)
	local least = minPixels / hexPixels
	if fit >= least then
		return fit, false
	end
	return least, true
end

-- When a hex at (q, r) starts popping in as a view opens: rings further out a little later.
function Honeycomb.enterDelay(q: number, r: number, stagger: number, cap: number): number
	return math.min(Honeycomb.distance(0, 0, q, r) * stagger, cap)
end

-- Where a gamepad step from points[from] toward unit direction (dx, dy) lands: the index of the
-- nearest point within 60 degrees of it (nearer the direction wins), nil for none.
function Honeycomb.step(points: { { x: number, y: number } }, from: number, dx: number, dy: number): number?
	local origin = points[from]
	local best, bestScore = nil, math.huge
	for i, point in points do
		local ox, oy = point.x - origin.x, point.y - origin.y
		local d = math.sqrt(ox * ox + oy * oy)
		local along = if d > 0 then (ox * dx + oy * dy) / d else 0
		if along > STEP_CONE and d * (2 - along) < bestScore then
			best, bestScore = i, d * (2 - along)
		end
	end
	return best
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

-- Where `count` (at most 18) hexes sit around a centre hex, symmetric about the vertical axis:
-- ring 1 first, then ring 2; in each an odd count takes the top cell, then mirror pairs, then the
-- top and bottom. Listed top to bottom, left to right, so the first upgrades sit nearest the top.
function Honeycomb.ringSlots(count: number): { Pos }
	assert(count <= 18, `honeycomb: {count} upgrades don't fit in two rings`)
	local slots: { Pos } = {}
	local function add(cell: { number })
		table.insert(slots, { q = cell[1], r = cell[2] })
	end
	local left = count
	for _, ring in RINGS do
		local k = math.min(left, 2 + 2 * #ring.pairs)
		left -= k
		if k % 2 == 1 then
			add(ring.axis[1])
			k -= 1
		end
		for _, pair in ring.pairs do
			if k >= 2 then
				add(pair[1])
				add(pair[2])
				k -= 2
			end
		end
		if k == 2 then
			add(ring.axis[1])
			add(ring.axis[2])
		end
	end
	table.sort(slots, function(a: Pos, b: Pos): boolean
		local ya, yb = 2 * a.r + a.q, 2 * b.r + b.q -- twice the row, so it stays whole
		return if ya ~= yb then ya < yb else a.q < b.q
	end)
	return slots
end

local function trackUpgrade(track): Upgrade
	local links = {}
	for level, data in track.levels do
		table.insert(links, { kind = "track", id = track.id, level = level, areaId = data.area } :: Link)
	end
	return { id = track.id, kind = "track", areaId = links[1].areaId, links = links }
end

local function itemLinks(item, links: { Link }): { Link }
	for level = 1, #item.levels + 1 do
		table.insert(links, { kind = "item", id = item.id, level = level, areaId = item.area })
	end
	return links
end

-- A category's upgrades from config only (a new track or item needs no layout change), earlier
-- areas first (config order on a tie).
local function upgradesOf(config, catId: string): { Upgrade }
	local list: { Upgrade } = {}
	if catId == "boosts" then
		for _, track in config.tracks do
			if track.id ~= "tool" then
				table.insert(list, trackUpgrade(track))
			end
		end
	elseif catId == "areas" then
		for _, area in config.areas do
			if area.gate then
				local id = `gate:{area.id}` -- common/Areas.gateId (the spec checks they agree)
				table.insert(list, { id = id, kind = "gate", areaId = area.id, links = { { kind = "gate", id = id, level = 1, areaId = area.id } } })
			end
		end
	else
		local packs: { Link } = {}
		for _, item in config.items do
			if catId == "gear" and item.kind == "backpack" then
				itemLinks(item, packs)
			elseif (catId == "gear" and item.kind == "gadget") or ITEM_KINDS[catId] == item.kind then
				table.insert(list, { id = item.id, kind = "item", areaId = item.area, links = itemLinks(item, {}) })
			end
		end
		if #packs > 0 then
			table.insert(list, 1, { id = "backpacks", kind = "backpacks", areaId = packs[1].areaId, links = packs } :: Upgrade)
		end
	end
	local index = {}
	for i, upgrade in list do
		index[upgrade] = i
	end
	table.sort(list, function(a: Upgrade, b: Upgrade): boolean
		return if a.areaId ~= b.areaId then a.areaId < b.areaId else index[a] < index[b]
	end)
	return list
end

function Honeycomb.layout(config): Layout
	local layout: Layout = { tool = trackUpgrade(config.track("tool")), ring = {}, order = CATEGORIES, categories = {} }
	for i, catId in CATEGORIES do
		table.insert(layout.ring, { id = catId, q = STEPS[i][1], r = STEPS[i][2] })
		local upgrades = upgradesOf(config, catId)
		layout.categories[catId] = { id = catId, upgrades = upgrades, slots = Honeycomb.ringSlots(#upgrades) }
	end
	return layout
end

-- The upgrades a view shows: the tool on "main", else the category's.
function Honeycomb.upgrades(layout: Layout, viewId: string): { Upgrade }
	return if viewId == "main" then { layout.tool } else layout.categories[viewId].upgrades
end

local function linkOwned(view: View, link: Link): boolean
	if link.kind == "track" then
		return (view.levels[link.id] or 0) >= link.level
	elseif link.kind == "item" then
		return (view.items[link.id] or 0) >= link.level
	end
	return view.openAreas[link.areaId] == true
end

-- How many of an upgrade's levels count as owned: up to the furthest one owned (a bigger backpack
-- passes the earlier ones' upgrades).
function Honeycomb.ownedCount(upgrade: Upgrade, view: View): number
	local last = 0
	for i, link in upgrade.links do
		if linkOwned(view, link) then
			last = i
		end
	end
	return last
end

-- The level an upgrade's hex sells with `owned` levels owned: the next one, the last once maxed.
function Honeycomb.link(upgrade: Upgrade, owned: number): Link
	return upgrade.links[math.min(owned + 1, #upgrade.links)]
end

-- An upgrade's state: "max" with every level owned; else its next level's: "locked" in a closed
-- area, of an unreachable item or without a price (not sold here); "buy" when the wallet pays it,
-- else "short".
function Honeycomb.state(upgrade: Upgrade, view: View): HexState
	local owned, total = Honeycomb.ownedCount(upgrade, view), #upgrade.links
	if owned == total then
		return { state = "max", owned = owned, total = total }
	end
	local link = upgrade.links[owned + 1]
	local price = view.price(link)
	local shut = link.kind ~= "gate" and (not view.openAreas[link.areaId] or (link.kind == "item" and not view.reachable(link.id)))
	if shut or not price then
		return { state = "locked", owned = owned, total = total }
	elseif view.wallet + MONEY_EPSILON >= price then
		return { state = "buy", owned = owned, total = total, price = price }
	end
	return { state = "short", owned = owned, total = total, price = price, progress = math.clamp(view.wallet / price, 0, 1) }
end

-- Every upgrade's state in a view, by upgrade id.
function Honeycomb.states(layout: Layout, viewId: string, view: View): { [string]: HexState }
	local out = {}
	for _, upgrade in Honeycomb.upgrades(layout, viewId) do
		out[upgrade.id] = Honeycomb.state(upgrade, view)
	end
	return out
end

-- Whether `upgrade` is `id` or sells it.
local function sells(upgrade: Upgrade, id: string): boolean
	if upgrade.id == id then
		return true
	end
	for _, link in upgrade.links do
		if link.id == id then
			return true
		end
	end
	return false
end

-- The view ("main" for the tool, else a category id) and upgrade that is or sells `id` (a track,
-- item or gate; a backpack: the backpacks hex), or nil.
function Honeycomb.find(layout: Layout, id: string): (string?, Upgrade?)
	for _, viewId in { "main", table.unpack(layout.order) } do
		for _, upgrade in Honeycomb.upgrades(layout, viewId) do
			if sells(upgrade, id) then
				return viewId, upgrade
			end
		end
	end
	return nil, nil
end

-- The upgrade id to select in a view (`states`: Honeycomb.states): with `id`, the hex that is or
-- sells it; without, the first "buy", else the first "short", else nil.
function Honeycomb.pick(layout: Layout, viewId: string, states: { [string]: HexState }, id: string?): string?
	local short = nil
	for _, upgrade in Honeycomb.upgrades(layout, viewId) do
		local state = states[upgrade.id].state
		if id then
			if sells(upgrade, id) then
				return upgrade.id
			end
		elseif state == "buy" then
			return upgrade.id
		elseif state == "short" then
			short = short or upgrade.id
		end
	end
	return if id then nil else short
end

-- Levels owned in category `catId` and all its levels, for its hex.
function Honeycomb.ownedShare(layout: Layout, catId: string, view: View): (number, number)
	local owned, total = 0, 0
	for _, upgrade in layout.categories[catId].upgrades do
		owned += Honeycomb.ownedCount(upgrade, view)
		total += #upgrade.links
	end
	return owned, total
end

-- What Buy(id, bought) sends as `bought` for a link's id: track levels bought, an item's upgrades
-- (-1 while the team doesn't own it), 1 for an open gate and 0 for a closed one.
function Honeycomb.bought(link: Link, view: View): number
	if link.kind == "track" then
		return view.levels[link.id] or 0
	elseif link.kind == "gate" then
		return if view.openAreas[link.areaId] then 1 else 0
	end
	return (view.items[link.id] or 0) - 1
end

-- The card's level line for the link a hex in `state` shows: "Buy" for a first level,
-- "Lv 2 → Lv 3", "MAX"; nothing for a gate.
function Honeycomb.levelText(link: Link, state: StateName): string
	if link.kind == "gate" then
		return ""
	elseif state == "max" then
		return "MAX"
	elseif link.level == 1 then
		return "Buy"
	end
	return `Lv {link.level - 1} → Lv {link.level}`
end

-- The red balls: "buy" hexes per view id ("main": the tool; the categories), and `total`; then the
-- wallets that keep them: they stay while low <= wallet < high (the dearest buy and the cheapest
-- short, -huge / huge for none).
function Honeycomb.badges(layout: Layout, view: View): ({ [string]: number }, number, number)
	local counts = { total = 0 }
	local low, high = -math.huge, math.huge
	for _, viewId in { "main", table.unpack(layout.order) } do
		local n = 0
		for _, state in Honeycomb.states(layout, viewId, view) do
			if state.state == "buy" then
				n += 1
				low = math.max(low, (state.price :: number) - MONEY_EPSILON)
			elseif state.state == "short" then
				high = math.min(high, (state.price :: number) - MONEY_EPSILON)
			end
		end
		counts[viewId] = n
		counts.total += n
	end
	return counts, low, high
end

-- An item's first link the team can get now, just not here: at its stand or on a plot.
function Honeycomb.elsewhere(link: Link, st: HexState, view: View): boolean
	return st.state == "locked" and link.kind == "item" and link.level == 1 and view.openAreas[link.areaId] == true and view.reachable(link.id)
end

-- The buyer's LastBuy attribute (server/Run): "<id>@<bought>@<serverTime>", `bought` as
-- Honeycomb.bought reads it after the buy.
export type Buy = { id: string, level: number, at: number }

function Honeycomb.encodeBuy(id: string, level: number, serverTime: number): string
	return `{id}@{level}@{serverTime}`
end

function Honeycomb.decodeBuy(text: unknown): Buy?
	if type(text) ~= "string" then
		return nil
	end
	local id, level, serverTime = text:match("^([^@]+)@([^@]+)@([^@]+)$")
	local n, time = tonumber(level), tonumber(serverTime)
	if not (id and n and time) then
		return nil
	end
	return { id = id, level = n, at = time }
end

return Honeycomb
