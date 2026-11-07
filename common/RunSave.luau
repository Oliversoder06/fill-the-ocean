--!strict
-- A team's saved run: its shape, its key and the exact-team check. Pure: Lune-tested.
-- RunStore does the DataStore calls; the gameplay server is the only writer.

export type PlayerState = { money: number, levels: { [string]: number }, litres: number }

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

-- A finite number, negatives clamped to 0; anything else (NaN, inf, wrong type) is 0.
local function amount(value: any): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 0
	end
	return math.max(0, value)
end

local function sanitizePlayer(raw: { [any]: any }): PlayerState
	local levels = {}
	if type(raw.levels) == "table" then
		for trackId, level in raw.levels do
			if type(trackId) == "string" and type(level) == "number" then
				levels[trackId] = math.floor(amount(level))
			end
		end
	end
	return { money = amount(raw.money), levels = levels, litres = amount(raw.litres) }
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
		finished = false,
		updatedAt = 0,
	}
end

-- The same team on the same map always gets the same key, whatever order they joined in.
function RunSave.key(mapId: string, members: { number }): string
	return `{mapId}_{table.concat(team(members), "_")}`
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
	save.finished = raw.finished == true
	save.updatedAt = amount(raw.updatedAt)
	return save
end

return RunSave
