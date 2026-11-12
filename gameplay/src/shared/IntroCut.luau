--!strict
-- The intro cutscene as data (client/Intro plays it, server/Run starts and ends it). Pure, Lune-tested.
-- The story: the ocean is full. You walk up the beach to your lounger, stretch with a yawn, sit on
-- its edge, swing your legs up and lie back. The bacon-hair strolls onto the beach in front of you,
-- sits down and plays in the sand; you watch him, your eyes get heavy and close. In the dark: a
-- slurp, far away. You wake to a dry ocean, and the view goes (no cut) to him far out, round as a
-- ball, sucking the last puddle up through a straw. He sees you, burps and rolls off. You get up:
-- the view rises into your own eyes, the spoon comes up into your hand, and play starts there.
-- One camera take runs from the music's drop until your eyes close (no cuts: a spline through
-- the keys); the only cuts are into the opening and into the dark. The cut's last frame is the
-- game's first: from `handover` the camera is the game's own (client/Intro).
-- Times are seconds from the cut's start (IntroAt on the server's clock). Places are studs in the
-- world {x, y, z} (the beach runs along X, the sea lies toward -Z). Track keys are { t, v, ease }:
-- the ease shapes the move INTO that key ("step" holds the last value until it).

local IntroCut = {}

IntroCut.length = 46.8
IntroCut.skipAfter = 2 -- seconds in before anyone may skip (the server checks it too)
IntroCut.handover = 45.8 -- the camera is the game's from here; the spoon swings up; play at `length`

-- Story beats.
IntroCut.beats = {
	drop = 2.72, -- the music's drop: the first picture and the logo
	walkFrom = 3.8, -- up the beach to the lounger
	walkTo = 9.6,
	lie = 9.6, -- IntroClips.lie from here: stretch, turn, sit, legs up, lie back, watch, doze
	baconFrom = 16.0, -- the bacon-hair strolls onto the beach
	baconTo = 19.6,
	baconSit = 19.6, -- sits down in the sand
	baconPlay = 20.8, -- and plays in it
	pov = 24.0, -- the camera is in your eyes
	swap = 28.2, -- eyes shut: the water goes, he turns into the ball with the straw far out
	wake = 31.4,
	drink = 34.8, -- the last puddle goes up the straw
	drunk = 37.2,
	notice = 37.6, -- he sees you
	burp = 38.3, -- the whole burp plays out before he moves
	roll = 41.2, -- and rolls off
	rollEnd = 44.4,
	back = 44.2, -- you get up: into your own eyes, standing
	sigh = 46.0,
}

IntroCut.places = {
	walkFrom = { 105.6, 0, 6.4 }, -- y: the ground under it
	walkTo = { 106.9, 0, -27.6 }, -- beside the lounger, facing the sea
	stand = { 106.0, 0, -26.9 }, -- where you stand when play starts
	standLook = { -0.2, -0.14, -0.97 }, -- and which way you look then (out to sea)
	lounger = { 109, 3.04, -28 }, -- the place's lounger nearest this (workspace.Map.Beach)
	-- its copy turned round to face the sea: the cushion's edge on your side, its middle and top,
	-- and the crease where the backrest rises
	cushion = { edge = 107.75, centre = 109, top = 3.02, hinge = -26.85 },
	recline = 38, -- degrees the body lies back from upright, along its backrest
	eye = { 109, 5.9, -25.9 }, -- about where your eyes are, lying there (where he looks to notice you)
	baconFrom = { 80, 0, -42 }, -- his stroll: a curve from here past `baconBend` to `baconTo`
	baconBend = { 99.5, 0, -44.5 },
	baconTo = { 102.5, 0, -39.5 }, -- where he sits, facing about your way
	sandPile = { 0.9, 0, -1.5 }, -- the sand he plays with, in his own axes from where he sits
	fat = { 20, -28, -430 }, -- where he later sits on the seabed (clear of the rocks)
	baconTurn = 60, -- degrees the ball sits turned from the beach (to his left), so the straw shows side-on
	puddle = { 77.2, -27.4, -397 }, -- the last water, in front of the turned ball
	puddleRadius = 30,
	rollTo = { -83, -28, -899 }, -- straight away from your eyes
}

IntroCut.stopSeconds = 0.6 -- a walk slows to a stop over its last this many seconds

