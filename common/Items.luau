--!strict
-- Things bought once at their area's stand (Config.items), then levelled in TAB. Pure: config is
-- passed in, so Lune tests and Roblox load it the same way.
-- `state` is the team's (everything bought is the team's): `owned` (item ids, in the order bought)
-- and `itemLevels` (upgrades bought per owned item, 0 right after the buy). RunSave.Team fits.
-- Buildings are kept apart (save.buildings, see Items.teamOwned).
-- Prices: a team pays Items.price for its size; `teamSize` (the save's members) defaults to 1, the
-- listed price.

export type State = { owned: { string }, itemLevels: { [string]: number } }
-- nextLevel: "buy" (an upgrade is next), "max", "unowned" (buy it at its stand first) or
-- "replaced" (a bigger backpack took over).
export type Status = "buy" | "max" | "unowned" | "replaced"

local MONEY_EPSILON = 1e-6 -- pours add fractional coins; 1199.9999999 must still buy a 1,200-coin item

local Items = {}

-- id may be anything (a remote value); only a listed item's id returns it.
function Items.get(config, id: any)
	for _, item in config.items do
		if item.id == id then
			return item
		end
	end
	return nil
end

function Items.owned(state: State, id: string): boolean
	return table.find(state.owned, id) ~= nil
end

-- The owned item of `kind` from the furthest area (a later one replaces the earlier ones). Nil = none.
function Items.furthest(config, state: State, kind: string)
	local best = nil
	for _, item in config.items do
		if item.kind == kind and Items.owned(state, item.id) and (not best or item.area > best.area) then
			best = item
		end
	end
	return best
end

-- The owned item of `kind` a Fire Station call brings next: with `current` (the one out now) the next
-- one down by area, wrapping to the furthest; with none out (or `current` not owned) the furthest.
-- Nil = none owned.
function Items.nextOwned(config, state: State, kind: string, current: string?)
	local list = {}
	for _, item in config.items do
		if item.kind == kind and Items.owned(state, item.id) then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		return a.area > b.area or (a.area == b.area and a.id < b.id)
	end)
	for i, item in list do
		if item.id == current then
			return list[i % #list + 1]
		end
	end
	return list[1]
end

-- The backpack worn: the owned one of the furthest area. Nil = none.
function Items.backpack(config, state: State)
	return Items.furthest(config, state, "backpack")
end

-- Whether a bigger worn backpack replaces `item`.
local function replaced(config, state: State, item): boolean
	if item.kind ~= "backpack" then
		return false
	end
	local worn = Items.backpack(config, state)
	return worn ~= nil and worn.area > item.area
end

-- Whether `money` pays `price`. Pours add fractional coins: 1199.9999999 must still buy a 1,200-coin item.
function Items.affords(money: number, price: number): boolean
	return money + MONEY_EPSILON >= price
end

-- How much dearer everything is for a team of `teamSize`: 1 solo, then +priceStep a player.
function Items.priceScale(config, teamSize: number): number
	return 1 + config.team.priceStep * (math.max(teamSize, 1) - 1)
end

-- What a listed `cost` (a price, a level's cost, a gate) costs a team of `teamSize`, in whole coins.
-- Every buy and every price shown goes through it.
function Items.price(config, cost: number, teamSize: number): number
	return math.round(cost * Items.priceScale(config, teamSize))
end

-- Whether the stand sells `id` to the team now, with `openAreas` areas open (Ladder.openAreas)
-- and `money`. The reason when not: "unknown", "owned", "replaced", "locked" or "money".
-- Buildings (3e) are kept apart: their caller checks Items.teamOwned instead of "owned".
function Items.canBuy(config, state: State, id: any, openAreas: number, money: number, teamSize: number?): (boolean, string?)
	local item = Items.get(config, id)
	if not item then
		return false, "unknown"
	elseif Items.owned(state, item.id) then
		return false, "owned"
	elseif replaced(config, state, item) then
		return false, "replaced"
	elseif item.area > openAreas then
		return false, "locked"
	elseif not Items.affords(money, Items.price(config, item.price, teamSize or 1)) then
		return false, "money"
	end
	return true, nil
end

-- The upgrade an item offers next in TAB, and its status. Unknown item: nil, nil.
function Items.nextLevel(config, state: State, id: any)
	local item = Items.get(config, id)
	if not item then
		return nil, nil
	elseif not Items.owned(state, item.id) then
		return nil, "unowned" :: Status
	elseif replaced(config, state, item) then
		return nil, "replaced" :: Status
	end
	local level = item.levels[(state.itemLevels[item.id] or 0) + 1]
	return level, (if level then "buy" else "max") :: Status
end

-- An owned item's stat at its bought level (`name`: "capacity", ...).
function Items.stat(state: State, item, name: string): number
	local n = state.itemLevels[item.id] or 0
	local level = if n > 0 then item.levels[math.min(n, #item.levels)] else item
	return level[name]
end

-- Gadget `id`'s stat at its bought level, or nil when the player doesn't own it (or id is unknown).
function Items.gadgetStat(config, state: State, id: any, name: string): number?
	local item = Items.get(config, id)
	return if item and Items.owned(state, item.id) then Items.stat(state, item, name) else nil
end

-- Extra litres carried on top of the tool: the worn backpack's plus every owned gadget that holds
-- water (the Jetpack Tank); 0 without them.
function Items.capacityBonus(config, state: State): number
	local worn = Items.backpack(config, state)
	local bonus = if worn then Items.stat(state, worn, "capacity") else 0
	for _, item in config.items do
		if item.kind == "gadget" and item.capacity and Items.owned(state, item.id) then
			bonus += Items.stat(state, item, "capacity")
		end
	end
	return bonus
end

-- The hotbar's gadget slots: owned gadgets used by hand (a `use`), in config order.
function Items.slots(config, state: State)
	local slots = {}
	for _, item in config.items do
		if item.kind == "gadget" and item.use and Items.owned(state, item.id) then
			table.insert(slots, item)
		end
	end
	return slots
end

-- The area ids of `ids` (open areas, in order) this player reaches: an area that `needs` an item
-- (Cloud Catcher: the Jetpack Tank) only when they own it.
function Items.reachable(config, state: State, ids: { number }): { number }
	local reached = {}
	for _, id in ids do
		local needs = nil
		for _, area in config.areas do
			if area.id == id then
				needs = area.needs
			end
		end
		if not needs or Items.owned(state, needs) then
			table.insert(reached, id)
		end
	end
	return reached
end

-- A copy of the tool's stats (Ladder.stats) with the gear on. The pack fills once the tool is full,
-- at the tool's pace: the same litres per sweep, so more sweeps fill the whole load.
function Items.withGear(config, state: State, stats)
	local s = table.clone(stats)
	local bonus = Items.capacityBonus(config, state)
	if bonus > 0 then
		s.sweeps = stats.sweeps * (stats.capacity + bonus) / stats.capacity
		s.capacity = stats.capacity + bonus
	end
	return s
end

-- Whether area `areaId`'s stand (or cove shop `stand`) sells `item`.
local function soldAt(item, areaId: number, stand: string?): boolean
	local here = if stand then item.stand == stand else item.area == areaId and item.stand == nil
	return here and item.kind ~= "building"
end

-- What a press on area `areaId`'s stand buys: the cheapest item sold there that canBuy allows now,
-- or nil. `stand`: a cove shop (Config.stands) instead of the area's own stand; each sells only its
-- own items, whatever their area (the Fire Station's vehicles open with areas 2-5). One prompt per
-- stand, so it picks for the team. Buildings are built on plots instead.
function Items.standPick(config, state: State, areaId: number, openAreas: number, money: number, stand: string?, teamSize: number?)
	local pick = nil
	for _, item in config.items do
		if soldAt(item, areaId, stand) and Items.canBuy(config, state, item.id, openAreas, money, teamSize) and (not pick or item.price < pick.price) then
			pick = item
		end
	end
	return pick
end

-- What the stand shows the team (args as standPick): the item a press buys and "buy"; else the
-- cheapest one there that is open but costs more than `money` and "money"; else the cheapest one
-- still behind its area's gate and "locked"; else nil and "owned" (all of it owned or replaced).
function Items.standOffer(config, state: State, areaId: number, openAreas: number, money: number, stand: string?, teamSize: number?)
	local pick = Items.standPick(config, state, areaId, openAreas, money, stand, teamSize)
	if pick then
		return pick, "buy"
	end
	for _, why in { "money", "locked" } do
		local cheapest = nil
		for _, item in config.items do
			if soldAt(item, areaId, stand) and select(2, Items.canBuy(config, state, item.id, openAreas, money, teamSize)) == why and (not cheapest or item.price < cheapest.price) then
				cheapest = item
			end
		end
		if cheapest then
			return cheapest, why
		end
	end
	return nil, "owned"
end

-- Whether the team owns building `id` (save.buildings: upgrades bought per building, 0 = just built).
function Items.teamOwned(buildings: { [string]: number }, id: string): boolean
	return buildings[id] ~= nil
end

-- The upgrade TAB offers next for building `id` (a remote value) with the team's `buildings` and
-- `openAreas` areas open, and its status: "buy", "max", "unbuilt" (build one on a plot first) or
-- "locked" (its area is closed). Not a building: nil, nil.
function Items.buildingOffer(config, buildings: { [string]: number }, id: any, openAreas: number)
	local item = Items.get(config, id)
	if not item or item.kind ~= "building" then
		return nil, nil
	elseif not Items.teamOwned(buildings, item.id) then
		return nil, if item.area <= openAreas then "unbuilt" else "locked"
	end
	local level = item.levels[buildings[item.id] + 1]
	return level, if level then "buy" else "max"
end

-- A built building's stat ("rate") at the team's level for it.
function Items.buildingStat(buildings: { [string]: number }, item, name: string): number
	return Items.stat({ owned = {}, itemLevels = buildings }, item, name)
end

return Items
