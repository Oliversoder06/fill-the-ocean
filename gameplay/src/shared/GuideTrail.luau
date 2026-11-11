-- The guide's lane on the ground (client/Guide): from the player along the straight flat line to a
-- goal, wide chevrons every `spacing` studs between two rails `laneHalfWidth` either side. The lane
-- runs from laneStart to laneLength studs ahead and never within hideNear of the goal; the chevrons
-- are counted back from the goal, so they stay put on the ground as the player walks. A gentle
-- brightness wave runs along them toward the goal. Distances are flat studs ahead of the player;
-- numbers come from `cue` (Cues.guide). Pure: no requires, so Lune tests and Roblox load it the same way.
local GuideTrail = {}

export type Point = { X: number, Y: number, Z: number }
export type Segment = { from: Point, to: Point }

local MIN_SEGMENT = 0.05 -- studs: a shorter rail segment is two stops in one place

-- The lane's stretch while the goal is `distance` studs away: studs ahead of the player it runs
-- from and to, or nil when none shows.
function GuideTrail.lane(cue, distance: number): (number?, number?)
	local to = math.min(cue.laneLength, distance - cue.hideNear)
	if to <= cue.laneStart then
		return nil, nil
	end
	return cue.laneStart, to
end

-- Studs ahead of the player of each chevron, nearest first: every `spacing` studs back from the goal.
function GuideTrail.chevrons(cue, distance: number): { number }
	local list = {}
	local from, to = GuideTrail.lane(cue, distance)
	if not (from and to) then
		return list
	end
	for k = math.floor((distance - from) / cue.spacing), math.ceil((distance - to) / cue.spacing), -1 do
		table.insert(list, distance - k * cue.spacing)
	end
	return list
end

-- The most chevrons a lane holds (the client's pool).
function GuideTrail.most(cue): number
	return math.floor((cue.laneLength - cue.laneStart) / cue.spacing) + 1
end

-- Where the client finds the ground for the rails: the lane's start, each chevron, its end.
function GuideTrail.stops(cue, distance: number): { number }
	local from, to = GuideTrail.lane(cue, distance)
	if not (from and to) then
		return {}
	end
	local list = GuideTrail.chevrons(cue, distance)
	table.insert(list, 1, from)
	table.insert(list, to)
	return list
end

local function offset(p: Point, right: Point, k: number): Point
	return { X = p.X + right.X * k, Y = p.Y + right.Y * k, Z = p.Z + right.Z * k }
end

-- The two rails over ground `points` (the stops', in order; false where no ground was found, which
-- breaks the rails): for each pair of neighbours, the segment `halfWidth` studs to the left and to
-- the right of them along the lane's unit `right`.
function GuideTrail.rails(points: { Point | false }, right: Point, halfWidth: number): ({ Segment }, { Segment })
	local left, rightSide = {}, {}
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if a and b then
			local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
			if dx * dx + dy * dy + dz * dz >= MIN_SEGMENT * MIN_SEGMENT then
				table.insert(left, { from = offset(a, right, -halfWidth), to = offset(b, right, -halfWidth) })
				table.insert(rightSide, { from = offset(a, right, halfWidth), to = offset(b, right, halfWidth) })
			end
		end
	end
	return left, rightSide
end

-- How lit (0..1) a chevron `ahead` studs along is, `seconds` in: a wave running toward the goal.
function GuideTrail.pulse(cue, ahead: number, seconds: number): number
	local phase = (ahead - seconds * cue.pulseSpeed) / cue.pulseLength
	return 0.5 + 0.5 * math.cos(phase * 2 * math.pi)
end

return GuideTrail
