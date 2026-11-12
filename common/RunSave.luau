--!strict
-- A team's saved run: its shape, its key and the exact-team check. Pure: Lune-tested.
-- RunStore does the DataStore calls; the gameplay server is the only writer.

-- Everything bought is the team's (owner, 2026-11-10): one wallet, the upgrade track `levels`, the
-- items bought at the stands (`owned`, common/Items) and upgrades per owned item (`itemLevels`), and
-- where each hired staff works (`assign`: staff item id -> area id, shared/StaffRules.post).
export type Team = {
	wallet: number,
	levels: { [string]: number },
	owned: { string },
	itemLevels: { [string]: number },
	assign: { [string]: number },
}

-- What stays a player's own: the litres they poured.
export type PlayerState = {
	litres: number,
}

-- players is keyed by user id as a string: DataStores need string keys.
export type Save = {
	version: number,
	mapId: string,
	members: { number },
	current: number,
	team: Team,
	players: { [string]: PlayerState },
	playSeconds: number,
	introSeen: boolean,
	gatesOpen: { number }, -- area ids whose gate is bought (2-5), in the order they opened
	buildings: { [string]: number }, -- the team's buildings (D2): upgrades bought per building id
	plots: { [string]: string }, -- the building id on each built plot, by plot number ("1", "2", ...)
	rocksBroken: { number }, -- area ids (1-5) whose rock is broken, opening its deeper pool
	-- Milestones reached (indices into gameplay's Config.milestones), each once; nil for a save from
	-- before milestones (4c): the gameplay server marks those below its fill as reached on load.
	milestones: { number }?,
	-- Those the gameplay server marked reached for such a save: never granted, so never paid.
	milestonesSkipped: { number },
	finished: boolean,
	updatedAt: number,
}

local RunSave = {}

-- 2: the team economy (one `team`); a version 1 save is migrated (mergePlayers) and written back.
-- 3: Phase 4's ladders (new tool levels, other tracks' counts changed); older saves migrate in sanitize.
RunSave.VERSION = 3

-- The version 2 tool ladder's model by level (git 5d73b33, gameplay/src/shared/Config.luau; level 0
-- is the Spoon). A version 2 (or 1) save's tool level becomes the first version 3 level with the same
-- model, so the team keeps the tool they saw.
RunSave.V2_TOOL_MODELS = {
	"Cup", -- 1 Cup
	"Cup", -- 2 Cup Lv2
	"Bucket", -- 3 Bucket
	"Bucket", -- 4 Bucket Lv2
	"Bucket", -- 5 Bucket Lv3
	"Bathtub", -- 6 Bathtub
	"Bathtub", -- 7 Bathtub Lv2
	"KiddiePool", -- 8 Kiddie Pool
	"KiddiePool", -- 9 Kiddie Pool Lv2
	"SwimmingPool", -- 10 Swimming Pool
	"SwimmingPool", -- 11 Swimming Pool Lv2
	"SwimmingPool", -- 12 Swimming Pool Lv3
	"CargoShip", -- 13 Cargo Ship
	"CargoShip", -- 14 Cargo Ship Lv2
	"CargoShip", -- 15 Cargo Ship Lv3
	"TheMoon", -- 16 The Moon
	"TheMoon", -- 17 The Moon Lv2
	"TheMoon", -- 18 The Moon Lv3
	"TheMoon", -- 19 The Moon Lv4
}

-- No map has more milestones than this; sanitize drops higher indices even without the Config.
RunSave.MAX_MILESTONES = 100

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
	return { litres = amount(raw.litres) }
end

-- Item ids: strings, each once, in their order.
local function itemIds(raw: any): { string }
	local owned = {}
	if type(raw) == "table" then
		for _, id in raw do
			if type(id) == "string" and not table.find(owned, id) then
				table.insert(owned, id)
			end
		end
	end
	return owned
end

-- Staff posts: area ids 1-5 by staff item id; saves from before 3f have none.
local function posts(raw: any): { [string]: number }
	local assign = {}
	if type(raw) == "table" then
		for id, area in raw do
			if type(id) == "string" and type(area) == "number" and area % 1 == 0 and area >= 1 and area <= 5 then
				assign[id] = area
			end
		end
	end
	return assign
end

function RunSave.newTeam(): Team
	return { wallet = 0, levels = {}, owned = {}, itemLevels = {}, assign = {} }
end

-- A copy of every team field, its tables copied too (their values are plain numbers and strings).
function RunSave.copyTeam(source: Team): Team
	local copy: any = table.clone(source)
	for field, value in copy do
		if type(value) == "table" then
			copy[field] = table.clone(value)
		end
	end
	return copy
end

local function sanitizeTeam(raw: { [any]: any }): Team
	return {
		wallet = amount(raw.wallet),
		levels = counts(raw.levels),
		owned = itemIds(raw.owned),
		itemLevels = counts(raw.itemLevels),
		assign = posts(raw.assign),
	}
