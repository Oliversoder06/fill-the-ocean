--!strict
-- The intro cutscene as data (client/Intro plays it, server/Run starts and ends it). Pure, Lune-tested.
-- The story: the ocean is full; you walk to your lounger, lie down, spot the bacon-hair standing far
-- out in the water, yawn and doze off. In the dark: a slurp, far away. You wake to a dry ocean, and
-- the view goes (no cut) to him, round as a ball, sucking the last puddle up through a straw. He
-- sees you, burps and rolls off. Back to your own eyes: a sigh, and a spoon in your hand.
-- Times are seconds from the cut's start (IntroAt on the server's clock). Places are studs in the
-- world {x, y, z} (the beach runs along X, the sea lies toward -Z). Track keys are { t, v, ease }:
-- the ease shapes the move INTO that key ("step" holds the last value until it).

local IntroCut = {}

IntroCut.length = 39.6
IntroCut.skipAfter = 2 -- seconds in before anyone may skip (the server checks it too)

-- Story beats.
IntroCut.beats = {
	drop = 2.72, -- the music's drop: the first picture and the logo
	walk = 7.6, -- following you up the beach to your lounger
	walkFrom = 7.6,
	walkTo = 11.4,
	lie = 11.7, -- lying on it; the bacon-hair stands far out in the full ocean
	yawn = 15.5,
	pov = 18.0, -- your own eyes, getting heavy
	swap = 22.3, -- eyes shut: the water goes, he turns into the ball with the straw
	wake = 25.8,
	drink = 29.2, -- the last puddle goes up the straw
	drunk = 31.6,
	notice = 32.0, -- he sees you
	burp = 32.7,
	roll = 34.4, -- and rolls off
	rollEnd = 37.6,
	back = 37.4, -- back to your eyes, standing
	sigh = 39.1,
}

IntroCut.places = {
	walkFrom = { 97.0, 0, -10.2 }, -- y: the ground under it; walkSpeed x the walk's time away
	walkTo = { 106.6, 0, -26.6 },
	stand = { 106.4, 0, -27.4 }, -- where you stand when play starts, facing the sea
	lounger = { 109, 3.04, -28 }, -- the place's lounger nearest this (workspace.Map.Beach)
	hips = { 109, 3.75, -26.75 }, -- your hips on it once it is turned round to face the sea
	recline = 38, -- degrees the body lies back from upright, along its backrest
	eye = { 109, 5.9, -25.9 }, -- your eyes lying there
	bacon = { 20, -28, -430 }, -- where he stands in the water, and later sits on the seabed (clear of the rocks)
	baconTurn = 60, -- degrees the ball sits turned from the beach (to his left), so the straw shows side-on
	puddle = { 77.2, -27.4, -397 }, -- the last water, in front of the turned ball
	puddleRadius = 30,
	rollTo = { -83, -28, -899 }, -- straight away from your eyes
}

IntroCut.walkSpeed = 5 -- studs a second (IntroClips.gaits.walk)
IntroCut.giantSway = { degrees = 1.5, seconds = 5.5 } -- the standing giant's slow sway

