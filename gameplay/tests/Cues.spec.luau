local Cues = require("../src/shared/Cues")

local tests = {}

function tests.size_grows_and_caps(t)
	t.expectEq(Cues.size(1), 1)
	t.expectNear(Cues.size(2), 1.08, 1e-9)
	t.expectEq(Cues.size(20), 2.5)
	t.expectEq(Cues.size(0), 1)
end

function tests.pitch_drops_and_floors(t)
	t.expectEq(Cues.pitch(1), 1)
	t.expectNear(Cues.pitch(9), 0.9, 1e-9)
	t.expectEq(Cues.pitch(30), 0.75)
end

function tests.pick_covers_every_variant(t)
	local list = { "a", "b", "c" }
	t.expectEq(Cues.pick(list, 0), "a")
	t.expectEq(Cues.pick(list, 0.34), "b")
	t.expectEq(Cues.pick(list, 0.99), "c")
	t.expectEq(Cues.pick(list, 1), "c")
end

function tests.between_blends(t)
	t.expectNear(Cues.between(0.92, 1.08, 0.5), 1.0, 1e-9)
end

function tests.pick_next_never_repeats_the_last_variant(t)
	local list = { "a", "b", "c" }
	t.expectEq(Cues.pickNext(list, 0, "a"), "b")
	t.expectEq(Cues.pickNext(list, 0.99, "a"), "c")
	t.expectEq(Cues.pickNext(list, 0, "b"), "a")
	t.expectEq(Cues.pickNext(list, 0.99, "c"), "b")
	t.expectEq(Cues.pickNext(list, 0.5, nil), "b")
	t.expectEq(Cues.pickNext({ "only" }, 0.5, "only"), "only")
end

