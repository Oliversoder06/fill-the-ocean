--!strict
-- Difficulty levels. Pure: Lune-tested, used by the lobby and the gameplay place.
-- Each level needs more water and pays more Raindrops. Beating your highest unlocks the next.

local Difficulty = {}

Difficulty.MAX = 5
Difficulty.WATER_STEP = 1.4 -- each level needs 40% more water
Difficulty.REWARD_STEP = 1.5 -- each level pays 50% more

-- Whole number between 1 and MAX; anything else (nil, NaN, strings) becomes 1.
function Difficulty.clamp(level: any): number
	if type(level) ~= "number" or level ~= level then
		return 1
	end
	return math.clamp(math.floor(level), 1, Difficulty.MAX)
end

function Difficulty.waterMultiplier(level: number): number
	return Difficulty.WATER_STEP ^ (Difficulty.clamp(level) - 1)
end

function Difficulty.rewardMultiplier(level: number): number
	return Difficulty.REWARD_STEP ^ (Difficulty.clamp(level) - 1)
end

return Difficulty
