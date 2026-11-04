local ToolView = require("../src/shared/ToolView")

local tests = {}

function tests.first_tool_starts_small(t)
	t.expectNear(ToolView.viewSize(1), 0.8, 1e-9)
end

function tests.grows_every_tier(_t)
	for tier = 2, 20 do
		if not (ToolView.viewSize(tier) > ToolView.viewSize(tier - 1)) then
			error(`viewSize({tier}) is not bigger than viewSize({tier - 1})`)
		end
	end
end

function tests.moon_stays_under_cap(t)
	if not (ToolView.viewSize(20) < 1.7) then
		error(`viewSize(20) = {ToolView.viewSize(20)} is not under 1.7`)
	end
	t.expectNear(ToolView.viewSize(20), 1.659, 0.001)
end

function tests.held_scales_down_big_tools(t)
	t.expectNear(ToolView.heldScale(14), 6 / 14, 1e-9)
end

function tests.held_never_scales_up(t)
	t.expectEq(ToolView.heldScale(1.2), 1)
	t.expectEq(ToolView.heldScale(6), 1)
end

return tests
