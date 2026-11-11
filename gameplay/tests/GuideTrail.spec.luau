local Cues = require("../src/shared/Cues")
local GuideTrail = require("../src/shared/GuideTrail")

local tests = {}

local cue = Cues.guide

-- The owner's videos (2026-11-11): the lane starts inside the player and floats just below the camera.
function tests.the_lane_looks_like_the_owners_ask(t)
	t.expectEq(cue.laneStart, 0, "the lane starts inside the player")
	if not (cue.belowCamera > 0 and cue.belowCamera < 4) then
		error(`belowCamera {cue.belowCamera}: the lane sits just below the camera, not at the feet`)
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
end

return tests
