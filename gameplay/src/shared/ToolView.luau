--!strict
-- Pure size and pose maths for held tools. Lune-tested.

local ToolView = {}

ToolView.VIEW_START = 0.8 -- studs, longest side of the first tool on screen
ToolView.VIEW_MAX = 1.7 -- approached but never reached, so the last tool stays in the corner
ToolView.VIEW_GROWTH = 0.85
ToolView.HELD_MAX = 6 -- studs, longest side of a tool in another player's hand

function ToolView.viewSize(tier: number): number
	return ToolView.VIEW_MAX - (ToolView.VIEW_MAX - ToolView.VIEW_START) * ToolView.VIEW_GROWTH ^ (tier - 1)
end

-- First-person poses, as (down, side, tilt): down in studs (positive lowers the tool), side in
-- studs (negative moves it toward the screen centre), tilt in radians (negative tips it forward).
ToolView.SCOOP_WINDUP = 0.2 -- share of the sweep spent lifting back before the plunge
ToolView.SCOOP_RISE = 0.08
ToolView.SCOOP_DOWN = 0.45
ToolView.SCOOP_SIDE = 0.35
ToolView.SCOOP_BACK_TILT = math.rad(10)
ToolView.SCOOP_TILT = math.rad(-35)

ToolView.POUR_TIP = 0.35 -- share of the pour spent tipping over; the rest holds the tip
ToolView.POUR_LIFT = 0.1
ToolView.POUR_SIDE = 0.2
ToolView.POUR_TILT = math.rad(-65)

local function smooth(k: number): number
	return k * k * (3 - 2 * k)
end

-- One sweep through the water: a short wind-up, then a smooth plunge down and toward the centre.
function ToolView.scoopPose(progress: number): (number, number, number)
	local p = math.clamp(progress, 0, 1)
	if p < ToolView.SCOOP_WINDUP then
		local k = p / ToolView.SCOOP_WINDUP
		return -ToolView.SCOOP_RISE * k, 0, ToolView.SCOOP_BACK_TILT * k
	end
	local s = smooth((p - ToolView.SCOOP_WINDUP) / (1 - ToolView.SCOOP_WINDUP))
	return -ToolView.SCOOP_RISE + (ToolView.SCOOP_DOWN + ToolView.SCOOP_RISE) * s,
		-ToolView.SCOOP_SIDE * s,
		ToolView.SCOOP_BACK_TILT + (ToolView.SCOOP_TILT - ToolView.SCOOP_BACK_TILT) * s
end

-- One pour: lift and tip the tool forward, then hold the tip until the pour ends.
function ToolView.pourPose(progress: number): (number, number, number)
	local s = smooth(math.clamp(progress / ToolView.POUR_TIP, 0, 1))
	return -ToolView.POUR_LIFT * s, -ToolView.POUR_SIDE * s, ToolView.POUR_TILT * s
end

-- A newly bought tool swings up from below, tipped back, and springs into place, as (down, tilt)
-- added to the normal pose.
ToolView.REVEAL_DOWN = 1.1
ToolView.REVEAL_TILT = math.rad(50)
ToolView.REVEAL_SECONDS = 0.5
ToolView.REVEAL_OVERSHOOT = 2

function ToolView.revealPose(progress: number): (number, number)
	-- Back-out, the same curve as shared/Ease (pure modules don't require each other).
	local u = math.clamp(progress, 0, 1) - 1
	local s = ToolView.REVEAL_OVERSHOOT
	local k = 1 - (1 + (s + 1) * u * u * u + s * u * u)
	return ToolView.REVEAL_DOWN * k, ToolView.REVEAL_TILT * k
end

function ToolView.heldScale(longestSide: number): number
	return math.min(1, ToolView.HELD_MAX / longestSide)
end

return ToolView
