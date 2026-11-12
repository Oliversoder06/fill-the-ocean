--!strict
-- The intro cutscene as data (client/Intro plays it, server/Run starts and ends it). Pure, Lune-tested.
-- The story: the ocean is full. You walk up the beach to your lounger, stretch with a yawn, sit on
-- its edge, swing your legs up and lie back. The bacon-hair strolls onto the beach in front of you,
-- sits down and plays in the sand; you watch him, your eyes get heavy and close. In the dark: a
-- slurp, far away. You wake to a dry ocean, and the view goes (no cut) to him far out, round as a
-- ball, sucking the last puddle up through a straw. He sees you and burps, then rolls for the beach,
-- faster and faster, and its slope throws him up past you and off into the distance (real rolling
-- and the game's gravity: IntroCut.flight). You get up: the view turns back to the sea and rises
-- into your own eyes, the spoon comes up into your hand, and play starts there.
-- One camera take runs from the music's drop until your eyes close (no cuts: a spline through
-- the keys); the only cuts are into the opening and into the dark. The cut's last frame is the
-- game's first: from `handover` the camera is the game's own (client/Intro).
-- Times are seconds from the cut's start (IntroAt on the server's clock). Places are studs in the
-- world {x, y, z} (the beach runs along X, the sea lies toward -Z). Track keys are { t, v, ease }:
-- the ease shapes the move INTO that key ("step" holds the last value until it).

local IntroCut = {}

IntroCut.length = 49.2
IntroCut.skipAfter = 2 -- seconds in before anyone may skip (the server checks it too)
IntroCut.handover = 48.2 -- the camera is the game's from here; the spoon swings up; play at `length`

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
	roll = 41.2, -- he rolls for the beach, faster and faster (IntroCut.rolled)
	rollEnd = 43.8, -- the shore starts lifting him: its slope throws him (IntroCut.flight)
	back = 46.4, -- you get up: back round to the sea, into your own eyes, standing
	sigh = 48.4,
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
	lean = { 106.2, 6.2, -29.8 }, -- sitting up, leaning out past the umbrella to watch him fly
	baconFrom = { 80, 0, -42 }, -- his stroll: a curve from here past `baconBend` to `baconTo`
	baconBend = { 99.5, 0, -44.5 },
	baconTo = { 102.5, 0, -39.5 }, -- where he sits, facing about your way
	sandPile = { 0.9, 0, -1.5 }, -- the sand he plays with, in his own axes from where he sits
	fat = { 20, -28, -430 }, -- where he later sits on the seabed (clear of the rocks)
	baconTurn = 60, -- degrees the ball sits turned from the beach (to his left), so the straw shows side-on
	puddle = { 77.2, -27.4, -397 }, -- the last water, in front of the turned ball
	puddleRadius = 30,
	rollAt = { 6, -57 }, -- {x, z}: he rolls straight for the beach's top here, left of your lounger
	-- the beach from the seabed up to the sand, {z, y} (the same all along the cove: workspace.Terrain);
	-- flat seabed before it, flat sand after
	shore = {
		{ -115, -28 },
		{ -110, -27.4 },
		{ -105, -24.9 },
		{ -100, -22.6 },
		{ -95, -20.1 },
		{ -90, -17.3 },
		{ -85, -15.2 },
		{ -80, -12.5 },
		{ -75, -9.9 },
		{ -70, -7.6 },
		{ -65, -4.9 },
		{ -60, 0.1 },
		{ -55, 2.2 },
	},
}

