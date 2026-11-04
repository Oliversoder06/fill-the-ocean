local Difficulty = require("../../common/Difficulty")
local Progress = require("../../common/Progress")

local tests = {}

function tests.level_one_is_normal(t)
	t.expectEq(Difficulty.waterMultiplier(1), 1)
	t.expectEq(Difficulty.rewardMultiplier(1), 1)
end

function tests.each_level_scales(t)
	t.expectNear(Difficulty.waterMultiplier(3), 1.96, 1e-9)
	t.expectNear(Difficulty.rewardMultiplier(3), 2.25, 1e-9)
	t.expectNear(Difficulty.waterMultiplier(5), 1.4 ^ 4, 1e-9)
end

function tests.clamp_rejects_bad_input(t)
	t.expectEq(Difficulty.clamp(nil), 1)
	t.expectEq(Difficulty.clamp("3"), 1)
	t.expectEq(Difficulty.clamp(0 / 0), 1)
	t.expectEq(Difficulty.clamp(-2), 1)
	t.expectEq(Difficulty.clamp(9), 5)
	t.expectEq(Difficulty.clamp(2.7), 2)
end

function tests.progress_defaults_and_sanitize(t)
	local d = Progress.sanitize(nil)
	t.expectEq(d.raindrops, 0)
	t.expectEq(d.unlocked, 1)
	t.expectEq(d.runs, 0)
	local s = Progress.sanitize({ raindrops = -5, unlocked = "x", runs = 2.9 })
	t.expectEq(s.raindrops, 0)
	t.expectEq(s.unlocked, 1)
	t.expectEq(s.runs, 2)
end

function tests.beating_highest_unlocks_next(t)
	local after = Progress.applyRun({ raindrops = 10, unlocked = 1, runs = 0 }, 100, 1, 5)
	t.expectEq(after.raindrops, 110)
	t.expectEq(after.unlocked, 2)
	t.expectEq(after.runs, 1)
end

function tests.replaying_lower_does_not_unlock(t)
	local after = Progress.applyRun({ raindrops = 0, unlocked = 3, runs = 4 }, 50, 2, 5)
	t.expectEq(after.unlocked, 3)
	t.expectEq(after.raindrops, 50)
end

function tests.unlock_caps_at_max(t)
	t.expectEq(Progress.applyRun({ unlocked = 5 }, 10, 5, 5).unlocked, 5)
end

return tests
