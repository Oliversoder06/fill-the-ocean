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

local function expectPose(t, label, down, side, tilt, eDown, eSide, eTilt)
	t.expectNear(down, eDown, 1e-9, `{label} down`)
	t.expectNear(side, eSide, 1e-9, `{label} side`)
	t.expectNear(tilt, eTilt, 1e-9, `{label} tilt`)
end

function tests.scoop_rests_at_start(t)
	local d, s, r = ToolView.scoopPose(0)
	expectPose(t, "p=0", d, s, r, 0, 0, 0)
end

function tests.scoop_winds_up(t)
	local d, s, r = ToolView.scoopPose(0.2)
	expectPose(t, "p=0.2", d, s, r, -0.08, 0, math.rad(10))
end

function tests.scoop_plunges_smoothly(t)
	local d, s, r = ToolView.scoopPose(0.6)
	expectPose(t, "p=0.6", d, s, r, 0.185, -0.175, math.rad(-12.5))
end

function tests.scoop_bottom_and_clamps(t)
	local d, s, r = ToolView.scoopPose(1)
	expectPose(t, "p=1", d, s, r, 0.45, -0.35, math.rad(-35))
	d, s, r = ToolView.scoopPose(1.5)
	expectPose(t, "p=1.5", d, s, r, 0.45, -0.35, math.rad(-35))
	d, s, r = ToolView.scoopPose(-1)
	expectPose(t, "p=-1", d, s, r, 0, 0, 0)
end

function tests.pour_tips_then_holds(t)
	local d, s, r = ToolView.pourPose(0)
	expectPose(t, "p=0", d, s, r, 0, 0, 0)
	d, s, r = ToolView.pourPose(0.175)
	expectPose(t, "p=0.175", d, s, r, -0.05, -0.1, math.rad(-32.5))
	d, s, r = ToolView.pourPose(0.35)
	expectPose(t, "p=0.35", d, s, r, -0.1, -0.2, math.rad(-65))
	d, s, r = ToolView.pourPose(2)
	expectPose(t, "p=2", d, s, r, -0.1, -0.2, math.rad(-65))
end

function tests.new_tool_swings_up_from_below(t)
	local down, tilt = ToolView.revealPose(0)
	t.expectNear(down, ToolView.REVEAL_DOWN, 1e-9)
	t.expectNear(tilt, ToolView.REVEAL_TILT, 1e-9)
	down, tilt = ToolView.revealPose(1)
	t.expectNear(down, 0, 1e-9)
	t.expectNear(tilt, 0, 1e-9)
	down, tilt = ToolView.revealPose(0.5) -- overshoots a little above rest, then settles
	t.expectNear(down, ToolView.REVEAL_DOWN * -0.125, 1e-9)
	t.expectNear(tilt, ToolView.REVEAL_TILT * -0.125, 1e-9)
	down = ToolView.revealPose(3)
	t.expectNear(down, 0, 1e-9)
end

return tests