end

-- A save from before the team economy kept money, levels, items and staff posts per player: the
-- team gets the money added up, the best level of each track and item, every item anyone had and each
-- staff's post from the first player (lowest user id) who set one. Only the save's `members` (sorted,
-- see team) count.
local function mergePlayers(players: { [any]: any }, members: { number }): Team
	local keys = {}
	for _, userId in members do
		if type(players[tostring(userId)]) == "table" then
			table.insert(keys, tostring(userId))
		end
	end
	local merged = RunSave.newTeam()
	for _, key in keys do
		local old = sanitizeTeam({
			wallet = players[key].money,
			levels = players[key].levels,
			owned = players[key].owned,
			itemLevels = players[key].itemLevels,
			assign = players[key].assign,
		})
		merged.wallet += old.wallet
		for id, level in old.levels do
			merged.levels[id] = math.max(merged.levels[id] or 0, level)
		end
		for id, level in old.itemLevels do
			merged.itemLevels[id] = math.max(merged.itemLevels[id] or 0, level)
		end
		for _, id in old.owned do
			if not table.find(merged.owned, id) then
				table.insert(merged.owned, id)
			end
		end
		for id, area in old.assign do
			merged.assign[id] = merged.assign[id] or area
		end
	end
	return merged
end

function RunSave.new(mapId: string, members: { number }): Save
	return {
		version = RunSave.VERSION,
		mapId = mapId,
		members = team(members),
		current = 0,
		team = RunSave.newTeam(),
		players = {},
		playSeconds = 0,
		introSeen = false,
		gatesOpen = {},
		buildings = {},
		plots = {},
		rocksBroken = {},
		milestones = {},
		milestonesSkipped = {},
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

-- The intro plays on a run nobody has played yet and only until it has been seen. Time played only
-- counts once play starts (server/Run), so a team that left during the intro sees it again; a save
-- from before the intro was played, so it never does.
function RunSave.wantsIntro(save: Save): boolean
	return not save.introSeen and save.current <= 0 and save.playSeconds <= 0 and not save.finished
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

-- A version 2 (or 1) tool level as the first level of `config`'s tool track with the model it showed.
local function remapTool(config, level: number): number
	if level <= 0 then
		return level
	end
	local model = RunSave.V2_TOOL_MODELS[math.min(level, #RunSave.V2_TOOL_MODELS)]
	for i, toolLevel in (config.track("tool") :: any).levels do
		if toolLevel.model == model then
			return i
		end
	end
	error(`the tool ladder has no {model} for an old save's tool level {level}`)
end

-- Clamps every known track, item and building level to its ladder in `config` (unknown ids stay).
local function fitLevels(save: Save, config)
	for id, level in save.team.levels do
		local track = config.track(id)
		if track then
			save.team.levels[id] = math.min(level, #track.levels)
		end
	end
	local itemLevels = {}
	for _, item in config.items do
		itemLevels[item.id] = #item.levels
	end
	for _, levels in { save.team.itemLevels, save.buildings } do
		for id, level in levels do
			if itemLevels[id] then
				levels[id] = math.min(level, itemLevels[id])
			end
		end
	end
end

-- Repairs a stored save: fixes types, clamps negatives to 0 and drops unknown fields. Returns nil
-- when it is not a table or has no map or no team, since such a save can't be matched to anyone,
-- and nil plus why for a save from newer code (a higher version): repairing it would wipe what this
-- code doesn't know. With gameplay's `config` an older save also migrates (remapTool) and every level
-- and milestone is fitted to it; the lobby passes none, as it never writes a loaded save back.
function RunSave.sanitize(raw: any, config: any?): (Save?, string?)
	if type(raw) == "table" and type(raw.version) == "number" and raw.version > RunSave.VERSION then
		return nil, `save version {raw.version} is newer than this server's ({RunSave.VERSION})`
	end
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
	if type(raw.team) == "table" then
		save.team = sanitizeTeam(raw.team)
	elseif type(raw.players) == "table" then
		save.team = mergePlayers(raw.players, members)
	end
	save.playSeconds = amount(raw.playSeconds)
	save.introSeen = raw.introSeen == true
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
	-- milestone indices are whole ids too; no field: a save from before milestones
	local lastMilestone = if config then #config.milestones else RunSave.MAX_MILESTONES
	save.milestones = if type(raw.milestones) == "table" then areaIds(raw.milestones, 1, lastMilestone) else nil
	save.milestonesSkipped = areaIds(raw.milestonesSkipped, 1, lastMilestone)
	save.finished = raw.finished == true
	save.updatedAt = amount(raw.updatedAt)
	if config then
		local tool = save.team.levels.tool
		if tool and type(raw.version) == "number" and raw.version < 3 then
			save.team.levels.tool = remapTool(config, tool)
		end
		fitLevels(save, config)
	end
	return save
end

return RunSave
