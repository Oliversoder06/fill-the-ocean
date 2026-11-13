local IntroClips = require("../src/shared/IntroClips")
local IntroCut = require("../src/shared/IntroCut")
local Rig = require("../vendor/Animation/Rig")
local Anatomy = require("../vendor/Animation/Anatomy")
local Templates = require("../vendor/Animation/Templates")
local Performance = require("../vendor/Animation/Performance")
local Lint = require("../vendor/Animation/Lint")
local Baked = require("../vendor/Animation/Baked")
local M = require("../vendor/Animation/Math")

local tests = {}

-- The runtime's stand-in rigs judge timing, spacing and weight offline: R15 for your avatar (also
-- half as big again, like a tall avatar, and on tall block feet, which the runtime reads as a plain
-- chain of three joints rather than a leg on a flat foot), R6 for the bacon-hair.
local r15 = Anatomy.classify(Rig.build(Templates.R15()))
local tall = Anatomy.classify(Rig.build(Rig.scaleSpec(Templates.R15(), 1.5)))
local tallFeet = (function()
	local spec = Templates.R15()
	for _, joint in spec.joints do
		if joint.name == "LeftAnkle" or joint.name == "RightAnkle" then
			joint.size = { 1, 0.7, 1 }
			joint.center = { pos = { 0, -0.35, 0 } }
		end
	end
	spec.ground = -3.5
	return Anatomy.classify(Rig.build(spec))
end)()
local r6 = Anatomy.classify(Rig.build(Templates.R6()))

local BEACH = 2.22 -- the sand's height beside the lounger in the place (measured)

local function fixes(baked, anatomy): string
	local bad = {}
	for _, finding in Lint.run(baked, anatomy) do
		if finding.severity == "fix" then
			table.insert(bad, `{finding.rule}: {finding.message}`)
		end
	end
	return table.concat(bad, "\n    ")
end

