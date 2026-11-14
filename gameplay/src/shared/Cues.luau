--!strict
-- Feel cues: every sound, volume, pitch and splash size for the scoop and pour, in one place.
-- Tune feel here, not in code. Names refer to ReplicatedStorage.Audio (Sounds) and
-- ReplicatedStorage.Vfx (Attachments with ParticleEmitters), both baked into the place.
-- Pure, Lune-tested.

local Cues = {}

-- Bigger tools splash bigger and sound deeper (the ladder is the joke).
Cues.SIZE_PER_TIER = 0.08
Cues.SIZE_MAX = 2.5
Cues.PITCH_PER_TIER = 0.0125
Cues.PITCH_MIN = 0.75

Cues.scoop = {
	holdSound = "ScoopHold",
	holdVolume = 0.35,
	holdPitchFrom = 0.9,
	holdPitchTo = 1.15,
	splashSounds = { "ScoopSplash1", "ScoopSplash2", "ScoopSplash3" },
	splashVolume = 0.7,
	otherVolume = 0.25,
	pitchMin = 0.92,
	pitchMax = 1.08,
	vfx = "ScoopSplash",
	sizeScale = 1,
	otherBurstScale = 0.5,
}

Cues.pour = {
	splashSounds = { "ScoopSplash1", "ScoopSplash2", "ScoopSplash3" },
	splashVolume = 0.8,
	otherVolume = 0.3,
	pitchMin = 0.78,
	pitchMax = 0.9,
	vfx = "ScoopSplash",
	sizeScale = 1.6,
	otherBurstScale = 0.5,
}

-- Poured water on its way to the ocean (client/Channels, shared/PourFlow). Channel water textures
-- trickle at trickleSpeed; a pour at an area's Pour sends `wave` (a part in ReplicatedStorage.Vfx) down
-- the channel at waveSpeed studs a second (faster on long channels, so none takes over waveSeconds),
-- at most maxWaves on screen; it lingers waveLinger seconds for its particles to fade, then `splash`
-- plays where it meets the ocean and the fill bar pulses.
-- The seabed's pour marker is gone by markerFadeFill.
Cues.channel = {
	wave = "ChannelWave",
	waveSpeed = 40,
	waveSeconds = 5,
	trickleSpeed = 3,
	maxWaves = 8,
	waveLinger = 1.5,
	pulseMin = 1.04,
	pulseMax = 1.12,
	pulseFullLitres = 1e6,
	markerFadeFill = 0.05,
	splash = {
		splashSounds = { "ScoopSplash1", "ScoopSplash2", "ScoopSplash3" },
		splashVolume = 0.8,
		otherVolume = 0.5,
		pitchMin = 0.7,
		pitchMax = 0.82,
		vfx = "ScoopSplash",
		sizeScale = 2,
		otherBurstScale = 1,
	},
}

-- Your own payout: coins from shared/CoinBurst. `coin` is a Part and `pop` a BillboardGui (with a
-- TextLabel "Amount") in ReplicatedStorage.Vfx.
Cues.coins = {
	coin = "Coin",
	pop = "MoneyPop",
	tickSound = "CoinTick",
	tickVolume = 0.45,
	burstSound = "CoinBurst",
	burstVolume = 0.35,
}

-- The guide (client/Guide): `lane` (a Part holding Attachments Start and End and a textured Beam
-- whose texture carries the rails and the sliding chevrons; speed, width and look are set on it in
-- Studio) runs flat belowCamera studs under the camera from inside the player toward the current
-- goal (placement in shared/GuideTrail): laneStart..laneLength studs ahead, never within hideNear
-- of the goal. `highlight` (a Highlight) outlines a pointed-to stand, gate or plot. Both live in
-- ReplicatedStorage.Vfx. The click hand bobs `handBob` pixels, `handSpeed` taps a second, over the
-- GUI element to click.
Cues.guide = {
	lane = "GuideLane",
	highlight = "GuideHighlight",
	laneStart = 0,
	laneLength = 40,
	hideNear = 8,
	belowCamera = 2.5,
	handBob = 10,
	handSpeed = 1.6,
	faceSeconds = 0.6, -- the camera's turn toward a new lane goal (client/CameraFeel.face)
	dimDarkness = 0.65, -- Hud.GuideDim's opacity around the button the hand taps
	dimPad = 10, -- clear pixels around that button
	dimOpen = 160, -- pixels wider the hole starts as it fades in, then closes in on the button
	dimEase = 9, -- how quickly the dim fades and its hole follows the button
}

