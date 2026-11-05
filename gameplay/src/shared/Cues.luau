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

-- Footsteps (client/Footsteps). Surfaces come from shared/Steps. Each surface's variants must come
-- from one matched set (same recording), or the steps sound like two different people. Carrying
-- water makes steps heavier: lower and a little louder.
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
}

-- Ambience (client/Ambience): one looping bed per stage, plus a heat layer. A dry basin is hot and
-- quiet; as it fills, the heat fades and the life in the bed comes back.
Cues.ambience = {
	beds = { Pool = "AmbPool", Lake = "AmbLake", Ocean = "AmbOcean" },
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

-- Music (client/Music): one track per stage, a faster one for the final push (the last stage's
-- last 5%) and a calm one for waiting and results. Tracks crossfade; big moments (stage cards,
-- purchases) duck the music so they read.
Cues.music = {
	tracks = {
		Pool = "MusicPool",
		Lake = "MusicLake",
		Ocean = "MusicOcean",
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
function Cues.musicTrack(phase: string?, stageName: string?, isLastStage: boolean, fill: number): string
	if (phase ~= "playing" and phase ~= "card") or not stageName then
		return "calm"
	end
	if isLastStage and fill >= Cues.music.finalPushFill then
		return "finale"
	end
	return stageName
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
