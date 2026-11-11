-- The guide's lane (client/Guide): a flat textured Beam from inside the player along the straight
-- line to a goal, just below the camera; its texture carries the rails and the sliding chevrons.
-- The lane runs from laneStart to laneLength studs ahead and never within hideNear of the goal.
-- Distances are flat studs ahead of the player; numbers come from `cue` (Cues.guide). Pure: no
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

return GuideTrail
