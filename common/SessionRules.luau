--!strict
-- Lobby session rules. Pure: Lune-tested; the lobby's Queue uses them.
-- A pad holds one session: a host picks max players (1-10), a map they have unlocked, and
-- friends-only. Anyone may join a session the host unlocked (friends get carried). The run starts
-- when it's full or the host presses Start. If the host leaves, the earliest remaining member hosts.
-- A saved run loads only with exactly its team on the pad (loadError says who is missing or extra).

export type Settings = { maxPlayers: number, mapId: string, friendsOnly: boolean }

local SessionRules = {}

SessionRules.MAX_PLAYERS = 10

local function wholeIn(value: any, low: number, high: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= low and value <= high
end

-- Client-sent settings; returns a clean copy or nil when anything is off. hostUnlocked is the set
-- of map ids the host may start (Common.Maps.unlocked for each map).
function SessionRules.validate(raw: any, hostUnlocked: { [string]: boolean }): Settings?
	if type(raw) ~= "table" then
		return nil
	end
	if not wholeIn(raw.maxPlayers, 1, SessionRules.MAX_PLAYERS) then
		return nil
	end
	if type(raw.mapId) ~= "string" or hostUnlocked[raw.mapId] ~= true then
		return nil
	end
	if type(raw.friendsOnly) ~= "boolean" then
		return nil
	end
	return { maxPlayers = raw.maxPlayers, mapId = raw.mapId, friendsOnly = raw.friendsOnly }
end

-- Why a saved run can't load with the players on the pad (nil = it can): "missing" (a save member
-- isn't on the pad) or "extra" (someone on the pad isn't in the save), plus who, in the given order.
-- Missing is reported first: those players have to come, and the extras can step off meanwhile.
function SessionRules.loadError(saveMembers: { number }, padMembers: { number }): (string?, { number })
	local missing = {}
	for _, userId in saveMembers do
		if not table.find(padMembers, userId) then
			table.insert(missing, userId)
		end
	end
	if #missing > 0 then
		return "missing", missing
	end
	local extra = {}
	for _, userId in padMembers do
		if not table.find(saveMembers, userId) and not table.find(extra, userId) then
			table.insert(extra, userId)
		end
	end
	if #extra > 0 then
		return "extra", extra
	end
	return nil, {}
end

-- Why a player can't join (nil = they can): "full" or "friends".
function SessionRules.joinError(settings: { maxPlayers: number, friendsOnly: boolean }, memberCount: number, isHostFriend: boolean): string?
	if memberCount >= settings.maxPlayers then
		return "full"
	end
	if settings.friendsOnly and not isHostFriend then
		return "friends"
	end
	return nil
end

function SessionRules.isFull(settings: { maxPlayers: number }, memberCount: number): boolean
	return memberCount >= settings.maxPlayers
end

-- members in join order (user ids); returns who hosts after `leaving` goes, or nil if nobody.
function SessionRules.nextHost(members: { number }, leaving: number): number?
	for _, userId in members do
		if userId ~= leaving then
			return userId
		end
	end
	return nil
end

return SessionRules
