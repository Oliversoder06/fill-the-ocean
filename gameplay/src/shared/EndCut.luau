--!strict
-- The ending cutscene as data (client/Ending plays it, server/Run starts it at 100% and ends the run
-- after it). Pure, Lune-tested. The story: the ocean is full again. You lie on your lounger, happy.
-- The bacon-hair strolls down the beach to the water's edge, sits down and dips a straw in. Right
-- before he drinks you get up ("huh?!"), march over and slap him: he flies off over the sea and out
-- of the picture (real gravity: EndCut.flown). You stand by your full ocean; black; the logo.
-- The set is the intro's (IntroCut.places: the lounger, where you lie, the stand); times are seconds
-- from the cut's start (EndingAt on the server's clock); places are studs in the world {x, y, z}.
-- Track keys are { t, v, ease } as in IntroCut.

local EndCut = {}

EndCut.length = 29.0
EndCut.skipAfter = 2 -- seconds in before anyone may skip (the server checks it too)

EndCut.beats = {
	drop = 2.72, -- the music's drop (the intro's track): the first picture
	baconFrom = 6.0, -- he strolls down the beach to the water's edge
	baconTo = 10.0,
	baconSit = 10.0, -- sits down facing the sea
	strawIn = 11.2, -- the straw goes into the water
	sip = 11.6, -- he leans in to drink
	getUp = 11.8, -- you get up: the lie-down backwards (IntroClips.lie), quicker
	marchFrom = 14.9, -- over to him
	marchTo = 18.9,
	slap = 18.9, -- the slap (IntroClips.slap); his flight from its hit
	hit = 19.45,
	wide = 20.8, -- the view rises over your full ocean
}

-- Getting up is the lie-down (IntroClips.lie) backwards: from watching him (its `watched`) quickly back
-- to just lain back (`lain`, over `scrub` seconds), the lie backwards `lie` times faster, then the
-- stand's turn backwards `turn` times faster to where it starts turning (`turnFrom`), facing the sea.
EndCut.getUp = { scrub = 0.4, lie = 2.0, turn = 1.5, lain = 3.5, watched = 8.9, turnFrom = 2.45 }

-- When getting up reaches each part: lain back, sat up (the lie's start), stood facing the sea.
function EndCut.getUpTimes(turnSeconds: number): (number, number, number)
	local g = EndCut.getUp
	local lain = EndCut.beats.getUp + g.scrub
	local sat = lain + g.lain / g.lie
	return lain, sat, sat + (turnSeconds - g.turnFrom) / g.turn
end

EndCut.places = {
	baconFrom = { 78, 0, -40 }, -- his stroll: a curve from here past `baconBend` to `baconTo`
	baconBend = { 99.5, 0, -46 },
	baconTo = { 99.5, 0, -54.6 }, -- where he sits, facing the sea (the full water's edge is at z -57)
	water = { 99.5, 1.2, -59.5 }, -- where the straw dips in (the full ocean's surface is at y 1.4)
	marchBend = { 103.5, 0, -40 }, -- your march from where you lie, past here, to `slapAt`
	slapAt = { 100.6, 0, -52.0 }, -- where you stand to slap him, behind him to his right
}

-- His flight off the slap: `speed` studs/s, `up` degrees over the ground, along `heading` (x, z: out
-- to sea and off to your left, the way the hand swept), tumbling `spin` degrees a second.
EndCut.launch = { speed = 260, up = 38, heading = { -0.35, -0.94 }, spin = 720 }

-- Camera: one smooth take (a spline through the keys) from the drop to the end; subjects as in
-- IntroCut ("player": the middle of your body; "bacon": his head). From over the sea onto you lying
-- there, onto him strolling in and sitting down, low in front of him as the straw goes in, round his
-- side to you getting up; then from the sea side, him in front unaware as you march up behind him and
-- slap him: he flies past the lens and out. Then up and out over your full ocean.
EndCut.shots = {
	{
		name = "take",
		at = 2.72,
		spline = true,
		keys = {
			{ t = 2.72, at = { 58, 42, -225 }, look = { 104, 3, -38 }, fov = 50 },
			{ t = 6.0, at = { 86, 13, -82 }, look = "player", fov = 44 },
			{ t = 9.6, at = { 93, 8, -68 }, look = "bacon", fov = 44 },
			{ t = 11.6, at = { 98.5, 4.4, -63 }, look = { 99.6, 3.6, -55.5 }, fov = 40 },
			{ t = 13.4, at = { 92.5, 6.5, -55 }, look = "player", fov = 46 },
			{ t = 16.6, at = { 95.5, 6.0, -64 }, look = { 101.5, 4.2, -46 }, fov = 46 },
			{ t = 18.6, at = { 100.2, 5.0, -63.5 }, look = { 100.1, 4.6, -53.5 }, fov = 50 },
			{ t = 19.45, at = { 100.2, 5.0, -63.4 }, look = { 100.1, 4.6, -53.5 }, fov = 50 },
			{ t = 20.8, at = { 100.4, 5.4, -63 }, look = "player", fov = 46 },
			{ t = 24.4, at = { 86, 34, -112 }, look = { 103, 3, -44 }, fov = 50 },
			{ t = 29.0, at = { 85, 35, -114 }, look = { 103, 3, -44 }, fov = 50 },
		},
	},
}

EndCut.lids = { { t = 0, v = 0 } }
EndCut.blur = { { t = 0, v = 0 } }

-- Black before the drop and at the end, under the logo.
EndCut.black = {
	{ t = 0, v = 1 },
	{ t = 2.72, v = 0, ease = "step" },
	{ t = 24.6, v = 0 },
	{ t = 25.4, v = 1, ease = "inOut" },
}
EndCut.logoAlpha = {
	{ t = 0, v = 0 },
	{ t = 25.5, v = 0 },
	{ t = 25.7, v = 1, ease = "out" },
}
EndCut.logoScale = {
	{ t = 0, v = 0.6 },
	{ t = 25.5, v = 0.6 },
	{ t = 25.8, v = 1.08, ease = "out" },
	{ t = 26.05, v = 1, ease = "inOut" },
}

-- The music (the intro's track): full, then gone with the picture.
EndCut.music = {
	{ t = 0, v = 1 },
	{ t = 25.0, v = 1 },
	{ t = 28.6, v = 0, ease = "inOut" },
}

EndCut.sounds = {
	{ t = 0, sound = "IntroMusic", volume = 0.5, music = true },
	{ t = 11.7, sound = "IntroHuh", volume = 0.8 },
	{ t = 19.45, sound = "EndSmack", volume = 1 },
	{ t = 19.47, sound = "IntroWhoosh", volume = 0.5 },
}

EndCut.shakes = {
	{ at = 19.45, seconds = 0.3, studs = 0.08, cycles = 4 },
}

-- His flight `tau` seconds after the hit, under `gravity`: how far he has gone from where he sat
-- ({x, y, z}) and how far he has tumbled (degrees).
function EndCut.flown(tau: number, gravity: number): ({ number }, number)
	local l = EndCut.launch
	local up = math.rad(l.up)
	local across, rise = l.speed * math.cos(up), l.speed * math.sin(up)
	local hx, hz = l.heading[1], l.heading[2]
	local flat = math.sqrt(hx * hx + hz * hz)
	return { across * hx / flat * tau, rise * tau - gravity * tau * tau / 2, across * hz / flat * tau }, l.spin * tau
end

return EndCut
