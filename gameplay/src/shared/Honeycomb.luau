--!strict
-- The shop's honeycomb (library ui/screens/shop.md): where every hex sits and what state it is in.
-- Pure: config is passed in, so Lune tests and Roblox load it the same way. Hexes are flat-top, in
-- axial coordinates (q, r); q is the column, r runs down it.
--
-- Category view arrangement: one cluster of touching hexes (library shop.md), the category hex at
-- (0, 0). Each chain is an arm of neighbours growing outward from it: the four longest chains leave
-- along the diagonals (a view is wide like the screen), the two shortest after them up and down;
-- past six chains the rest start in the second ring beside an arm's first hex, left and right
-- first. Each next slot is the free neighbour farthest from the centre, the same direction on a tie.
-- Longer chains show a window of their links (Honeycomb.window): the i-th shown link sits in the
-- chain's slot i.

export type Pos = { q: number, r: number }
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
	slots: { Pos }, -- min(#links, MAX_VISIBLE) touching places, outward from the category hex
}
export type Category = {
	id: string,
	hex: Pos, -- (0, 0)
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
-- Flat-top neighbour steps, clockwise from straight up.
local STEPS = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 0, 1 }, { -1, 1 }, { -1, 0 } }
local DIAGONALS = { 2, 3, 5, 6 } -- STEPS a category's longest chains leave by, clockwise
local VERTICALS = { 1, 4 }
local STEP_CONE = 0.5 -- cos 60 degrees: how far off its direction a gamepad step may land
local CATEGORIES = { "tools", "boosts", "gear", "vehicles", "buildings", "staff" }

local Honeycomb = {}

Honeycomb.MAX_VISIBLE = 5

function Honeycomb.toPixel(q: number, r: number, size: number): (number, number)
	return size * 1.5 * q, size * SQRT3 * (r + q / 2)
end

-- The box around `hexes` (flat-top, `size` from centre to corner): its centre and size in pixels.
function Honeycomb.bounds(hexes: { Pos }, size: number): (number, number, number, number)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local halfH = size * SQRT3 / 2
	for _, pos in hexes do
		local x, y = Honeycomb.toPixel(pos.q, pos.r, size)
		minX, maxX = math.min(minX, x - size), math.max(maxX, x + size)
		minY, maxY = math.min(minY, y - halfH), math.max(maxY, y + halfH)
	end
	return (minX + maxX) / 2, (minY + maxY) / 2, maxX - minX, maxY - minY
end

-- The zoom that fits content (w x h) on a board, at most `maxZoom`, but never so small that a hex
-- (`hexPixels` tall on screen at zoom 1) drops under `minPixels`; then the board pans (true).
function Honeycomb.zoom(contentW: number, contentH: number, boardW: number, boardH: number, hexPixels: number, minPixels: number, maxZoom: number): (number, boolean)
	local fit = math.min(boardW / contentW, boardH / contentH, maxZoom)
	local least = minPixels / hexPixels
	if fit >= least then
		return fit, false
	end
	return least, true
end

-- A pan offset kept so zoomed content (w x h) still covers the board where it is bigger than it.
function Honeycomb.clampPan(x: number, y: number, contentW: number, contentH: number, boardW: number, boardH: number): (number, number)
	local maxX, maxY = math.max(0, (contentW - boardW) / 2), math.max(0, (contentH - boardH) / 2)
	return math.clamp(x, -maxX, maxX), math.clamp(y, -maxY, maxY)
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
	return { id = id, links = links, slots = {} }
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

local function cell(pos: Pos): string
	return `{pos.q},{pos.r}`
end

