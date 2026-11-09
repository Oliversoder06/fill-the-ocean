--!strict
-- Things bought once at their area's stand (Config.items), then levelled in TAB. Pure: config is
-- passed in, so Lune tests and Roblox load it the same way.
-- `state` is a player's: `owned` (item ids, in the order bought) and `itemLevels` (upgrades bought
-- per owned item, 0 right after the buy). The server's player state and RunSave's PlayerState fit.
-- Buildings are the team's instead (save.buildings, see Items.teamOwned).

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

-- The backpack worn: the owned one of the furthest area (each replaces the earlier ones). Nil = none.
function Items.backpack(config, state: State)
	local best = nil
	for _, item in config.items do
		if item.kind == "backpack" and Items.owned(state, item.id) and (not best or item.area > best.area) then
			best = item
		end
	end
	return best
end

-- Whether a bigger worn backpack replaces `item`.
local function replaced(config, state: State, item): boolean
	if item.kind ~= "backpack" then
		return false
	end
	local worn = Items.backpack(config, state)
	return worn ~= nil and worn.area > item.area
end

-- Whether the stand sells `id` to this player now, with `openAreas` areas open (Ladder.openAreas)
-- and `money`. The reason when not: "unknown", "owned", "replaced", "locked" or "money".
-- Buildings (3e) are the team's: their caller checks Items.teamOwned instead of "owned".
function Items.canBuy(config, state: State, id: any, openAreas: number, money: number): (boolean, string?)
	local item = Items.get(config, id)
	if not item then
		return false, "unknown"
	elseif Items.owned(state, item.id) then
		return false, "owned"
	elseif replaced(config, state, item) then
		return false, "replaced"
	elseif item.area > openAreas then
		return false, "locked"
	elseif money + MONEY_EPSILON < item.price then
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

-- Extra litres carried on top of the tool: the worn backpack's, 0 without one.
function Items.capacityBonus(config, state: State): number
	local worn = Items.backpack(config, state)
	return if worn then Items.stat(state, worn, "capacity") else 0
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

-- What a press on area `areaId`'s stand buys: the cheapest item sold there that canBuy allows now,
-- or nil. One prompt per stand, so it picks for the player (a picker comes with more items, 3b).
function Items.standPick(config, state: State, areaId: number, openAreas: number, money: number)
	local pick = nil
	for _, item in config.items do
		if item.area == areaId and Items.canBuy(config, state, item.id, openAreas, money) and (not pick or item.price < pick.price) then
			pick = item
		end
	end
	return pick
end

-- Whether the team owns building `id` (save.buildings: upgrades bought per building, 0 = just built).
function Items.teamOwned(buildings: { [string]: number }, id: string): boolean
	return buildings[id] ~= nil
end

return Items
