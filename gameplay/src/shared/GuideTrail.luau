-- The guide's lane (client/Guide): a flat lane from the player along the straight line to a goal,
-- just below the camera, wide chevrons every `spacing` studs sliding forward at `scrollSpeed`,
-- between two rails `laneHalfWidth` either side. The lane runs from laneStart to laneLength studs
-- ahead and never within hideNear of the goal; chevrons fade in and out over edgeFade studs at its
-- ends. Distances are flat studs ahead of the player; numbers come from `cue` (Cues.guide). Pure: no
-- requires, so Lune tests and Roblox load it the same way.
local GuideTrail = {}

-- The lane's stretch while the goal is `distance` studs away: studs ahead of the player it runs
-- from and to, or nil when none shows.
function GuideTrail.lane(cue, distance: number): (number?, number?)
	local to = math.min(cue.laneLength, distance - cue.hideNear)
	if to <= cue.laneStart then
		return nil, nil
	end
	return cue.laneStart, to
end

-- Studs ahead of the player of each chevron, nearest first, `seconds` into the slide.
function GuideTrail.chevrons(cue, distance: number, seconds: number): { number }
	local list = {}
	local from, to = GuideTrail.lane(cue, distance)
	if not (from and to) then
		return list
	end
	local ahead = from + (seconds * cue.scrollSpeed) % cue.spacing
	while ahead <= to do
		table.insert(list, ahead)
		ahead += cue.spacing
	end
	return list
end

-- The most chevrons a lane holds (the client's pool).
function GuideTrail.most(cue): number
	return math.floor((cue.laneLength - cue.laneStart) / cue.spacing) + 1
end

-- How visible (0..1) a chevron `ahead` studs along is in a lane from `from` to `to`.
function GuideTrail.fade(cue, ahead: number, from: number, to: number): number
	return math.clamp(math.min(ahead - from, to - ahead) / cue.edgeFade, 0, 1)
end

return GuideTrail