-- Windows opening and closing (client/Window): one whoosh, a little lower on close.
Cues.window = {
	whoosh = "WindowWhoosh",
	openVolume = 0.4,
	closeVolume = 0.3,
	openPitch = 1.1,
	closePitch = 0.85,
}

-- Buying (client/Purchase). `sparkle` is an Attachment in ReplicatedStorage.Vfx.
Cues.purchase = {
	sting = "BuySting",
	stingVolume = 0.5,
	deny = "BuyDenied",
	denyVolume = 0.6,
	unlock = "ToolUnlock",
	unlockVolume = 0.55,
	whoosh = "SpeedWhoosh",
	whooshVolume = 0.5,
	sparkle = "Sparkle",
}

-- Hotbar slots (client/Hotbar): the one in hand at full size and opacity; the rest at idleScale with
-- their art idleTransparency, easing over `seconds`.
Cues.hotbar = {
	idleScale = 0.82,
	idleTransparency = 0.45,
	seconds = 0.12,
}

-- Milestones every 5% (client/Milestones). The camera swoops swoopRise studs up and up to swoopOut
-- studs out toward the ocean, looking swoopLook studs past that, and back over swoopSeconds; the
-- music ducks for duckSeconds under `sound`. A revived cove decoration pops from reviveFrom of its
-- size (reviveOvershoot) over reviveSeconds with purchase's sparkle. A sighting puts the bacon-hair
-- sightingDistance studs out to sea for sightingSeconds: up out of the water over sightingRise,
-- swaying sightingRock degrees sightingWaves times a second, back down over sightingSink. A
-- Milestone older than freshSeconds (a late join) plays nothing.
Cues.milestone = {
	swoopSeconds = 2,
	swoopRise = 45,
	swoopOut = 70,
	swoopLook = 140,
	duckSeconds = 2.5,
	sound = "ToolUnlock",
	soundVolume = 0.6,
	reviveFrom = 0.6,
	reviveOvershoot = 1.6,
	reviveSeconds = 0.45,
	sightingDistance = 900,
	sightingSeconds = 6,
	sightingRise = 1.2,
	sightingSink = 1.5,
	sightingRock = 8,
	sightingWaves = 0.8,
	freshSeconds = 5,
}

-- The honeycomb upgrades (client/Honeycomb), seconds and scales. Opening blurs the world to blur
-- and fades the Backdrop in over coverSeconds; closing takes them away over uncoverSeconds. A buy
-- landing on its hex: coins fly in, the hex's water rises (waterSeconds), the hex pops (the theme's
-- motion.buyPop -> 1 over popSeconds)
-- as its check stamps (checkOvershoot over checkSeconds) and its Level ticks up, and bridgeSeconds
-- after the check it wakes into its next level (wakeFrom -> wakeOvershoot -> 1). The sting climbs
-- stingPitchStep a level bought, up to stingPitchMax. A refused click shakes the hex and pulses the
-- card's hint (needPulse). Opening a view: the canvas glides from glideZoomFrom and hexes pop in
-- from enterFrom, enterStagger later per ring out (at most enterCap). No hex breathes any more
-- (owner, 2026-11-11); breatheScale and breatheSeconds stay because tests/Cues.spec pins them.
-- Hexes are never shown under minHexPixels tall, and
-- a view grows to at most maxZoom. Hovers ease over quickSeconds. The Upgrades button squishes to
-- holdScale while held (holdDownSeconds) and springs back (holdUpSeconds).
Cues.honeycomb = {
	blur = 18,
	coverSeconds = 0.25,
	uncoverSeconds = 0.15,
	quickSeconds = 0.08,
	holdScale = 0.82,
	holdDownSeconds = 0.12,
	holdUpSeconds = 0.4,
	bounceLow = 0.95,
	bounceHigh = 1.05,
	bounceSeconds = 0.2,
	waterSeconds = 0.35,
	popSeconds = 0.2,
	checkOvershoot = 1.2,
	checkSeconds = 0.25,
	bridgeSeconds = 0.25,
	wakeFrom = 0.8,
	wakeOvershoot = 1.05,
	wakeSeconds = 0.3,
	stingPitchStep = 0.06,
	stingPitchMax = 1.5,
	needPulse = 1.15,
	needSeconds = 0.3,
	badgeSeconds = 0.2,
	glideSeconds = 0.25,
	glideZoomFrom = 0.9,
	enterFrom = 0.6,
	enterSeconds = 0.2,
	enterStagger = 0.03,
	enterCap = 0.1,
	breatheScale = 1.04,
	breatheSeconds = 1.5,
	minHexPixels = 64,
	maxZoom = 1.6,
	-- The canvas: the mouse wheel zooms toward the pointer (x zoomStep a notch, zoomMin..zoomMax of
	-- the fitted zoom); a press that moves dragPixels drags it instead of clicking.
	zoomStep = 1.12,
	zoomMin = 0.6,
	zoomMax = 2.5,
	dragPixels = 6,
}

