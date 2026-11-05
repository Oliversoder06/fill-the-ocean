local SessionRules = require("../../common/SessionRules")

local tests = {}

function tests.valid_settings_pass(t)
	local s = SessionRules.validate({ maxPlayers = 4, difficulty = 2, friendsOnly = true }, 3)
	t.expectEq(s and s.maxPlayers, 4)
	t.expectEq(s and s.difficulty, 2)
	t.expectEq(s and s.friendsOnly, true)
end

function tests.rejects_bad_types_and_ranges(t)
	t.expectEq(SessionRules.validate(nil, 5), nil)
	t.expectEq(SessionRules.validate("x", 5), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 0, difficulty = 1, friendsOnly = false }, 5), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 11, difficulty = 1, friendsOnly = false }, 5), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 2.5, difficulty = 1, friendsOnly = false }, 5), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 0 / 0, difficulty = 1, friendsOnly = false }, 5), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 2, difficulty = 1, friendsOnly = "yes" }, 5), nil)
end

function tests.difficulty_must_be_unlocked_by_host(t)
	t.expectEq(SessionRules.validate({ maxPlayers = 2, difficulty = 3, friendsOnly = false }, 2), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 2, difficulty = 6, friendsOnly = false }, 9), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 2, difficulty = 1, friendsOnly = false }, 1).difficulty, 1)
end

function tests.join_checks(t)
	local session = { maxPlayers = 2, friendsOnly = false }
	t.expectEq(SessionRules.joinError(session, 1, false), nil)
	t.expectEq(SessionRules.joinError(session, 2, false), "full")
	local friends = { maxPlayers = 4, friendsOnly = true }
	t.expectEq(SessionRules.joinError(friends, 1, false), "friends")
	t.expectEq(SessionRules.joinError(friends, 1, true), nil)
end

function tests.ready_when_full(t)
	t.expectEq(SessionRules.isFull({ maxPlayers = 3 }, 2), false)
	t.expectEq(SessionRules.isFull({ maxPlayers = 3 }, 3), true)
	t.expectEq(SessionRules.isFull({ maxPlayers = 1 }, 1), true)
end

function tests.next_host_is_earliest_remaining(t)
	t.expectEq(SessionRules.nextHost({ 11, 22, 33 }, 11), 22)
	t.expectEq(SessionRules.nextHost({ 11, 22, 33 }, 22), 11)
	t.expectEq(SessionRules.nextHost({ 11 }, 11), nil)
	t.expectEq(SessionRules.nextHost({}, 11), nil)
end

return tests
