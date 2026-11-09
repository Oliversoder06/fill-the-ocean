-- The guide's ground chevrons (client/Guide): where each one sits along the straight line from the
-- player to a goal. They slide toward the goal and loop, show only over the next stretch and hide
-- near the goal. Pure: no requires, so Lune tests and Roblox load it the same way.
local GuideTrail = {}

GuideTrail.COUNT = 8 -- chevrons in the trail
GuideTrail.SPACING = 4 -- studs between neighbours
GuideTrail.START = 3 -- studs ahead of the player where each one appears
GuideTrail.SPEED = 2 -- studs a second they slide toward the goal
GuideTrail.SHOW = 30 -- studs ahead beyond which none shows
GuideTrail.HIDE_NEAR = 8 -- studs from the goal within which the whole trail hides

-- Studs ahead of the player of chevron `i` (1..COUNT), `seconds` into the slide.
function GuideTrail.ahead(i: number, seconds: number): number
	local loop = GuideTrail.COUNT * GuideTrail.SPACING
	return GuideTrail.START + ((i - 1) * GuideTrail.SPACING + seconds * GuideTrail.SPEED) % loop
end

-- Whether a chevron `ahead` studs along shows while the goal is `distance` studs away.
function GuideTrail.shows(ahead: number, distance: number): boolean
	return distance > GuideTrail.HIDE_NEAR and ahead <= GuideTrail.SHOW and ahead < distance
end

return GuideTrail