IntroCut.rollPower = 5 -- his run-up covers (share of its time)^this of the way: he gathers speed

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
			-- on him as he gets going; wider as he comes (he stays about half the frame's height)
			{ t = 42.4, at = "eye", look = "fat", fov = 26, ease = "inOut" },
			{ t = 43.0, at = "eye", look = "fat", fov = 28, ease = "in" },
			{ t = 43.4, at = "eye", look = "fat", fov = 34, ease = "linear" },
			{ t = 43.6, at = "eye", look = "fat", fov = 42, ease = "linear" },
			{ t = 43.7, at = "eye", look = "fat", fov = 50, ease = "linear" },
			{ t = 43.8, at = "eye", look = "fat", fov = 62, ease = "linear" },
			-- the shore throws him past you: you sit up and lean out to follow him
			{ t = 43.9, at = "eye", look = "fat", fov = 72, ease = "out" },
			{ t = 44.3, at = IntroCut.places.lean, look = "fat", fov = 72, ease = "inOut" },
			-- off into the distance (behind the palm a moment), the view closing in a little as he goes
			{ t = 46.4, at = IntroCut.places.lean, look = "fat", fov = 36, ease = "inOut" },
			-- back round to the sea as you stand
			{ t = 48.2, at = "stand", look = "standLook", fov = 70, ease = "inOut" },
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
	{ t = 41.55, sound = "IntroRoll", volume = 0.7 }, -- over as the shore throws him
	{ t = 43.85, sound = "IntroWhoosh", volume = 0.6 }, -- past you
	{ t = 46.4, sound = "IntroWhoosh", volume = 0.3 },
	{ t = 48.4, sound = "IntroSigh", volume = 0.7 },
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

-- How far along his run-up for the beach he is (0-1) at `t`: a slow start, faster and faster.
function IntroCut.rolled(t: number): number
	local b = IntroCut.beats
	local a = math.clamp((t - b.roll) / (b.rollEnd - b.roll), 0, 1)
	return a ^ IntroCut.rollPower
end

-- The height of a ball's middle resting on the shore (IntroCut.places.shore) at z. The shore is the
-- same along X, so the ball touches it in the y-z plane: the highest of its segments pushed out by
-- the radius and the circles round its corners.
function IntroCut.rideHeight(z: number, radius: number): number
	local shore = IntroCut.places.shore
	local n = #shore
	local function point(i: number): (number, number)
		if i < 1 then
			return shore[1][1] - 1e5, shore[1][2]
		elseif i > n then
			return shore[n][1] + 1e5, shore[n][2]
		end
		return shore[i][1], shore[i][2]
	end
	local h = -math.huge
	for i = 0, n do
		local az, ay = point(i)
		local bz, by = point(i + 1)
		local dz, dy = bz - az, by - ay
		local len = math.sqrt(dz * dz + dy * dy)
		local nz, ny = -dy / len * radius, dz / len * radius
		if z >= az + nz and z <= bz + nz then
			h = math.max(h, ay + ny + (z - az - nz) * dy / dz)
		end
		local off = z - az
		if i >= 1 and math.abs(off) <= radius then
			h = math.max(h, ay + math.sqrt(radius * radius - off * off))
		end
	end
	return h
end

local STEP = 1 / 240 -- the shore's bake step, seconds

export type Flight = {
	radius: number,
	gravity: number,
	x0: number, -- where the run starts (IntroCut.places.fat)
	z0: number,
	hx: number, -- the run's way across the ground, a unit
	hz: number,
	seabed: number, -- his middle's height on the seabed
	runUp: number, -- studs across the seabed before the shore lifts him
	speed: number, -- studs/s as it does
	samples: { { number } }, -- from beats.rollEnd every STEP: { t, along, height, turned (radians) }
	vs: number, -- then free: along the run and up, studs/s, and his spin, radians/s
	vy: number,
	spin: number,
}

-- His roll for the beach and his flight off it, for a ball of `radius` under `gravity`
-- (Workspace.Gravity). The run-up is his own push (IntroCut.rolled); from the shore on it is
-- physics alone: rolling without slipping (0.7 v^2 + g y is kept), a turn up into the slope loses
-- the speed into it, and he flies as soon as the shore falls away faster than he falls. Energy
-- never grows after the run-up.
function IntroCut.flight(radius: number, gravity: number): Flight
	local b, places = IntroCut.beats, IntroCut.places
	local x0, z0 = places.fat[1], places.fat[3]
	local hx, hz = places.rollAt[1] - x0, places.rollAt[2] - z0
	local across = math.sqrt(hx * hx + hz * hz)
	hx, hz = hx / across, hz / across
	local function height(s: number): number
		return IntroCut.rideHeight(z0 + hz * s, radius)
	end
	local seabed = height(0)
	-- the run-up: across the flat seabed until the shore first lifts him
	local lo, hi = 0, across
	for _ = 1, 60 do
		local mid = (lo + hi) / 2
		if height(mid) > seabed + 1e-6 then
			hi = mid
		else
			lo = mid
		end
	end
	local runUp = lo
	local speed = runUp * IntroCut.rollPower / (b.rollEnd - b.roll)

	local s, y = runUp, seabed
	local vs, vy = speed, 0
	local turned, spin = runUp / radius, speed / radius
	local grounded = true
	local samples = { { b.rollEnd, s, y, turned } }
	local clear = (places.shore[#places.shore][1] + radius - z0) / hz -- past this only flat sand lies ahead
	while s < clear do
		assert(#samples < 2400, "IntroCut.flight: he never gets over the shore")
		if grounded then
			local ds = vs * STEP
			local y2 = height(s + ds)
			if y + vy * STEP - gravity * STEP * STEP / 2 > y2 then
				grounded = false -- the shore falls away faster than he falls: he flies
			else
				local len = math.sqrt(ds * ds + (y2 - y) ^ 2)
				local us, uy = ds / len, (y2 - y) / len
				local along = vs * us + vy * uy -- what turns up into the shore is lost
				local v2 = along * along - gravity * (y2 - y) / 0.7
				assert(v2 > 0, "IntroCut.flight: he stops on the shore")
				local v = math.sqrt(v2)
				vs, vy = v * us, v * uy
				turned += len / radius
				spin = v / radius
				s, y = s + ds, y2
			end
		end
		if not grounded then
			s += vs * STEP
			y += vy * STEP - gravity * STEP * STEP / 2
			vy -= gravity * STEP
			turned += spin * STEP
			local floor = height(s)
			if y < floor then -- down on the shore again: only the speed along it is kept
				local rise = height(s + 0.5) - height(s - 0.5) -- per stud along the run
				local len = math.sqrt(1 + rise * rise)
				local v = math.max(0, (vs + vy * rise) / len)
				vs, vy = v / len, v * rise / len
				spin = v / radius
				y = floor
				grounded = true
			end
		end
		table.insert(samples, { b.rollEnd + #samples * STEP, s, y, turned })
	end
	assert(not grounded, "IntroCut.flight: the shore never throws him")
	return {
		radius = radius,
		gravity = gravity,
		x0 = x0,
		z0 = z0,
		hx = hx,
		hz = hz,
		seabed = seabed,
		runUp = runUp,
		speed = speed,
		samples = samples,
		vs = vs,
		vy = vy,
		spin = spin,
	}
end

-- Where his middle is at `t` ({x, y, z}) and how far he has turned (radians, about the run's
-- axis: the run's way across the ground crossed with up).
function IntroCut.ballAt(flight: Flight, t: number): (number, number, number, number)
	local b = IntroCut.beats
	local samples = flight.samples
	local last = samples[#samples]
	local s, y, turned
	if t < b.rollEnd then
		s = flight.runUp * IntroCut.rolled(t)
		y = flight.seabed
		turned = s / flight.radius
	elseif t >= last[1] then
		local tau = t - last[1]
		s = last[2] + flight.vs * tau
		y = last[3] + flight.vy * tau - flight.gravity * tau * tau / 2
		turned = last[4] + flight.spin * tau
	else
		local i = math.clamp(math.floor((t - b.rollEnd) / STEP) + 1, 1, #samples - 1)
		local a, c = samples[i], samples[i + 1]
		local u = math.clamp((t - a[1]) / (c[1] - a[1]), 0, 1)
		s = a[2] + (c[2] - a[2]) * u
		y = a[3] + (c[3] - a[3]) * u
		turned = a[4] + (c[4] - a[4]) * u
	end
	return flight.x0 + flight.hx * s, y, flight.z0 + flight.hz * s, turned
end

return IntroCut