-- The purchase sting's pitch for the `level`-th level bought of an upgrade: one step higher each, capped.
function Cues.stingPitch(level: number): number
	local cue = Cues.honeycomb
	return math.min(cue.stingPitchMax, 1 + cue.stingPitchStep * (math.max(level, 1) - 1))
end

-- Footsteps (client/Footsteps). Surfaces come from shared/Steps. Each surface's variants must come
-- from one matched set (same recording), or the steps sound like two different people. Carrying
-- water makes steps heavier: lower and a little louder. Dry floors puff dust (ReplicatedStorage.Vfx)
-- at every step, and more on landing.
Cues.steps = {
	surfaces = {
		stone = { "StepStone1", "StepStone2", "StepStone3", "StepStone4", "StepStone5", "StepStone6" },
		grass = { "StepGrass1", "StepGrass2", "StepGrass3", "StepGrass4" },
		sand = { "StepSand1" },
		wood = { "StepWood1" },
	},
	volume = 0.35,
	otherVolume = 0.3,
	pitchMin = 0.95,
	pitchMax = 1.05,
	carryPitch = 0.88,
	carryVolume = 1.25,
	dust = "StepDust",
	dustSurfaces = { stone = true, sand = true },
	landDust = 3, -- times a step's puff
}

-- A full tool drips water while carried (client/Bodies, other players only).
Cues.carry = {
	drips = "Drips",
}

-- Area mechanics (client/Mechanics). Each steam vent part holds ParticleEmitters `puff` (the warning)
-- and `burst`, each with a number attribute "Burst" (particles per event). `golden` is an Attachment
-- in ReplicatedStorage.Vfx with enabled emitters, put on the golden spring's Source while it lasts.
Cues.mechanics = {
	puff = "Puff",
	burst = "Burst",
	golden = "GoldenSpring",
}

-- Ambience (client/Ambience): one looping bed (the ocean), plus a heat layer. A dry ocean is hot
-- and quiet; as it fills, the heat fades and the life in the bed comes back.
Cues.ambience = {
	bed = "AmbOcean",
	heat = "AmbHeat",
	bedVolume = 0.45,
	heatVolume = 0.3,
	lifeMin = 0.35,
	fadeSeconds = 2.5,
}

-- (life, heat) volume scales for a fill fraction.
function Cues.ambienceMix(fill: number): (number, number)
	local f = math.clamp(fill, 0, 1)
	local lifeMin = Cues.ambience.lifeMin
	return lifeMin + (1 - lifeMin) * f, 1 - f
end

-- Music (client/Music): the map's track, a faster one for the final push (the last 5% of the
-- ocean) and a calm one for waiting. Tracks crossfade; big moments (cards, purchases) duck the
-- music so they read.
Cues.music = {
	tracks = {
		ocean = "MusicMap1",
		finale = "MusicFinale",
		calm = "MusicCalm",
	},
	volume = 0.35,
	fadeSeconds = 2.5,
	finalPushFill = 0.95,
	duck = 0.4, -- volume scale while ducked
	duckSeconds = 1.2, -- after a purchase
}

-- Which track should play: a key of Cues.music.tracks.
function Cues.musicTrack(phase: string?, fill: number): string
	if phase ~= "playing" and phase ~= "ending" then
		return "calm"
	end
	if fill >= Cues.music.finalPushFill then
		return "finale"
	end
	return "ocean"
end

function Cues.size(tier: number): number
	return math.min(Cues.SIZE_MAX, 1 + Cues.SIZE_PER_TIER * (math.max(tier, 1) - 1))
end

function Cues.pitch(tier: number): number
	return math.max(Cues.PITCH_MIN, 1 - Cues.PITCH_PER_TIER * (math.max(tier, 1) - 1))
end

-- One variant from a list; roll is a random number in [0, 1).
function Cues.pick(list: { string }, roll: number): string
	return list[math.min(#list, math.floor(roll * #list) + 1)]
end

-- Like pick, but never the same variant as `last` (a repeat sounds like a stutter).
function Cues.pickNext(list: { string }, roll: number, last: string?): string
	local others = {}
	for _, name in list do
		if name ~= last then
			table.insert(others, name)
		end
	end
	return if #others > 0 then Cues.pick(others, roll) else list[1]
end

function Cues.between(min: number, max: number, roll: number): number
	return min + (max - min) * roll
end

return Cues
