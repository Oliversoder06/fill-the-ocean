--!strict
-- A team's saved run: its shape, its key and the exact-team check. Pure: Lune-tested.
-- RunStore does the DataStore calls; the gameplay server is the only writer.

-- owned: item ids bought at the stands (common/Items); itemLevels: upgrades bought per owned item;
-- assign: where each hired staff works (staff item id -> area id, shared/StaffRules.post).
export type PlayerState = {
	money: number,
	levels: { [string]: number },
	litres: number,
	owned: { string },
	itemLevels: { [string]: number },
	assign: { [string]: number },
}

-- players is keyed by user id as a string: DataStores need string keys.
export type Save = {
	version: number,
	mapId: string,
	members: { number },
	current: number,
	players: { [string]: PlayerState },
	playSeconds: number,
	introSeen: boolean,
	boostsPlayed: { string },
	gatesOpen: { number }, -- area ids whose gate is bought (2-5), in the order they opened
	buildings: { [string]: number }, -- the team's buildings (D2): upgrades bought per building id
	plots: { [string]: string }, -- the building id on each built plot, by plot number ("1", "2", ...)
	rocksBroken: { number }, -- area ids (1-5) whose rock is broken, opening its deeper pool
	finished: boolean,
	updatedAt: number,
}

local RunSave = {}

RunSave.VERSION = 1

local function isUserId(value: any): boolean
	return type(value) == "number" and value % 1 == 0 and value > 0 and value < math.huge
end

-- Valid user ids, sorted and deduplicated: the one order a team is stored and keyed in.
local function team(userIds: { any }): { number }
	local sorted = {}
	for _, userId in userIds do
		if isUserId(userId) and not table.find(sorted, userId) then
			table.insert(sorted, userId)
		end
	end
	table.sort(sorted)
	return sorted
end

-- Whole area ids from `raw` between `low` and `high`, each once, in their order; anything else is dropped.
local function areaIds(raw: any, low: number, high: number): { number }
	local ids = {}
	if type(raw) == "table" then
		for _, id in raw do
			if type(id) == "number" and id % 1 == 0 and id >= low and id <= high and not table.find(ids, id) then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

-- A finite number, negatives clamped to 0; anything else (NaN, inf, wrong type) is 0.
local function amount(value: any): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 0
	end
	return math.max(0, value)
end

-- Levels by id (tracks, items, buildings): string ids, whole numbers, never negative.
local function counts(raw: any): { [string]: number }
	local levels = {}
	if type(raw) == "table" then
		for id, level in raw do
			if type(id) == "string" and type(level) == "number" then
				levels[id] = math.floor(amount(level))
			end
		end
	end
	return levels
end

local function sanitizePlayer(raw: { [any]: any }): PlayerState
	local owned = {}
	if type(raw.owned) == "table" then
		for _, id in raw.owned do
			if type(id) == "string" and not table.find(owned, id) then
				table.insert(owned, id)
			end
		end
	end
	-- staff posts are area ids 1-5; saves from before 3f have none
	local assign = {}
	if type(raw.assign) == "table" then
		for id, area in raw.assign do
			if type(id) == "string" and type(area) == "number" and area % 1 == 0 and area >= 1 and area <= 5 then
				assign[id] = area
			end
		end
	end
	return {
		money = amount(raw.money),
		levels = counts(raw.levels),
		litres = amount(raw.litres),
		owned = owned,
		itemLevels = counts(raw.itemLevels),
		assign = assign,
	}
end

function RunSave.new(mapId: string, members: { number }): Save
	return {
		version = RunSave.VERSION,
		mapId = mapId,
		members = team(members),
		current = 0,
		players = {},
		playSeconds = 0,
		introSeen = false,
		boostsPlayed = {},
		gatesOpen = {},
		buildings = {},
		plots = {},
		rocksBroken = {},
		finished = false,
		updatedAt = 0,
	}
end

