--!strict
-- Upgrades: what a player's levels add up to, and what each track offers next. Pure: config is
-- passed in. `levels` maps a track id to how many of its levels are bought (missing = 0).

export type Stats = {
	capacity: number,
	walkSpeed: number,
	actSeconds: number,
	sweeps: number, -- scoop sweeps to fill the tool
	toolName: string,
	toolModel: string,
	toolTier: number, -- 1 for the starting tool, +1 per tool level
	coinBonus: number,
	hold: boolean, -- holding the button keeps scooping
}

export type Status = "buy" | "locked" | "max"

local Ladder = {}

-- Sweeps a tool needs before Pickup: 1 for the Spoon, +1 every few tool levels, capped.
function Ladder.baseSweeps(config, toolTier: number): number
	local s = config.sweeps
	return math.min(s.maxSweeps, 1 + math.ceil((toolTier - 1) / s.toolsPerSweep))
end

-- The bought level of a track, or nil when none is bought.
local function owned(config, levels: { [string]: number }, id: string)
	local track = config.track(id)
	local n = levels[id] or 0
	return if track and n > 0 then track.levels[math.min(n, #track.levels)] else nil
end

function Ladder.stats(config, levels: { [string]: number }): Stats
	local start = config.start
	local tool = owned(config, levels, "tool")
	local toolTier = 1 + (levels.tool or 0)
	local walk, quick, tip = owned(config, levels, "walk"), owned(config, levels, "quick"), owned(config, levels, "tip")
	return {
		capacity = if tool then tool.capacity else start.capacity,
		walkSpeed = if walk then walk.walkSpeed else start.walkSpeed,
		actSeconds = if quick then quick.actSeconds else start.actSeconds,
		sweeps = math.max(1, Ladder.baseSweeps(config, toolTier) - (levels.pickup or 0)),
		toolName = if tool then tool.name else start.toolName,
		toolModel = if tool then tool.model else start.toolModel,
		toolTier = toolTier,
		coinBonus = if tip then tip.coinBonus else 1,
		hold = (levels.hold or 0) > 0,
	}
end

-- The next level of a track and whether it can be bought in this stage. A locked level is still
-- returned so the shop can show it. Unknown track: nil, nil.
function Ladder.offer(config, levels: { [string]: number }, id: string, stageIndex: number)
	local track = config.track(id)
	if not track then
		return nil, nil
	end
	local level = track.levels[(levels[id] or 0) + 1]
	if not level then
		return nil, "max" :: Status
	end
	return level, (if level.stage <= stageIndex then "buy" else "locked") :: Status
end

-- Walk there and back, the scoop sweeps, then one quick pour.
function Ladder.tripSeconds(config, stats: Stats): number
	return 2 * config.tripDistance / stats.walkSpeed + stats.sweeps * stats.actSeconds + config.pourSeconds
end

return Ladder