function tests.scoop_cue_is_sane(t)
	local cue = Cues.scoop
	t.expectEq(#cue.splashSounds, 3)
	if not (cue.pitchMin < cue.pitchMax) then
		error("scoop pitchMin must be below pitchMax")
	end
	for _, field in { "holdVolume", "splashVolume", "otherVolume" } do
		local v = cue[field]
		if not (type(v) == "number" and v > 0 and v <= 1) then
			error(`scoop {field} = {tostring(v)} is not in (0, 1]`)
		end
	end
end

function tests.pour_cue_is_sane(t)
	local cue = Cues.pour
	t.expectEq(#cue.splashSounds, 3)
	if not (cue.pitchMin < cue.pitchMax) then
		error("pour pitchMin must be below pitchMax")
	end
	for _, field in { "splashVolume", "otherVolume" } do
		local v = cue[field]
		if not (type(v) == "number" and v > 0 and v <= 1) then
			error(`pour {field} = {tostring(v)} is not in (0, 1]`)
		end
	end
end

-- client/Feel.splash multiplies the splash by sizeScale, so every splash cue needs one.
function tests.every_splash_cue_has_a_size_scale(t)
	for name, cue in { scoop = Cues.scoop, pour = Cues.pour, channelSplash = Cues.channel.splash } do
		local v = cue.sizeScale
		if not (type(v) == "number" and v > 0) then
			error(`{name} sizeScale = {tostring(v)} is not a positive number`)
		end
	end
end

function tests.coins_cue_is_sane(t)
	local cue = Cues.coins
	t.expectEq(type(cue.tickSound), "string")
	t.expectEq(type(cue.burstSound), "string")
	t.expectEq(type(cue.coin), "string")
	t.expectEq(type(cue.pop), "string")
	for _, field in { "tickVolume", "burstVolume" } do
		local v = cue[field]
		if not (type(v) == "number" and v > 0 and v <= 1) then
			error(`coins {field} = {tostring(v)} is not in (0, 1]`)
		end
	end
end

function tests.purchase_cue_is_sane(t)
	local cue = Cues.purchase
	for _, field in { "sting", "deny", "unlock", "whoosh", "sparkle" } do
		t.expectEq(type(cue[field]), "string", field)
	end
	for _, field in { "stingVolume", "denyVolume", "unlockVolume", "whooshVolume" } do
		local v = cue[field]
		if not (type(v) == "number" and v > 0 and v <= 1) then
			error(`purchase {field} = {tostring(v)} is not in (0, 1]`)
		end
	end
end

-- Slots not in hand sit smaller and fainter, still visible.
function tests.hotbar_idle_slots_are_smaller_and_fainter(t)
	local cue = Cues.hotbar
	t.expectEq(cue.idleScale, 0.82)
	t.expectEq(cue.idleTransparency, 0.45)
	t.expectEq(cue.seconds, 0.12)
end

function tests.milestone_cue_is_sane(t)
	local cue = Cues.milestone
	t.expectEq(cue.swoopSeconds, 2, "the swoop takes 2 s (D9)")
	t.expectEq(type(cue.sound), "string")
	if not (cue.soundVolume > 0 and cue.soundVolume <= 1) then
		error(`milestone soundVolume {cue.soundVolume} is not in (0, 1]`)
	end
	if not (cue.reviveFrom > 0 and cue.reviveFrom < 1) then
		error("a revive pops up from a smaller size (ScaleTo can't take 0)")
	end
	if not (cue.sightingRise + cue.sightingSink < cue.sightingSeconds) then
		error("the bacon-hair must stand on the horizon between rising and sinking")
	end
end

function tests.honeycomb_cue_is_sane(t)
	local cue = Cues.honeycomb
	t.expectEq(Cues.stingPitch(1), 1)
	t.expectNear(Cues.stingPitch(2), 1 + cue.stingPitchStep, 1e-9)
	t.expectEq(Cues.stingPitch(100), cue.stingPitchMax, "the climb caps")
	t.expectEq(Cues.stingPitch(0), 1)
	if not (cue.breatheScale > 1 and cue.breatheScale <= 1.05) then
		error(`breatheScale {cue.breatheScale} must be a gentle swell above 1`)
	end
	if cue.enterSeconds + cue.enterCap > 0.3 + 1e-9 then
		error("hexes must finish entering within 0.3 s")
	end
	for _, field in { "glideSeconds", "waterSeconds", "popSeconds", "checkSeconds", "bridgeSeconds", "wakeSeconds", "bounceSeconds", "breatheSeconds" } do
		local v = cue[field]
		if not (type(v) == "number" and v > 0 and v <= 1.5) then
			error(`honeycomb {field} = {tostring(v)} is not in (0, 1.5]`)
		end
	end
	t.expectEq(cue.minHexPixels, 64, "phones: hexes at least 64 px (library shop.md)")
end

function tests.every_surface_has_step_sounds(t)
	for _, surface in { "stone", "grass", "sand", "wood" } do
		local list = Cues.steps.surfaces[surface]
		if not (list and #list > 0) then
			error(`no step sounds for {surface}`)
		end
	end
end

function tests.dust_and_drips_are_named(t)
	t.expectEq(type(Cues.steps.dust), "string")
	t.expectEq(Cues.steps.dustSurfaces.sand, true)
	t.expectEq(Cues.steps.dustSurfaces.grass, nil, "grass doesn't puff")
	if not (Cues.steps.landDust > 1) then
		error("a landing should puff more dust than a step")
	end
	t.expectEq(type(Cues.carry.drips), "string")
end

function tests.the_ocean_has_an_ambience_bed(t)
	t.expectEq(type(Cues.ambience.bed), "string")
	t.expectEq(Cues.ambience.beds, nil, "one bed, not a table of beds")
end

function tests.filling_brings_life_back_and_quiets_the_heat(t)
	local life, heat = Cues.ambienceMix(0)
	t.expectNear(life, Cues.ambience.lifeMin, 1e-9)
	t.expectNear(heat, 1, 1e-9)
	life, heat = Cues.ambienceMix(1)
	t.expectNear(life, 1, 1e-9)
	t.expectNear(heat, 0, 1e-9)
	life, heat = Cues.ambienceMix(0.5)
	t.expectNear(life, Cues.ambience.lifeMin + (1 - Cues.ambience.lifeMin) * 0.5, 1e-9)
	t.expectNear(heat, 0.5, 1e-9)
	life, heat = Cues.ambienceMix(2)
	t.expectNear(heat, 0, 1e-9)
end

function tests.the_ocean_plays_its_track(t)
	t.expectEq(Cues.musicTrack("playing", 0), "ocean")
	t.expectEq(Cues.musicTrack("playing", 0.5), "ocean")
	t.expectEq(Cues.musicTrack("loading", 0), "calm", "waiting for the team")
	t.expectEq(Cues.musicTrack("intro", 0), "calm")
	t.expectEq(Cues.musicTrack("done", 1), "calm")
	t.expectEq(Cues.musicTrack(nil, 0), "calm")
end

function tests.the_final_push_speeds_up(t)
	t.expectEq(Cues.musicTrack("playing", 0.94), "ocean")
	t.expectEq(Cues.musicTrack("playing", 0.95), "finale")
	t.expectEq(Cues.musicTrack("ending", 1), "finale", "stays on through the ending")
end

function tests.every_music_track_is_named(t)
	for _, key in { "ocean", "finale", "calm" } do
		t.expectEq(type(Cues.music.tracks[key]), "string", key)
	end
	if not (Cues.music.duck > 0 and Cues.music.duck < 1) then
		error("music duck must be between 0 and 1")
	end
end

return tests
