--!strict
-- The staff's motion as data (client/Staff plays it on their R15 bodies with the roblox-animation
-- runtime, ReplicatedStorage.Animation): keyed clips (Performance format: parts in the character's
-- own axes, degrees, rig units of one stud on R15) and gait options for Gait.cycle. Baked once per
-- rig on the client and linted offline in Lune (tests/StaffClips.spec) until no [fix] remains.
-- House style: restraint. Weight from the hips, uneven key timing, no springs, no overshoot; the
-- runtime's overlap, mirror and drift passes keep it from reading as machine-made.
-- rot = { pitch, yaw, roll }: +pitch lifts a hanging arm forward and tips a body part back, +yaw
-- turns left, +roll swings the right arm out (the left arm in).

local StaffClips = {}

-- Walking (Gait.cycle, in place; client/Staff moves the body at the same speed, so the feet stay
-- planted). 5 studs/s is a brisk walk for R15 (Froude 0.4); 6 makes the feet slide. Carrying is
-- slower, and its arms are held by `clips.carry` (StaffClips.overlay).
StaffClips.gaits = {
	walk = { speed = 5, style = "walk", seed = "StaffWalk" },
	walkCarry = { speed = 4.5, style = "walk", seed = "StaffCarry" },
}

-- The hold the arms keep while carrying: a full tool in front at the waist.
local HOLD = {
	rightArm = { rot = { 34, 0, -12 } },
	rightForearm = { rot = { 58, 0, 0 } },
	leftArm = { rot = { 34, 0, 12 } },
	leftForearm = { rot = { 58, 0, 0 } },
}

local REST_ARMS = {
	rightArm = { rot = { 0, 0, 0 } },
	rightForearm = { rot = { 0, 0, 0 } },
	leftArm = { rot = { 0, 0, 0 } },
	leftForearm = { rot = { 0, 0, 0 } },
}

local function with(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

local STILL_HIPS = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } }

