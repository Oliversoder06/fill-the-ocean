local Cues = require("../src/shared/Cues")
local GuideTrail = require("../src/shared/GuideTrail")

local tests = {}

local cue = Cues.guide

local function same(t, actual: { number }, expected: { number }, label: string)
	t.expectEq(#actual, #expected, `{label}: count`)
	for i, v in expected do
		t.expectNear(actual[i], v, 1e-9, `{label} [{i}]`)
	end
end

local function point(x: number, y: number, z: number)
	return { X = x, Y = y, Z = z }
end

local function samePoint(t, actual, expected, label: string)
	t.expectNear(actual.X, expected.X, 1e-9, `{label}.X`)
	t.expectNear(actual.Y, expected.Y, 1e-9, `{label}.Y`)
	t.expectNear(actual.Z, expected.Z, 1e-9, `{label}.Z`)
end

-- The owner's ref (clear-tide refs/tutorial-arrow-ref-1.png): wide chevrons ~5 studs apart in a lane ~6 wide.
function tests.the_lane_looks_like_the_ref(t)
	if not (cue.spacing >= 4 and cue.spacing <= 6) then
		error(`chevrons {cue.spacing} studs apart: the ref has them about 5 apart`)
	end
	if not (cue.laneHalfWidth >= 2.5 and cue.laneHalfWidth <= 3.5) then
		error(`lane half-width {cue.laneHalfWidth}: the ref's lane is about a 6-stud chevron wide`)
	end
	if not (cue.pulseDim > 0 and cue.pulseDim <= 0.4) then
		error(`pulseDim {cue.pulseDim}: the wave must stay gentle`)
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
	t.expectEq(#GuideTrail.chevrons(cue, cue.hideNear), 0)
	t.expectEq(#GuideTrail.stops(cue, cue.hideNear), 0)
end

function tests.chevrons_sit_every_spacing_back_from_the_goal_nearest_first(t)
	local s = cue.spacing
	local d = 20 * s
	local expected = {}
	for k = 20, 0, -1 do
		local ahead = d - k * s
		if ahead >= cue.laneStart and ahead <= cue.laneLength then
			table.insert(expected, ahead)
		end
	end
	same(t, GuideTrail.chevrons(cue, d), expected, "chevrons")
end

function tests.chevrons_stay_put_on_the_ground_as_the_player_walks(t)
	for _, d in { 100, 99.3, 87.25, 41, 15.5 } do
		for _, ahead in GuideTrail.chevrons(cue, d) do
			local fromGoal = d - ahead
			local steps = fromGoal / cue.spacing
			t.expectNear(steps, math.round(steps), 1e-6, `chevron {fromGoal} studs from the goal`)
		end
	end
end

function tests.every_chevron_is_inside_the_lane(t)
	for d = 0, 120, 0.37 do
		local from, to = GuideTrail.lane(cue, d)
		local list = GuideTrail.chevrons(cue, d)
		if not from then
			t.expectEq(#list, 0, `no lane at {d}`)
			continue
		end
		if #list > GuideTrail.most(cue) then
			error(`{#list} chevrons at {d} studs: more than the pool's {GuideTrail.most(cue)}`)
		end
		local last = -math.huge
		for _, ahead in list do
			if not (ahead >= from and ahead <= (to :: number) and ahead > last) then
				error(`chevron at {ahead} outside {from}..{to} or out of order (goal {d} studs off)`)
			end
			if d - ahead < cue.hideNear then
				error(`chevron {d - ahead} studs from the goal: inside hideNear`)
			end
			last = ahead
		end
	end
end

function tests.a_long_way_off_the_lane_is_full(t)
	local count = #GuideTrail.chevrons(cue, 500)
	if count < GuideTrail.most(cue) - 1 then
		error(`only {count} chevrons on a full lane`)
	end
end

function tests.the_rails_stops_are_the_lane_ends_and_the_chevrons(t)
	local d = 100.5
	local from, to = GuideTrail.lane(cue, d)
	local expected = { from :: number }
	for _, ahead in GuideTrail.chevrons(cue, d) do
		table.insert(expected, ahead)
	end
	table.insert(expected, to :: number)
	same(t, GuideTrail.stops(cue, d), expected, "stops")
end

function tests.rails_run_both_sides_between_neighbouring_ground_points(t)
	local points = { point(0, 0, 0), point(0, 1, -5), point(0, 1.5, -10) }
	local left, right = GuideTrail.rails(points, point(1, 0, 0), 3)
	t.expectEq(#left, 2, "left segments")
	t.expectEq(#right, 2, "right segments")
	samePoint(t, left[1].from, point(-3, 0, 0), "left 1 from")
	samePoint(t, left[1].to, point(-3, 1, -5), "left 1 to")
	samePoint(t, left[2].from, point(-3, 1, -5), "left 2 from")
	samePoint(t, left[2].to, point(-3, 1.5, -10), "left 2 to")
	samePoint(t, right[1].from, point(3, 0, 0), "right 1 from")
	samePoint(t, right[2].to, point(3, 1.5, -10), "right 2 to")
end

function tests.rails_break_over_a_missing_ground_point(t)
	local points = { point(0, 0, 0), false, point(0, 0, -10), point(0, 0, -15) }
	local left, right = GuideTrail.rails(points, point(0, 0, 1), 2)
	t.expectEq(#left, 1)
	t.expectEq(#right, 1)
	samePoint(t, left[1].from, point(0, 0, -12), "left from")
	samePoint(t, left[1].to, point(0, 0, -17), "left to")
	samePoint(t, right[1].from, point(0, 0, -8), "right from")
end

function tests.rails_skip_a_zero_length_segment(t)
	local points = { point(1, 2, 3), point(1, 2, 3), point(1, 2, 8) }
	local left = GuideTrail.rails(points, point(1, 0, 0), 3)
	t.expectEq(#left, 1)
	samePoint(t, left[1].to, point(-2, 2, 8), "left to")
end

function tests.the_pulse_is_a_brightness_from_0_to_1(t)
	local low, high = math.huge, -math.huge
	for ahead = 0, 40, 0.25 do
		local p = GuideTrail.pulse(cue, ahead, 1.3)
		if not (p >= 0 and p <= 1) then
			error(`pulse {p} at {ahead} studs is outside 0..1`)
		end
		low, high = math.min(low, p), math.max(high, p)
	end
	t.expectNear(low, 0, 0.01, "its trough")
	t.expectNear(high, 1, 0.01, "its crest")
end

function tests.the_pulse_travels_toward_the_goal(t)
	for _, ahead in { 3, 7.5, 20 } do
		for _, seconds in { 0, 0.4, 5.1 } do
			local later = GuideTrail.pulse(cue, ahead + cue.pulseSpeed * 0.5, seconds + 0.5)
			t.expectNear(later, GuideTrail.pulse(cue, ahead, seconds), 1e-9, "the crest moves forward at pulseSpeed")
		end
	end
end

return tests
