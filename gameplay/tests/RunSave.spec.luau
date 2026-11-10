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

function tests.key_fits_datastore_limit(t)
	local function ids(first: number, n: number): { number }
		local list = {}
		for i = 1, n do
			table.insert(list, first + i * 7919)
		end
		return list
	end
	local four = ids(1000000000, 4)
	t.expectEq(RunSave.key("map1", four), `map1_{table.concat(four, "_")}`, "a team that fits keeps the readable key")
	local ten = ids(1000000000, 10)
	local key = RunSave.key("map1", ten)
	t.expectEq(#key <= 50, true, `key of {#key} chars is over the DataStore limit`)
	t.expectEq(string.sub(key, 1, 5), "map1_", "map stays in the key")
	local reversed = {}
	for i = #ten, 1, -1 do
		table.insert(reversed, ten[i])
	end
	t.expectEq(RunSave.key("map1", reversed), key, "still order-independent")
	t.expectEq(RunSave.key("map1", ids(1000000001, 10)) == key, false, "a different team gets a different key")
	t.expectEq(RunSave.key("map2", ten) == key, false, "a different map gets a different key")
	t.expectEq(#RunSave.key("map1", ids(9000000000, 5)) <= 50, true, "five ten-digit ids fit")
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
	t.expectEq(save.version, 2)
	t.expectEq(save.mapId, "ocean1")
	t.expectEq(#save.members, 2, "members kept")
	t.expectEq(save.members[1], 10)
	t.expectEq(save.members[2], 20)
	t.expectEq(save.current, 0, "negative clamped")
	t.expectEq(count(save.players), 1, "only well-formed player entries kept")
	local player = save.players["10"]
	t.expectEq(player.litres, 0, "NaN litres")
	t.expectEq((player :: any).money, nil, "money moved to the team")
	t.expectEq((player :: any).extra, nil, "unknown player field dropped")
	t.expectEq(save.team.wallet, 0, "negative money clamped")
	t.expectEq(save.team.levels.tool, 3)
	t.expectEq(save.team.levels.walk, 0, "negative level clamped")
	t.expectEq(count(save.team.levels), 2, "bad level entries dropped")
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
	fresh.players["1"] = { litres = 12.5 }
	fresh.team.wallet = 300
	fresh.team.levels = { tool = 2 }
	fresh.boostsPlayed = { "tide" }
	fresh.introSeen = true
	fresh.updatedAt = 1700000000
	local again = RunSave.sanitize(fresh)
	assert(again, "a valid save must survive sanitize")
	t.expectEq(again.current, 12.5)
	t.expectEq(again.players["1"].litres, 12.5)
	t.expectEq(again.team.wallet, 300)
	t.expectEq(again.team.levels.tool, 2)
	t.expectEq(again.introSeen, true)
	t.expectEq(again.boostsPlayed[1], "tide")
	t.expectEq(again.updatedAt, 1700000000)
end

-- Only gates 2-5 can be open, each once; the cove (1) has no gate.
function tests.sanitize_gates(t)
	local save = RunSave.sanitize({ mapId = "ocean1", members = { 1 }, gatesOpen = { 3, 2, 3, 1, 6, 2.5, "4", 0 / 0, 5 } })
	assert(save, "sanitize returned nil for a repairable save")
	t.expectEq(table.concat(save.gatesOpen, ","), "3,2,5")
	local broken = RunSave.sanitize({ mapId = "ocean1", members = { 1 }, gatesOpen = "all" })
	assert(broken, "a bad gatesOpen must not drop the save")
	t.expectEq(#broken.gatesOpen, 0)
	local fresh = RunSave.new("ocean1", { 1 })
	fresh.gatesOpen = { 2, 3 }
	local again = RunSave.sanitize(fresh)
	assert(again, "a valid save must survive sanitize")
	t.expectEq(table.concat(again.gatesOpen, ","), "2,3")
end

-- Milestones reached (indices into Config.milestones), each once; a save from before milestones has
-- none recorded (nil), so the server can mark those below its fill without granting them.
function tests.sanitize_milestones(t)
	local save = RunSave.sanitize({ mapId = "map1", members = { 1 }, milestones = { 2, 1, 2, 0, -3, 1.5, "4", 0 / 0, math.huge, 5 } })
	assert(save, "sanitize returned nil for a repairable save")
	t.expectEq(table.concat(save.milestones :: { number }, ","), "2,1,5")
	local old = RunSave.sanitize({ mapId = "map1", members = { 1 }, current = 900 })
	assert(old, "an old save must load")
	t.expectEq(old.milestones, nil, "from before milestones")
	local broken = RunSave.sanitize({ mapId = "map1", members = { 1 }, milestones = "all" })
	assert(broken, "a bad milestones field must not drop the save")
	t.expectEq(broken.milestones, nil)
	local fresh = RunSave.new("map1", { 1 })
	t.expectEq(#(fresh.milestones :: { number }), 0, "a new run has reached none")
	fresh.milestones = { 1, 2 }
	local again = RunSave.sanitize(fresh)
	assert(again, "a valid save must survive sanitize")
	t.expectEq(table.concat(again.milestones :: { number }, ","), "1,2")
	t.expectEq(#(RunSave.blank(fresh, 0).milestones :: { number }), 0, "erasing forgets them")
end

-- Broken rocks (deeper pools, areas 1-5), each once; a save from before rocks loads with none.
function tests.sanitize_rocks(t)
	local save = RunSave.sanitize({ mapId = "ocean1", members = { 1 }, rocksBroken = { 3, 1, 3, 6, 0, 2.5, "4", 0 / 0, 5 } })
	assert(save, "sanitize returned nil for a repairable save")
	t.expectEq(table.concat(save.rocksBroken, ","), "3,1,5")
	local old = RunSave.sanitize({ mapId = "ocean1", members = { 1 } })
	assert(old, "an old save must load")
	t.expectEq(#old.rocksBroken, 0, "no rocks broken in an old save")
	t.expectEq(#RunSave.new("ocean1", { 1 }).rocksBroken, 0, "a new run has every rock")
end

-- The team's items and buildings: ids are strings, levels whole and never negative.
function tests.sanitize_items(t)
	local save = RunSave.sanitize({
		mapId = "ocean1",
		members = { 1 },
		team = {
			wallet = 5,
			owned = { "backpackTank", 7, "bigTank", "backpackTank", true },
			itemLevels = { backpackTank = 2.7, bigTank = -1, [3] = 1, twinTanks = "x" },
		},
		buildings = { pump = 1, tower = -4, [2] = 1, rain = 0 / 0 },
	})
	assert(save, "sanitize returned nil for a repairable save")
	t.expectEq(table.concat(save.team.owned, ","), "backpackTank,bigTank", "strings, each once")
	t.expectEq(save.team.itemLevels.backpackTank, 2)
	t.expectEq(save.team.itemLevels.bigTank, 0, "negative level clamped")
	t.expectEq(count(save.team.itemLevels), 2, "bad level entries dropped")
	t.expectEq(save.buildings.pump, 1)
	t.expectEq(save.buildings.tower, 0)
	t.expectEq(save.buildings.rain, 0, "NaN level")
	t.expectEq(count(save.buildings), 3, "bad building entries dropped")

	-- A save from before items loads with none.
	local old = RunSave.sanitize({ mapId = "ocean1", members = { 1 }, players = { ["1"] = { money = 5, levels = { tool = 1 }, litres = 2 } } })
	assert(old, "an old save must load")
	t.expectEq(#old.team.owned, 0)
	t.expectEq(count(old.team.itemLevels), 0)
	t.expectEq(count(old.buildings), 0)
	local broken = RunSave.sanitize({ mapId = "ocean1", members = { 1 }, team = { owned = "all", itemLevels = 3, wallet = "lots" }, buildings = "many" })
	assert(broken, "bad item fields must not drop the save")
	t.expectEq(#broken.team.owned, 0)
	t.expectEq(count(broken.team.itemLevels), 0)
	t.expectEq(broken.team.wallet, 0)
	t.expectEq(count(broken.buildings), 0)

	local fresh = RunSave.new("ocean1", { 1 })
	fresh.team.owned = { "bigTank" }
	fresh.team.itemLevels = { bigTank = 1 }
	fresh.buildings = { pump = 2 }
	local again = RunSave.sanitize(fresh)
	assert(again, "a valid save must survive sanitize")
	t.expectEq(again.team.owned[1], "bigTank")
	t.expectEq(again.team.itemLevels.bigTank, 1)
	t.expectEq(again.buildings.pump, 2)
end

-- A save from before the team economy (2026-11-10) kept money, levels and items per player: the
-- team gets the money added up, the best level of each, every item anyone had, and each staff's post
-- from the first member (lowest user id) who set one.
function tests.sanitize_migrates_per_player_saves(t)
	local save = RunSave.sanitize({
		mapId = "ocean1",
		members = { 20, 10 },
		players = {
			["20"] = { money = 500, levels = { tool = 2, walk = 4 }, litres = 30, owned = { "bigTank", "waterGun" }, itemLevels = { bigTank = 1, waterGun = 2 }, assign = { helper = 3 } },
			["10"] = { money = 1200.5, levels = { tool = 5, quick = 1 }, litres = 70, owned = { "waterGun", "helper" }, itemLevels = { waterGun = 1, helper = 2 }, assign = { helper = 2, lifeguard = 4 } },
		},
	})
	assert(save, "an old save must load")
	t.expectEq(save.team.wallet, 1700.5, "the members' money added up")
	t.expectEq(save.team.levels.tool, 5, "the best tool level")
	t.expectEq(save.team.levels.walk, 4)
	t.expectEq(save.team.levels.quick, 1)
	t.expectEq(count(save.team.levels), 3)
	t.expectEq(table.concat(save.team.owned, ","), "waterGun,helper,bigTank", "every item once, first member first")
	t.expectEq(save.team.itemLevels.bigTank, 1)
	t.expectEq(save.team.itemLevels.waterGun, 2, "the best level of each")
	t.expectEq(save.team.itemLevels.helper, 2)
	t.expectEq(save.team.assign.helper, 2, "the first member's post")
	t.expectEq(save.team.assign.lifeguard, 4)
	t.expectEq(save.players["10"].litres, 70, "litres stay each player's")
	t.expectEq(save.players["20"].litres, 30)
	t.expectEq((save.players["10"] :: any).money, nil, "nothing else stays per player")
	t.expectEq((save.players["10"] :: any).owned, nil)
end

-- Version 2 is the team economy: a version 1 save migrates and is written back as 2; a save from
-- newer code than this is refused (nil and why), never repaired into a wiped run.
function tests.sanitize_versions(t)
	t.expectEq(RunSave.VERSION, 2)
	local old = RunSave.sanitize({ version = 1, mapId = "ocean1", members = { 1 }, players = { ["1"] = { money = 50, litres = 4 } } })
	assert(old, "a version 1 save must load")
	t.expectEq(old.version, 2, "written back as version 2")
	t.expectEq(old.team.wallet, 50, "migrated as before")
	local same = RunSave.sanitize({ version = 2, mapId = "ocean1", members = { 1 }, team = { wallet = 7 } })
	assert(same, "a version 2 save must load")
	t.expectEq(same.team.wallet, 7)
	local newer, why = RunSave.sanitize({ version = 3, mapId = "ocean1", members = { 1 }, team = { wallet = 7 } })
	t.expectEq(newer, nil, "a newer save is refused")
	t.expectEq(type(why), "string", "with a reason")
	t.expectEq((RunSave.sanitize({ version = math.huge, mapId = "ocean1", members = { 1 } })), nil, "infinitely new")
end

-- Only the save's members' old fields reach the team: a stray player entry adds nothing.
function tests.migration_merges_only_members(t)
	local save = RunSave.sanitize({
		mapId = "ocean1",
		members = { 10 },
		players = {
			["10"] = { money = 100, levels = { tool = 1 }, litres = 5 },
			["30"] = { money = 9000, levels = { tool = 9 }, litres = 1, owned = { "bigTank" }, assign = { helper = 2 } },
		},
	})
	assert(save, "an old save must load")
	t.expectEq(save.team.wallet, 100, "a non-member's money stays out")
	t.expectEq(save.team.levels.tool, 1)
	t.expectEq(#save.team.owned, 0)
	t.expectEq(count(save.team.assign), 0)
end

-- copyTeam: a deep copy of every team field, so a save in flight never shares tables with play.
function tests.copy_team_is_deep(t)
	local team = RunSave.newTeam()
	team.wallet = 12.5
	team.levels = { tool = 2 }
	team.owned = { "bigTank" }
	team.itemLevels = { bigTank = 1 }
	team.assign = { helper = 3 }
	local copy = RunSave.copyTeam(team)
	for field, value in team :: any do
		if type(value) == "table" then
			t.expectEq((copy :: any)[field] ~= value, true, `{field} is a new table`)
			for k, v in value do
				t.expectEq((copy :: any)[field][k], v, `{field}.{k} copied`)
			end
		else
			t.expectEq((copy :: any)[field], value, `{field} copied`)
		end
	end
	t.expectEq(count(copy), count(team), "no field missing or added")
	copy.wallet = 0
	copy.levels.tool = 9
	table.insert(copy.owned, "twinTanks")
	copy.itemLevels.bigTank = 5
	copy.assign.helper = 1
	t.expectEq(team.wallet, 12.5, "the original is untouched")
	t.expectEq(team.levels.tool, 2)
	t.expectEq(#team.owned, 1)
	t.expectEq(team.itemLevels.bigTank, 1)
	t.expectEq(team.assign.helper, 3)
end

-- Once a save has a team section, left-over per-player fields don't add to it again.
function tests.sanitize_team_section_wins(t)
	local save = RunSave.sanitize({
		mapId = "ocean1",
		members = { 1 },
		team = { wallet = 40, levels = { tool = 1 } },
		players = { ["1"] = { money = 999, levels = { tool = 9 }, litres = 3, owned = { "bigTank" } } },
	})
	assert(save, "sanitize returned nil for a repairable save")
	t.expectEq(save.team.wallet, 40)
	t.expectEq(save.team.levels.tool, 1)
	t.expectEq(#save.team.owned, 0)
	t.expectEq(save.players["1"].litres, 3)
end

function tests.new_save_has_an_empty_team(t)
	local save = RunSave.new("ocean1", { 1, 2 })
	t.expectEq(save.team.wallet, 0)
	t.expectEq(count(save.team.levels), 0)
	t.expectEq(#save.team.owned, 0)
	t.expectEq(count(save.team.itemLevels), 0)
	t.expectEq(count(save.team.assign), 0)
	save.team.wallet = 50
	save.team.owned = { "bigTank" }
	local blank = RunSave.blank(save, 10)
	t.expectEq(blank.team.wallet, 0, "erasing a run empties the wallet")
	t.expectEq(#blank.team.owned, 0)
end

-- Which building stands on which plot: plot numbers as string keys, building ids as values.
function tests.sanitize_plots(t)
	local save = RunSave.sanitize({
		mapId = "ocean1",
		members = { 1 },
		plots = { ["1"] = "pump", ["3"] = "waterTower", ["0"] = "pump", ["2.5"] = "pump", x = "pump", [4] = "pump", ["5"] = 7, ["6"] = "" },
	})
	assert(save, "sanitize returned nil for a repairable save")
	t.expectEq(save.plots["1"], "pump")
	t.expectEq(save.plots["3"], "waterTower")
	t.expectEq(count(save.plots), 2, "bad plot entries dropped")
	local old = RunSave.sanitize({ mapId = "ocean1", members = { 1 } })
	assert(old, "an old save must load")
	t.expectEq(count(old.plots), 0, "no plots built in an old save")
	t.expectEq(count(RunSave.new("ocean1", { 1 }).plots), 0, "a new run has empty plots")
	local broken = RunSave.sanitize({ mapId = "ocean1", members = { 1 }, plots = "all" })
	assert(broken, "bad plots must not drop the save")
	t.expectEq(count(broken.plots), 0)
end

-- 3f: where each of the team's staff works (staff item id -> area id 1-5).
function tests.sanitize_staff_assignments(t)
	local save = RunSave.sanitize({
		mapId = "ocean1",
		members = { 1 },
		team = { assign = { helper = 2, lifeguard = 3.5, plumber = 1, firefighter = 6, x = 0, [2] = 2, y = "2", z = 0 / 0 } },
	})
	assert(save, "sanitize returned nil for a repairable save")
	local assign = save.team.assign
	t.expectEq(assign.helper, 2)
	t.expectEq(assign.plumber, 1)
	t.expectEq(count(assign), 2, "areas are whole numbers 1-5 by string id")
	local old = RunSave.sanitize({ mapId = "ocean1", members = { 1 }, players = { ["1"] = { money = 5 } } })
	assert(old, "an old save must load")
	t.expectEq(count(old.team.assign), 0, "a save from before staff has no assignments")
	local broken = RunSave.sanitize({ mapId = "ocean1", members = { 1 }, team = { assign = "all" } })
	assert(broken, "bad assignments must not drop the save")
	t.expectEq(count(broken.team.assign), 0)
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
	t.expectEq(save.version, 2)
	t.expectEq(save.mapId, "ocean1")
	t.expectEq(#save.members, 2, "deduplicated")
	t.expectEq(save.members[1], 10, "sorted")
	t.expectEq(save.members[2], 20)
	t.expectEq(save.current, 0)
	t.expectEq(count(save.players), 0)
	t.expectEq(save.playSeconds, 0)
	t.expectEq(save.introSeen, false)
	t.expectEq(#save.boostsPlayed, 0)
	t.expectEq(#save.gatesOpen, 0, "no gate open")
	t.expectEq(count(save.buildings), 0, "no building")
	t.expectEq(save.finished, false)
	t.expectEq(save.updatedAt, 0)
end

-- Erasing a run (New Game, Delete, admin resets) leaves a blank save of the same map and team,
-- stamped newer than the old one so an older write can't land over it.
function tests.blank_keeps_map_and_team_and_is_newer(t)
	local old = RunSave.new("map1", { 20, 10 })
	old.current = 500
	old.players["10"] = { money = 9, levels = { tool = 2 }, litres = 500, owned = { "bigTank" }, itemLevels = {}, assign = {} }
	old.gatesOpen = { 2 }
	old.buildings = { pump = 1 }
	old.plots = { ["1"] = "pump" }
	old.rocksBroken = { 1 }
	old.boostsPlayed = { "tide" }
	old.playSeconds = 3600
	old.introSeen = true
	old.finished = true
	old.updatedAt = 1000
	local blank = RunSave.blank(old, 900)
	t.expectEq(blank.mapId, "map1")
	t.expectEq(table.concat(blank.members, ","), "10,20")
	t.expectEq(blank.updatedAt, 1001, "newer than the old save even with a clock behind")
	t.expectEq(RunSave.blank(old, 5000).updatedAt, 5000, "now when the clock is ahead")
	t.expectEq(blank.current, 0)
	t.expectEq(count(blank.players), 0)
	t.expectEq(#blank.gatesOpen, 0)
	t.expectEq(count(blank.buildings), 0)
	t.expectEq(count(blank.plots), 0)
	t.expectEq(#blank.rocksBroken, 0)
	t.expectEq(#blank.boostsPlayed, 0)
	t.expectEq(blank.playSeconds, 0)
	t.expectEq(blank.finished, false)
	t.expectEq(old.current, 500, "the old save is untouched")
	t.expectEq(old.players["10"].money, 9)
end

function tests.only_unplayed_saves_are_blank(t)
	t.expectEq(RunSave.isBlank(RunSave.new("map1", { 1 })), true)
	local old = RunSave.new("map1", { 1 })
	old.updatedAt = 50
	t.expectEq(RunSave.isBlank(RunSave.blank(old, 60)), true)
	local played = RunSave.new("map1", { 1 })
	played.players["1"] = { money = 0, levels = {}, litres = 0, owned = {}, itemLevels = {}, assign = {} }
	t.expectEq(RunSave.isBlank(played), false, "someone played it")
	local filled = RunSave.new("map1", { 1 })
	filled.current = 1
	t.expectEq(RunSave.isBlank(filled), false, "water in it")
	local timed = RunSave.new("map1", { 1 })
	timed.playSeconds = 2
	t.expectEq(RunSave.isBlank(timed), false, "time played")
	local done = RunSave.new("map1", { 1 })
	done.finished = true
	t.expectEq(RunSave.isBlank(done), false, "finished")
end

-- A write lands only over an older stamp: an erase's blank stamped in the same second as a late
-- gameplay write must win.
function tests.write_lands_only_over_an_older_stamp(t)
	t.expectEq(RunSave.storedNewer(nil, 100), false, "nothing stored")
	t.expectEq(RunSave.storedNewer({ updatedAt = 99 }, 100), false, "older stamp")
	t.expectEq(RunSave.storedNewer({ updatedAt = 100 }, 100), true, "same second")
	t.expectEq(RunSave.storedNewer({ updatedAt = 101 }, 100), true, "newer stamp")
	t.expectEq(RunSave.storedNewer({ updatedAt = "101" }, 100), false, "no readable stamp")
	t.expectEq(RunSave.storedNewer("broken", 100), false, "not a save")
end

return tests
