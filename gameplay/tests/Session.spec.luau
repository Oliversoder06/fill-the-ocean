local Session = require("../src/shared/Session")
-- The clamp common/Difficulty used to give (a whole number 1..5); Task 4 moves Session to mapId.
local function clamp(level: any): number
	if type(level) ~= "number" or level ~= level then
		return 1
	end
	return math.clamp(math.floor(level), 1, 5)
end

local tests = {}

local TICKET = { difficulty = 3, members = { 11, 22 } }

function tests.studio_is_test_mode(t)
	local s = Session.decide({ isStudio = true, privateServerId = "", privateServerOwnerId = 0, ticket = nil }, clamp)
	t.expectEq(s.mode, "test")
	t.expectEq(Session.admits(s, 999), true, "anyone may test in Studio")
end

function tests.public_live_server_is_closed(t)
	-- someone reached the gameplay place without the lobby (direct join, join-a-friend, old link)
	local s = Session.decide({ isStudio = false, privateServerId = "", privateServerOwnerId = 0, ticket = nil }, clamp)
	t.expectEq(s.mode, "closed")
	t.expectEq(Session.admits(s, 11), false)
end

function tests.vip_private_server_is_closed(t)
	local s = Session.decide({ isStudio = false, privateServerId = "abc", privateServerOwnerId = 55, ticket = TICKET }, clamp)
	t.expectEq(s.mode, "closed")
end

function tests.reserved_without_ticket_is_closed(t)
	local s = Session.decide({ isStudio = false, privateServerId = "abc", privateServerOwnerId = 0, ticket = nil }, clamp)
	t.expectEq(s.mode, "closed")
	t.expectEq(Session.admits(s, 11), false)
end

function tests.reserved_with_ticket_admits_only_the_party(t)
	local s = Session.decide({ isStudio = false, privateServerId = "abc", privateServerOwnerId = 0, ticket = TICKET }, clamp)
	t.expectEq(s.mode, "party")
	t.expectEq(s.difficulty, 3)
	t.expectEq(s.expected, 2)
	t.expectEq(Session.admits(s, 11), true)
	t.expectEq(Session.admits(s, 22), true)
	t.expectEq(Session.admits(s, 33), false, "a friend who follows in is sent to the lobby")
end

function tests.ticket_difficulty_is_clamped(t)
	local s = Session.decide({ isStudio = false, privateServerId = "abc", privateServerOwnerId = 0, ticket = { difficulty = 99, members = { 1 } } }, clamp)
	t.expectEq(s.difficulty, 5)
end

function tests.studio_difficulty_from_attribute(t)
	local s = Session.decide({ isStudio = true, privateServerId = "", privateServerOwnerId = 0, ticket = nil, studioDifficulty = 4 }, clamp)
	t.expectEq(s.difficulty, 4)
end

return tests
