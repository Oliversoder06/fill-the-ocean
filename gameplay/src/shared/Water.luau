--!strict
-- Water math: the ocean's fill curve, rescaling on player-count change, litres moved per tick.

export type Curve = { firstPercent: number, growth: number }

local Water = {}

-- The fill curve: percent k needs firstPercent * growth^(k-1) litres per player, so the fill rises
-- at a steady pace while income grows. Both directions add the percents up in the same order, so
-- they agree exactly at whole percents.

-- The fill fraction 0..1 for `current` litres: exact at whole percents, straight between them.
function Water.fill(current: number, ocean: Curve, players: number): number
	local perPlayer = ocean.firstPercent * math.max(players, 1)
	local reached = 0
	for k = 0, 99 do
		local need = perPlayer * ocean.growth ^ k
		if current < reached + need then
			return (k + math.max(0, current - reached) / need) / 100
		end
		reached += need
	end
	return 1
end

-- The litres that fill the ocean to `fraction` (clamped to 0..1); the inverse of Water.fill.
function Water.litresAt(fraction: number, ocean: Curve, players: number): number
	local perPlayer = ocean.firstPercent * math.max(players, 1)
	local percent = math.clamp(fraction, 0, 1) * 100
	local litres = 0
	for k = 0, 99 do
		local need = perPlayer * ocean.growth ^ k
		if percent <= k + 1 then
			return litres + (percent - k) * need
		end
		litres += need
	end
	return litres
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

return Water