local function clean(t, name: string, clip, anatomy)
	local errors = Performance.validate(clip)
	t.expectEq(#errors, 0, `{name} validates{if errors[1] then `: {errors[1].path} {errors[1].expected}` else ""}`)
	local baked = Performance.bake(anatomy, clip)
	t.expectEq(Baked.finite(baked), true, `{name} bakes finite`)
	t.expectEq(#baked.warnings, 0, `{name}: {table.concat(baked.warnings, "; ")}`)
	t.expectEq(fixes(baked, anatomy), "", `{name}'s lint`)
end

-- The lie-down as client/Intro builds it for a body standing where the walk stops: the stand (the
-- stretch and the turn), then the lie.
local function lieFor(anatomy)
	local places = IntroCut.places
	local root = { places.walkTo[1], BEACH - anatomy.rig.ground, places.walkTo[3] }
	return IntroClips.lie(anatomy, IntroClips.seat(places.cushion, places.recline, root), IntroClips.watch(places.baconFrom, places.baconTo, root))
end

local BODIES = { { "R15", r15 }, { "tall R15", tall }, { "R15 on tall feet", tallFeet } }

function tests.tall_feet_read_as_a_plain_chain(t)
	for _, leg in tallFeet.legs do
		t.expectEq(leg.ik, "chain", `{leg.name}: the case the lie-down must pose by hand`)
	end
end

-- The lowest corner of a leg's foot part, over a baked clip's frames from `from` to `to` seconds.
local function lowestFoot(anatomy, baked, leg, from: number, to: number): number
	local rig = anatomy.rig
	local ankle = leg.movable[#leg.movable]
	local joint = rig.joints[ankle]
	local half = { x = joint.size.x / 2, y = joint.size.y / 2, z = joint.size.z / 2 }
	local low = math.huge
	for s = math.floor(from * baked.rate), math.floor(to * baked.rate) do
		local frame = Rig.fk(rig, Baked.locals(baked, rig, s), Baked.get(baked, s, 0))[ankle]
		local box = M.xmul(frame, joint.center)
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					low = math.min(low, M.xpoint(box, { x = sx * half.x, y = sy * half.y, z = sz * half.z }).y)
				end
			end
		end
	end
	return low
end

-- Standing, stretching, stepping round and sitting down, no foot goes into the sand.
function tests.no_foot_goes_into_the_sand(t)
	for _, body in BODIES do
		local anatomy = body[2]
		local stand, lie = lieFor(anatomy)
		local standBaked, lieBaked = Performance.bake(anatomy, stand), Performance.bake(anatomy, lie)
		for _, leg in anatomy.legs do
			local sink = 0.02 * leg.reach
			local what = `{body[1]} {leg.name}`
			local standing = lowestFoot(anatomy, standBaked, leg, 0, stand.length)
			t.expectEq(standing >= anatomy.rig.ground - sink, true, `{what}: {anatomy.rig.ground - standing} studs into the sand standing`)
			local sitting = lowestFoot(anatomy, lieBaked, leg, 0, 1.45)
			t.expectEq(sitting >= anatomy.rig.ground - sink, true, `{what}: {anatomy.rig.ground - sitting} studs into the sand sitting down`)
		end
	end
end

-- Swinging the legs up onto the cushion, no foot goes through it: over the cushion (in front of
-- the backrest), every corner of each foot is above its top.
function tests.the_legs_swing_up_over_the_cushion_not_through_it(t)
	for _, body in BODIES do
		local anatomy = body[2]
		local rig = anatomy.rig
		local places = IntroCut.places
		local root = { places.walkTo[1], BEACH - rig.ground, places.walkTo[3] }
		local seat = IntroClips.seat(places.cushion, places.recline, root)
		local far = 2 * seat.centre - seat.edge
		local _, lie = lieFor(anatomy)
		local baked = Performance.bake(anatomy, lie)
		for _, leg in anatomy.legs do
			local ankle = leg.movable[#leg.movable]
			local joint = rig.joints[ankle]
			local worst = 0
			for s = math.floor(1.0 * baked.rate), math.floor(3.5 * baked.rate) do
				local frame = Rig.fk(rig, Baked.locals(baked, rig, s), Baked.get(baked, s, 0))[ankle]
				local box = M.xmul(frame, joint.center)
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local p = M.xpoint(box, { x = sx * joint.size.x / 2, y = sy * joint.size.y / 2, z = sz * joint.size.z / 2 })
							if p.x > seat.edge and p.x < far and p.z < seat.hinge then
								worst = math.max(worst, seat.top - p.y)
							end
						end
					end
				end
			end
			t.expectEq(worst < 0.03 * leg.reach, true, `{body[1]} {leg.name}: {worst} studs into the cushion swinging up`)
		end
	end
end

-- Lying back, the heels rest on the cushion: not in it, not floating over it.
function tests.lying_back_rests_the_heels_on_the_cushion(t)
	for _, body in BODIES do
		local anatomy = body[2]
		local places = IntroCut.places
		local root = { places.walkTo[1], BEACH - anatomy.rig.ground, places.walkTo[3] }
		local seat = IntroClips.seat(places.cushion, places.recline, root)
		local _, lie = lieFor(anatomy)
		local baked = Performance.bake(anatomy, lie)
		for _, leg in anatomy.legs do
			local low = lowestFoot(anatomy, baked, leg, 4, lie.length)
			local what = `{body[1]} {leg.name}`
			t.expectEq(low >= seat.top - 0.02 * leg.reach, true, `{what}: {seat.top - low} studs into the cushion`)
			t.expectEq(low <= seat.top + 0.05 * leg.reach, true, `{what}: {low - seat.top} studs over the cushion`)
		end
	end
end

function tests.the_lie_down_lints_clean_on_any_size(t)
	for _, body in BODIES do
		local stand, lie = lieFor(body[2])
		clean(t, `stand ({body[1]})`, stand, body[2])
		clean(t, `lie ({body[1]})`, lie, body[2])
	end
end

-- Sitting down on the cushion's edge, each foot stays flat on the sand where it stood.
function tests.sitting_down_keeps_the_feet_flat_on_the_sand(t)
	for _, body in BODIES do
		local anatomy = body[2]
		local rig = anatomy.rig
		local _, lie = lieFor(anatomy)
		local baked = Performance.bake(anatomy, lie)
		for _, leg in anatomy.legs do
			local ankle = leg.joints[#leg.joints]
			local rest = rig.joints[ankle].world.q
			local first = nil
			local tilt, height, slide = 0, 0, 0
			for s = 0, math.floor(1.45 * baked.rate) do
				local frame = Rig.fk(rig, Baked.locals(baked, rig, s), Baked.get(baked, s, 0))[ankle]
				local contact = M.xpoint(frame, leg.foot)
				first = first or contact
				local up = M.qrot(M.qmul(frame.q, M.qconj(rest)), { x = 0, y = 1, z = 0 })
				tilt = math.max(tilt, math.deg(math.acos(math.clamp(up.y, -1, 1))))
				height = math.max(height, math.abs(contact.y - leg.contact.y))
				slide = math.max(slide, M.vdist(contact, first))
			end
			local what = `{body[1]} {leg.name}`
			t.expectEq(tilt < 6, true, `{what}: the foot tips {tilt} degrees`)
			t.expectEq(height < 0.04 * leg.reach, true, `{what}: the sole leaves the sand by {height} studs`)
			t.expectEq(slide < 0.06 * leg.reach, true, `{what}: the foot slides {slide} studs`)
		end
	end
end

function tests.the_other_clips_lint_clean(t)
	clean(t, "slump", IntroClips.slump, r15)
	clean(t, "sandSit", IntroClips.sandSit, r6)
	clean(t, "sandPlay", IntroClips.sandPlay, r6)
end

-- An R6 avatar lies down too (straight legs swung whole at the hip): the clips lint clean; its legs
-- keep out of the sand and the cushion but for a corner's brush (a fifth of the leg's thickness: a
-- leg that can't bend tips as the hips go down), and lying back they rest on the cushion.
function tests.an_r6_avatar_lies_down_too(t)
	local BRUSH = 0.2
	local rig = r6.rig
	local places = IntroCut.places
	local root = { places.walkTo[1], BEACH - rig.ground, places.walkTo[3] }
	local seat = IntroClips.seat(places.cushion, places.recline, root)
	local far = 2 * seat.centre - seat.edge
	local stand, lie = lieFor(r6)
	clean(t, "stand (R6)", stand, r6)
	clean(t, "lie (R6)", lie, r6)
	local standBaked, lieBaked = Performance.bake(r6, stand), Performance.bake(r6, lie)
	for _, leg in r6.legs do
		local what = `R6 {leg.name}`
		local standing = lowestFoot(r6, standBaked, leg, 0, stand.length)
		t.expectEq(standing >= rig.ground - BRUSH, true, `{what}: {rig.ground - standing} studs into the sand standing`)
		local sitting = lowestFoot(r6, lieBaked, leg, 0, 1.45)
		t.expectEq(sitting >= rig.ground - BRUSH, true, `{what}: {rig.ground - sitting} studs into the sand sitting down`)
		local joint = rig.joints[leg.movable[1]]
		local worst = 0
		for s = math.floor(1.0 * lieBaked.rate), math.floor(3.5 * lieBaked.rate) do
			local box = M.xmul(Rig.fk(rig, Baked.locals(lieBaked, rig, s), Baked.get(lieBaked, s, 0))[leg.movable[1]], joint.center)
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = M.xpoint(box, { x = sx * joint.size.x / 2, y = sy * joint.size.y / 2, z = sz * joint.size.z / 2 })
						if p.x > seat.edge and p.x < far and p.z < seat.hinge then
							worst = math.max(worst, seat.top - p.y)
						end
					end
				end
			end
		end
		t.expectEq(worst < BRUSH, true, `{what}: {worst} studs into the cushion swinging up`)
		local lying = lowestFoot(r6, lieBaked, leg, 4, lie.length)
		t.expectEq(lying >= seat.top - 0.05 and lying <= seat.top + 0.1, true, `{what}: lies {lying - seat.top} studs from the cushion's top`)
	end
end

-- Lying back ends with the hips on the cushion: the clip's last hips key, added to the body's
-- pivot, sits over the cushion's middle, above its top and by the backrest.
function tests.the_lie_down_ends_on_the_cushion(t)
	for _, anatomy in { r15, tall } do
		local places = IntroCut.places
		local root = { places.walkTo[1], BEACH - anatomy.rig.ground, places.walkTo[3] }
		local seat = IntroClips.seat(places.cushion, places.recline, root)
		local _, clip = lieFor(anatomy)
		local hips = clip.tracks.hips
		local last = hips[#hips]
		local pivot = anatomy.rig.joints[anatomy.body].world.p
		t.expectNear(pivot.x + last.pos[1], seat.centre, 1e-6, "over the cushion's middle")
		t.expectEq(pivot.y + last.pos[2] > seat.top, true, "above its top")
		t.expectEq(math.abs(pivot.z + last.pos[3] - seat.hinge) < 0.5, true, "by the backrest")
		t.expectEq(last.rot[1] >= places.recline, true, "lying back")
	end
end

-- The ending's slap lints clean on any body (its forearm and chest keys only where they exist), and
-- lands on its Hit marker.
function tests.the_slap_lints_clean_on_any_body(t)
	for _, body in { { "R15", r15 }, { "tall R15", tall }, { "R6", r6 } } do
		local clip = IntroClips.slap(body[2])
		clean(t, `slap ({body[1]})`, clip, body[2])
		t.expectEq(clip.markers[1].name, "Hit")
		t.expectEq(clip.markers[1].t, IntroClips.slapHit)
	end
	t.expectEq(IntroClips.slap(r6).tracks.rightForearm, nil, "no forearm on R6")
	t.expectEq(IntroClips.slap(r15).tracks.rightForearm ~= nil, true, "a forearm on R15")
end

-- The yawn's sound comes as the stretch's yawn does.
function tests.the_yawn_lines_up_with_the_cut(t)
	local stand, lie = lieFor(r15)
	local yawn = nil
	for _, cue in IntroCut.sounds do
		if cue.sound == "IntroYawn" then
			yawn = cue
		end
	end
	t.expectEq(stand.markers[1].name, "Yawn")
	t.expectNear(yawn.t - IntroCut.beats.lie, stand.markers[1].t, 0.1, "the yawn's sound")
	t.expectEq(stand.length, IntroClips.turnSeconds, "the lie takes over as the stand ends")
	t.expectEq(IntroCut.beats.lie + IntroClips.turnSeconds + lie.length >= IntroCut.beats.swap, true, "lies until the eyes are shut")
end

-- The walks are Roblox's own animations: your avatar's matches the ground at the default Animate
-- script's walk speed (16 x 0.5 / 1.25 studs a second at height scale 1).
function tests.the_walks_are_robloxs_own(t)
	t.expectEq(IntroClips.walks.player.pace, 6.4)
	t.expectEq(IntroClips.walks.player.default, "rbxassetid://913402848")
	t.expectEq(IntroClips.walks.bacon.pace, 14.5)
end

return tests