-- Camera shots: from `at` until the next shot starts. Keys: { t, at, look, fov, ease }: `at` a place,
-- or "stand" (your own eyes where you stand at the end); `look` a place or a subject the client
-- tracks: "player" (your body's head), "bacon" (his middle), "sea" (level, straight out to sea).
IntroCut.shots = {
	{
		name = "drone",
		at = 2.72,
		keys = {
			{ t = 2.72, at = { 128, 64, 70 }, look = { 70, 0, -300 }, fov = 55 },
			{ t = 7.6, at = { 118, 40, 22 }, look = { 70, 0, -320 }, fov = 55, ease = "out" },
		},
	},
	{
		name = "walk",
		at = 7.6,
		keys = {
			{ t = 7.6, at = { 94.5, 6.2, -38 }, look = "player", fov = 46 },
			{ t = 11.7, at = { 95.5, 6.0, -40.5 }, look = "player", fov = 46, ease = "inOut" },
		},
	},
	{
		name = "lie",
		at = 11.7,
		keys = {
			{ t = 11.7, at = { 108.2, 6.7, -21.6 }, look = { 30, 18, -430 }, fov = 50 },
			{ t = 15.3, at = { 108.4, 6.6, -22.3 }, look = { 30, 20, -430 }, fov = 44, ease = "inOut" },
		},
	},
	{
		name = "yawn",
		at = 15.3,
		keys = {
			{ t = 15.3, at = { 101.5, 6.4, -30.0 }, look = "player", fov = 55 },
			{ t = 18.0, at = { 101.8, 6.3, -29.6 }, look = "player", fov = 52, ease = "inOut" },
		},
	},
	{
		name = "doze",
		at = 18.0,
		keys = {
			{ t = 18.0, at = { 109, 5.9, -25.9 }, look = { 22, 24, -430 }, fov = 50 },
			{ t = 22.3, at = { 109, 5.75, -25.85 }, look = { 22, 6, -430 }, fov = 50, ease = "inOut" },
		},
	},
	{
		name = "wake",
		at = 22.3,
		keys = {
			{ t = 22.3, at = { 109, 5.9, -25.9 }, look = { 150, 30, -300 }, fov = 70 },
			{ t = 27.6, at = { 109, 5.9, -25.9 }, look = { 150, 30, -300 }, fov = 70 },
			{ t = 29.2, at = { 109, 5.9, -25.9 }, look = { 50, 12, -413 }, fov = 26, ease = "inOut" },
			{ t = 34.4, at = { 109, 5.9, -25.9 }, look = { 50, 12, -413 }, fov = 26 },
			{ t = 35.4, at = { 109, 5.9, -25.9 }, look = "bacon", fov = 24, ease = "inOut" },
			{ t = 37.4, at = { 109, 5.9, -25.9 }, look = "bacon", fov = 24 },
			{ t = 39.0, at = "stand", look = "sea", fov = 70, ease = "inOut" },
		},
	},
}

-- Eyelids: 0 open, 1 shut. Heavy blinks, each closing longer and opening less, then dark; waking
-- flutters open.
IntroCut.lids = {
	{ t = 0, v = 0 },
	{ t = 18.6, v = 0 },
	{ t = 19.1, v = 1, ease = "inOut" },
	{ t = 19.4, v = 1 },
	{ t = 19.9, v = 0.45, ease = "out" },
	{ t = 20.3, v = 0.45 },
	{ t = 20.8, v = 1, ease = "inOut" },
	{ t = 21.0, v = 1 },
	{ t = 21.4, v = 0.72, ease = "out" },
	{ t = 21.6, v = 0.72 },
	{ t = 22.0, v = 1, ease = "inOut" },
	{ t = 25.8, v = 1 },
	{ t = 26.15, v = 0.5, ease = "out" },
	{ t = 26.35, v = 0.85, ease = "inOut" },
	{ t = 26.8, v = 0, ease = "out" },
}

IntroCut.blur = {
	{ t = 0, v = 0 },
	{ t = 18.6, v = 0 },
	{ t = 19.1, v = 3, ease = "inOut" },
	{ t = 20.8, v = 8, ease = "inOut" },
	{ t = 22.0, v = 14, ease = "inOut" },
	{ t = 25.8, v = 14 },
	{ t = 27.0, v = 0, ease = "out" },
}

-- The black screen before the drop.
IntroCut.black = {
	{ t = 0, v = 1 },
	{ t = 2.72, v = 0, ease = "step" },
}

-- The logo pops in on the drop and fades before the walk.
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
	{ t = 19.0, v = 1 },
	{ t = 22.5, v = 0, ease = "inOut" },
}

-- Sounds (ReplicatedStorage.Audio; the far ones carry their own muffling effects). `stop` cuts a
-- sound off; `fade` takes it to silence over its last seconds.
IntroCut.sounds = {
	{ t = 0, sound = "IntroMusic", volume = 0.5, music = true },
	{ t = 15.6, sound = "IntroYawn", volume = 0.7 },
	{ t = 22.6, sound = "IntroSlurpFar", volume = 0.55 },
	{ t = 27.0, sound = "IntroHuh", volume = 0.8 },
	{ t = 27.6, sound = "IntroWhoosh", volume = 0.35 },
	{ t = 29.2, sound = "IntroSlurp", volume = 0.6, stop = 31.8 },
	{ t = 32.7, sound = "IntroBurp", volume = 0.9 },
	{ t = 34.4, sound = "IntroRoll", volume = 0.7, fade = 2.0 },
	{ t = 37.4, sound = "IntroWhoosh", volume = 0.3 },
	{ t = 39.1, sound = "IntroSigh", volume = 0.7 },
}

-- Camera shakes: { at, seconds, studs, cycles }.
IntroCut.shakes = {
	{ at = 32.75, seconds = 0.6, studs = 0.06, cycles = 5 },
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

-- How far along the walk (0-1) you are at `t`.
function IntroCut.walked(t: number): number
	local b = IntroCut.beats
	return math.clamp((t - b.walkFrom) / (b.walkTo - b.walkFrom), 0, 1)
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
