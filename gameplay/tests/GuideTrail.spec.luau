local Cues = require("../src/shared/Cues")
local GuideTrail = require("../src/shared/GuideTrail")

local tests = {}

local cue = Cues.guide

-- The owner's ref (clear-tide refs/tutorial-arrow-ref-1.png): wide chevrons ~5 studs apart in a lane
-- ~6 wide; the owner (2026-11-11): the lane floats just below the camera and moves forward.
function tests.the_lane_looks_like_the_owners_ask(t)
	if not (cue.spacing >= 4 and cue.spacing <= 6) then
		error(`chevrons {cue.spacing} studs apart: the ref has them about 5 apart`)
	end
	if not (cue.laneHalfWidth >= 2.5 and cue.laneHalfWidth <= 3.5) then
		error(`lane half-width {cue.laneHalfWidth}: the ref's lane is about a 6-stud chevron wide`)
	end
	if not (cue.belowCamera > 0 and cue.belowCamera < 4) then
		error(`belowCamera {cue.belowCamera}: the lane sits just below the camera, not at the feet`)
	end
	if not (cue.scrollSpeed > 0) then
		error(`scrollSpeed {cue.scrollSpeed}: the chevrons must move forward`)
	end
end

function tests.a_far_goal_shows_the_next_stretch(t)
	local from, to = GuideTrail.lane(cue, 200)
	t.expectEq(from, cue.laneStart)
	t.expectEq(to, cue.laneLength)
end

function tests.the_lane_stops_short_of_the_goal(t)
	local from, to = GuideTrail.lane(cue, 30)
	t.expectEq(from, cue.laneStart)
	t.expectEq(to, 30 - cue.hideNear)
end

function tests.nothing_shows_near_the_goal(t)
	t.expectEq(GuideTrail.lane(cue, cue.hideNear + cue.laneStart), nil)
	t.expectEq(GuideTrail.lane(cue, 2), nil)
	t.expectEq(#GuideTrail.chevrons(cue, cue.hideNear, 1), 0)
end

function tests.chevrons_are_spaced_evenly_inside_the_lane(t)
	for _, seconds in { 0, 0.3, 1.7, 12.05 } do
		for d = 0, 120, 0.37 do
			local from, to = GuideTrail.lane(cue, d)
			local list = GuideTrail.chevrons(cue, d, seconds)
			if not from then
				t.expectEq(#list, 0, `no lane at {d}`)
				continue
			end
			if #list > GuideTrail.most(cue) then
				error(`{#list} chevrons at {d} studs: more than the pool's {GuideTrail.most(cue)}`)
			end
			for i, ahead in list do
				if not (ahead >= from and ahead <= (to :: number)) then
					error(`chevron at {ahead} outside {from}..{to}`)
				end
				if i > 1 then
					t.expectNear(ahead - list[i - 1], cue.spacing, 1e-9, "spacing")
				end
			end
		end
	end
end

function tests.chevrons_move_forward_over_time(t)
	local now = GuideTrail.chevrons(cue, 200, 1)
	local soon = GuideTrail.chevrons(cue, 200, 1 + 0.1)
	t.expectNear(soon[1] - now[1], cue.scrollSpeed * 0.1, 1e-9, "the first chevron moved forward")
end

function tests.a_full_lane_keeps_its_count_as_it_scrolls(t)
	for seconds = 0, 3, 0.05 do
		local count = #GuideTrail.chevrons(cue, 500, seconds)
		if count < GuideTrail.most(cue) - 1 then
			error(`only {count} chevrons on a full lane at {seconds} s`)
		end
	end
end

function tests.chevrons_fade_in_and_out_at_the_lane_ends(t)
	local from, to = cue.laneStart, cue.laneLength
	t.expectNear(GuideTrail.fade(cue, from, from, to), 0, 1e-9, "at the start")
	t.expectNear(GuideTrail.fade(cue, to, from, to), 0, 1e-9, "at the end")
	t.expectNear(GuideTrail.fade(cue, (from + to) / 2, from, to), 1, 1e-9, "in the middle")
	for ahead = from, to, 0.1 do
		local f = GuideTrail.fade(cue, ahead, from, to)
		if not (f >= 0 and f <= 1) then
			error(`fade {f} at {ahead} is outside 0..1`)
		end
	end
end

return tests
