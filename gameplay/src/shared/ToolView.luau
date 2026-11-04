--!strict
-- Pure size maths for held tools. Lune-tested.

local ToolView = {}

ToolView.VIEW_START = 0.8 -- studs, longest side of the first tool on screen
ToolView.VIEW_MAX = 1.7 -- approached but never reached, so the last tool stays in the corner
ToolView.VIEW_GROWTH = 0.85
ToolView.HELD_MAX = 6 -- studs, longest side of a tool in another player's hand

function ToolView.viewSize(tier: number): number
	return ToolView.VIEW_MAX - (ToolView.VIEW_MAX - ToolView.VIEW_START) * ToolView.VIEW_GROWTH ^ (tier - 1)
end

function ToolView.heldScale(longestSide: number): number
	return math.min(1, ToolView.HELD_MAX / longestSide)
end

return ToolView
