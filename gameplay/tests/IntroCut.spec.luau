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

-- Story.BaconFat's belly (92 studs) and Workspace.Gravity, as the client bakes it.
local RADIUS, GRAVITY = 46, 196.2
local ROLL_SOUND = 2.3 -- Audio.IntroRoll's length, seconds

local function distance(a: { number }, x: number, y: number, z: number): number
	return math.sqrt((x - a[1]) ^ 2 + (y - a[2]) ^ 2 + (z - a[3]) ^ 2)
end

-- When the shore first lets go of him.
local function liftOff(flight): number
	for _, sample in flight.samples do
		local _, y, z = IntroCut.ballAt(flight, sample[1])
		if y > IntroCut.rideHeight(z, RADIUS) + 0.05 then
			return sample[1]
		end
	end
	error("he never leaves the shore")
end

-- A ball resting on the shore touches it and never sinks into it: flat seabed, the slope, flat sand.
function tests.the_ball_rests_on_the_shore(t)
	local shore = IntroCut.places.shore
	t.expectNear(IntroCut.rideHeight(-400, RADIUS), shore[1][2] + RADIUS, 1e-9, "on the seabed")
	t.expectNear(IntroCut.rideHeight(100, RADIUS), shore[#shore][2] + RADIUS, 1e-9, "on the sand")
	for z = -200, 0, 0.5 do
		local y = IntroCut.rideHeight(z, RADIUS)
		local nearest = math.huge
		for i = 1, #shore - 1 do
			local az, ay, bz, by = shore[i][1], shore[i][2], shore[i + 1][1], shore[i + 1][2]
			local u = math.clamp(((z - az) * (bz - az) + (y - ay) * (by - ay)) / ((bz - az) ^ 2 + (by - ay) ^ 2), 0, 1)
			nearest = math.min(nearest, math.sqrt((z - az - u * (bz - az)) ^ 2 + (y - ay - u * (by - ay)) ^ 2))
		end
		if z <= shore[1][1] then
			nearest = math.min(nearest, y - shore[1][2]) -- the flat seabed
		end
		if z >= shore[#shore][1] then
			nearest = math.min(nearest, y - shore[#shore][2]) -- the flat sand
		end
		t.expectEq(nearest >= RADIUS - 1e-6, true, `clear of the shore at z {z}`)
		t.expectNear(nearest, RADIUS, 1e-6, `touching it at z {z}`)
	end
end

-- He starts where he drank, still, and gathers speed all the way to the shore.
function tests.he_rolls_for_the_beach_gathering_speed(t)
	local b = IntroCut.beats
	local flight = IntroCut.flight(RADIUS, GRAVITY)
	local fat = IntroCut.places.fat
	local x, y, z, turned = IntroCut.ballAt(flight, b.roll)
	t.expectNear(distance({ fat[1], fat[2] + RADIUS, fat[3] }, x, y, z), 0, 1e-9, "starts where he drank")
	t.expectEq(turned, 0)
	local lastAt, lastSpeed = { x, y, z }, 0
	for at = b.roll + 0.05, b.rollEnd, 0.05 do
		local x2, y2, z2, turned2 = IntroCut.ballAt(flight, at)
		local speed = distance(lastAt, x2, y2, z2) / 0.05
		t.expectEq(speed >= lastSpeed, true, `faster and faster at {at}`)
		t.expectNear(turned2, (z2 - z) / flight.hz / RADIUS, 1e-6, `rolls without slipping at {at}`)
		t.expectNear(y2, y, 1e-9, "along the seabed")
		lastAt, lastSpeed = { x2, y2, z2 }, speed
	end
	t.expectEq(lastSpeed > 400, true, "at speed when the shore lifts him")
end

-- From the shore on it is physics: energy never grows, he leaves it going up, and he never sinks
-- into it.
function tests.the_shore_throws_him(t)
	local b = IntroCut.beats
	local flight = IntroCut.flight(RADIUS, GRAVITY)
	local start = 0.7 * flight.speed ^ 2 + GRAVITY * flight.seabed -- rolling: 1/2 v^2 + 1/5 v^2 (spin)
	local last = flight.samples[#flight.samples]
	local free = 0.5 * (flight.vs ^ 2 + flight.vy ^ 2) + 0.2 * (RADIUS * flight.spin) ^ 2 + GRAVITY * last[3]
	t.expectEq(free <= start + 1e-6, true, "energy never grows after the run-up")
	t.expectEq(free > 0.5 * start, true, "and most of it is kept")
	local angle = math.deg(math.atan2(flight.vy, flight.vs))
	t.expectEq(angle > 20 and angle < 50, true, `thrown up like off a ramp ({angle} degrees)`)
	local lift = liftOff(flight)
	t.expectEq(lift > b.rollEnd and lift < b.rollEnd + 0.3, true, "the shore throws him as he hits it")
	for at = b.roll, b.back, 0.01 do
		local _, y, z = IntroCut.ballAt(flight, at)
		t.expectEq(y >= IntroCut.rideHeight(z, RADIUS) - 0.01, true, `never into the shore at {at}`)
	end
end

-- He flies past you on your left, clear of you and the umbrella, and is far off and still high
-- over the island when you get up.
function tests.he_flies_past_you_and_off_into_the_distance(t)
	local b, places = IntroCut.beats, IntroCut.places
	local flight = IntroCut.flight(RADIUS, GRAVITY)
	local closest, closestX = math.huge, 0
	for at = b.roll, b.back, 0.01 do
		local x, y, z = IntroCut.ballAt(flight, at)
		local d = distance(places.eye, x, y, z)
		if d < closest then
			closest, closestX = d, x
		end
	end
	t.expectEq(closest - RADIUS > 50, true, `well clear of you ({closest - RADIUS} studs)`)
	t.expectEq(closestX < places.eye[1] - 80, true, "on your left")
	local x, y, z = IntroCut.ballAt(flight, b.back)
	t.expectEq(distance(places.lean, x, y, z) > 700, true, "far off when you get up")
	t.expectEq(y - RADIUS > 150, true, "and still in the air, high over the island")
end

-- The camera's view at `t` in the wake shot: where it is and its zoom (tan of half the field of view).
local function view(t: number): ({ number }, number)
	local a, c, alpha = IntroCut.segment((IntroCut.shot(t) :: any).keys, t)
	local function place(key): { number }
		return if key.at == "eye" then IntroCut.places.eye else key.at
	end
	local pa, pc = place(a), place(c)
	local at = {}
	for i = 1, 3 do
		at[i] = pa[i] + (pc[i] - pa[i]) * alpha
	end
	local ta, tc = math.tan(math.rad(a.fov) / 2), math.tan(math.rad(c.fov) / 2)
	return at, ta + (tc - ta) * alpha
end

-- While the camera follows him he is whole in the frame, and big enough to read.
function tests.the_camera_keeps_him_in_the_frame(t)
	local b = IntroCut.beats
	local flight = IntroCut.flight(RADIUS, GRAVITY)
	local followFrom = nil
	for _, key in (IntroCut.shot(b.roll) :: any).keys do
		if key.look == "fat" and not followFrom then
			followFrom = key.t
		end
	end
	t.expectEq(followFrom ~= nil and followFrom < b.rollEnd - 1, true, "on him well before the shore")
	for at = followFrom :: number, b.back, 0.01 do
		local camera, half = view(at)
		local x, y, z = IntroCut.ballAt(flight, at)
		local share = math.tan(math.asin(RADIUS / distance(camera, x, y, z))) / half -- of the frame's half-height
		t.expectEq(share < 0.8, true, `whole in the frame at {at} ({share})`)
		t.expectEq(share > 0.12, true, `big enough to read at {at} ({share})`)
	end
end

-- Getting up, the view turns back to the sea the way it came: he is never so far round that the
-- short way back would be the other way.
function tests.the_view_turns_back_the_way_it_came(t)
	local b, places = IntroCut.beats, IntroCut.places
	local flight = IntroCut.flight(RADIUS, GRAVITY)
	local x, _, z = IntroCut.ballAt(flight, b.back)
	local function yaw(dx: number, dz: number): number -- degrees to the left of looking out to sea
		return math.deg(math.atan2(-dx, -dz))
	end
	local round = yaw(x - places.lean[1], z - places.lean[3]) - yaw(places.standLook[1], places.standLook[3])
	t.expectEq(round > 90 and round < 170, true, `back to the sea the way it came ({round} degrees)`)
	local backKey = nil
	for _, key in (IntroCut.shot(b.back) :: any).keys do
		if key.t == b.back then
			backKey = key
		end
	end
	t.expectEq(backKey and backKey.look, "fat", "still on him as you get up")
end

-- The roll is heard until the shore throws him, the whoosh as he flies past.
function tests.the_sounds_follow_him(t)
	local flight = IntroCut.flight(RADIUS, GRAVITY)
	local lift = liftOff(flight)
	local roll, whoosh = nil, nil
	for _, cue in IntroCut.sounds do
		if cue.sound == "IntroRoll" then
			roll = cue
		elseif cue.sound == "IntroWhoosh" and cue.t > IntroCut.beats.rollEnd and cue.t < IntroCut.beats.back then
			whoosh = cue
		end
	end
	t.expectEq(roll.t >= IntroCut.beats.roll, true, "not before he moves")
	t.expectNear(roll.t + ROLL_SOUND, lift, 0.1, "the roll plays out as the shore throws him")
	local closest, closestAt = math.huge, 0
	for at = IntroCut.beats.rollEnd, IntroCut.beats.back, 0.01 do
		local x, y, z = IntroCut.ballAt(flight, at)
		local d = distance(IntroCut.places.eye, x, y, z)
		if d < closest then
			closest, closestAt = d, at
		end
	end
	t.expectNear(whoosh.t, closestAt, 0.1, "the whoosh as he passes")
end

return tests
