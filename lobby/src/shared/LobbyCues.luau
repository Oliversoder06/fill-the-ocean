--!strict
-- Lobby feel cues: every sound name, volume, pitch, speed and colour (a sunbaked-sea theme key: the
-- lobby's style, as client/Session) the lobby's client uses, and the small maths behind them. Tune feel
-- here, not in code. Sounds are in the lobby place's ReplicatedStorage.Audio (copies of gameplay's),
-- effects in ReplicatedStorage.Vfx and models in ReplicatedStorage.Scenery. Pure, Lune-tested
-- (gameplay/tests/LobbyCues.spec).

local LobbyCues = {}

local TAU = 2 * math.pi
local GOLDEN = 0.6180339887 -- spreads per-item numbers so neighbours never match
local GOLDEN_ANGLE = 2.3999632297

local function frac(x: number): number
	return x - math.floor(x)
end

-- Music (client/Music): one looping track that fades in on join, ducks under the countdown and fades
-- out as the party leaves.
LobbyCues.music = {
	track = "MusicLobby",
	volume = 0.35,
	fadeSeconds = 2.5,
	duck = 0.4, -- volume scale while ducked
	outSeconds = 1.2, -- the fade at launch
}

-- Ambience (client/Ambience): the surf and gulls bed, always full of life here.
LobbyCues.ambience = {
	bed = "AmbOcean",
	volume = 0.45,
	fadeSeconds = 2.5,
}

-- Footsteps (client/Footsteps): one step every `stride` studs walked, everyone's (third person). The
-- surfaces and stride are gameplay's shared/Steps (its tests hold the two the same); the sound sets
-- are gameplay's Cues.steps.
LobbyCues.steps = {
	surfaces = {
		stone = { "StepStone1", "StepStone2", "StepStone3", "StepStone4", "StepStone5", "StepStone6" },
		grass = { "StepGrass1", "StepGrass2", "StepGrass3", "StepGrass4" },
		sand = { "StepSand1" },
		wood = { "StepWood1" },
	},
	stride = 1 / (2 * 0.09), -- studs between steps: gameplay's camera bob dips twice per 1 / 0.09 studs
	volume = 0.35,
	otherVolume = 0.3,
	pitchMin = 0.95,
	pitchMax = 1.05,
	range = 80, -- studs; farther players' steps are skipped
}

local SURFACES = {
	Grass = "grass",
	LeafyGrass = "grass",
	Ground = "grass",
	Mud = "grass",
	Sand = "sand",
	Snow = "sand",
	Salt = "sand",
	Wood = "wood",
	WoodPlanks = "wood",
}

-- The surface a floor material sounds like (by Enum.Material name). Anything hard is stone.
function LobbyCues.surface(materialName: string): string
	return SURFACES[materialName] or "stone"
end

-- Buttons and windows (client/UiSounds): a soft tick on hover, a pop on press, a whoosh when a
-- window opens (a little lower on close), a buzz when a button can't do anything, a pop for a toast.
LobbyCues.ui = {
	click = "UiClick",
	clickVolume = 0.4,
	hoverVolume = 0.12,
	hoverPitch = 1.4,
	hoverGap = 0.05, -- seconds; hovers closer together than this play once
	whoosh = "WindowWhoosh",
	openVolume = 0.4,
	closeVolume = 0.3,
	openPitch = 1.1,
	closePitch = 0.85,
	deny = "BuyDenied",
	denyVolume = 0.5,
	toastVolume = 0.3,
	toastPitch = 0.8,
}

-- The pads (client/Pads): colours and light by the pad's State attribute (common/SessionRules
-- padState), the Ripple texture drifting, bubbles while it invites, a splash under whoever steps on
-- or off. `splash` and `bubbles` are Attachments in ReplicatedStorage.Vfx.
LobbyCues.pads = {
	inside = 6.5, -- studs from a Zone's centre (X and Z) that count as on the pad (server/Queue's INSIDE)
	rippleSpeed = 0.6, -- studs per second the Ripple texture drifts
	ease = 6, -- how quickly colour and light follow a new state (per second)
	light = 0.6, -- the Water PointLight's Brightness at a look's light 1
	pulseDepth = 0.45, -- how far a pulse dips the light and fades the rim
	rimTransparency = 0.3,
	splash = "ScoopSplash",
	splashSound = "ScoopSplash1",
	splashVolume = 0.5,
	splashPitchMin = 0.9,
	splashPitchMax = 1.1,
	leaveScale = 0.5, -- stepping off splashes this much of stepping on
	bubbles = "PadBubbles",
	rise = 0.6, -- studs the water rises over a countdown
}