-- What erasing a run leaves (the lobby's New Game and Delete, admin resets): a fresh save of the same
-- map and team, stamped newer than `old` (and no older than `now`) so an older write can't land on it.
function RunSave.blank(old: Save, now: number): Save
	local save = RunSave.new(old.mapId, old.members)
	save.updatedAt = math.max(now, old.updatedAt + 1)
	return save
end

-- A write stamped `updatedAt` must not land on `stored` with the same or a newer stamp. Gameplay
-- writes always step up by at least 1 (Run's snapshot), so an equal stamp is an erase's blank or a
-- late copy.
function RunSave.storedNewer(stored: any, updatedAt: number): boolean
	return type(stored) == "table" and type(stored.updatedAt) == "number" and stored.updatedAt >= updatedAt
end

-- Nobody has played this save (an erased run): a new party may start over it without asking.
function RunSave.isBlank(save: Save): boolean
	return next(save.players) == nil and save.current <= 0 and save.playSeconds <= 0 and not save.finished
end

-- DataStore keys are at most 50 characters.
RunSave.KEY_LIMIT = 50

-- 32-bit FNV-1a from the given start value. h * 16777619 is split into h * 2^24 + h * 403 so the
-- product stays exact in a double.
local function fnv1a(text: string, start: number): number
	local h = start
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return h
end

-- The same team on the same map always gets the same key, whatever order they joined in. A team
-- too big for "<mapId>_<ids>" to fit the limit (5+ ten-digit ids) gets "<mapId>_h<16 hex digits>"
-- instead; "h" keeps it apart from id keys. A hash can collide, so a loader must still check sameTeam.
function RunSave.key(mapId: string, members: { number }): string
	local ids = table.concat(team(members), "_")
	local key = `{mapId}_{ids}`
	if #key <= RunSave.KEY_LIMIT then
		return key
	end
	return `{mapId}_h{string.format("%08x%08x", fnv1a(ids, 2166136261), fnv1a(ids, 3735928559))}`
end

-- True only for exactly the save's members: no one missing, no one extra, no one twice.
function RunSave.sameTeam(save: Save, userIds: { number }): boolean
	if #userIds ~= #save.members then
		return false
	end
	local seen = {}
	for _, userId in userIds do
		if seen[userId] or not table.find(save.members, userId) then
			return false
		end
		seen[userId] = true
	end
	return true
end

-- Repairs a stored save: fixes types, clamps negatives to 0 and drops unknown fields. Returns nil
-- when it is not a table or has no map or no team, since such a save can't be matched to anyone.
function RunSave.sanitize(raw: any): Save?
	if type(raw) ~= "table" or type(raw.mapId) ~= "string" or raw.mapId == "" or type(raw.members) ~= "table" then
		return nil
	end
	local members = team(raw.members)
	if #members == 0 then
		return nil
	end
	local save = RunSave.new(raw.mapId, members)
	save.current = amount(raw.current)
	if type(raw.players) == "table" then
		for userId, state in raw.players do
			if type(userId) == "string" and type(state) == "table" then
				save.players[userId] = sanitizePlayer(state)
			end
		end
	end
	save.playSeconds = amount(raw.playSeconds)
	save.introSeen = raw.introSeen == true
	if type(raw.boostsPlayed) == "table" then
		for _, boostId in raw.boostsPlayed do
			if type(boostId) == "string" then
				table.insert(save.boostsPlayed, boostId)
			end
		end
	end
	save.gatesOpen = areaIds(raw.gatesOpen, 2, 5)
	save.buildings = counts(raw.buildings)
	-- plot numbers stay string keys (DataStores need them); saves from before 3e have none
	if type(raw.plots) == "table" then
		for plot, id in raw.plots do
			if type(plot) == "string" and plot:match("^[1-9]%d*$") and type(id) == "string" and id ~= "" then
				save.plots[plot] = id
			end
		end
	end
	save.rocksBroken = areaIds(raw.rocksBroken, 1, 5) -- saves from before 3c have none
	save.finished = raw.finished == true
	save.updatedAt = amount(raw.updatedAt)
	return save
end

return RunSave
