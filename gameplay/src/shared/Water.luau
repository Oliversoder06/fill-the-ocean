--!strict
-- Water math: stage target, rescaling on player-count change, litres moved per tick.

local Water = {}

function Water.target(waterPerPlayer: number, players: number, scale: number): number
	return waterPerPlayer * math.max(players, 1) * scale
end

-- Keeps the fill fraction when the target changes.
function Water.rescale(current: number, oldTarget: number, newTarget: number): number
	return current / oldTarget * newTarget
end

-- One pour empties the tool, but never past the target; the rest stays carried.
function Water.pourAmount(carried: number, current: number, target: number): number
	return math.max(0, math.min(carried, target - current))
end

return Water
