local GuideTrail = require("../src/shared/GuideTrail")

local tests = {}

local LOOP = GuideTrail.COUNT * GuideTrail.SPACING

function tests.chevrons_start_spaced_out_ahead_of_the_player(t)
	t.expectEq(GuideTrail.ahead(1, 0), GuideTrail.START)
	t.expectEq(GuideTrail.ahead(2, 0), GuideTrail.START + GuideTrail.SPACING)
	t.expectEq(GuideTrail.ahead(GuideTrail.COUNT, 0), GuideTrail.START + (GuideTrail.COUNT - 1) * GuideTrail.SPACING)
end

function tests.chevrons_slide_toward_the_goal(t)
	t.expectNear(GuideTrail.ahead(1, 1), GuideTrail.START + GuideTrail.SPEED, 1e-9)
	t.expectNear(GuideTrail.ahead(3, 0.5), GuideTrail.START + 2 * GuideTrail.SPACING + 0.5 * GuideTrail.SPEED, 1e-9)
end

function tests.the_farthest_chevron_loops_back_to_the_start(t)
	t.expectNear(GuideTrail.ahead(GuideTrail.COUNT, GuideTrail.SPACING / GuideTrail.SPEED), GuideTrail.START, 1e-9)
	for _, seconds in { 0, 0.3, 1.7, 9.2, 123.4 } do
		for i = 1, GuideTrail.COUNT do
			local ahead = GuideTrail.ahead(i, seconds)
			if not (ahead >= GuideTrail.START and ahead < GuideTrail.START + LOOP) then
				error(`chevron {i} at {seconds}s is {ahead} studs ahead, outside the loop`)
			end
		end
	end
end

function tests.only_the_next_stretch_shows(t)
	t.expectEq(GuideTrail.shows(10, 100), true)
	t.expectEq(GuideTrail.shows(GuideTrail.SHOW, 100), true)
	t.expectEq(GuideTrail.shows(GuideTrail.SHOW + 0.1, 100), false)
end

function tests.nothing_shows_past_the_goal(t)
	t.expectEq(GuideTrail.shows(20, 15), false)
	t.expectEq(GuideTrail.shows(12, 15), true)
end

function tests.the_trail_hides_near_the_goal(t)
	t.expectEq(GuideTrail.shows(GuideTrail.START, GuideTrail.HIDE_NEAR), false)
	t.expectEq(GuideTrail.shows(GuideTrail.START, GuideTrail.HIDE_NEAR + 1), true)
end

function tests.a_long_way_off_most_chevrons_show(t)
	for _, seconds in { 0, 0.9, 4.4 } do
		local shown = 0
		for i = 1, GuideTrail.COUNT do
			if GuideTrail.shows(GuideTrail.ahead(i, seconds), 200) then
				shown += 1
			end
		end
		if shown < GuideTrail.COUNT - 2 then
			error(`only {shown} of {GuideTrail.COUNT} chevrons show at {seconds}s`)
		end
	end
end

return tests