-- Adds `count` slots to `chain` from `from`, each the free neighbour of the last farthest from the
-- centre, on a tie the one in direction `dir` (a STEPS index), else the first clockwise.
local function grow(used: { [string]: boolean }, chain: Chain, from: Pos, dir: number, count: number)
	for _ = 1, count do
		local best: Pos?, bestDir, bestDistance = nil, dir, -1
		for d, step in STEPS do
			local pos = { q = from.q + step[1], r = from.r + step[2] }
			local distance = Honeycomb.distance(0, 0, pos.q, pos.r)
			if not used[cell(pos)] and (distance > bestDistance or (distance == bestDistance and d == dir)) then
				best, bestDir, bestDistance = pos, d, distance
			end
		end
		assert(best, `honeycomb: chain {chain.id} is boxed in at {cell(from)}`)
		used[cell(best :: Pos)] = true
		table.insert(chain.slots, best :: Pos)
		from, dir = best :: Pos, bestDir
	end
end

-- A second-ring cell beside an arm's first hex for a chain past six: the one furthest left or right
-- (the screen is wide), and the step from that arm's hex into it.
local function wedgeStart(used: { [string]: boolean }, arms: { Chain }): (Pos, number)
	local best: Pos?, bestDir, bestX = nil, 0, -1
	for _, arm in arms do
		local first = arm.slots[1]
		for d, step in STEPS do
			local pos = { q = first.q + step[1], r = first.r + step[2] }
			local x = math.abs((Honeycomb.toPixel(pos.q, pos.r, 1)))
			if not used[cell(pos)] and Honeycomb.distance(0, 0, pos.q, pos.r) == 2 and x > bestX then
				best, bestDir, bestX = pos, d, x
			end
		end
	end
	assert(best, "honeycomb: no room in the second ring")
	return best :: Pos, bestDir
end

