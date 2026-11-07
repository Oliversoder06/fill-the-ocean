local Config = require("../src/shared/Config")
local Ladder = require("../src/shared/Ladder")

local tests = {}

function tests.no_levels_is_the_starting_kit(t)
	local s = Ladder.stats(Config, {})
	t.expectEq(s.capacity, 1)
	t.expectEq(s.walkSpeed, 16)
	t.expectEq(s.actSeconds, 0.5)
	t.expectEq(s.sweeps, 1)
	t.expectEq(s.toolName, "Spoon")
	t.expectEq(s.toolModel, "Spoon")
	t.expectEq(s.toolTier, 1)
	t.expectEq(s.coinBonus, 1)
	t.expectEq(s.hold, false)
end

function tests.each_track_sets_its_own_stat(t)
	local s = Ladder.stats(Config, { tool = 2, walk = 1, quick = 1, tip = 1, hold = 1 })
	t.expectEq(s.toolName, "Cup Lv2")
	t.expectEq(s.toolModel, "Cup", "levels keep the hero model")
	t.expectEq(s.toolTier, 3)
	t.expectEq(s.capacity, 10)
	t.expectEq(s.walkSpeed, 20)
	t.expectEq(s.actSeconds, 0.45)
	t.expectEq(s.coinBonus, 1.05)
	t.expectEq(s.hold, true)
end

function tests.cup_takes_two_sweeps_and_pickup_takes_one_off(t)
	t.expectEq(Ladder.stats(Config, { tool = 1 }).sweeps, 2, "cup")
	t.expectEq(Ladder.stats(Config, { tool = 1, pickup = 1 }).sweeps, 1, "cup + pickup")
	t.expectEq(Ladder.stats(Config, { pickup = 1 }).sweeps, 1, "never below one")
end

function tests.base_sweeps_grow_every_two_tools_up_to_eight(t)
	t.expectEq(Ladder.baseSweeps(Config, 1), 1, "spoon")
	t.expectEq(Ladder.baseSweeps(Config, 2), 2, "cup")
	t.expectEq(Ladder.baseSweeps(Config, 3), 2)
	t.expectEq(Ladder.baseSweeps(Config, 4), 3, "bucket")
	t.expectEq(Ladder.baseSweeps(Config, 14), 8, "cargo ship")
	t.expectEq(Ladder.baseSweeps(Config, 20), 8, "moon is capped")
end

function tests.offer_is_the_next_level(t)
	local level, status = Ladder.offer(Config, {}, "tool", 1)
	t.expectEq(status, "buy")
	t.expectEq(level.name, "Cup")
	level = Ladder.offer(Config, { tool = 1 }, "tool", 1)
	t.expectEq(level.name, "Cup Lv2")
end

function tests.level_waits_for_its_area(t)
	local firstArea = 0
	for _, level in Config.track("tool").levels do
		if level.area == 1 then
			firstArea += 1
		end
	end
	local level, status = Ladder.offer(Config, { tool = firstArea }, "tool", 1)
	t.expectEq(status, "locked")
	t.expectEq(level.area, 2, "the locked level is still returned for the shop")
	local _, laterStatus = Ladder.offer(Config, { tool = firstArea }, "tool", 2)
	t.expectEq(laterStatus, "buy")
end

function tests.offer_is_max_after_the_last_level(t)
	local level, status = Ladder.offer(Config, { hold = 1 }, "hold", 3)
	t.expectEq(status, "max")
	t.expectEq(level, nil)
end

function tests.offer_rejects_unknown_tracks(t)
	local level, status = Ladder.offer(Config, {}, "nope", 1)
	t.expectEq(level, nil)
	t.expectEq(status, nil)
end

function tests.trip_seconds(t)
	-- 80 studs there and back at 16, one 0.5 s sweep, then the quick pour
	t.expectNear(Ladder.tripSeconds(Config, Ladder.stats(Config, {})), 10.5 + Config.pourSeconds, 1e-9)
end

function tests.trip_seconds_counts_sweeps(t)
	local s = Ladder.stats(Config, { tool = 1 })
	t.expectNear(Ladder.tripSeconds(Config, s), 10 + 2 * 0.5 + Config.pourSeconds, 1e-9)
end

return tests