StaffClips.clips = {
	-- Standing about: one slow weight shift and one glance away and back.
	idle = {
		name = "StaffIdle",
		length = 6.2,
		loop = true,
		tracks = {
			hips = {
				{ t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
				{ t = 2.1, pos = { 0.04, -0.02, 0 }, rot = { 0, 1, -1.2 } },
				{ t = 4.3, pos = { 0.03, -0.012, 0 }, rot = { 0, 0.4, -0.8 } },
				{ t = 6.2, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
			},
			head = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 1.7, rot = { 0, 0, 0 } },
				{ t = 2.5, rot = { -3, 14, 0 } },
				{ t = 3.6, rot = { -2, 13, 0 } },
				{ t = 4.6, rot = { 0, 0, 0 } },
				{ t = 6.2, rot = { 0, 0, 0 } },
			},
		},
		seed = "StaffIdle",
	},

	-- Into the carry hold; its last pose is laid over the carrying walk (StaffClips.overlay). No
	-- drift, so only the arms move and the overlay takes nothing else. A slow lift: only its end is
	-- used, and a quick one reads to the lint as a strike.
	carry = {
		name = "StaffCarry",
		length = 0.9,
		polish = { drift = 0 },
		keys = {
			{ t = 0, pose = REST_ARMS },
			{ t = 0.9, pose = HOLD },
		},
		seed = "StaffCarry",
	},

	-- Bend from the hips, sweep both hands through the water, rise with the tool held in front.
	scoop = {
		name = "StaffScoop",
		length = 1.5,
		keys = {
			{ t = 0, pose = with(REST_ARMS, { hips = STILL_HIPS, chest = { rot = { 0, 0, 0 } }, head = { rot = { 0, 0, 0 } } }) },
			{
				t = 0.38,
				pose = {
					hips = { pos = { 0, -0.22, 0.12 }, rot = { -16, 0, 0 } },
					chest = { rot = { -12, 0, 0 } },
					head = { rot = { 10, 0, 0 } },
					rightArm = { rot = { 52, 0, -8 } },
					rightForearm = { rot = { 18, 0, 0 } },
					leftArm = { rot = { 38, 0, 10 } },
					leftForearm = { rot = { 30, 0, 0 } },
				},
			},
			{
				t = 0.74,
				pose = {
					hips = { pos = { 0, -0.28, 0.17 }, rot = { -22, 0, 0 } },
					chest = { rot = { -16, 0, 0 } },
					head = { rot = { 14, 0, 0 } },
					rightArm = { rot = { 68, 0, -10 } },
					rightForearm = { rot = { 46, 0, 0 } },
					leftArm = { rot = { 56, 0, 12 } },
					leftForearm = { rot = { 60, 0, 0 } },
				},
			},
			{
				t = 1.05,
				pose = with(HOLD, { hips = { pos = { 0, -0.08, 0.04 }, rot = { -6, 0, 0 } }, chest = { rot = { -3, 0, 0 } }, head = { rot = { 3, 0, 0 } } }),
			},
			{ t = 1.5, pose = with(REST_ARMS, { hips = STILL_HIPS, chest = { rot = { 0, 0, 0 } }, head = { rot = { 0, 0, 0 } } }) },
		},
		seed = "StaffScoop",
	},

	-- From the carry hold: lift the tool forward, tip it out, and let the arms down.
	pour = {
		name = "StaffPour",
		length = 1.3,
		-- tipping a tool out is a gesture, not a strike: nothing is hit, so the hips need not drive it
		waive = { "no-body-commitment" },
		keys = {
			{ t = 0, pose = with(HOLD, { hips = STILL_HIPS, chest = { rot = { 0, 0, 0 } }, rightHand = { rot = { 0, 0, 0 } }, leftHand = { rot = { 0, 0, 0 } } }) },
			{
				t = 0.32,
				pose = {
					hips = { pos = { 0, -0.05, -0.04 }, rot = { -3, 0, 0 } },
					chest = { rot = { -6, 0, 0 } },
					rightArm = { rot = { 72, 0, -8 } },
					rightForearm = { rot = { 32, 0, 0 } },
					leftArm = { rot = { 60, 0, 10 } },
					leftForearm = { rot = { 44, 0, 0 } },
				},
			},
			{
				t = 0.6,
				pose = {
					hips = { pos = { 0, -0.07, -0.06 }, rot = { -5, 0, 0 } },
					chest = { rot = { -9, 0, 0 } },
					rightArm = { rot = { 82, 0, -6 } },
					rightForearm = { rot = { 18, 0, 0 } },
					rightHand = { rot = { -35, 0, 0 } },
					leftArm = { rot = { 72, 0, 9 } },
					leftForearm = { rot = { 28, 0, 0 } },
					leftHand = { rot = { -24, 0, 0 } },
				},
			},
			{
				t = 0.86,
				pose = {
					hips = { pos = { 0, -0.06, -0.05 }, rot = { -4, 0, 0 } },
					chest = { rot = { -8, 0, 0 } },
					rightArm = { rot = { 78, 0, -6 } },
					rightForearm = { rot = { 20, 0, 0 } },
					rightHand = { rot = { -38, 0, 0 } },
					leftArm = { rot = { 70, 0, 9 } },
					leftForearm = { rot = { 30, 0, 0 } },
					leftHand = { rot = { -27, 0, 0 } },
				},
			},
			{ t = 1.3, pose = with(REST_ARMS, { hips = STILL_HIPS, chest = { rot = { 0, 0, 0 } }, rightHand = { rot = { 0, 0, 0 } }, leftHand = { rot = { 0, 0, 0 } } }) },
		},
		seed = "StaffPour",
	},

	-- Both arms straight up with a dip of the hips, one pump, and down; the left arm follows the right
	-- a few frames later. The arms rise by pitch alone (a roll on top of a big pitch twists the shoulder).
	cheer = {
		name = "StaffCheer",
		length = 1.75,
		-- a cheer is a gesture, not a strike: nothing is hit, so the hips need not drive it
		waive = { "no-body-commitment" },
		tracks = {
			hips = {
				{ t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
				{ t = 0.22, pos = { 0, -0.12, 0.02 }, rot = { -4, 0, 0 } },
				{ t = 0.55, pos = { 0, -0.02, 0 }, rot = { 1, 0, 0 } },
				{ t = 0.86, pos = { 0, -0.06, 0 }, rot = { 0, 0, 0 } },
				{ t = 1.08, pos = { 0, -0.02, 0 }, rot = { 1, 0, 0 } },
				{ t = 1.75, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
			},
			head = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.22, rot = { -2, 0, 0 } },
				{ t = 0.58, rot = { 12, 0, 0 } },
				{ t = 0.88, rot = { 9, 0, 0 } },
				{ t = 1.1, rot = { 11, 0, 0 } },
				{ t = 1.75, rot = { 0, 0, 0 } },
			},
			rightArm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.2, rot = { 0, 0, 0 } },
				{ t = 0.55, rot = { 160, 0, 0 } },
				{ t = 0.86, rot = { 148, 0, 0 } },
				{ t = 1.08, rot = { 162, 0, 0 } },
				{ t = 1.66, rot = { 0, 0, 0 } },
			},
			rightForearm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.2, rot = { 0, 0, 0 } },
				{ t = 0.55, rot = { 14, 0, 0 } },
				{ t = 0.86, rot = { 34, 0, 0 } },
				{ t = 1.08, rot = { 12, 0, 0 } },
				{ t = 1.66, rot = { 0, 0, 0 } },
			},
			leftArm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.29, rot = { 0, 0, 0 } },
				{ t = 0.66, rot = { 146, 0, 0 } },
				{ t = 0.95, rot = { 134, 0, 0 } },
				{ t = 1.17, rot = { 150, 0, 0 } },
				{ t = 1.75, rot = { 0, 0, 0 } },
			},
			leftForearm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.29, rot = { 0, 0, 0 } },
				{ t = 0.66, rot = { 26, 0, 0 } },
				{ t = 0.95, rot = { 46, 0, 0 } },
				{ t = 1.17, rot = { 22, 0, 0 } },
				{ t = 1.75, rot = { 0, 0, 0 } },
			},
		},
		seed = "StaffCheer",
	},

	-- Helper: the right hand raised (by pitch alone, no shoulder twist), a few easy waves of the forearm.
	wave = {
		name = "StaffWave",
		length = 1.9,
		-- a wave is a gesture, not a strike: nothing is hit, so the hips need not drive it
		waive = { "no-body-commitment" },
		tracks = {
			hips = {
				{ t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
				{ t = 0.4, pos = { -0.04, -0.03, 0 }, rot = { 0, 0, 1.5 } },
				{ t = 1.4, pos = { -0.03, -0.02, 0 }, rot = { 0, 0, 1 } },
				{ t = 1.9, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
			},
			head = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.45, rot = { 3, 0, -4 } },
				{ t = 1.5, rot = { 2, 0, -3 } },
				{ t = 1.9, rot = { 0, 0, 0 } },
			},
			rightArm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.42, rot = { 148, 0, 0 } },
				{ t = 1.42, rot = { 144, 0, 0 } },
				{ t = 1.9, rot = { 0, 0, 0 } },
			},
			rightForearm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.42, rot = { 24, 0, 0 } },
				{ t = 0.68, rot = { 24, 0, 22 } },
				{ t = 0.95, rot = { 22, 0, -16 } },
				{ t = 1.2, rot = { 23, 0, 18 } },
				{ t = 1.42, rot = { 22, 0, -5 } },
				{ t = 1.9, rot = { 0, 0, 0 } },
			},
		},
		seed = "StaffWave",
	},

	-- Lifeguard: whistle to the mouth, the other hand pointing out over the water.
	whistle = {
		name = "StaffWhistle",
		length = 1.7,
		-- a hand to the mouth is a gesture, not a strike: nothing is hit, so the hips need not drive it
		waive = { "no-body-commitment" },
		tracks = {
			hips = {
				{ t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
				{ t = 0.3, pos = { 0, -0.04, 0.02 }, rot = { 0, 4, 0 } },
				{ t = 1.25, pos = { 0, -0.03, 0.02 }, rot = { 0, 3, 0 } },
				{ t = 1.7, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
			},
			chest = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.36, rot = { 3, 6, 0 } },
				{ t = 1.3, rot = { 2, 5, 0 } },
				{ t = 1.7, rot = { 0, 0, 0 } },
			},
			head = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.4, rot = { 6, -4, 0 } },
				{ t = 1.3, rot = { 5, -3, 0 } },
				{ t = 1.7, rot = { 0, 0, 0 } },
			},
			rightArm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.34, rot = { 68, 0, -30 } },
				{ t = 1.28, rot = { 66, 0, -28 } },
				{ t = 1.7, rot = { 0, 0, 0 } },
			},
			rightForearm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.34, rot = { 120, 0, 0 } },
				{ t = 1.28, rot = { 118, 0, 0 } },
				{ t = 1.7, rot = { 0, 0, 0 } },
			},
			leftArm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.5, rot = { 82, 0, 6 } },
				{ t = 1.2, rot = { 80, 0, 4 } },
				{ t = 1.7, rot = { 0, 0, 0 } },
			},
			leftForearm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.5, rot = { 6, 0, 0 } },
				{ t = 1.2, rot = { 8, 0, 0 } },
				{ t = 1.7, rot = { 0, 0, 0 } },
			},
		},
		seed = "StaffWhistle",
	},

	-- Firefighter: both hands on the hose at the waist, a slow sweep from the chest.
	hoseSpray = {
		name = "StaffHoseSpray",
		length = 2.6,
		tracks = {
			hips = {
				{ t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
				{ t = 0.35, pos = { 0, -0.07, 0.03 }, rot = { -2, 0, 0 } },
				{ t = 2.15, pos = { 0, -0.06, 0.03 }, rot = { -2, 0, 0 } },
				{ t = 2.6, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
			},
			chest = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.4, rot = { -4, 0, 0 } },
				{ t = 0.95, rot = { -4, 13, 0 } },
				{ t = 1.6, rot = { -5, -11, 0 } },
				{ t = 2.1, rot = { -4, 2, 0 } },
				{ t = 2.6, rot = { 0, 0, 0 } },
			},
			rightArm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.36, rot = { 44, 0, -10 } },
				{ t = 2.15, rot = { 42, 0, -9 } },
				{ t = 2.6, rot = { 0, 0, 0 } },
			},
			rightForearm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.36, rot = { 42, 0, 0 } },
				{ t = 2.15, rot = { 40, 0, 0 } },
				{ t = 2.6, rot = { 0, 0, 0 } },
			},
			leftArm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.4, rot = { 56, 0, 16 } },
				{ t = 2.1, rot = { 54, 0, 15 } },
				{ t = 2.6, rot = { 0, 0, 0 } },
			},
			leftForearm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.4, rot = { 52, 0, 0 } },
				{ t = 2.1, rot = { 50, 0, 0 } },
				{ t = 2.6, rot = { 0, 0, 0 } },
			},
		},
		seed = "StaffHoseSpray",
	},

	-- Plumber: down on bent knees at a building, ratcheting a wrench in short pulls; the hips sit back
	-- into each pull.
	wrench = {
		name = "StaffWrench",
		length = 2.3,
		tracks = {
			hips = {
				{ t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
				{ t = 0.45, pos = { 0, -0.34, 0.1 }, rot = { -12, 0, 0 } },
				{ t = 0.78, pos = { 0, -0.4, 0.16 }, rot = { -10, 0, 0 } },
				{ t = 1.1, pos = { 0, -0.34, 0.1 }, rot = { -12, 0, 0 } },
				{ t = 1.45, pos = { 0, -0.39, 0.15 }, rot = { -10, 0, 0 } },
				{ t = 1.85, pos = { 0, -0.32, 0.09 }, rot = { -11, 0, 0 } },
				{ t = 2.3, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
			},
			chest = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.5, rot = { -8, 0, 0 } },
				{ t = 1.8, rot = { -7, 0, 0 } },
				{ t = 2.3, rot = { 0, 0, 0 } },
			},
			rightArm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.45, rot = { 58, 0, -10 } },
				{ t = 0.78, rot = { 64, 0, -10 } },
				{ t = 1.1, rot = { 57, 0, -9 } },
				{ t = 1.45, rot = { 63, 0, -10 } },
				{ t = 1.85, rot = { 58, 0, -10 } },
				{ t = 2.3, rot = { 0, 0, 0 } },
			},
			rightForearm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.45, rot = { 52, 0, 0 } },
				{ t = 0.78, rot = { 78, 0, 0 } },
				{ t = 1.1, rot = { 50, 0, 0 } },
				{ t = 1.45, rot = { 76, 0, 0 } },
				{ t = 1.85, rot = { 54, 0, 0 } },
				{ t = 2.3, rot = { 0, 0, 0 } },
			},
			leftArm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.5, rot = { 40, 0, 14 } },
				{ t = 1.8, rot = { 38, 0, 13 } },
				{ t = 2.3, rot = { 0, 0, 0 } },
			},
			leftForearm = {
				{ t = 0, rot = { 0, 0, 0 } },
				{ t = 0.5, rot = { 62, 0, 0 } },
				{ t = 1.8, rot = { 60, 0, 0 } },
				{ t = 2.3, rot = { 0, 0, 0 } },
			},
		},
		seed = "StaffWrench",
	},
}

-- Each staff job's own move (client/Staff plays it now and then on their loop).
StaffClips.signature = { helper = "wave", lifeguard = "whistle", firefighter = "hoseSpray", plumber = "wrench" }

-- `base` (a bake, Gait.cycle) with each channel `top` (a compacted bake of the same rig: Baked.compact
-- keeps only the channels it moves) held at top's last pose in every sample: the carry hold laid
-- over the carrying walk. Changes and returns `base`. Baked data: per sample, channel 0 (the root)
-- then each joint channel, 7 numbers apiece; `joints[c]` is channel c's rig joint.
function StaffClips.overlay(base, top)
	local last = (top.count - 1) * top.stride
	for c = 1, top.nch do
		local into = table.find(base.joints, top.joints[c])
		if into then
			for s = 0, base.count - 1 do
				local at = s * base.stride + into * 7
				for k = 1, 7 do
					base.data[at + k] = top.data[last + c * 7 + k]
				end
			end
		end
	end
	return base
end

return StaffClips
