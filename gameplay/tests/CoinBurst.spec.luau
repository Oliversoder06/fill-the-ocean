local CoinBurst = require("../src/shared/CoinBurst")

local tests = {}

function tests.count_grows_with_the_payout_and_caps(t)
	t.expectEq(CoinBurst.count(0), 0)
	t.expectEq(CoinBurst.count(-5), 0)
	t.expectEq(CoinBurst.count(1), 3)
	t.expectEq(CoinBurst.count(10), 5)
	t.expectEq(CoinBurst.count(1000), 8)
	t.expectEq(CoinBurst.count(1e9), 12)
end

function tests.split_adds_up_exactly(t)
	local values = CoinBurst.split(10, 4)
	t.expectEq(#values, 4)
	t.expectEq(values[1], 2.5)
	t.expectEq(values[4], 2.5)
	local sum = 0
	for _, v in CoinBurst.split(7, 3) do
		sum += v
	end
	t.expectNear(sum, 7, 1e-9)
end

function tests.coins_fly_in_one_after_another(t)
	t.expectNear(CoinBurst.flyAt(1), 0.8, 1e-9)
	t.expectNear(CoinBurst.flyAt(3), 0.9, 1e-9)
end

function tests.tick_pitch_climbs_and_caps(t)
	t.expectEq(CoinBurst.tickPitch(1), 1)
	t.expectNear(CoinBurst.tickPitch(6), 1.2, 1e-9)
	t.expectEq(CoinBurst.tickPitch(20), 1.5)
end

function tests.launch_lands_on_time(t)
	-- climb 8 studs in 0.5 s under gravity -80: vy = (8 + 10) / 0.5
	local vy = CoinBurst.launchVertical(8, 0.5, -80)
	t.expectNear(vy, 36, 1e-9)
	t.expectNear(vy * 0.5 + 0.5 * -80 * 0.25, 8, 1e-9)
end

return tests
