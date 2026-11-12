local IntroCut = require("../src/shared/IntroCut")

local tests = {}

local function sorted(keys: { any }, label: string, t)
	for i = 2, #keys do
		t.expectEq(keys[i].t >= keys[i - 1].t, true, `{label}: key {i} comes after key {i - 1}`)
	end
end

function tests.tracks_are_in_order_and_inside_the_cut(t)
	for _, name in { "lids", "blur", "black", "logoAlpha", "logoScale", "music" } do
		local keys = IntroCut[name]
		sorted(keys, name, t)
		t.expectEq(keys[#keys].t <= IntroCut.length, true, `{name} ends inside the cut`)
	end
	for i, shot in IntroCut.shots do
		sorted(shot.keys, shot.name, t)
		t.expectEq(shot.keys[1].t, shot.at, `{shot.name} keys start with the shot`)
		local nextAt = if IntroCut.shots[i + 1] then IntroCut.shots[i + 1].at else IntroCut.length
		t.expectEq(shot.keys[#shot.keys].t <= nextAt, true, `{shot.name} ends by the next shot`)
		if i > 1 then
			t.expectEq(shot.at > IntroCut.shots[i - 1].at, true, `{shot.name} after the shot before`)
		end
	end
	for _, cue in IntroCut.sounds do
		t.expectEq(cue.t >= 0 and cue.t < IntroCut.length, true, `{cue.sound} plays inside the cut`)
		t.expectEq(cue.sound:sub(1, 5), "Intro", `{cue.sound}: the intro's sounds are Audio.Intro*`)
		t.expectEq(cue.volume > 0 and cue.volume <= 1, true, `{cue.sound}'s volume`)
	end
end

-- The picture comes in on the music's drop, the logo with it; the screen is black before.
function tests.opens_on_the_drop(t)
	local drop = IntroCut.beats.drop
	t.expectEq(IntroCut.value(IntroCut.black, drop - 0.01), 1, "black before the drop")
	t.expectEq(IntroCut.value(IntroCut.black, drop), 0, "the picture on the drop")
	t.expectEq((IntroCut.shot(drop) :: any).name, "drone")
	t.expectEq(IntroCut.shot(drop - 0.01), nil)
	t.expectEq(IntroCut.value(IntroCut.logoAlpha, drop + 0.5), 1, "the logo shows")
	t.expectEq(IntroCut.value(IntroCut.logoAlpha, IntroCut.beats.walk), 0, "gone by the walk")
end

-- Nobody sees the world change: the eyes are shut from before the swap until waking.
function tests.eyes_are_shut_over_the_swap(t)
	local b = IntroCut.beats
	t.expectEq(IntroCut.value(IntroCut.lids, b.pov), 0, "open as your eyes take over")
	for at = b.swap - 0.25, b.wake, 0.05 do
		t.expectEq(IntroCut.value(IntroCut.lids, at), 1, `shut at {at}`)
	end
	t.expectEq(IntroCut.value(IntroCut.lids, b.drink), 0, "awake for the drink")
	t.expectEq(IntroCut.value(IntroCut.blur, b.drink), 0, "and sharp")
	t.expectEq(IntroCut.value(IntroCut.music, b.swap + 0.3), 0, "the music is gone in the dark")
end

-- The far slurp plays in the dark; the shot that wakes you goes to him without a cut.
function tests.the_drink_is_heard_then_seen_without_a_cut(t)
	local b = IntroCut.beats
	local far = nil
	for _, cue in IntroCut.sounds do
		if cue.sound == "IntroSlurpFar" then
			far = cue
		end
	end
	t.expectEq(far ~= nil, true, "a far slurp")
	t.expectEq(far.t > b.swap and far.t < b.wake, true, "in the dark")
	local shot = IntroCut.shot(b.wake) :: any
	t.expectEq(shot, IntroCut.shot(b.rollEnd), "one shot from waking until he has rolled off")
	t.expectEq(shot, IntroCut.shot(b.drink))
end

function tests.skip_comes_in_early(t)
	t.expectEq(IntroCut.skipAfter > 0 and IntroCut.skipAfter < IntroCut.beats.walk, true)
end

function tests.values_ease_between_keys(t)
	local keys = { { t = 0, v = 0 }, { t = 1, v = 10 }, { t = 2, v = 10 }, { t = 3, v = 0, ease = "step" } }
	t.expectEq(IntroCut.value(keys, -1), 0, "before the first key")
	t.expectNear(IntroCut.value(keys, 0.5), 5, 1e-9, "inOut is halfway at half time")
	t.expectEq(IntroCut.value(keys, 0.25) < 2.5, true, "inOut starts slow")
	t.expectEq(IntroCut.value(keys, 2.99), 10, "a step holds")
	t.expectEq(IntroCut.value(keys, 3), 0, "and jumps on its key")
	t.expectEq(IntroCut.value(keys, 9), 0, "after the last key")
	t.expectNear(IntroCut.eased("out", 0.5), math.sin(math.pi / 4), 1e-9)
	t.expectEq(IntroCut.eased("linear", 0.3), 0.3)
end

function tests.the_walk_puddle_and_roll_run_zero_to_one(t)
	local b = IntroCut.beats
	t.expectEq(IntroCut.walked(b.walkFrom - 1), 0)
	t.expectEq(IntroCut.walked(b.walkTo + 1), 1)
	t.expectEq(IntroCut.puddleLeft(b.drink), 1)
	t.expectEq(IntroCut.puddleLeft(b.drunk), 0)
	t.expectEq(IntroCut.rolled(b.roll), 0)
	t.expectNear(IntroCut.rolled(b.rollEnd), 1, 1e-9)
	local last = 0
	for at = b.roll, b.rollEnd, 0.1 do
		local r = IntroCut.rolled(at)
		t.expectEq(r >= last, true, "never rolls back")
		last = r
	end
end

return tests
