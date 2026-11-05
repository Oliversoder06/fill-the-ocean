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

function tests.every_stage_has_an_ambience_bed(t)
	for _, stage in { "Pool", "Lake", "Ocean" } do
		t.expectEq(type(Cues.ambience.beds[stage]), "string", stage)
	end
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

function tests.each_stage_plays_its_own_track(t)
	t.expectEq(Cues.musicTrack("playing", "Pool", false, 0.5), "Pool")
	t.expectEq(Cues.musicTrack("playing", "Lake", false, 0.99), "Lake", "the final push is only the last stage")
	t.expectEq(Cues.musicTrack("card", "Ocean", true, 0), "Ocean")
end

function tests.the_final_push_speeds_up(t)
	t.expectEq(Cues.musicTrack("playing", "Ocean", true, 0.94), "Ocean")
	t.expectEq(Cues.musicTrack("playing", "Ocean", true, 0.95), "finale")
	t.expectEq(Cues.musicTrack("card", "Ocean", true, 1), "finale", "stays on through the FULL! card")
end

function tests.waiting_and_results_are_calm(t)
	t.expectEq(Cues.musicTrack("waiting", nil, false, 0), "calm")
	t.expectEq(Cues.musicTrack("saving", nil, false, 0), "calm")
	t.expectEq(Cues.musicTrack("results", nil, false, 0), "calm")
	t.expectEq(Cues.musicTrack(nil, nil, false, 0), "calm")
	t.expectEq(Cues.musicTrack("playing", nil, false, 0), "calm", "no stage yet")
end

function tests.every_music_track_is_named(t)
	for _, key in { "Pool", "Lake", "Ocean", "finale", "calm" } do
		t.expectEq(type(Cues.music.tracks[key]), "string", key)
	end
	if not (Cues.music.duck > 0 and Cues.music.duck < 1) then
		error("music duck must be between 0 and 1")
	end
end

return tests