local function place(catId: string, chains: { Chain }): Category
	local function slotCount(chain: Chain): number
		return math.min(#chain.links, Honeycomb.MAX_VISIBLE)
	end
	-- Longest first (config order on a tie): the four longest take the diagonals, the two shortest
	-- of the rest up and down, any others the second ring.
	local order = {}
	for i in chains do
		table.insert(order, i)
	end
	table.sort(order, function(a: number, b: number): boolean
		local na, nb = slotCount(chains[a]), slotCount(chains[b])
		return if na ~= nb then na > nb else a < b
	end)
	local diagonal = math.min(4, #order)
	local vertical = math.min(2, #order - diagonal)
	local groups = { { table.unpack(order, 1, diagonal) }, { table.unpack(order, #order - vertical + 1, #order) }, { table.unpack(order, diagonal + 1, #order - vertical) } }
	for _, group in groups do
		table.sort(group) -- clockwise in config order
	end

	local used = { [cell({ q = 0, r = 0 })] = true }
	local arms = {}
	for g, dirs in { DIAGONALS, VERTICALS } do
		for k, i in groups[g] do
			local chain = chains[i]
			grow(used, chain, { q = 0, r = 0 }, dirs[k], slotCount(chain))
			table.insert(arms, chain)
		end
	end
	for _, i in groups[3] do
		local chain = chains[i]
		local start, dir = wedgeStart(used, arms)
		used[cell(start)] = true
		table.insert(chain.slots, start)
		grow(used, chain, start, dir, slotCount(chain) - 1)
	end
	return { id = catId, hex = { q = 0, r = 0 }, chains = chains }
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

-- For a window change (Honeycomb.window lists, old then new): the old slot each new slot's link sat
-- in, nil for a link new to the window, so its hexes can slide over.
function Honeycomb.moves(old: { number }, new: { number }): { [number]: number? }
	local moves = {}
	for i, index in new do
		moves[i] = table.find(old, index)
	end
	return moves
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

-- The category and chain holding track or item `id` (a backpack: the backpacks chain), or nil.
function Honeycomb.find(layout: Layout, id: string): (string?, Chain?)
	for _, catId in layout.order do
		for _, chain in layout.categories[catId].chains do
			for _, link in chain.links do
				if link.id == id then
					return catId, chain
				end
			end
		end
	end
	return nil, nil
end

-- The link key to select in category `catId` (`states`: Honeycomb.states): with `id`, its next link
-- (else its first); without, the first "buy" in chain order, else the first "short", else nil.
function Honeycomb.pick(layout: Layout, catId: string, states: { [string]: HexState }, id: string?): string?
	local first, short = nil, nil
	for _, chain in layout.categories[catId].chains do
		for _, link in chain.links do
			local state = states[link.key].state
			if id then
				if link.id == id then
					first = first or link.key
					if state ~= "owned" then
						return link.key
					end
				end
			elseif state == "buy" then
				return link.key
			elseif state == "short" then
				short = short or link.key
			end
		end
	end
	return if id then first else short
end

-- Links owned in category `catId` and all its links (gates not counted), for its progress.
function Honeycomb.ownedShare(layout: Layout, catId: string, view: View): (number, number)
	local owned, total = 0, 0
	for _, chain in layout.categories[catId].chains do
		owned += Honeycomb.ownedCount(chain, view)
		for _, link in chain.links do
			if link.kind ~= "gate" then
				total += 1
			end
		end
	end
	return owned, total
end

-- What Buy(id, bought) sends as `bought` for a link's id: track levels bought, or an item's
-- upgrades (-1 while the team doesn't own it).
function Honeycomb.bought(link: Link, view: View): number
	if link.kind == "track" then
		return view.levels[link.id :: string] or 0
	end
	return (view.items[link.id :: string] or 0) - 1
end

-- The card's level line for a link in `state`: "Buy" for a first level, "Lv 2 → Lv 3", the
-- level owned, "MAX"; nothing for a gate.
function Honeycomb.levelText(link: Link, state: StateName): string
	local level = link.level
	if link.kind == "gate" or not level then
		return ""
	elseif state == "max" then
		return "MAX"
	elseif state == "owned" then
		return `Lv {level}`
	elseif level == 1 then
		return "Buy"
	end
	return `Lv {level - 1} → Lv {level}`
end

-- The red balls: "buy" hexes per category id, and `total`; then the wallets that keep them: they
-- stay while low <= wallet < high (the dearest buy and the cheapest short, -huge / huge for none).
function Honeycomb.badges(layout: Layout, view: View): ({ [string]: number }, number, number)
	local counts = { total = 0 }
	local low, high = -math.huge, math.huge
	for _, catId in layout.order do
		local n = 0
		for _, state in Honeycomb.states(layout, catId, view) do
			if state.state == "buy" then
				n += 1
				low = math.max(low, (state.price :: number) - MONEY_EPSILON)
			elseif state.state == "short" then
				high = math.min(high, (state.price :: number) - MONEY_EPSILON)
			end
		end
		counts[catId] = n
		counts.total += n
	end
	return counts, low, high
end

-- An item's first link the team can get now, just not here: at its stand or on a plot.
function Honeycomb.elsewhere(link: Link, st: HexState, view: View): boolean
	return st.state == "locked" and link.kind == "item" and link.level == 1 and view.openAreas[link.areaId] == true and view.reachable(link.id :: string)
end

-- The links of `chain` whose hex shows its 3D model, so few ViewportFrames run: an item's own chain
-- (one model) its next link, else its last; other chains (the tool's models, the backpacks) the
-- last owned, the next and the max end.
function Honeycomb.modelKeys(chain: Chain, states: { [string]: HexState }): { [string]: boolean }
	local lastOwned, nextKey = nil, nil
	local single = true
	for _, link in chain.links do
		if link.kind ~= "gate" then
			single = single and link.kind == "item" and link.id == chain.id
			local state = states[link.key].state
			if state == "owned" or state == "max" then
				lastOwned = link.key
			elseif not nextKey then
				nextKey = link.key
			end
		end
	end
	local last = chain.links[#chain.links].key
	if single then
		return { [nextKey or last] = true }
	end
	local keys = { [last] = true }
	if lastOwned then
		keys[lastOwned] = true
	end
	if nextKey then
		keys[nextKey] = true
	end
	return keys
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
