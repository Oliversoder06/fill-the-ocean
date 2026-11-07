local Config = require("../src/shared/Config")
local Ladder = require("../src/shared/Ladder")
local Boosts = require("../src/shared/Boosts")

local tests = {}

function tests.one_boost_per_milestone(t)
	t.expectEq(#Config.boosts.kinds, #Config.boosts.milestones, "each save plays every boost once")
	t.expectEq(Config.boosts.seconds > 0, true)
	for _, kind in Config.boosts.kinds do
		t.expectEq(type(kind.tag), "string", `{kind.id} tag`)
		t.expectEq(type(kind.card), "string", `{kind.id} card`)
	end
end

function tests.crossed_finds_the_milestone_a_pour_passes(t)
	local m = { 0.25, 0.5, 0.75 }
	t.expectEq(Boosts.crossed(m, 0, 0.2), nil, "below the first")
	t.expectEq(Boosts.crossed(m, 0.2, 0.25), 1, "landing exactly on it counts")
	t.expectEq(Boosts.crossed(m, 0.25, 0.3), nil, "already past")
	t.expectEq(Boosts.crossed(m, 0.4, 0.6), 2)
	t.expectEq(Boosts.crossed(m, 0.1, 0.8), 3, "one big pour: the last one crossed")
end

function tests.no_boost_keeps_the_stats(t)
	local stats = Ladder.stats(Config, { tool = 3 })
	local s = Boosts.apply(Config, stats, nil)
	t.expectEq(s.sweeps, stats.sweeps)
	t.expectEq(s.walkSpeed, stats.walkSpeed)
	t.expectEq(s.coinBonus, stats.coinBonus)
end

function tests.coins_doubles_the_coin_bonus(t)
	local stats = Ladder.stats(Config, { tip = 1 })
	t.expectNear(Boosts.apply(Config, stats, "coins").coinBonus, 2 * 1.05, 1e-9)
end

function tests.gusher_fills_in_one_sweep(t)
	local stats = Ladder.stats(Config, { tool = 5 })
	t.expectEq(stats.sweeps > 1, true)
	t.expectEq(Boosts.apply(Config, stats, "gusher").sweeps, 1)
end

function tests.tailwind_is_faster_walking(t)
	local stats = Ladder.stats(Config, {})
	t.expectEq(Boosts.apply(Config, stats, "tailwind").walkSpeed, 16 * 1.5)
end

function tests.apply_does_not_change_the_players_stats(t)
	local stats = Ladder.stats(Config, { tool = 5 })
	local sweeps = stats.sweeps
	Boosts.apply(Config, stats, "gusher")
	t.expectEq(stats.sweeps, sweeps)
end

function tests.unknown_boost_errors(t)
	local ok = pcall(Boosts.apply, Config, Ladder.stats(Config, {}), "nope")
	t.expectEq(ok, false)
end

return tests
