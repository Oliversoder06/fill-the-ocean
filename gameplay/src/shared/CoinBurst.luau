--!strict
-- Coin payout maths: how many coins a payout shows, what each is worth, and their timing.
-- Matched to the coin reference clip (gameplay/ref for ai/collect coins.mkv): coins burst out,
-- land around you, then fly into you one after another, each with a rising tick. Pure, Lune-tested.

local CoinBurst = {}

CoinBurst.MIN_COINS = 3
CoinBurst.MAX_COINS = 12
CoinBurst.PER_DECADE = 1.5 -- extra coins per 10x payout, so the ladder's growth shows but stays capped
CoinBurst.AIR_SECONDS = 0.55 -- burst to first landing
CoinBurst.SETTLE_SECONDS = 0.25 -- lying on the ground before the first coin flies in
CoinBurst.STAGGER = 0.05
CoinBurst.FLY_SECONDS = 0.32
CoinBurst.GRAVITY = -80
CoinBurst.PITCH_STEP = 0.04
CoinBurst.PITCH_MAX = 1.5

function CoinBurst.count(amount: number): number
	if amount <= 0 then
		return 0
	end
	local n = math.floor(CoinBurst.MIN_COINS + CoinBurst.PER_DECADE * math.log10(math.max(amount, 1)) + 0.5)
	return math.clamp(n, CoinBurst.MIN_COINS, CoinBurst.MAX_COINS)
end

-- n equal values that add up to amount (the last one absorbs rounding).
function CoinBurst.split(amount: number, n: number): { number }
	local each = amount / n
	local values, sum = {}, 0
	for i = 1, n - 1 do
		values[i] = each
		sum += each
	end
	values[n] = amount - sum
	return values
end

-- Seconds after the burst that coin i starts flying to the player.
function CoinBurst.flyAt(i: number): number
	return CoinBurst.AIR_SECONDS + CoinBurst.SETTLE_SECONDS + (i - 1) * CoinBurst.STAGGER
end

function CoinBurst.tickPitch(i: number): number
	return math.min(CoinBurst.PITCH_MAX, 1 + CoinBurst.PITCH_STEP * (i - 1))
end

-- Upward speed that rises (or drops) by dy over `air` seconds under `gravity`.
function CoinBurst.launchVertical(dy: number, air: number, gravity: number): number
	return (dy - 0.5 * gravity * air * air) / air
end

return CoinBurst