export type PadLook = { color: string, pulseHz: number, light: number, bubbles: boolean }

-- One look per pad state: blue and bubbling is free, a slow warm pulse is "join me", slate is busy, a
-- quick warm pulse is the countdown and white is the launch.
local BUSY: PadLook = { color = "locked", pulseHz = 0, light = 0.5, bubbles = false }
LobbyCues.padLooks = {
	open = { color = "shallowWater", pulseHz = 0, light = 1, bubbles = true },
	party = { color = "toolTag", pulseHz = 0.8, light = 1.5, bubbles = true },
	setup = BUSY,
	closed = BUSY,
	saved = BUSY,
	counting = { color = "toolTag", pulseHz = 2, light = 2.5, bubbles = true },
	launching = { color = "foam", pulseHz = 0, light = 3, bubbles = false },
} :: { [string]: PadLook }

function LobbyCues.padLook(state: string): PadLook
	local look = LobbyCues.padLooks[state]
	if not look then
		error(`LobbyCues has no pad look for state {state}`)
	end
	return look
end

-- The launch countdown (client/Countdown): the number pops on each second with a tick that climbs,
-- then a chime, a whoosh and a sparkle on the pad; a cancel buzzes. `sparkle` is in ReplicatedStorage.Vfx.
LobbyCues.countdown = {
	tick = "CoinTick",
	tickVolume = 0.6,
	tickPitch = 1,
	tickPitchStep = 0.12,
	go = "ToolUnlock",
	goVolume = 0.55,
	whoosh = "SpeedWhoosh",
	whooshVolume = 0.5,
	cancel = "BuyDenied",
	cancelVolume = 0.4,
	pop = 1.4, -- the number's scale as it lands
	duckSeconds = 1.2, -- the music ducks under each tick for this long
	goSeconds = 0.8, -- how long "GO!" stays before it shrinks away
	sparkle = "Sparkle",
}

-- The whole seconds left before endsAt (both server time): 3, 2, 1, then 0.
function LobbyCues.countdownNumber(endsAt: number, now: number): number
	return math.max(0, math.ceil(endsAt - now))
end

-- Palms (client/World) tilt about their base, each on its own slow rhythm.
LobbyCues.palms = {
	degrees = 1.5,
	hzMin = 0.18,
	hzMax = 0.3,
	range = 300, -- studs from the camera; farther palms hold still
}

-- A palm's tilt about X and Z (radians) at time t; seed picks its rhythm. A slow sway plus a quicker
-- flutter, weighted so the two never add past `degrees`.
function LobbyCues.sway(t: number, seed: number): (number, number)
	local p = LobbyCues.palms
	local max = math.rad(p.degrees)
	local hz = p.hzMin + (p.hzMax - p.hzMin) * frac(seed * GOLDEN)
	local phase = seed * GOLDEN_ANGLE
	local w = TAU * hz * t
	local x = max * (0.75 * math.sin(w + phase) + 0.25 * math.sin(2.3 * w + 1.7 * phase))
	local z = max * (0.75 * math.sin(0.83 * w + 0.6 * phase) + 0.25 * math.sin(1.9 * w + 2.1 * phase))
	return x, z
end

-- Gulls (client/World): copies of ReplicatedStorage.Scenery.<model> circling over the beach. Heights
-- are world y; centre is { x, y, z } (its y unused).
LobbyCues.gulls = {
	model = "Gull",
	count = 4,
	centre = { 0, 0, -10 },
	radiusMin = 40,
	radiusMax = 90,
	heightMin = 35,
	heightMax = 60,
	lapMin = 24, -- seconds per circle
	lapMax = 36,
	wobble = 0.12, -- how far the circle bends in and out (share of its radius)
	bankDegrees = 18,
	flapDegrees = 28,
	flapHz = 2.6,
	flapCycles = 3, -- wingbeats in a burst, then a glide
	flapEvery = 5, -- seconds from one burst to the next (plus 0-2 per gull)
}