-- Camera shots: from `at` until the next shot starts. Keys: { t, at, look, fov, ease }: `at` a place,
-- "eye" (your eyes on the lounger) or "stand" (your eyes where play starts); `look` a place or a
-- subject the client tracks: "player" (the middle of your body, head to feet: the whole of you in
-- the shot, standing or lying), "bacon" (the bacon-hair on the beach),
-- "baconLow" (a little below him: heavy eyes), "fat" (the ball's middle), "standLook" (the game's
-- first view). A `spline` shot runs smoothly through its keys (IntroCut.spline), still only at its
-- ends; the others ease into each key.
IntroCut.shots = {
	{
		name = "take",
		at = 2.72,
		spline = true,
		keys = {
			{ t = 2.72, at = { 128, 64, 70 }, look = { 70, 0, -300 }, fov = 55 },
			{ t = 6.0, at = { 116, 30, 30 }, look = "player", fov = 52 },
			{ t = 8.4, at = { 101.5, 8.5, -6 }, look = "player", fov = 50 },
			{ t = 10.6, at = { 97.8, 7.2, -24.5 }, look = "player", fov = 50 },
			{ t = 13.0, at = { 97.2, 6.4, -29.5 }, look = "player", fov = 48 },
			{ t = 15.2, at = { 98.6, 7.0, -25.0 }, look = "player", fov = 48 },
			{ t = 17.4, at = { 106.2, 8.2, -20.6 }, look = { 98, 3.6, -42 }, fov = 50 },
			{ t = 20.0, at = { 106.9, 7.9, -21.2 }, look = "bacon", fov = 46 },
			{ t = 22.0, at = { 107.9, 7.2, -22.6 }, look = "bacon", fov = 46 },
			{ t = 24.0, at = "eye", look = "bacon", fov = 55 },
			{ t = 28.2, at = "eye", look = "baconLow", fov = 55 },
		},
	},
	{
		name = "wake",
		at = 28.2,
		keys = {
			{ t = 28.2, at = "eye", look = { 150, 30, -300 }, fov = 70 },
			{ t = 33.2, at = "eye", look = { 150, 30, -300 }, fov = 70 },
			{ t = 34.8, at = "eye", look = { 50, 12, -413 }, fov = 26, ease = "inOut" },
			{ t = 41.2, at = "eye", look = { 50, 12, -413 }, fov = 26 },
			{ t = 42.2, at = "eye", look = "fat", fov = 24, ease = "inOut" },
			{ t = 44.2, at = "eye", look = "fat", fov = 24 },
			{ t = 45.8, at = "stand", look = "standLook", fov = 70, ease = "inOut" },
		},
	},
}

-- Eyelids: 0 open, 1 shut. Heavy blinks, each closing longer and opening less, then dark; waking
-- flutters open.
IntroCut.lids = {
	{ t = 0, v = 0 },
	{ t = 24.4, v = 0 },
	{ t = 24.9, v = 1, ease = "inOut" },
	{ t = 25.2, v = 1 },
	{ t = 25.7, v = 0.45, ease = "out" },
	{ t = 26.1, v = 0.45 },
	{ t = 26.6, v = 1, ease = "inOut" },
	{ t = 26.8, v = 1 },
	{ t = 27.2, v = 0.72, ease = "out" },
	{ t = 27.4, v = 0.72 },
	{ t = 27.8, v = 1, ease = "inOut" },
	{ t = 31.4, v = 1 },
	{ t = 31.75, v = 0.5, ease = "out" },
	{ t = 31.95, v = 0.85, ease = "inOut" },
	{ t = 32.4, v = 0, ease = "out" },
}

IntroCut.blur = {
	{ t = 0, v = 0 },
	{ t = 24.4, v = 0 },
	{ t = 24.9, v = 3, ease = "inOut" },
	{ t = 26.6, v = 8, ease = "inOut" },
	{ t = 27.8, v = 14, ease = "inOut" },
	{ t = 31.4, v = 14 },
	{ t = 32.6, v = 0, ease = "out" },
}

-- The black screen before the drop.
IntroCut.black = {
	{ t = 0, v = 1 },
	{ t = 2.72, v = 0, ease = "step" },
}

-- The logo pops in on the drop and fades as the camera comes down to you.
IntroCut.logoAlpha = {
	{ t = 0, v = 0 },
	{ t = 2.72, v = 0 },
	{ t = 2.9, v = 1, ease = "out" },
	{ t = 6.8, v = 1 },
	{ t = 7.4, v = 0, ease = "inOut" },
}
IntroCut.logoScale = {
	{ t = 0, v = 0.6 },
	{ t = 2.72, v = 0.6 },
	{ t = 3.0, v = 1.08, ease = "out" },
	{ t = 3.25, v = 1, ease = "inOut" },
	{ t = 6.8, v = 1.02 },
	{ t = 7.4, v = 0.96, ease = "in" },
}

-- The intro's music: full, then gone as you doze off.
IntroCut.music = {
	{ t = 0, v = 1 },
	{ t = 24.6, v = 1 },
	{ t = 28.0, v = 0, ease = "inOut" },
}

