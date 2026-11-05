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

return tests
