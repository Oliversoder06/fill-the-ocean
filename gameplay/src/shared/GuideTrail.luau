-- The guide's ground chevrons (client/Guide): where each one sits along the straight line from the
-- player to a goal. They slide toward the goal and loop, show only over the next stretch and hide
-- near the goal; a brightness wave runs along them, faster than they slide. Pure: no requires, so
-- Lune tests and Roblox load it the same way.
local GuideTrail = {}

GuideTrail.COUNT = 10 -- chevrons in the trail
GuideTrail.SPACING = 3 -- studs between neighbours
GuideTrail.START = 3 -- studs ahead of the player where each one appears
GuideTrail.SPEED = 2 -- studs a second they slide toward the goal
GuideTrail.SHOW = 30 -- studs ahead beyond which none shows
GuideTrail.HIDE_NEAR = 8 -- studs from the goal within which the whole trail hides
GuideTrail.PULSE_SPEED = 12 -- studs a second the brightness wave runs toward the goal
GuideTrail.PULSE_LENGTH = 12 -- studs from one crest to the next

-- Studs ahead of the player of chevron `i` (1..COUNT), `seconds` into the slide.
function GuideTrail.ahead(i: number, seconds: number): number
	local loop = GuideTrail.COUNT * GuideTrail.SPACING
	return GuideTrail.START + ((i - 1) * GuideTrail.SPACING + seconds * GuideTrail.SPEED) % loop
end

-- How lit (0..1) a chevron `ahead` studs along is, `seconds` in: a wave running toward the goal.
function GuideTrail.pulse(ahead: number, seconds: number): number
	local phase = (ahead - seconds * GuideTrail.PULSE_SPEED) / GuideTrail.PULSE_LENGTH
	return 0.5 + 0.5 * math.cos(phase * 2 * math.pi)
end

-- Whether a chevron `ahead` studs along shows while the goal is `distance` studs away.
function GuideTrail.shows(ahead: number, distance: number): boolean
	return distance > GuideTrail.HIDE_NEAR and ahead <= GuideTrail.SHOW and ahead < distance
end

return GuideTrail