-- Sounds (ReplicatedStorage.Audio; the far ones carry their own muffling effects). `stop` cuts a
-- sound off; `fade` takes it to silence over its last seconds.
IntroCut.sounds = {
	{ t = 0, sound = "IntroMusic", volume = 0.5, music = true },
	{ t = 10.25, sound = "IntroYawn", volume = 0.7 },
	{ t = 28.6, sound = "IntroSlurpFar", volume = 0.55 },
	{ t = 32.6, sound = "IntroHuh", volume = 0.8 },
	{ t = 33.2, sound = "IntroWhoosh", volume = 0.35 },
	{ t = 34.8, sound = "IntroSlurp", volume = 0.6, stop = 37.4 },
	{ t = 38.3, sound = "IntroBurp", volume = 1 },
	{ t = 41.2, sound = "IntroRoll", volume = 0.7, fade = 2.0 },
	{ t = 44.2, sound = "IntroWhoosh", volume = 0.3 },
	{ t = 46.0, sound = "IntroSigh", volume = 0.7 },
}

-- Camera shakes: { at, seconds, studs, cycles }.
IntroCut.shakes = {
	{ at = 38.35, seconds = 0.6, studs = 0.06, cycles = 5 },
}

local function eased(ease: string?, a: number): number
	if ease == "step" then
		return 0 -- holds the key before; the key's own value from its time on
	elseif ease == "linear" then
		return a
	elseif ease == "in" then
		return 1 - math.cos(a * math.pi / 2)
	elseif ease == "out" then
		return math.sin(a * math.pi / 2)
	end
	return (1 - math.cos(a * math.pi)) / 2 -- inOut, the default: still at both ends
end
IntroCut.eased = eased

-- The segment of `keys` (sorted by t) holding `t`: the key before, the key after and how far along
-- (eased by the later key). Before the first key or after the last, that key alone (alpha 0).
function IntroCut.segment(keys: { any }, t: number): (any, any, number)
	if t <= keys[1].t then
		return keys[1], keys[1], 0
	end
	for i = 2, #keys do
		local b = keys[i]
		if t < b.t then
			local a = keys[i - 1]
			local span = b.t - a.t
			return a, b, eased(b.ease, if span > 0 then (t - a.t) / span else 1)
		end
	end
	local last = keys[#keys]
	return last, last, 0
end

-- A smooth path through the keys (a cubic Hermite with tangents from each key's neighbours, still
-- at the first and last key): the weights of the keys around `t`, as { index, weight } pairs that
-- sum to 1. A value at `t` is the weighted sum of the keys' values.
function IntroCut.spline(keys: { any }, t: number): { { number } }
	local n = #keys
	if t <= keys[1].t then
		return { { 1, 1 } }
	elseif t >= keys[n].t then
		return { { n, 1 } }
	end
	local i = 1
	while keys[i + 1].t <= t do
		i += 1
	end
	local d = keys[i + 1].t - keys[i].t
	local u = (t - keys[i].t) / d
	local u2, u3 = u * u, u * u * u
	local w: { [number]: number } = { [i] = 2 * u3 - 3 * u2 + 1, [i + 1] = -2 * u3 + 3 * u2 }
	if i > 1 then
		local c = (u3 - 2 * u2 + u) * d / (keys[i + 1].t - keys[i - 1].t)
		w[i + 1] += c
		w[i - 1] = -c
	end
	if i + 1 < n then
		local c = (u3 - u2) * d / (keys[i + 2].t - keys[i].t)
		w[i + 2] = c
		w[i] -= c
	end
	local out = {}
	for index, weight in w do
		table.insert(out, { index, weight })
	end
	table.sort(out, function(a, b)
		return a[1] < b[1]
	end)
	return out
end

-- A number track's value at `t`.
function IntroCut.value(keys: { any }, t: number): number
	local a, b, alpha = IntroCut.segment(keys, t)
	return a.v + (b.v - a.v) * alpha
end

-- The shot on screen at `t` (nil before the first: the black opening).
function IntroCut.shot(t: number): any?
	local current = nil
	for _, shot in IntroCut.shots do
		if shot.at <= t then
			current = shot
		end
	end
	return current
end

-- How far along a walk from `from` to `to` (seconds) you are at `t`, 0-1 of the way: a steady pace
-- that slows to a stop over its last IntroCut.stopSeconds.
function IntroCut.walked(t: number, from: number, to: number): number
	local stop = math.min(IntroCut.stopSeconds, to - from)
	local steady = to - from - stop
	local whole = steady + stop / 2
	local tt = math.clamp(t - from, 0, to - from)
	if tt <= steady then
		return tt / whole
	end
	local u = tt - steady
	return (steady + u - u * u / (2 * stop)) / whole
end

-- How much of the puddle is left (0-1) at `t`.
function IntroCut.puddleLeft(t: number): number
	local b = IntroCut.beats
	return 1 - eased("inOut", math.clamp((t - b.drink) / (b.drunk - b.drink), 0, 1))
end

-- How far he has rolled (0-1) at `t`: slow to start, then away.
function IntroCut.rolled(t: number): number
	local b = IntroCut.beats
	local a = math.clamp((t - b.roll) / (b.rollEnd - b.roll), 0, 1)
	return a * a * (1.6 - 0.6 * a) -- eases in, leaves at speed
end

return IntroCut
