local RunSave = require("../../common/RunSave")

local tests = {}

local function count(map: { [any]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

function tests.key_is_order_independent(t)
	t.expectEq(RunSave.key("ocean1", { 30, 10, 20 }), "ocean1_10_20_30")
	t.expectEq(RunSave.key("ocean1", { 20, 30, 10 }), RunSave.key("ocean1", { 10, 20, 30 }))
	t.expectEq(RunSave.key("ocean1", { 7 }), "ocean1_7")
	t.expectEq(RunSave.key("ocean2", { 10, 20 }) == RunSave.key("ocean1", { 10, 20 }), false, "map is part of the key")
end

function tests.same_team_needs_exactly_the_members(t)
	local save = RunSave.new("ocean1", { 1, 2, 3 })
	t.expectEq(RunSave.sameTeam(save, { 3, 1, 2 }), true, "same set in any order")
	t.expectEq(RunSave.sameTeam(save, { 1, 2 }), false, "a member missing")
	t.expectEq(RunSave.sameTeam(save, { 1, 2, 3, 4 }), false, "an extra player")
	t.expectEq(RunSave.sameTeam(save, { 1, 2, 2 }), false, "a duplicate in place of a member")
	t.expectEq(RunSave.sameTeam(save, { 1, 2, 3, 3 }), false, "a duplicate on top of the team")
	t.expectEq(RunSave.sameTeam(save, {}), false, "nobody")
end

function tests.sanitize_repairs_bad_fields(t)
	local save = RunSave.sanitize({
		version = "one",
		mapId = "ocean1",
		members = { 20, 10, 20, -1, 2.5, "30" },
		current = -40,
		players = {
			["10"] = { money = -5, levels = { tool = 3, walk = -2, quick = "x", [5] = 1 }, litres = 0 / 0, extra = true },
			["20"] = "broken",
			[30] = { money = 1, levels = {}, litres = 1 },
		},
		playSeconds = "long",
		introSeen = "yes",
		boostsPlayed = { "tide", 4, "surge" },
		finished = 1,
		updatedAt = -3,
		cheat = 99,
	})
	assert(save, "sanitize returned nil for a repairable save")
	t.expectEq(save.version, 1)
	t.expectEq(save.mapId, "ocean1")
	t.expectEq(#save.members, 2, "members kept")
	t.expectEq(save.members[1], 10)
	t.expectEq(save.members[2], 20)
	t.expectEq(save.current, 0, "negative clamped")
	t.expectEq(count(save.players), 1, "only well-formed player entries kept")
	local player = save.players["10"]
	t.expectEq(player.money, 0, "negative money clamped")
	t.expectEq(player.litres, 0, "NaN litres")
	t.expectEq(player.levels.tool, 3)
	t.expectEq(player.levels.walk, 0, "negative level clamped")
	t.expectEq(count(player.levels), 2, "bad level entries dropped")
	t.expectEq((player :: any).extra, nil, "unknown player field dropped")
	t.expectEq(save.playSeconds, 0)
	t.expectEq(save.introSeen, false)
	t.expectEq(#save.boostsPlayed, 2)
	t.expectEq(save.boostsPlayed[1], "tide")
	t.expectEq(save.boostsPlayed[2], "surge")
	t.expectEq(save.finished, false)
	t.expectEq(save.updatedAt, 0)
	t.expectEq((save :: any).cheat, nil, "unknown field dropped")

	local fresh = RunSave.new("ocean1", { 1 })
	fresh.current = 12.5
	fresh.players["1"] = { money = 300, levels = { tool = 2 }, litres = 12.5 }
	fresh.boostsPlayed = { "tide" }
	fresh.introSeen = true
	fresh.updatedAt = 1700000000
	local again = RunSave.sanitize(fresh)
	assert(again, "a valid save must survive sanitize")
	t.expectEq(again.current, 12.5)
	t.expectEq(again.players["1"].money, 300)
	t.expectEq(again.players["1"].levels.tool, 2)
	t.expectEq(again.introSeen, true)
	t.expectEq(again.boostsPlayed[1], "tide")
	t.expectEq(again.updatedAt, 1700000000)
end

function tests.sanitize_rejects_non_tables(t)
	t.expectEq(RunSave.sanitize(nil), nil)
	t.expectEq(RunSave.sanitize("save"), nil)
	t.expectEq(RunSave.sanitize(5), nil)
	t.expectEq(RunSave.sanitize(true), nil)
end

function tests.sanitize_rejects_saves_without_map_or_team(t)
	t.expectEq(RunSave.sanitize({ members = { 1 } }), nil, "no map")
	t.expectEq(RunSave.sanitize({ mapId = "", members = { 1 } }), nil, "empty map")
	t.expectEq(RunSave.sanitize({ mapId = "ocean1" }), nil, "no members")
	t.expectEq(RunSave.sanitize({ mapId = "ocean1", members = { -1, "2" } }), nil, "no valid members")
end

function tests.new_save_starts_empty(t)
	local save = RunSave.new("ocean1", { 20, 10, 20 })
	t.expectEq(save.version, 1)
	t.expectEq(save.mapId, "ocean1")
	t.expectEq(#save.members, 2, "deduplicated")
	t.expectEq(save.members[1], 10, "sorted")
	t.expectEq(save.members[2], 20)
	t.expectEq(save.current, 0)
	t.expectEq(count(save.players), 0)
	t.expectEq(save.playSeconds, 0)
	t.expectEq(save.introSeen, false)
	t.expectEq(#save.boostsPlayed, 0)
	t.expectEq(save.finished, false)
	t.expectEq(save.updatedAt, 0)
end

return tests
