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

return Ladder
