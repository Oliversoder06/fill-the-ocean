local Config = require("../src/shared/Config")
local Ladder = require("../src/shared/Ladder")

local tests = {}

local function start()
	return { capacity = 1, walkSpeed = 16, actSeconds = 0.5 }
end

function tests.first_pool_item_is_cup(t)
	t.expectEq(Ladder.nextItem(Config, 1, 0).name, "Cup")
end

function tests.pool_list_ends(t)
	t.expectEq(Ladder.nextItem(Config, 1, #Config.stages[1].items), nil)
end

function tests.no_peeking_into_lake(t)
	local item = Ladder.nextItem(Config, 1, #Config.stages[1].items)
	t.expectEq(item and item.name, nil, "after last pool item")
end

function tests.last_item_of_run_is_moon_then_nil(t)
	t.expectEq(#Config.stages[3].items, 14, "ocean item count")
	t.expectEq(Ladder.nextItem(Config, 3, 13).name, "The Moon Lv4")
	t.expectEq(Ladder.nextItem(Config, 3, 14), nil)
end

function tests.apply_tool_sets_capacity(t)
	local before = start()
	local after = Ladder.apply(before, Config.stages[1].items[1])
	t.expectEq(after.capacity, 4)
	t.expectEq(before.capacity, 1, "input unchanged")
	t.expectEq(after.walkSpeed, 16)
end

function tests.tool_name_follows_tools_only(t)
	local items = Config.stages[1].items
	local s = Ladder.apply({ capacity = 1, walkSpeed = 16, actSeconds = 0.5, toolName = "Spoon", toolModel = "Spoon" }, items[1])
	t.expectEq(s.toolName, "Cup")
	t.expectEq(s.toolModel, "Cup")
	s = Ladder.apply(s, items[2]) -- Sneakers 1
	t.expectEq(s.toolName, "Cup", "speed items keep the tool")
	s = Ladder.apply(s, items[4]) -- Cup Lv2
	t.expectEq(s.toolName, "Cup Lv2")
	t.expectEq(s.toolModel, "Cup", "levels keep the model")
	t.expectEq(Config.start.toolName, "Spoon")
end

function tests.tool_tier_counts_every_tool_rung(t)
	t.expectEq(Ladder.toolTier(Config, "Spoon"), 1)
	t.expectEq(Ladder.toolTier(Config, "Cup"), 2)
	t.expectEq(Ladder.toolTier(Config, "Cup Lv2"), 3)
	t.expectEq(Ladder.toolTier(Config, "The Moon Lv4"), 20)
	t.expectEq(Ladder.toolTier(Config, "Nope"), 1)
end

function tests.apply_walk_and_hands(t)
	local items = Config.stages[1].items
	local s = Ladder.apply(start(), items[2])
	t.expectEq(s.walkSpeed, 20)
	t.expectEq(s.actSeconds, 0.5)
	s = Ladder.apply(s, items[3])
	t.expectEq(s.actSeconds, 0.45)
	t.expectEq(s.walkSpeed, 20)
	t.expectEq(s.capacity, 1)
end

function tests.trip_seconds(t)
	t.expectNear(Ladder.tripSeconds(Config, start()), 11, 1e-9)
end

function tests.missed_items_listed(t)
	local missed = Ladder.missedFromEarlierStages(Config, 2, { 3, 0 })
	t.expectEq(#missed, 7)
	t.expectEq(missed[1].stage, 1)
	t.expectEq(missed[1].item.name, "Cup Lv2")
	t.expectEq(missed[7].item.name, "Quick Hands 3")
end

function tests.nothing_missed_in_first_stage(t)
	t.expectEq(#Ladder.missedFromEarlierStages(Config, 1, { 0 }), 0)
end

function tests.upcoming_starts_with_next_item(t)
	local list = Ladder.upcoming(Config, 1, { 0 }, 3)
	t.expectEq(#list, 3)
	t.expectEq(list[1].item.name, "Cup")
	t.expectEq(list[3].item.name, "Quick Hands 1")
end

function tests.upcoming_puts_catch_up_first(t)
	local list = Ladder.upcoming(Config, 2, { 9, 0 }, 3)
	t.expectEq(list[1].item.name, "Quick Hands 3", "missed pool item first")
	t.expectEq(list[1].stage, 1)
	t.expectEq(list[2].item.name, "Bucket Lv3")
	t.expectEq(list[2].stage, 2)
end

function tests.upcoming_shrinks_at_end_of_list(t)
	t.expectEq(#Ladder.upcoming(Config, 3, { 10, 9, 13 }, 3), 1)
	t.expectEq(#Ladder.upcoming(Config, 3, { 10, 9, 14 }, 3), 0)
	t.expectEq(#Ladder.upcoming(Config, 4, { 10, 9, 14 }, 3), 0, "after the last stage")
end

function tests.kind_progress_counts_bought_of_total(t)
	local bought, total = Ladder.kindProgress(Config, { 0 }, "walk")
	t.expectEq(bought, 0)
	t.expectEq(total, 7)
	bought = Ladder.kindProgress(Config, { 6, 2 }, "walk") -- Sneakers 1, 2, then 4
	t.expectEq(bought, 3)
	bought, total = Ladder.kindProgress(Config, { 10, 9, 14 }, "hands")
	t.expectEq(bought, total)
end

return tests
