--!strict
-- Pure maths for how characters hold their tool and move in third person (client/Bodies).
-- Lune-tested. Lengths in studs, angles in radians. Torso space: X right, Y up, Z back.

local BodyPose = {}

export type Style = {
	reach: { number }, -- right hand from the right shoulder, in arm lengths (torso space)
	hand: number, -- hand pitch in torso space: 0 fingers down, pi/2 fingers forward, pi fingers up
	pole: { number }, -- which way the right elbow points (torso space); mirrored for the left arm
	twoHanded: boolean, -- the left hand holds the tool too (mirrored across the body)
	heavy: boolean, -- leans back and waddles while carrying water
}

BodyPose.STYLES = {
	hand = { reach = { -0.15, -0.35, -0.55 }, hand = math.pi / 2, pole = { 0.6, -1, 0.4 }, twoHanded = false, heavy = false },
	hang = { reach = { 0.08, -0.9, -0.15 }, hand = 0, pole = { 0.3, 0, 1 }, twoHanded = false, heavy = false },
	hug = { reach = { -0.25, -0.45, -0.5 }, hand = math.pi / 2, pole = { 1, -0.6, 0.3 }, twoHanded = true, heavy = true },
	overhead = { reach = { -0.2, 1.6, 0 }, hand = math.pi, pole = { 1, -0.2, 0.2 }, twoHanded = true, heavy = true }, -- past full reach: arms straight up, so the head clears
} :: { [string]: Style }

-- How each hero tool is carried, and how far it is turned about the vertical, so its grip
-- (art/manifest.json "origin") sits in the hand: side-gripped tubs and pools reach away from you.
BodyPose.CARRY = {
	Spoon = { style = "hand", turn = 0 },
	Cup = { style = "hand", turn = 0 },
	Bucket = { style = "hang", turn = 0 },
	Bathtub = { style = "hug", turn = math.pi / 2 },
	KiddiePool = { style = "hug", turn = math.pi / 2 },
	SwimmingPool = { style = "overhead", turn = math.pi / 2 },
	CargoShip = { style = "overhead", turn = 0 },
	TheMoon = { style = "overhead", turn = 0 },
}

-- The carry style and turn for a tool model. Unknown models are held like a spoon.
function BodyPose.carry(modelName: string): (Style, number)
	local entry = BodyPose.CARRY[modelName]
	if not entry then
		return BodyPose.STYLES.hand, 0
	end
	return BodyPose.STYLES[entry.style], entry.turn
end

BodyPose.REACH_MARGIN = 1e-3

-- Two-bone reach (shoulder, elbow, wrist): for a target `distance` from the shoulder, the elbow's
-- distance along the shoulder-to-target line, its offset toward the pole, and the distance the arm
-- actually reaches (clamped to what it can).
function BodyPose.elbow(upper: number, lower: number, distance: number): (number, number, number)
	local reach = math.clamp(distance, math.abs(upper - lower) + BodyPose.REACH_MARGIN, upper + lower - BodyPose.REACH_MARGIN)
	local along = (upper * upper - lower * lower + reach * reach) / (2 * reach)
	return along, math.sqrt(math.max(0, upper * upper - along * along)), reach
end

-- Thigh angle (hips and ankles bend by it, knees by twice it) that lowers the hips by `dip`
-- while the feet stay put, for legs whose two halves are `thigh` long.
function BodyPose.crouch(dip: number, thigh: number): number
	if dip <= 0 or thigh <= 0 then
		return 0
	end
	return math.acos(math.clamp(1 - dip / (2 * thigh), -1, 1))
end

-- Walk: the body rises as the legs pass each other and sinks as they spread, and the upper body
-- twists against the legs. `swing` is the animated hip angle; `intensity` is 0 standing, 1 walking.
-- A heavy load bounces more and waddles side to side (roll, positive leans left).
BodyPose.BOUNCE = 0.12 -- studs
BodyPose.TWIST = math.rad(4)
BodyPose.HEAVY_BOUNCE = 1.6
BodyPose.WADDLE = math.rad(5)

function BodyPose.stride(swing: number, maxSwing: number, intensity: number, heavy: boolean?): (number, number, number)
	local s = if maxSwing > 1e-3 then math.clamp(swing / maxSwing, -1, 1) else 0
	local bounce = BodyPose.BOUNCE * intensity * (1 - 2 * math.abs(s))
	if heavy then
		return bounce * BodyPose.HEAVY_BOUNCE, -BodyPose.TWIST * intensity * s, BodyPose.WADDLE * intensity * s
	end
	return bounce, -BodyPose.TWIST * intensity * s, 0
end

-- Upper-body pitch (negative leans forward) and whole-body roll (positive leans left).
BodyPose.LEAN_PER_SPEED = math.rad(3) / 16 -- radians per stud/s of forward speed
BodyPose.LEAN_MAX = math.rad(10)
BodyPose.ROLL_PER_TURN = math.rad(4) -- radians per radian/s of turning, at walking speed
BodyPose.ROLL_MAX = math.rad(8)
BodyPose.HEAVY_BACK = math.rad(7)
BodyPose.WALK_SPEED = 16

function BodyPose.lean(forward: number, speed: number, turnRate: number, heavy: boolean): (number, number)
	local pitch = -math.clamp(forward * BodyPose.LEAN_PER_SPEED, -BodyPose.LEAN_MAX, BodyPose.LEAN_MAX)
	if heavy then
		pitch += BodyPose.HEAVY_BACK
	end
	local moving = math.min(speed / BodyPose.WALK_SPEED, 1)
	return pitch, math.clamp(turnRate * BodyPose.ROLL_PER_TURN * moving, -BodyPose.ROLL_MAX, BodyPose.ROLL_MAX)
end

-- Where a player looks (pitch in degrees, up positive), split as (neck, waist) pitch.
BodyPose.LOOK_MAX = math.rad(60)
BodyPose.NECK_SHARE = 0.65

function BodyPose.look(pitchDegrees: number): (number, number)
	local p = math.clamp(math.rad(pitchDegrees), -BodyPose.LOOK_MAX, BodyPose.LOOK_MAX)
	return p * BodyPose.NECK_SHARE, p * (1 - BodyPose.NECK_SHARE)
end

-- Landing: how far a fall at `fallSpeed` (studs/s) pushes the hips down. A spring brings them back.
BodyPose.DIP_FROM_SPEED = 12
BodyPose.DIP_PER_SPEED = 0.012
BodyPose.DIP_MAX = 0.45
BodyPose.DIP_SPRING = 120
BodyPose.DIP_DAMPING = 0.6

function BodyPose.landDip(fallSpeed: number): number
	return math.clamp((fallSpeed - BodyPose.DIP_FROM_SPEED) * BodyPose.DIP_PER_SPEED, 0, BodyPose.DIP_MAX)
end

-- Third-person scoop and pour from the first-person pose curves (shared/ToolView), so everyone's
-- actions keep the same timing: the grip drops (studs, negative lifts) and moves forward, the tool
-- tips by `tilt`, and the upper body bends over by `bend`.
BodyPose.ACTION_DOWN = 2.2 -- grip studs per first-person stud
BodyPose.ACTION_FORWARD = 1.2
BodyPose.ACTION_BEND = math.rad(55) -- per first-person stud of dip

function BodyPose.fromView(down: number, tilt: number): (number, number, number, number)
	local dip = math.max(down, 0)
	return down * BodyPose.ACTION_DOWN, dip * BodyPose.ACTION_FORWARD, tilt, dip * BodyPose.ACTION_BEND
end

return BodyPose
