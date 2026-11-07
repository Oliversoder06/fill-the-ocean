local SessionRules = require("../../common/SessionRules")

local tests = {}

local UNLOCKED = { map1 = true }

function tests.valid_settings_pass(t)
	local s = SessionRules.validate({ maxPlayers = 4, mapId = "map1", friendsOnly = true }, UNLOCKED)
	t.expectEq(s and s.maxPlayers, 4)
	t.expectEq(s and s.mapId, "map1")
	t.expectEq(s and s.friendsOnly, true)
end

function tests.rejects_bad_types_and_ranges(t)
	t.expectEq(SessionRules.validate(nil, UNLOCKED), nil)
	t.expectEq(SessionRules.validate("x", UNLOCKED), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 0, mapId = "map1", friendsOnly = false }, UNLOCKED), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 11, mapId = "map1", friendsOnly = false }, UNLOCKED), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 2.5, mapId = "map1", friendsOnly = false }, UNLOCKED), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 0 / 0, mapId = "map1", friendsOnly = false }, UNLOCKED), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 2, mapId = "map1", friendsOnly = "yes" }, UNLOCKED), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 2, mapId = 1, friendsOnly = false }, UNLOCKED), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 2, friendsOnly = false }, UNLOCKED), nil)
end

function tests.map_must_be_unlocked_by_host(t)
	t.expectEq(SessionRules.validate({ maxPlayers = 2, mapId = "map2", friendsOnly = false }, UNLOCKED), nil)
	t.expectEq(SessionRules.validate({ maxPlayers = 2, mapId = "map9", friendsOnly = false }, UNLOCKED), nil)
	local both = { map1 = true, map2 = true }
	t.expectEq(SessionRules.validate({ maxPlayers = 2, mapId = "map2", friendsOnly = false }, both).mapId, "map2")
end

function tests.load_needs_exactly_the_team(t)
	t.expectEq(SessionRules.loadError({ 11, 22 }, { 11, 22 }), nil)
	t.expectEq(SessionRules.loadError({ 11, 22 }, { 22, 11 }), nil)
	t.expectEq(SessionRules.loadError({ 11 }, { 11 }), nil)
end

function tests.load_says_who_is_missing(t)
	local reason, who = SessionRules.loadError({ 11, 22, 33 }, { 11 })
	t.expectEq(reason, "missing")
	t.expectEq(who and #who, 2)
	t.expectEq(who and who[1], 22)
	t.expectEq(who and who[2], 33)
	-- someone missing and someone extra: who is missing comes first
	reason, who = SessionRules.loadError({ 11, 22 }, { 11, 44 })
	t.expectEq(reason, "missing")
	t.expectEq(who and who[1], 22)
end

function tests.load_says_who_must_step_off(t)
	local reason, who = SessionRules.loadError({ 11 }, { 11, 44 })
	t.expectEq(reason, "extra")
	t.expectEq(who and #who, 1)
	t.expectEq(who and who[1], 44)
	t.expectEq(SessionRules.loadError({ 11, 22 }, { 11, 22, 11 }), nil)
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
