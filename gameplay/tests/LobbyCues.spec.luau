local LobbyCues = require("../../lobby/src/shared/LobbyCues")
local Steps = require("../src/shared/Steps")

local tests = {}

local PAD_STATES = { "open", "setup", "party", "closed", "saved", "counting", "launching" }

local function isName(value: any): boolean
	return type(value) == "string" and value ~= ""
end

function tests.every_named_sound_is_a_string(t)
	local names = {
		LobbyCues.music.track,
		LobbyCues.ambience.bed,
		LobbyCues.ui.click,
		LobbyCues.ui.whoosh,
		LobbyCues.ui.deny,
		LobbyCues.pads.splashSound,
		LobbyCues.countdown.tick,
		LobbyCues.countdown.go,
		LobbyCues.countdown.whoosh,
		LobbyCues.countdown.cancel,
		LobbyCues.horizon.slurp,
		LobbyCues.horizon.burp,
	}
	for _, list in LobbyCues.steps.surfaces do
		for _, name in list do
			table.insert(names, name)
		end
	end
	t.expectEq(#names > 12, true, "names collected")
	for i, name in names do
		t.expectEq(isName(name), true, `sound {i}`)
	end
end

function tests.every_named_effect_and_model_is_a_string(t)
	for _, name in { LobbyCues.pads.splash, LobbyCues.pads.bubbles, LobbyCues.countdown.sparkle, LobbyCues.gulls.model, LobbyCues.horizon.model } do
		t.expectEq(isName(name), true, tostring(name))
	end
end

function tests.volumes_are_between_0_and_1(t)
	local checked = 0
	for group, cue in LobbyCues :: any do
		if type(cue) == "table" then
			for key, value in cue do
				if type(key) == "string" and (key == "volume" or key:sub(-6) == "Volume") then
					t.expectEq(type(value) == "number" and value >= 0 and value <= 1, true, `{group}.{key}`)
					checked += 1
				end
			end
		end
	end
	t.expectEq(checked >= 12, true, "volumes checked")
end

function tests.step_surfaces_match_gameplay_steps(t)
	for _, material in { "WoodPlanks", "Wood", "Sand", "Snow", "Salt", "LeafyGrass", "Grass", "Ground", "Mud", "Plastic", "Concrete", "Slate", "Neon" } do
		t.expectEq(LobbyCues.surface(material), Steps.surface(material), material)
		local list = LobbyCues.steps.surfaces[LobbyCues.surface(material)]
		t.expectEq(list ~= nil and #list > 0, true, material)
	end
	t.expectEq(LobbyCues.steps.stride, Steps.STRIDE)
end

function tests.pick_next_never_repeats_the_last_variant(t)
	local list = { "a", "b", "c" }
	t.expectEq(LobbyCues.pickNext(list, 0, "a"), "b")
	t.expectEq(LobbyCues.pickNext(list, 0.99, "a"), "c")
	t.expectEq(LobbyCues.pickNext(list, 0, "b"), "a")
	t.expectEq(LobbyCues.pickNext(list, 0.5, nil), "b")
	t.expectEq(LobbyCues.pickNext({ "only" }, 0.5, "only"), "only")
end

function tests.every_pad_state_has_a_look(t)
	for _, state in PAD_STATES do
		local look = LobbyCues.padLook(state)
		t.expectEq(isName(look.color), true, `{state}.color`)
		t.expectEq(type(look.pulseHz) == "number" and look.pulseHz >= 0, true, `{state}.pulseHz`)
		t.expectEq(type(look.light) == "number" and look.light >= 0, true, `{state}.light`)
		t.expectEq(type(look.bubbles), "boolean", `{state}.bubbles`)
	end
end

function tests.pad_looks_tell_free_joinable_and_busy_apart(t)
	t.expectEq(LobbyCues.padLook("open").color ~= LobbyCues.padLook("party").color, true)
	t.expectEq(LobbyCues.padLook("party").color ~= LobbyCues.padLook("closed").color, true)
	t.expectEq(LobbyCues.padLook("party").pulseHz > 0, true)
	t.expectEq(LobbyCues.padLook("counting").pulseHz > LobbyCues.padLook("party").pulseHz, true)
end

function tests.unknown_pad_state_errors(t)
	t.expectEq((pcall(LobbyCues.padLook, "nope")), false)
end

function tests.countdown_number_counts_down_whole_seconds(t)
	t.expectEq(LobbyCues.countdownNumber(10, 7.0), 3)
	t.expectEq(LobbyCues.countdownNumber(10, 7.01), 3)
	t.expectEq(LobbyCues.countdownNumber(10, 8.5), 2)
	t.expectEq(LobbyCues.countdownNumber(10, 9.99), 1)
	t.expectEq(LobbyCues.countdownNumber(10, 10), 0)
	t.expectEq(LobbyCues.countdownNumber(10, 12), 0)
end

function tests.palm_sway_stays_within_its_angle(t)
	local max = math.rad(LobbyCues.palms.degrees) + 1e-9
	for seed = 1, 20 do
		for step = 0, 400 do
			local x, z = LobbyCues.sway(step * 0.37, seed)
			t.expectEq(math.abs(x) <= max and math.abs(z) <= max, true, `seed {seed} t {step * 0.37}`)
		end
	end
end

function tests.palm_sway_differs_by_seed(t)
	local ax, az = LobbyCues.sway(3.3, 1)
	local bx, bz = LobbyCues.sway(3.3, 2)
	t.expectEq(math.abs(ax - bx) + math.abs(az - bz) > 1e-4, true)
end

function tests.gull_paths_stay_in_the_sky(t)
	local g = LobbyCues.gulls
	for i = 1, g.count do
		for step = 0, 300 do
			local x, y, z = LobbyCues.gullAt(step * 0.53, i)
			local r = math.sqrt((x - g.centre[1]) ^ 2 + (z - g.centre[3]) ^ 2)
			t.expectEq(y >= g.heightMin - 1e-9 and y <= g.heightMax + 1e-9, true, `gull {i} height {y}`)
			t.expectEq(r >= g.radiusMin - 1e-6 and r <= g.radiusMax + 1e-6, true, `gull {i} radius {r}`)
		end
	end
end

function tests.gull_heading_is_flat_and_unit(t)
	for i = 1, LobbyCues.gulls.count do
		local _, _, _, dx, dz, turn = LobbyCues.gullAt(5.5, i)
		t.expectNear(dx * dx + dz * dz, 1, 1e-6, `gull {i} heading`)
		t.expectEq(turn == 1 or turn == -1, true, `gull {i} turn`)
	end
end

function tests.gulls_follow_their_heading(t)
	-- a short step forward moves the gull roughly along the heading it reports
	for i = 1, LobbyCues.gulls.count do
		local x0, _, z0, dx, dz = LobbyCues.gullAt(10, i)
		local x1, _, z1 = LobbyCues.gullAt(10.01, i)
		local mx, mz = x1 - x0, z1 - z0
		local length = math.sqrt(mx * mx + mz * mz)
		t.expectEq(length > 0, true, `gull {i} moves`)
		t.expectEq((mx * dx + mz * dz) / length > 0.9, true, `gull {i} faces where it flies`)
	end
end

function tests.gull_wings_flap_within_their_angle_and_glide_between(t)
	local max = math.rad(LobbyCues.gulls.flapDegrees) + 1e-9
	for i = 1, LobbyCues.gulls.count do
		local gliding = 0
		for step = 0, 2000 do
			local angle = LobbyCues.flap(step * 0.01, i)
			t.expectEq(math.abs(angle) <= max, true, `gull {i} flap {angle}`)
			if angle == 0 then
				gliding += 1
			end
		end
		t.expectEq(gliding > 500, true, `gull {i} glides between flaps`)
	end
end

function tests.belly_swell_rises_and_settles(t)
	local h = LobbyCues.horizon
	t.expectEq(LobbyCues.swell(0), 0)
	t.expectNear(LobbyCues.swell(h.swellIn), 1, 1e-9)
	t.expectEq(LobbyCues.swell(h.swellIn + h.swellOut), 0)
	t.expectEq(LobbyCues.swell(h.swellIn + h.swellOut + 5), 0)
	t.expectEq(LobbyCues.swell(-1), 0)
	for step = 0, 100 do
		local s = LobbyCues.swell(step * 0.06)
		t.expectEq(s >= 0 and s <= 1, true, `swell {s}`)
	end
end

function tests.burp_hop_is_one_arc(t)
	local h = LobbyCues.horizon
	t.expectEq(LobbyCues.hop(0), 0)
	t.expectNear(LobbyCues.hop(h.hopSeconds / 2), 1, 1e-9)
	t.expectEq(LobbyCues.hop(h.hopSeconds), 0)
	t.expectEq(LobbyCues.hop(-0.1), 0)
	t.expectEq(LobbyCues.hop(h.hopSeconds + 1), 0)
end

return tests
