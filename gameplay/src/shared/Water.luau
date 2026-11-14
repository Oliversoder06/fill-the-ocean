--!strict
-- Water math: the ocean's fill curve, litres moved per scoop and pour, and carried water's value.

-- stretches: percents up to `to` grow by that stretch's growth instead (each area's tools grow at
-- their own pace); `growth` after the last. teamStep: a team of n needs 1 + teamStep * (n - 1)
-- times the water (default 1: n times).
export type Curve = { firstPercent: number, growth: number, stretches: { { to: number, growth: number } }?, teamStep: number? }

local Water = {}

-- The fill curve: percent 1 needs firstPercent litres for one player and each next percent `growth`
-- times the last (within a stretch, its growth), so the fill rises at a steady pace while income
-- grows. Both directions add the percents up in the same order, so they agree exactly at whole percents.

-- The growth from percent k to percent k + 1.
local function growthAt(ocean: Curve, k: number): number
	for _, stretch in ocean.stretches or {} do
		if k <= stretch.to then
			return stretch.growth
		end
	end
	return ocean.growth
end

-- The litres percent 1 needs for a team of `players`.
local function firstLitres(ocean: Curve, players: number): number
	return ocean.firstPercent * (1 + (ocean.teamStep or 1) * (math.max(players, 1) - 1))
end

-- The fill fraction 0..1 for `current` litres: exact at whole percents, straight between them.
function Water.fill(current: number, ocean: Curve, players: number): number
	local reached, need = 0, firstLitres(ocean, players)
	for k = 0, 99 do
		if current < reached + need then
			return (k + math.max(0, current - reached) / need) / 100
		end
		reached += need
		need *= growthAt(ocean, k + 1)
	end
	return 1
end

-- The litres that fill the ocean to `fraction` (clamped to 0..1); the inverse of Water.fill.
function Water.litresAt(fraction: number, ocean: Curve, players: number): number
	local percent = math.clamp(fraction, 0, 1) * 100
	local litres, need = 0, firstLitres(ocean, players)
	for k = 0, 99 do
		if percent <= k + 1 then
			return litres + (percent - k) * need
		end
		litres += need
		need *= growthAt(ocean, k + 1)
	end
	return litres
end

-- The ocean's water surface for a fill fraction, in studs above its floor: `depth` when full, else
-- the nearest whole number of `step`s (the terrain water is rewritten only when it moves a step;
-- one step for any water at all); nil when dry.
function Water.surface(fraction: number, depth: number, step: number): number?
	if fraction <= 0 then
		return nil
	elseif fraction >= 1 then
		return depth
	end
	local steps = math.max(1, math.floor(fraction * depth / step + 0.5))
	return math.min(depth, steps * step)
end

-- One pour empties the tool, but never past the target; the rest stays carried.
function Water.pourAmount(carried: number, current: number, target: number): number
	return math.max(0, math.min(carried, target - current))
end

-- One scoop sweep adds capacity / sweeps; the last sweep tops up exactly to capacity.
function Water.scoopAmount(carried: number, capacity: number, sweeps: number): number
	local room = math.max(0, capacity - carried)
	local per = capacity / math.max(1, sweeps)
	return if per >= room - capacity * 1e-9 then room else per
end

-- A tool holds litres and their total coin value: adding `litres` worth `payPerLitre` each returns
-- the new value, so water scooped in two areas pays each area's rate when poured.
function Water.mix(carriedValue: number, litres: number, payPerLitre: number): number
	return carriedValue + litres * payPerLitre
end

-- The coin value of `litres` poured out of `carried` litres worth `carriedValue`.
function Water.share(carriedValue: number, carried: number, litres: number): number
	return carriedValue * litres / carried
end

return Water
