local Rewards = require("../src/shared/Rewards")

local tests = {}

local WEIGHTS = { 7 / 45, 13 / 45, 25 / 45 }

function tests.even_group_gets_100_each(t)
	local players = {}
	for i = 1, 4 do
		players[i] = { id = i, share = 0.25, pouredEveryStage = true }
	end
	local result = Rewards.split(players)
	for i = 1, 4 do
		t.expectEq(result[i], 100, `player {i}`)
	end
end

function tests.spec_example(t)
	local result = Rewards.split({
		{ id = "a", share = 0.40, pouredEveryStage = true },
		{ id = "b", share = 0.25, pouredEveryStage = true },
		{ id = "c", share = 0.25, pouredEveryStage = true },
		{ id = "d", share = 0.05, pouredEveryStage = true },
	})
	t.expectEq(result.a, 130)
	t.expectEq(result.b, 100)
	t.expectEq(result.c, 100)
	t.expectEq(result.d, 60)
end

function tests.ineligible_gets_only_share(t)
	local result = Rewards.split({
		{ id = "a", share = 0.10, pouredEveryStage = false },
		{ id = "b", share = 0.90, pouredEveryStage = true },
	})
	t.expectEq(result.a, 10)
	t.expectEq(result.b, 140)
end

function tests.zero_share_no_nan(t)
	local share = Rewards.shares(WEIGHTS, { 0, 0, 0 }, { 0, 0, 0 })
	t.expectEq(share, 0)
	t.expectEq(share == share, true, "not NaN")
end

function tests.weights_applied(t)
	t.expectNear(Rewards.shares(WEIGHTS, { 100, 0, 0 }, { 100, 50, 50 }), 7 / 45, 1e-12)
end

function tests.missing_later_stages_count_zero(t)
	t.expectNear(Rewards.shares(WEIGHTS, { 50 }, { 100 }), 0.5 * 7 / 45, 1e-12)
end

return tests
