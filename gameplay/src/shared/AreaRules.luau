--!strict
-- Area mechanics maths (Config.steam, ice, snow, deepPool, golden; areas' `mechanic`). Pure: config
-- is passed in, so Lune tests and Roblox load it the same way. server/Mechanics runs them.

local AreaRules = {}

-- Whether a time of the form phase + k * period (any whole k) lies in (before, after].
local function crossed(before: number, after: number, phase: number, period: number): boolean
	return math.floor((after - phase) / period) > math.floor((before - phase) / period)
end

-- What a vent did between `before` and `after` (seconds on one clock): it bursts at offset + k * period
-- and warns (a puff) warnSeconds before each burst. Returns warned, burst.
function AreaRules.ventEvents(before: number, after: number, offset: number, steam): (boolean, boolean)
	return crossed(before, after, offset - steam.warnSeconds, steam.period), crossed(before, after, offset, steam.period)
end

-- Vent `i` of `count` bursts this long into the period, so the vents take turns.
function AreaRules.ventOffset(i: number, count: number, period: number): number
	return (i - 1) / count * period
end

-- Whether a burst knocks back a player `distance` studs from the vent (never with Heat Gloves).
function AreaRules.knocked(distance: number, steam, gloves: boolean): boolean
	return not gloves and distance <= steam.radius
end

-- Seconds one scoop sweep takes at `area`: actSeconds x its scoopFactor, divided by the Heat Gloves'
-- hotFill (nil without them) in a hot ("steam") area.
function AreaRules.scoopSeconds(actSeconds: number, area, hotFill: number?): number
	local seconds = actSeconds * area.scoopFactor
	return if area.mechanic == "steam" and hotFill then seconds / hotFill else seconds
end

-- Hits to chip one ice block loose: the Ice Pick's (nil without one), else Config.ice.hits.
function AreaRules.iceHits(config, pickHits: number?): number
	return pickHits or config.ice.hits
end

-- One credited sweep at `area` (deep: at its deeper pool). Returns the hits on the current ice block
-- afterwards and how many normal sweeps' litres it brings. At an ice Source each sweep is a hit and
-- only the one that frees the block brings litres (Config.ice.blockSweeps); a deep pool brings
-- Config.deepPool.sweepScale; anywhere else 1. A sweep anywhere but an ice Source drops the block
-- being chipped (its hits go back to 0).
function AreaRules.sweep(config, area, deep: boolean, iceHits: number, pickHits: number?): (number, number)
	if deep then
		return 0, config.deepPool.sweepScale
	elseif area.mechanic ~= "ice" then
		return 0, 1
	end
	local hits = iceHits + 1
	if hits >= AreaRules.iceHits(config, pickHits) then
		return 0, config.ice.blockSweeps
	end
	return hits, 0
end

-- Walking speed with snow under the feet (onSnow) or not.
function AreaRules.walkSpeed(config, base: number, onSnow: boolean): number
	return if onSnow then base * config.snow.walkFactor else base
end

-- The tool that breaks area `areaId`'s rock: the first tool level of the area's `rockTool` model.
-- Returns its index in the tool track and the level.
function AreaRules.rockTool(config, areaId: number)
	local model = nil
	for _, area in config.areas do
		if area.id == areaId then
			model = area.rockTool
		end
	end
	for i, level in config.track("tool").levels do
		if level.model == model then
			return i, level
		end
	end
	error(`area {areaId}'s rockTool {model} is not a tool model`)
end

-- Whether a player with these track levels may break area `areaId`'s rock.
function AreaRules.canBreak(config, levels: { [string]: number }, areaId: number): boolean
	return (levels.tool or 0) >= (AreaRules.rockTool(config, areaId))
end

-- Seconds until the next golden spring; roll is a random number in [0, 1).
function AreaRules.goldenDelay(config, roll: number): number
	local g = config.golden
	return g.minSeconds + (g.maxSeconds - g.minSeconds) * roll
end

-- The area that turns golden: one of `openIds`; roll is a random number in [0, 1).
function AreaRules.goldenPick(openIds: { number }, roll: number): number
	return openIds[math.min(#openIds, math.floor(roll * #openIds) + 1)]
end

-- The pay factor of a sweep at area `areaId` (deep: its deeper pool) while `goldenId`'s Source is
-- golden (nil: none is).
function AreaRules.payScale(config, areaId: number, deep: boolean, goldenId: number?): number
	return if not deep and areaId == goldenId then config.golden.pay else 1
end

return AreaRules
