--!strict
-- Lobby session rules. Pure: Lune-tested; the lobby's Queue uses them.
-- A pad holds one session: a host picks max players (1-10), a difficulty they have unlocked, and
-- friends-only. Anyone may join a session the host unlocked (friends get carried). The run starts
-- when it's full or the host presses Start. If the host leaves, the earliest remaining member hosts.

export type Settings = { maxPlayers: number, difficulty: number, friendsOnly: boolean }

local SessionRules = {}

SessionRules.MAX_PLAYERS = 10
SessionRules.MAX_DIFFICULTY = 5

local function wholeIn(value: any, low: number, high: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= low and value <= high
end

-- Client-sent settings; returns a clean copy or nil when anything is off.
function SessionRules.validate(raw: any, hostUnlocked: number): Settings?
	if type(raw) ~= "table" then
		return nil
	end
	local maxDifficulty = math.min(hostUnlocked, SessionRules.MAX_DIFFICULTY)
	if not wholeIn(raw.maxPlayers, 1, SessionRules.MAX_PLAYERS) then
		return nil
	end
	if not wholeIn(raw.difficulty, 1, maxDifficulty) then
		return nil
	end
	if type(raw.friendsOnly) ~= "boolean" then
		return nil
	end
	return { maxPlayers = raw.maxPlayers, difficulty = raw.difficulty, friendsOnly = raw.friendsOnly }
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
