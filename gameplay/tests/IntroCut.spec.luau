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
	t.expectEq((IntroCut.shot(drop) :: any).name, "take")
	t.expectEq(IntroCut.shot(drop - 0.01), nil)
	t.expectEq(IntroCut.value(IntroCut.logoAlpha, drop + 0.5), 1, "the logo shows")
	t.expectEq(IntroCut.value(IntroCut.logoAlpha, IntroCut.beats.walkTo), 0, "gone before the lounger")
end

-- No cut while your eyes are open: one smooth take from the drop until they shut, into your own
-- eyes; the next shot starts in the dark.
function tests.one_take_until_the_eyes_shut(t)
	local b = IntroCut.beats
	local take = IntroCut.shot(b.drop) :: any
	t.expectEq(take.spline, true, "a smooth path through its keys")
	t.expectEq(IntroCut.shot(b.swap - 0.01), take, "the same take until the swap")
	t.expectEq(take.keys[#take.keys].at, "eye", "ends in your eyes")
	t.expectEq(IntroCut.value(IntroCut.lids, b.swap), 1, "the next shot starts in the dark")
end

-- Nobody sees the world change: the eyes are shut from before the swap until waking.
function tests.eyes_are_shut_over_the_swap(t)
	local b = IntroCut.beats
	t.expectEq(IntroCut.value(IntroCut.lids, b.pov), 0, "open as the camera reaches your eyes")
	for at = b.swap - 0.25, b.wake, 0.05 do
		t.expectEq(IntroCut.value(IntroCut.lids, at), 1, `shut at {at}`)
	end
	t.expectEq(IntroCut.value(IntroCut.lids, b.drink), 0, "awake for the drink")
	t.expectEq(IntroCut.value(IntroCut.blur, b.drink), 0, "and sharp")
	t.expectEq(IntroCut.value(IntroCut.music, b.swap + 0.3), 0, "the music is gone in the dark")
end

-- The far slurp plays in the dark; the shot that wakes you goes to him without a cut, and ends
-- where the game's camera takes over.
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
	local last = shot.keys[#shot.keys]
	t.expectEq(last.at, "stand", "ends in your eyes where play starts")
	t.expectEq(last.t, IntroCut.handover, "as the game's camera takes over")
	t.expectEq(last.fov, 70, "at the game's field of view")
	t.expectEq(IntroCut.handover < IntroCut.length, true, "a moment of the game's own view before play")
end

-- The burp plays out whole: nothing stops or fades it, and he only rolls off once it has
-- (IntroBurp is 2.5 s long).
function tests.the_burp_plays_out(t)
	local burp = nil
	for _, cue in IntroCut.sounds do
		if cue.sound == "IntroBurp" then
			burp = cue
		end
	end
	t.expectEq(burp.stop, nil, "never stopped")
	t.expectEq(burp.fade, nil, "never faded")
	t.expectEq(burp.t, IntroCut.beats.burp)
	t.expectEq(IntroCut.beats.roll - burp.t >= 2.6, true, "he rolls after it")
end

function tests.skip_comes_in_early(t)
	t.expectEq(IntroCut.skipAfter > 0 and IntroCut.skipAfter < IntroCut.beats.walkFrom, true)
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

-- The spline passes through every key, its weights always sum to 1, and it moves without jumps.
function tests.the_spline_runs_smoothly_through_the_keys(t)
	local keys = { { t = 0, v = 0 }, { t = 1, v = 4 }, { t = 3, v = 5 }, { t = 4, v = 1 } }
	local function at(time: number): number
		local sum, total = 0, 0
		for _, pair in IntroCut.spline(keys, time) do
			sum += keys[pair[1]].v * pair[2]
			total += pair[2]
		end
		t.expectNear(total, 1, 1e-9, `weights sum to 1 at {time}`)
		return sum
	end
	for _, key in keys do
		t.expectNear(at(key.t), key.v, 1e-9, `through the key at {key.t}`)
	end
	local last = at(0)
	for time = 0.01, 4, 0.01 do
		local now = at(time)
		t.expectEq(math.abs(now - last) < 0.1, true, `no jump at {time}`)
		last = now
	end
	t.expectNear(at(0.01) - at(0), 0, 0.01, "still at the first key")
end

function tests.walks_puddle_and_roll_run_zero_to_one(t)
	local b = IntroCut.beats
	t.expectEq(IntroCut.walked(b.walkFrom - 1, b.walkFrom, b.walkTo), 0)
	t.expectNear(IntroCut.walked(b.walkTo, b.walkFrom, b.walkTo), 1, 1e-9)
	t.expectNear(IntroCut.walked(b.walkTo + 1, b.walkFrom, b.walkTo), 1, 1e-9)
	local last, lastStep = 0, math.huge
	for at = b.walkTo - IntroCut.stopSeconds, b.walkTo, 0.05 do
		local w = IntroCut.walked(at, b.walkFrom, b.walkTo)
		t.expectEq(w >= last, true, "never walks back")
		t.expectEq(w - last <= lastStep + 1e-9, true, "slows into the stop")
		lastStep, last = w - last, w
	end
	t.expectEq(IntroCut.puddleLeft(b.drink), 1)
	t.expectEq(IntroCut.puddleLeft(b.drunk), 0)
	t.expectEq(IntroCut.rolled(b.roll), 0)
	t.expectNear(IntroCut.rolled(b.rollEnd), 1, 1e-9)
	local rolled = 0
	for at = b.roll, b.rollEnd, 0.1 do
		local r = IntroCut.rolled(at)
		t.expectEq(r >= rolled, true, "never rolls back")
		rolled = r
	end
end

return tests
