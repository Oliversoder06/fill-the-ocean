local EndCut = require("../src/shared/EndCut")
local IntroCut = require("../src/shared/IntroCut")
local IntroClips = require("../src/shared/IntroClips")
local Rig = require("../vendor/Animation/Rig")
local Anatomy = require("../vendor/Animation/Anatomy")
local Templates = require("../vendor/Animation/Templates")

local tests = {}

local GRAVITY = 196.2 -- Workspace.Gravity

local function sorted(keys: { any }, label: string, t)
	for i = 2, #keys do
		t.expectEq(keys[i].t >= keys[i - 1].t, true, `{label}: key {i} comes after key {i - 1}`)
	end
end

function tests.tracks_are_in_order_and_inside_the_cut(t)
	for _, name in { "lids", "blur", "black", "logoAlpha", "logoScale", "music" } do
		local keys = EndCut[name]
		sorted(keys, name, t)
		t.expectEq(keys[#keys].t <= EndCut.length, true, `{name} ends inside the cut`)
	end
	for _, shot in EndCut.shots do
		sorted(shot.keys, shot.name, t)
		t.expectEq(shot.keys[1].t, shot.at, `{shot.name} keys start with the shot`)
		t.expectEq(shot.keys[#shot.keys].t <= EndCut.length, true, `{shot.name} ends inside the cut`)
	end
	for _, cue in EndCut.sounds do
		t.expectEq(cue.t >= 0 and cue.t < EndCut.length, true, `{cue.sound} plays inside the cut`)
		local kind = cue.sound:sub(1, 5)
		t.expectEq(kind == "Intro" or cue.sound:sub(1, 3) == "End", true, `{cue.sound}: the story's sounds are Audio.Intro* / End*`)
		t.expectEq(cue.volume > 0 and cue.volume <= 1, true, `{cue.sound}'s volume`)
	end
end

-- He sits down and dips his straw in; you get up just before he drinks, march over and slap him the
-- moment you reach him: the get-up (the lie-down backwards) is over before the march.
function tests.the_story_runs_in_order(t)
	local b = EndCut.beats
	t.expectEq(EndCut.skipAfter > 0 and EndCut.skipAfter < b.drop, true, "skip comes in early")
	t.expectEq(b.drop < b.baconFrom and b.baconFrom < b.baconTo, true, "he strolls in after the drop")
	t.expectEq(b.baconSit, b.baconTo, "and sits where he stops")
	t.expectEq(b.strawIn > b.baconSit and b.sip > b.strawIn, true, "the straw goes in, then he leans in")
	t.expectEq(b.getUp > b.strawIn and b.getUp - b.sip < 0.5, true, "you get up right before he drinks")
	local lain, sat, stood = EndCut.getUpTimes(IntroClips.turnSeconds)
	t.expectEq(b.getUp < lain and lain < sat and sat < stood, true, "getting up runs in order")
	t.expectEq(stood <= b.marchFrom, true, `standing by the march ({stood} <= {b.marchFrom})`)
	t.expectEq(b.marchTo, b.slap, "the slap comes as you reach him")
	t.expectNear(b.hit - b.slap, IntroClips.slapHit, 1e-9, "the hit is the slap clip's")
	t.expectEq(b.wide > b.hit, true)
end

-- The smack is heard and felt on the hit.
function tests.the_smack_lands_on_the_hit(t)
	local smack = nil
	for _, cue in EndCut.sounds do
		if cue.sound == "EndSmack" then
			smack = cue
		end
	end
	t.expectEq(smack ~= nil, true, "a smack")
	t.expectNear(smack.t, EndCut.beats.hit, 1e-9, "on the hit")
	t.expectEq(smack.stop == nil and smack.fade == nil, true, "played out whole")
	t.expectNear(EndCut.shakes[1].at, EndCut.beats.hit, 1e-9, "the picture shakes on it")
end

-- Real gravity: he leaves the close shot at once, rises and comes down into the sea far out, out of
-- sight long before the cut ends.
function tests.he_flies_off_over_the_sea(t)
	local quick = EndCut.flown(0.15, GRAVITY)
	t.expectEq(math.sqrt(quick[1] ^ 2 + quick[2] ^ 2 + quick[3] ^ 2) > 30, true, "out of the close shot in a moment")
	local water = EndCut.places.water[2]
	local seat = EndCut.places.baconTo
	local landed = nil
	for tau = 0.05, 6, 0.01 do
		local off = EndCut.flown(tau, GRAVITY)
		if seat[2] + 2.2 + off[2] < water then -- his middle, from the sand at his seat
			landed = { tau, off }
			break
		end
	end
	t.expectEq(landed ~= nil, true, "he comes down")
	local tau, off = landed[1], landed[2]
	t.expectEq(seat[3] + off[3] < -250, true, `far out at sea (z {seat[3] + off[3]})`)
	t.expectEq(EndCut.beats.hit + tau < EndCut.beats.wide + 4, true, "into the sea while the view rises over it")
	local up = EndCut.flown(0.5, GRAVITY)
	local rise = EndCut.launch.speed * math.sin(math.rad(EndCut.launch.up))
	t.expectNear(up[2], rise * 0.5 - GRAVITY * 0.125, 1e-9, "the game's gravity")
end

-- It ends on black with the logo, the music gone.
function tests.it_ends_on_black_with_the_logo(t)
	local last = EndCut.length - 0.01
	t.expectEq(IntroCut.value(EndCut.black, EndCut.beats.drop - 0.01), 1, "black before the drop")
	t.expectEq(IntroCut.value(EndCut.black, EndCut.beats.drop), 0, "the picture on the drop")
	t.expectEq(IntroCut.value(EndCut.black, last), 1, "black at the end")
	t.expectEq(IntroCut.value(EndCut.logoAlpha, last), 1, "the logo")
	t.expectEq(IntroCut.value(EndCut.music, last) < 0.05, true, "the music gone")
	t.expectEq(EndCut.handover, nil, "no handover: the lobby takes over")
end

-- Getting up plays the lie-down (IntroClips.lie) backwards through its own moments: lain back with
-- the head straight, watching him, and the stand facing the sea just before it turns round.
function tests.getting_up_runs_the_lie_down_backwards(t)
	local anatomy = Anatomy.classify(Rig.build(Templates.R15()))
	local places = IntroCut.places
	local root = { places.walkTo[1], 2.22 - anatomy.rig.ground, places.walkTo[3] }
	local stand, lie = IntroClips.lie(anatomy, IntroClips.seat(places.cushion, places.recline, root), IntroClips.watch(EndCut.places.baconFrom, EndCut.places.baconTo, root))
	local g = EndCut.getUp
	local function keyAt(keys, at: number)
		for _, key in keys do
			if math.abs(key.t - at) < 1e-6 then
				return key
			end
		end
		return nil
	end
	local lain = keyAt(lie.tracks.hips, g.lain)
	t.expectEq(lain ~= nil and lain.rot[1] >= places.recline, true, "lain back at `lain`")
	t.expectEq(keyAt(lie.tracks.head, g.watched) ~= nil, true, "still watching at `watched`")
	for _, key in stand.tracks.hips do
		if key.t <= g.turnFrom then
			t.expectEq(math.abs(key.rot[2]) < 1e-6, true, `facing the sea until \`turnFrom\` (at {key.t})`)
		end
	end
	t.expectNear(stand.tracks.hips[#stand.tracks.hips].rot[2], 90, 1e-6, "turned round by the stand's end")
	t.expectEq(stand.length, IntroClips.turnSeconds)
end

return tests
