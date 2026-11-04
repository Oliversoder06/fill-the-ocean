--!strict
-- The upgrade ladder: which item is next and what buying it changes. Pure: config is passed in.

export type Stats = {
	capacity: number,
	walkSpeed: number,
	actSeconds: number,
	toolName: string?,
	toolModel: string?,
}

local Ladder = {}

-- The item after `boughtInStage` in that stage's list, or nil when the list is used up.
function Ladder.nextItem(config, stageIndex: number, boughtInStage: number)
	local stage = config.stages[stageIndex]
	return stage and stage.items[boughtInStage + 1]
end

function Ladder.apply(stats: Stats, item): Stats
	return {
		capacity = item.capacity or stats.capacity,
		walkSpeed = item.walkSpeed or stats.walkSpeed,
		actSeconds = item.actSeconds or stats.actSeconds,
		toolName = if item.kind == "tool" then item.name else stats.toolName,
		toolModel = if item.kind == "tool" then item.model else stats.toolModel,
	}
end

-- Position of a tool in the whole ladder: 1 for the starting tool, then one per tool rung.
-- Unknown names count as the starting tool.
function Ladder.toolTier(config, toolName: string): number
	local tier = 1
	for _, stage in config.stages do
		for _, item in stage.items do
			if item.kind == "tool" then
				tier += 1
				if item.name == toolName then
					return tier
				end
			end
		end
	end
	return 1
end

function Ladder.tripSeconds(config, stats: Stats): number
	return 2 * config.tripDistance / stats.walkSpeed + 2 * stats.actSeconds
end

-- Items left unbought in stages before `stageIndex`, earliest stage first (catch-up buys).
function Ladder.missedFromEarlierStages(config, stageIndex: number, boughtPerStage: { number })
	local missed = {}
	for s = 1, stageIndex - 1 do
		local items = config.stages[s].items
		for i = (boughtPerStage[s] or 0) + 1, #items do
			table.insert(missed, { stage = s, item = items[i] })
		end
	end
	return missed
end

-- The next `count` items a player will be offered, in buy order: catch-up items from earlier
-- stages first, then the rest of this stage's list. Each entry is { stage, item }.
function Ladder.upcoming(config, stageIndex: number, boughtPerStage: { number }, count: number)
	local list = Ladder.missedFromEarlierStages(config, stageIndex, boughtPerStage)
	local stage = config.stages[stageIndex]
	if stage then
		for i = (boughtPerStage[stageIndex] or 0) + 1, #stage.items do
			table.insert(list, { stage = stageIndex, item = stage.items[i] })
		end
	end
	local result = {}
	for i = 1, math.min(count, #list) do
		result[i] = list[i]
	end
	return result
end

-- How many items of one kind ("walk", "hands", "tool") are bought, out of how many in the run.
function Ladder.kindProgress(config, boughtPerStage: { number }, kind: string): (number, number)
	local bought, total = 0, 0
	for s, stage in config.stages do
		for i, item in stage.items do
			if item.kind == kind then
				total += 1
				if i <= (boughtPerStage[s] or 0) then
					bought += 1
				end
			end
		end
	end
	return bought, total
end

return Ladder
