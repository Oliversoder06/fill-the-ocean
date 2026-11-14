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

-- The team a new party would be for (padIds: the host first): the host alone for a solo party, or
-- everyone on the pad when 2 to maxPlayers stand there; nil when it can't be known yet.
function tests.new_team_is_the_host_alone_for_solo(t)
	local team = SessionRules.newTeam(1, { 11, 22 })
	t.expectEq(team and table.concat(team, ","), "11")
	t.expectEq(SessionRules.newTeam(1, {}), nil)
end

function tests.new_team_needs_two_to_max_on_the_pad(t)
	local team = SessionRules.newTeam(3, { 11, 22 })
	t.expectEq(team and table.concat(team, ","), "11,22")
	t.expectEq(SessionRules.newTeam(3, { 11 }), nil, "a party of 3 with only the host is no team yet")
	t.expectEq(SessionRules.newTeam(2, { 11, 22, 33 }), nil, "more on the pad than the party holds")
end

-- One save per map per team: the saved run a new party would start over.
function tests.saved_for_finds_the_same_map_and_team(t)
	local runs = {
		{ mapId = "map1", memberIds = { 11, 22 } },
		{ mapId = "map2", memberIds = { 11 } },
		{ mapId = "map1", memberIds = { 11 } },
	}
	t.expectEq(SessionRules.savedFor(runs, "map1", { 11 }), 3)
	t.expectEq(SessionRules.savedFor(runs, "map1", { 22, 11 }), 1, "any order")
	t.expectEq(SessionRules.savedFor(runs, "map2", { 11 }), 2)
	t.expectEq(SessionRules.savedFor(runs, "map2", { 11, 22 }), nil, "another team")
	t.expectEq(SessionRules.savedFor(runs, "map1", { 11, 22, 33 }), nil, "an extra player")
	t.expectEq(SessionRules.savedFor(runs, "map1", nil), nil, "no team yet")
	t.expectEq(SessionRules.savedFor({}, "map1", { 11 }), nil)
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

local function pad(overrides: { [string]: any })
	local p: { [string]: any } = { host = true, saved = false, maxPlayers = 4, friendsOnly = false, count = 1, counting = false, launching = false }
	for k, v in overrides do
		p[k] = v
	end
	return p :: any
end

function tests.pad_state_open_without_host(t)
	t.expectEq(SessionRules.padState({ host = false, saved = false, friendsOnly = false, count = 0, counting = false, launching = false }), "open")
end

function tests.pad_state_setup_while_host_chooses(t)
	-- no maxPlayers: the host hasn't created a party yet
	t.expectEq(SessionRules.padState({ host = true, saved = false, friendsOnly = false, count = 1, counting = false, launching = false }), "setup")
end

function tests.pad_state_party_while_joinable(t)
	t.expectEq(SessionRules.padState(pad({ count = 2 })), "party")
end

function tests.pad_state_closed_when_friends_only_or_full(t)
	t.expectEq(SessionRules.padState(pad({ friendsOnly = true })), "closed")
	t.expectEq(SessionRules.padState(pad({ count = 4 })), "closed")
end

function tests.pad_state_saved_for_a_saved_team(t)
	t.expectEq(SessionRules.padState(pad({ saved = true, maxPlayers = 3 })), "saved")
end

function tests.pad_state_counting_beats_everything(t)
	t.expectEq(SessionRules.padState(pad({ counting = true, launching = true })), "counting")
	t.expectEq(SessionRules.padState(pad({ counting = true, saved = true, launching = true })), "counting")
end

function tests.pad_state_launching_beats_the_rest(t)
	t.expectEq(SessionRules.padState(pad({ launching = true })), "launching")
	t.expectEq(SessionRules.padState(pad({ launching = true, saved = true })), "launching")
end

function tests.countdown_is_a_few_seconds(t)
	t.expectEq(type(SessionRules.COUNTDOWN), "number")
	t.expectEq(SessionRules.COUNTDOWN >= 2 and SessionRules.COUNTDOWN <= 5, true)
end

return tests
