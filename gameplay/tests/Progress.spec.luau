local Progress = require("../../common/Progress")

local tests = {}

local function keys(n: number): { string }
	local list = {}
	for i = 1, n do
		table.insert(list, `map1_{i}`)
	end
	return list
end

function tests.defaults_are_empty(t)
	local d = Progress.sanitize(nil)
	t.expectEq(d.raindrops, 0)
	t.expectEq(#d.runs, 0)
	t.expectEq(next(d.mapsCleared), nil)
end

function tests.sanitize_repairs_bad_fields(t)
	local s = Progress.sanitize({
		raindrops = -5,
		runs = { "map1_1", 7, "", "map1_2", "map1_1" },
		mapsCleared = { map1 = true, map2 = "yes", [3] = true },
		extra = 1,
	})
	t.expectEq(s.raindrops, 0)
	t.expectEq(#s.runs, 2, "only non-empty strings, each once")
	t.expectEq(s.runs[1], "map1_1")
	t.expectEq(s.runs[2], "map1_2")
	t.expectEq(s.mapsCleared.map1, true)
	t.expectEq(s.mapsCleared.map2, nil)
	t.expectEq(s.mapsCleared[3], nil)
	t.expectEq((s :: any).extra, nil)
	t.expectEq(Progress.sanitize({ raindrops = 12.9 }).raindrops, 12)
end

function tests.old_saves_with_unlocked_still_sanitize(t)
	local s = Progress.sanitize({ raindrops = 40, unlocked = 3, runs = 4 })
	t.expectEq(s.raindrops, 40)
	t.expectEq((s :: any).unlocked, nil, "the difficulty field is dropped")
	t.expectEq(#s.runs, 0, "the old run count is not a list of keys")
	t.expectEq(next(s.mapsCleared), nil)
end

function tests.sanitize_keeps_the_newest_ten_runs(t)
	local s = Progress.sanitize({ runs = keys(12) })
	t.expectEq(#s.runs, Progress.MAX_RUNS)
	t.expectEq(Progress.MAX_RUNS, 10)
	t.expectEq(s.runs[1], "map1_1")
	t.expectEq(s.runs[10], "map1_10")
end

function tests.add_run_puts_the_key_first(t)
	local after = Progress.addRun({ runs = { "map1_1", "map1_2" } }, "map1_3")
	t.expectEq(#after.runs, 3)
	t.expectEq(after.runs[1], "map1_3")
	t.expectEq(after.runs[2], "map1_1")
	t.expectEq(after.runs[3], "map1_2")
end

function tests.add_run_moves_a_known_key_first(t)
	local after = Progress.addRun({ runs = { "map1_1", "map1_2", "map1_3" } }, "map1_3")
	t.expectEq(#after.runs, 3, "no duplicate")
	t.expectEq(after.runs[1], "map1_3")
	t.expectEq(after.runs[2], "map1_1")
	t.expectEq(after.runs[3], "map1_2")
end

function tests.add_run_drops_the_oldest_past_ten(t)
	local after = Progress.addRun({ runs = keys(10) }, "map1_new")
	t.expectEq(#after.runs, 10)
	t.expectEq(after.runs[1], "map1_new")
	t.expectEq(after.runs[10], "map1_9", "map1_10 was the oldest")
	t.expectEq(table.find(after.runs, "map1_10"), nil)
end

function tests.add_run_keeps_other_fields(t)
	local after = Progress.addRun({ raindrops = 30, mapsCleared = { map1 = true } }, "map2_1")
	t.expectEq(after.raindrops, 30)
	t.expectEq(after.mapsCleared.map1, true)
end

function tests.remove_run_drops_only_that_key(t)
	local after = Progress.removeRun({ raindrops = 5, runs = { "map1_1", "map1_2", "map1_3" } }, "map1_2")
	t.expectEq(#after.runs, 2)
	t.expectEq(after.runs[1], "map1_1")
	t.expectEq(after.runs[2], "map1_3")
	t.expectEq(after.raindrops, 5)
end

function tests.remove_unknown_run_changes_nothing(t)
	local after = Progress.removeRun({ runs = { "map1_1" } }, "map1_9")
	t.expectEq(#after.runs, 1)
	t.expectEq(after.runs[1], "map1_1")
	t.expectEq(#Progress.removeRun(nil, "map1_1").runs, 0)
end

-- An erased run (New Game, Delete) leaves the list and its payment, so the fresh run on the same
-- key pays its Raindrops when it fills.
function tests.forget_run_drops_the_key_and_its_payment(t)
	local raw = { raindrops = 7, runs = { "map1_1", "map1_2" }, mapsCleared = { map1 = true }, paidRuns = { map1_1 = true, map1_2 = true } }
	local after = Progress.forgetRun(raw, "map1_1")
	t.expectEq(table.concat(after.runs, ","), "map1_2")
	t.expectEq(after.paidRuns.map1_1, nil)
	t.expectEq(after.paidRuns.map1_2, true, "other runs stay paid")
	t.expectEq(after.raindrops, 7, "Raindrops already paid are kept")
	t.expectEq(after.mapsCleared.map1, true, "a cleared map stays cleared")
	t.expectEq(#raw.runs, 2, "a new table")
	t.expectEq(raw.paidRuns.map1_1, true)
	t.expectEq(Progress.isPaid(Progress.forgetRun(nil, "map1_1"), "map1_1"), false)
end

function tests.clear_map_adds_raindrops_and_marks_the_map(t)
	local after = Progress.clearMap({ raindrops = 10, runs = { "map1_1" } }, "map1", 100, "map1_1")
	t.expectEq(after.raindrops, 110)
	t.expectEq(after.mapsCleared.map1, true)
	t.expectEq(after.paidRuns.map1_1, true, "the run is marked paid")
	t.expectEq(after.runs[1], "map1_1", "clearing a map keeps the run list")
	local again = Progress.clearMap(after, "map1", 100, "map1_1_2")
	t.expectEq(again.raindrops, 210, "a replay (another run) still pays")
	t.expectEq(again.mapsCleared.map1, true)
end

function tests.clear_map_pays_each_run_once(t)
	local after = Progress.clearMap({ raindrops = 10 }, "map1", 100, "map1_1")
	local again = Progress.clearMap(after, "map1", 100, "map1_1")
	t.expectEq(again.raindrops, 110, "the same run's ending again pays nothing")
	t.expectEq(again.mapsCleared.map1, true)
	t.expectEq(Progress.isPaid(again, "map1_1"), true)
	t.expectEq(Progress.isPaid(again, "map1_2"), false)
end

function tests.sanitize_keeps_paid_runs(t)
	local s = Progress.sanitize({ paidRuns = { map1_1 = true, map1_2 = "yes", [3] = true, [""] = true } })
	t.expectEq(s.paidRuns.map1_1, true)
	t.expectEq(s.paidRuns.map1_2, nil)
	t.expectEq(s.paidRuns[3], nil)
	t.expectEq(s.paidRuns[""], nil)
	t.expectEq(next(Progress.sanitize(nil).paidRuns), nil)
end

function tests.clear_map_ignores_bad_raindrops(t)
	t.expectEq(Progress.clearMap({ raindrops = 10 }, "map1", -50, "map1_1").raindrops, 10)
	t.expectEq(Progress.clearMap({ raindrops = 10 }, "map1", 2.7, "map1_1").raindrops, 12)
end

function tests.milestones_pay_each_run_once(t)
	local raw = { raindrops = 10 }
	local after = Progress.payMilestones(raw, "map1_1", { [2] = 5, [7] = 10 })
	t.expectEq(after.raindrops, 25)
	t.expectEq(raw.raindrops, 10, "a new table")
	after = Progress.payMilestones(after, "map1_1", { [2] = 5, [12] = 15 })
	t.expectEq(after.raindrops, 40, "milestone 2 paid already: only 12")
	after = Progress.payMilestones(after, "map1_2", { [2] = 5 })
	t.expectEq(after.raindrops, 45, "another run pays its own")
	t.expectEq(Progress.payMilestones(after, "map1_1", { [3] = -5 }).raindrops, 45, "never takes Raindrops")
	t.expectEq(Progress.payMilestones(after, "map1_1", { [3] = 2.7 }).raindrops, 47)
end

-- payMilestones' second result: whether it recorded anything new (PlayerData writes only then).
function tests.milestones_say_when_nothing_is_new(t)
	local paid, changed = Progress.payMilestones(nil, "map1_1", { [2] = 5 })
	t.expectEq(changed, true)
	local again, changedAgain = Progress.payMilestones(paid, "map1_1", { [2] = 5 })
	t.expectEq(changedAgain, false, "all paid already")
	t.expectEq(again.raindrops, 5)
	local _, empty = Progress.payMilestones(paid, "map1_1", {})
	t.expectEq(empty, false, "nothing to pay")
	local _, other = Progress.payMilestones(paid, "map1_2", { [2] = 5 })
	t.expectEq(other, true, "another run")
end

function tests.paid_milestones_survive_sanitize_and_forget(t)
	local paid = Progress.payMilestones(nil, "map1_1", { [2] = 5 })
	paid = Progress.payMilestones(paid, "map1_2", { [2] = 5 })
	local again = Progress.sanitize(paid)
	t.expectEq(Progress.payMilestones(again, "map1_1", { [2] = 5 }).raindrops, 10, "still paid after a load")
	local bad = Progress.sanitize({ paidMilestones = { map1_1 = { 2, "3", 0, 1.5, 2 }, [""] = { 1 }, map1_2 = "x" } })
	t.expectEq(table.concat(bad.paidMilestones.map1_1, ","), "2")
	t.expectEq(bad.paidMilestones[""], nil)
	t.expectEq(bad.paidMilestones.map1_2, nil)
	local forgot = Progress.forgetRun(paid, "map1_1")
	t.expectEq(Progress.payMilestones(forgot, "map1_1", { [2] = 5 }).raindrops, 10, "a New Game on the same run key can't earn them again")
	t.expectEq(Progress.payMilestones(forgot, "map1_2", { [2] = 5 }).raindrops, 10, "other runs stay paid")
	t.expectEq(next(Progress.default().paidMilestones), nil, "only a profile reset (Progress.default) clears them")
end

function tests.changes_return_new_tables(t)
	local raw = { raindrops = 1, runs = { "map1_1" }, mapsCleared = {} }
	Progress.addRun(raw, "map1_2")
	Progress.removeRun(raw, "map1_1")
	Progress.clearMap(raw, "map1", 5, "map1_1")
	t.expectEq(#raw.runs, 1)
	t.expectEq(raw.runs[1], "map1_1")
	t.expectEq(raw.raindrops, 1)
	t.expectEq(raw.mapsCleared.map1, nil)
end

return tests