-- Gull i at time t: x, y, z, its flat heading (dx, dz, unit length) and which way it turns (1 or -1).
-- Odd gulls circle one way and even ones the other, each at its own radius, height bob and lap time.
function LobbyCues.gullAt(t: number, i: number): (number, number, number, number, number, number)
	local g = LobbyCues.gulls
	local turn = if i % 2 == 0 then -1 else 1
	local base = g.radiusMin + (g.radiusMax - g.radiusMin) * (0.2 + 0.6 * frac(i * GOLDEN))
	local lap = g.lapMin + (g.lapMax - g.lapMin) * frac(i * GOLDEN + 0.5)
	local speed = turn * TAU / lap
	local a = speed * t + i * GOLDEN_ANGLE
	local r = base * (1 + g.wobble * math.sin(2 * a + i))
	local dr = base * g.wobble * 2 * math.cos(2 * a + i) -- dr/da
	if r < g.radiusMin then
		r, dr = g.radiusMin, 0
	elseif r > g.radiusMax then
		r, dr = g.radiusMax, 0
	end
	local c, s = math.cos(a), math.sin(a)
	local mid = (g.heightMin + g.heightMax) / 2
	local amp = (g.heightMax - g.heightMin) / 2
	local y = mid + amp * math.sin(TAU * t / (lap * 0.6) + i)
	local dx = speed * (dr * c - r * s)
	local dz = speed * (dr * s + r * c)
	local length = math.sqrt(dx * dx + dz * dz)
	return g.centre[1] + c * r, y, g.centre[3] + s * r, dx / length, dz / length, turn
end

-- Gull i's wing angle (radians, up positive) at time t: a burst of flapCycles wingbeats every
-- flapEvery (+ 0-2) seconds, flat wings gliding between. A burst starts and ends level.
function LobbyCues.flap(t: number, i: number): number
	local g = LobbyCues.gulls
	local period = g.flapEvery + (i % 3)
	local phase = (t + i * 1.7) % period
	if phase >= g.flapCycles / g.flapHz then
		return 0
	end
	return math.rad(g.flapDegrees) * math.sin(TAU * g.flapHz * phase)
end

-- The bacon-hair on the horizon (client/Horizon): a copy of ReplicatedStorage.Scenery.<model> drinking
-- the sea through his straw far behind the pads. Every slurpMin..slurpMax seconds a slurp swells his
-- belly; every burpEvery-th one ends in a burp and a hop. Both sounds come from him, faint at the deck.
LobbyCues.horizon = {
	model = "BaconFat",
	slurp = "IntroSlurpFar",
	slurpVolume = 0.6,
	burp = "IntroBurp",
	burpVolume = 0.5,
	slurpMin = 14,
	slurpMax = 22,
	burpEvery = 3,
	swell = 0.04, -- share his belly grows on a slurp
	swellIn = 2.5, -- seconds the belly takes to fill (about the slurp's length)
	swellOut = 2, -- and to settle
	swayDegrees = 2,
	swayHz = 0.07,
	hop = 4, -- studs he bounces on a burp
	hopSeconds = 0.6,
	burpDelay = 0.4, -- seconds after the slurp's swell before the burp
	rollOffMin = 120,
	rollOffMax = 800,
}

-- How full his belly is (0 to 1) `elapsed` seconds into a slurp: eases up over swellIn, back down
-- over swellOut.
function LobbyCues.swell(elapsed: number): number
	local h = LobbyCues.horizon
	if elapsed <= 0 or elapsed >= h.swellIn + h.swellOut then
		return 0
	elseif elapsed <= h.swellIn then
		return 0.5 - 0.5 * math.cos(math.pi * elapsed / h.swellIn)
	end
	return 0.5 + 0.5 * math.cos(math.pi * (elapsed - h.swellIn) / h.swellOut)
end

-- His burp hop's height (0 to 1) `elapsed` seconds into it: one arc over hopSeconds.
function LobbyCues.hop(elapsed: number): number
	local h = LobbyCues.horizon
	if elapsed <= 0 or elapsed >= h.hopSeconds then
		return 0
	end
	return math.sin(math.pi * elapsed / h.hopSeconds)
end

-- One variant from a list; roll is a random number in [0, 1). Never the same one as `last` (a repeat
-- sounds like a stutter), unless there is only one.
function LobbyCues.pickNext(list: { string }, roll: number, last: string?): string
	local others = {}
	for _, name in list do
		if name ~= last then
			table.insert(others, name)
		end
	end
	if #others == 0 then
		return list[1]
	end
	return others[math.min(#others, math.floor(roll * #others) + 1)]
end

return LobbyCues
