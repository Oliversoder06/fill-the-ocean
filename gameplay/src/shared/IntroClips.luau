--!strict
-- The intro's motion for your own body (client/Intro plays it with the roblox-animation runtime,
-- ReplicatedStorage.Animation), linted offline in Lune (tests/IntroClips.spec) until no [fix]
-- remains. Same format and house style as StaffClips: restraint, weight from the hips, uneven
-- key timing, no springs, no overshoot.
-- rot = { pitch, yaw, roll }: +pitch lifts a hanging limb forward and tips a body part back, +yaw
-- turns left, +roll swings the right arm or leg out (the left one in).
-- `lie` is played on a body whose root client/Intro has laid back along the lounger's backrest
-- (IntroCut.places.recline), so the thighs lift by the rest of a right angle to lie flat.

local IntroClips = {}

-- The walk up the beach (Gait.cycle, in place; client/Intro moves the body at the same speed, which
-- IntroCut.walkSpeed matches, so the feet stay planted).
IntroClips.gaits = {
	walk = { speed = 5, style = "walk", seed = "IntroWalk" },
}

-- Lying back: legs flat along the cushion, arms along the body, the head forward to the sea.
local REST = {
	hips = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
	chest = { rot = { -5, 0, 0 } },
	head = { rot = { -22, 0, 0 } },
	rightThigh = { rot = { 52, 0, 2 } },
	rightShin = { rot = { -8, 0, 0 } },
	leftThigh = { rot = { 50, 0, -3 } },
	leftShin = { rot = { -6, 0, 0 } },
	rightArm = { rot = { 14, 0, 8 } },
	rightForearm = { rot = { 30, 0, 0 } },
	leftArm = { rot = { 12, 0, -8 } },
	leftForearm = { rot = { 26, 0, 0 } },
}

local function with(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

IntroClips.clips = {
	-- On the lounger: lying still, the head comes up at the bacon-hair far out (spot), a big yawn
	-- with both arms up (by pitch alone: a roll on top of a big pitch twists the shoulder), and down
	-- again folded on the belly, the head rolling aside (asleep soon).
	lie = {
		name = "IntroLie",
		length = 6.6,
		plant = false, -- lying down: no foot is on the ground
		-- a look and a yawn are gestures, not strikes: nothing is hit, so the hips need not drive them
		waive = { "no-body-commitment" },
		keys = {
			{ t = 0, pose = REST },
			{ t = 1.4, pose = REST },
			{ t = 2.1, pose = with(REST, { chest = { rot = { -9, 2, 0 } }, head = { rot = { -30, 7, 0 } } }) },
			{ t = 3.4, pose = with(REST, { chest = { rot = { -8, 2, 0 } }, head = { rot = { -28, 6, 0 } } }) },
			{
				t = 3.8,
				pose = with(REST, {
					chest = { rot = { -4, 0, 0 } },
					head = { rot = { -16, 3, 0 } },
					rightArm = { rot = { 40, 0, 10 } },
					rightForearm = { rot = { 40, 0, 0 } },
					leftArm = { rot = { 30, 0, -10 } },
					leftForearm = { rot = { 36, 0, 0 } },
				}),
			},
			{
				t = 4.55,
				pose = with(REST, {
					chest = { rot = { 8, 0, 0 } },
					head = { rot = { 10, 0, 0 } },
					rightThigh = { rot = { 54, 0, 2 } },
					rightShin = { rot = { -2, 0, 0 } },
					leftThigh = { rot = { 53, 0, -3 } },
					leftShin = { rot = { -2, 0, 0 } },
					rightArm = { rot = { 158, 0, 0 } },
					rightForearm = { rot = { 18, 0, 0 } },
					leftArm = { rot = { 152, 0, 0 } },
					leftForearm = { rot = { 22, 0, 0 } },
				}),
			},
			{
				t = 5.3,
				pose = with(REST, {
					chest = { rot = { 10, 0, 0 } },
					head = { rot = { 13, 0, 0 } },
					rightThigh = { rot = { 54, 0, 2 } },
					rightShin = { rot = { -2, 0, 0 } },
					leftThigh = { rot = { 53, 0, -3 } },
					leftShin = { rot = { -2, 0, 0 } },
					rightArm = { rot = { 162, 0, 0 } },
					rightForearm = { rot = { 14, 0, 0 } },
					leftArm = { rot = { 157, 0, 0 } },
					leftForearm = { rot = { 17, 0, 0 } },
				}),
			},
			{
				t = 6.1,
				pose = with(REST, {
					chest = { rot = { -6, 0, 0 } },
					head = { rot = { -14, -4, 5 } },
					rightArm = { rot = { 20, 0, 4 } },
					rightForearm = { rot = { 68, 0, 0 } },
					leftArm = { rot = { 18, 0, -4 } },
					leftForearm = { rot = { 64, 0, 0 } },
				}),
			},
			{
				t = 6.6,
				pose = with(REST, {
					chest = { rot = { -6, 0, 0 } },
					head = { rot = { -15, -5, 6 } },
					rightArm = { rot = { 20, 0, 4 } },
					rightForearm = { rot = { 70, 0, 0 } },
					leftArm = { rot = { 18, 0, -4 } },
					leftForearm = { rot = { 66, 0, 0 } },
				}),
			},
		},
		markers = { { t = 3.8, name = "Yawn" } },
		seed = "IntroLie",
	},
}

return IntroClips
