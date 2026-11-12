--!strict
-- The intro's motion (client/Intro plays it with the roblox-animation runtime,
-- ReplicatedStorage.Animation), linted offline in Lune (tests/IntroClips.spec) until no [fix]
-- remains. Same format and house style as StaffClips: restraint, weight from the hips, uneven key
-- timing, no springs, no overshoot.
-- rot = { pitch, yaw, roll } in degrees: +pitch lifts a hanging limb forward and tips a body part
-- back, +yaw turns left, +roll swings the right arm or leg out (the left one in). A body part turns
-- about its own axes, under whatever its parent did; the hips turn about the character's.
-- Walks are Roblox's own animations on the copies' Animators (your avatar's walk, the classic R6
-- one for the bacon-hair): the same steps as in play. A walk animation matches the ground at
-- `pace` x the body's height scale studs a second (the default Animate script's numbers), so the
-- client plays it by the distance walked and the feet never slide.

local IntroClips = {}

IntroClips.walks = {
	-- your avatar's walk (its Animate script's walk.WalkAnim; this default without one)
	player = { default = "rbxassetid://913402848", pace = 16 * 0.5 / 1.25 },
	-- the bacon-hair's R6 walk
	bacon = { id = "rbxassetid://180426354", pace = 14.5 },
}

local function with(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

-- Tired, layered over your walk: the head a little down, the chest sagging.
IntroClips.slump = {
	name = "IntroSlump",
	length = 2.4,
	loop = true,
	-- a held posture layered on a walk: no strike, nothing to commit to
	waive = { "no-body-commitment" },
	tracks = {
		chest = {
			{ t = 0, rot = { -4, 0, 0 } },
			{ t = 1.3, rot = { -5, 0, 0 } },
			{ t = 2.4, rot = { -4, 0, 0 } },
		},
		head = {
			{ t = 0, rot = { -7, 0, 0 } },
			{ t = 1.1, rot = { -9, 0, 0 } },
			{ t = 2.4, rot = { -7, 0, 0 } },
		},
	},
	seed = "IntroSlump",
}

type V = { x: number, y: number, z: number }

local function v(x: number, y: number, z: number): { number }
	return { x, y, z }
end

-- The cushion (IntroCut.places.cushion, in the world) in the lie-down's frame: the root part at
-- `root` {x, y, z} when the walk stops, facing -Z, so the frame's axes are the world's.
function IntroClips.seat(cushion: any, recline: number, root: { number }): any
	return {
		edge = cushion.edge - root[1],
		centre = cushion.centre - root[1],
		top = cushion.top - root[2],
		hinge = cushion.hinge - root[3],
		recline = recline,
	}
end

-- Where the bacon-hair walks in from and sits (world places), in the same frame.
function IntroClips.watch(from: { number }, at: { number }, root: { number }): any
	return {
		from = v(from[1] - root[1], 0, from[3] - root[3]),
		at = v(at[1] - root[1], 0, at[3] - root[3]),
	}
end

-- IntroClips.lie's first clip (the stretch and the turn) is this long; its second goes on from here.
IntroClips.turnSeconds = 3.5

local RELAXED = { left = -22, right = -27 } -- degrees a foot off the ground points its toes, from the shin
local STEP = 0.1 -- seconds between the hand-solved keys while the body moves
local LIFT = 0.1 -- of the leg's reach: how high a stepping foot comes up

type M3 = { { number } }

-- Rx(pitch) * Ry(yaw) * Rz(roll) in degrees: a rot key as the runtime turns it (CFrame.Angles order).
local function rot(pitch: number, yaw: number, roll: number): M3
	local a, b, c = math.rad(pitch), math.rad(yaw), math.rad(roll)
	local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
	return {
		{ cb * cc, -cb * sc, sb },
		{ ca * sc + sa * sb * cc, ca * cc - sa * sb * sc, -sa * cb },
		{ sa * sc - ca * sb * cc, sa * cc + ca * sb * sc, ca * cb },
	}
end

-- A rotation back to rot's { pitch, yaw, roll }.
local function angles(m: M3): { number }
	local yaw = math.deg(math.asin(math.clamp(m[1][3], -1, 1)))
	return { math.deg(math.atan2(-m[2][3], m[3][3])), yaw, math.deg(math.atan2(-m[1][2], m[1][1])) }
end

local function mul(a: M3, b: M3): M3
	local out = {}
	for i = 1, 3 do
		out[i] = {}
		for j = 1, 3 do
			out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return out
end

local function transpose(m: M3): M3
	return { { m[1][1], m[2][1], m[3][1] }, { m[1][2], m[2][2], m[3][2] }, { m[1][3], m[2][3], m[3][3] } }
end

local function apply(m: M3, p: { number }): { number }
	return {
		m[1][1] * p[1] + m[1][2] * p[2] + m[1][3] * p[3],
		m[2][1] * p[1] + m[2][2] * p[2] + m[2][3] * p[3],
		m[3][1] * p[1] + m[3][2] * p[2] + m[3][3] * p[3],
	}
end

local function add(a: { number }, b: { number }): { number }
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end
local function sub(a: { number }, b: { number }): { number }
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function scale(a: { number }, k: number): { number }
	return { a[1] * k, a[2] * k, a[3] * k }
end
local function dot(a: { number }, b: { number }): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
local function cross(a: { number }, b: { number }): { number }
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function len(a: { number }): number
	return math.sqrt(dot(a, a))
end
local function unit(a: { number }): { number }
	local l = len(a)
	return if l > 1e-9 then scale(a, 1 / l) else { 0, 0, 0 }
end
local function lerp(a: { number }, b: { number }, u: number): { number }
	return { a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u }
end
local function arr(p: V): { number }
	return { p.x, p.y, p.z }
end

-- A quaternion {x, y, z, w} as a rotation.
local function fromQ(q: any): M3
	local x, y, z, w = q.x, q.y, q.z, q.w
	return {
		{ 1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y) },
		{ 2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x) },
		{ 2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y) },
	}
end

-- The rotation from a bone at rest (hanging along `bone0`, its knee hinge along +X) to the bone along
-- `bone` with its hinge along `hinge`.
local function align(hinge: { number }, bone: { number }, bone0: { number }): M3
	local function frame(x: { number }, b: { number }): M3
		local up = scale(b, -1)
		local y = unit(sub(up, scale(x, dot(up, x))))
		local z = cross(x, y)
		return { { x[1], y[1], z[1] }, { x[2], y[2], z[2] }, { x[3], y[3], z[3] } }
	end
	return mul(frame(hinge, bone), transpose(frame({ 1, 0, 0 }, bone0)))
end

-- A leg to pose by hand (hip, knee and ankle: every R15 leg, whichever way the runtime reads its
-- foot), at rest in the clips' frame: the bones, the sole's contact from the ankle and the foot
-- part's corners from the ankle. Nil for any other leg.
local function legOf(rig: any, leg: any): any
	local m = leg.movable
	if #m ~= 3 then
		return nil
	end
	local hip, knee, ankle = arr(rig.joints[m[1]].world.p), arr(rig.joints[m[2]].world.p), arr(rig.joints[m[3]].world.p)
	local foot = rig.joints[m[3]]
	local sole = sub(arr(leg.contact), ankle)
	local corners = { sole }
	if foot.size then
		local turn = fromQ(foot.world.q)
		local centre = if foot.center then arr(foot.center.p) else { 0, 0, 0 }
		local centreTurn = if foot.center then fromQ(foot.center.q) else rot(0, 0, 0)
		corners = {}
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = { sx * foot.size.x / 2, sy * foot.size.y / 2, sz * foot.size.z / 2 }
					table.insert(corners, apply(turn, add(centre, apply(centreTurn, corner))))
				end
			end
		end
	end
	local drop = 0
	for _, c in corners do
		drop = math.max(drop, -c[2])
	end
	return {
		hip = hip,
		a = len(sub(knee, hip)),
		b = len(sub(ankle, knee)),
		thigh0 = unit(sub(knee, hip)),
		shin0 = unit(sub(ankle, knee)),
		sole = sole,
		corners = corners,
		drop = drop, -- how far the foot reaches below the ankle at rest
	}
end

-- The thigh's and shin's turns (from rest, in the hips' frame) that put the ankle at `ankle`, the
-- knee bending about `side` (the foot's right: toward its toes, and up when the leg points ahead).
local function solveLeg(g: any, ankle: { number }, side: { number }): (M3, M3)
	local d = sub(ankle, g.hip)
	local dist = math.clamp(len(d), math.abs(g.a - g.b) + 1e-3, (g.a + g.b) * 0.999)
	local along = unit(d)
	local toward = cross(side, along)
	if len(toward) < 1e-3 then
		toward = cross({ 1, 0, 0 }, along)
	end
	toward = unit(toward)
	local cosHip = math.clamp((g.a * g.a + dist * dist - g.b * g.b) / (2 * g.a * dist), -1, 1)
	local knee = add(g.hip, scale(add(scale(along, cosHip), scale(toward, math.sqrt(1 - cosHip * cosHip))), g.a))
	local foot = add(g.hip, scale(along, dist))
	local hinge = unit(cross(along, toward))
	return align(hinge, unit(sub(knee, g.hip)), g.thigh0), align(hinge, unit(sub(foot, knee)), g.shin0)
end

-- A leg that can't bend (R6: one part swinging at the hip), at rest in the clips' frame: its hip, its
-- length and way down to the foot's contact, and half its thickness. Nil for any other leg.
local function stickOf(rig: any, leg: any): any
	if not leg.rigid or #leg.movable ~= 1 then
		return nil
	end
	local joint = rig.joints[leg.movable[1]]
	local hip = arr(joint.world.p)
	local down = sub(arr(leg.contact), hip)
	return { hip = hip, length = len(down), bone0 = unit(down), half = if joint.size then math.min(joint.size.x, joint.size.z) / 2 else 0 }
end

-- A stick's turn (from rest, in the hips' frame) toward `target`. Nearer than its length it can't
-- reach down to it without digging in, so its foot swings ahead instead and rests on the level
-- through the target (`up`: the world's up as the hips see it), its lower edge on it.
local function swingStick(k: any, target: { number }, up: { number }, side: { number }): M3
	local d = sub(target, k.hip)
	local along = unit(d)
	if len(d) < k.length then
		local flat = sub(d, scale(up, dot(d, up)))
		if len(flat) < 1e-6 then
			flat = sub({ 0, 0, -1 }, scale(up, -up[3]))
		end
		local ahead = unit(flat)
		local height = -dot(d, up) -- the hip over the level
		local s = len(flat) / len(d)
		for _ = 1, 4 do
			local c = math.clamp((k.half * s - height) / k.length, -1, 1)
			s = math.sqrt(1 - c * c)
			along = add(scale(up, c), scale(ahead, s))
		end
	end
	-- align keeps the hinge square to the bone: square it to the way the leg points first
	return align(unit(sub(side, scale(along, dot(side, along)))), along, k.bone0)
end

-- A monotone cubic through the keys (the runtime's own kind of curve), still at both ends.
local function spline(ts: { number }, ys: { number }): (number) -> number
	local n = #ts
	local slopes, m = {}, {}
	for i = 1, n - 1 do
		slopes[i] = (ys[i + 1] - ys[i]) / (ts[i + 1] - ts[i])
	end
	m[1], m[n] = 0, 0
	for i = 2, n - 1 do
		if slopes[i - 1] * slopes[i] <= 0 then
			m[i] = 0
		else
			local h0, h1 = ts[i] - ts[i - 1], ts[i + 1] - ts[i]
			local w1, w2 = 2 * h1 + h0, h1 + 2 * h0
			m[i] = (w1 + w2) / (w1 / slopes[i - 1] + w2 / slopes[i])
		end
	end
	return function(t: number): number
		if t <= ts[1] then
			return ys[1]
		elseif t >= ts[n] then
			return ys[n]
		end
		local i = 1
		while ts[i + 1] < t do
			i += 1
		end
		local h = ts[i + 1] - ts[i]
		local s = (t - ts[i]) / h
		local s2, s3 = s * s, s * s * s
		return (2 * s3 - 3 * s2 + 1) * ys[i] + (s3 - 2 * s2 + s) * h * m[i] + (-2 * s3 + 3 * s2) * ys[i + 1] + (s3 - s2) * h * m[i + 1]
	end
end

-- The lie-down's moving body, solved by hand: hips keys, and each leg's thigh, shin and foot, every
-- STEP seconds until `dense` (then at the hips' later keys), so planted feet stay flat where they are
-- while the hips turn, sit and lie. `hips`: keys { t, pos, rot } (the hips' moves, through which a
-- spline runs). `feet[side]`: the foot's keys, each `on` a point of the sand facing `yaw` (planted
-- flat; between two on the same point it pivots there, between two apart it steps), or with its
-- `ankle` at a point, its `heel` resting on a point (off the ground, the toes relaxed), or `tuck`ed:
-- the ankle `tuck[1]` of the leg's length in front of the hip and as high over it as the foot hangs
-- plus `tuck[2]` of the reach, so the foot clears a seat the hips sit on (lifted with the hips). Off
-- the ground a foot moves with the hips: it goes from one key to the next as the hips see them. A
-- leg that can't bend (R6) swings whole at the hip (swingStick).
local function solved(anatomy: any, hips: { any }, feet: { [string]: { any } }, dense: number): { [string]: any }
	local rig = anatomy.rig
	local pivot = arr(rig.joints[anatomy.body].world.p)
	local times = {}
	for _, key in hips do
		table.insert(times, key.t)
	end
	local curves = {}
	for c = 1, 3 do
		local ps, rs = {}, {}
		for _, key in hips do
			table.insert(ps, key.pos[c])
			table.insert(rs, key.rot[c])
		end
		curves[c] = spline(times, ps)
		curves[c + 3] = spline(times, rs)
	end
	local function hipsAt(t: number): ({ number }, { number })
		return { curves[1](t), curves[2](t), curves[3](t) }, { curves[4](t), curves[5](t), curves[6](t) }
	end
	-- a point of the clips' frame where the hips see it at rest, and the hips' turn
	local function hipsFrame(t: number): ((p: { number }) -> { number }, M3)
		local pos, r = hipsAt(t)
		local turn = rot(r[1], r[2], r[3])
		local back = transpose(turn)
		return function(p: { number }): { number }
			return add(pivot, apply(back, sub(sub(p, pivot), pos)))
		end, turn
	end

	local L = 0
	local legs = {}
	local step = STEP
	for _, leg in anatomy.legs do
		local side = if leg.side < 0 then "left" elseif leg.side > 0 then "right" else nil
		if side and feet[side] then
			L += leg.reach / 2
			legs[side] = { leg = leg, g = legOf(rig, leg), stick = stickOf(rig, leg) }
			if legs[side].stick then
				step = STEP / 3 -- a straight leg swings far for a small move of the hips: keyed closer
			end
		end
	end

	-- the knee's hinge in the hips' frame: a planted foot's right (facing `yaw`), else the hips' right
	local function sideOf(back: M3, yaw: number, off: number): { number }
		local right = apply(back, { math.cos(math.rad(yaw)), 0, -math.sin(math.rad(yaw)) })
		return unit(lerp(right, { 1, 0, 0 }, off))
	end

	-- each foot key's ankle: planted, from the sole; resting a heel, as high as the foot's lowest
	-- corner sits on the point, with the toes relaxed; tucked, where the bent leg puts it. Each also
	-- as the hips see it at the key (`held`).
	for side, l in legs do
		local g = l.g
		for _, key in feet[side] do
			if key.on then
				key.ankle = if g then sub(key.on, apply(rot(0, key.yaw, 0), g.sole)) else key.on
			elseif key.heel then
				key.ankle = if g then { key.heel[1], key.heel[2] + g.drop, key.heel[3] } else key.heel
				if g then
					for _ = 1, 3 do
						local inHips, turn = hipsFrame(key.t)
						local _, shin = solveLeg(g, inHips(key.ankle), sideOf(transpose(turn), 0, 1))
						local footTurn = mul(turn, mul(shin, rot(RELAXED[side], 0, 0)))
						local low = math.huge
						for _, c in g.corners do
							low = math.min(low, apply(footTurn, c)[2])
						end
						key.ankle = { key.heel[1], key.heel[2] - low + 0.005 * L, key.heel[3] }
					end
				end
			end
			local inHips = hipsFrame(key.t)
			if key.tuck and l.stick then
				local k = l.stick -- held out straight, its underside clear of the seat
				key.held = add(k.hip, { 0, key.tuck[2] * L + k.half, -key.tuck[1] * k.length })
			elseif key.tuck then
				assert(g, "a tucked foot needs a hip, knee and ankle, or a leg that can't bend")
				key.held = add(g.hip, { 0, g.drop + key.tuck[2] * L, -key.tuck[1] * (g.a + g.b) })
			else
				key.held = inHips(key.ankle)
			end
		end
	end

	-- where a foot is at `t`, as the hips see it then: its ankle, the way it faces while (partly)
	-- planted (nil: as the hips do, once it lifts), and how far off the ground it is (0 planted, 1 off)
	local function footAt(keys: { any }, g: any, t: number): ({ number }, number?, number)
		local inHips = hipsFrame(t)
		local function state(key: any): ({ number }, number?, number)
			if key.on then
				return inHips(key.ankle), key.yaw, 0
			end
			return key.held, nil, 1
		end
		if t <= keys[1].t then
			return state(keys[1])
		end
		for i = 2, #keys do
			local b = keys[i]
			if t < b.t then
				local a = keys[i - 1]
				local s = (t - a.t) / (b.t - a.t)
				local u = (1 - math.cos(math.pi * s)) / 2
				if a.on and b.on then
					local yaw = a.yaw + (b.yaw - a.yaw) * u
					local contact = lerp(a.on, b.on, u)
					if len(sub(b.on, a.on)) > 1e-6 then
						contact = add(contact, { 0, LIFT * L * math.sin(math.pi * s), 0 })
					end
					return inHips(sub(contact, apply(rot(0, yaw, 0), if g then g.sole else { 0, 0, 0 }))), yaw, 0
				end
				local offA, offB = if a.on then 0 else 1, if b.on then 0 else 1
				return lerp(a.held, b.held, u), nil, offA + (offB - offA) * u
			end
		end
		return state(keys[#keys])
	end

	local samples = {}
	for i = 0, math.floor(dense / step + 0.5) do
		table.insert(samples, i * step)
	end
	for _, key in hips do
		if key.t > dense + 1e-6 then
			table.insert(samples, key.t)
		end
	end
	if step ~= STEP then
		-- a straight leg swings as fast as the hips' height changes near standing: keyed at the hips'
		-- and the feet's own keys only (one side leads), the runtime's smooth curve carries it between
		samples = table.clone(times)
		for _, keys in feet do
			for _, key in keys do
				if not table.find(samples, key.t) then
					table.insert(samples, key.t)
				end
			end
		end
		table.sort(samples)
	end
	local tracks: { [string]: any } = { hips = {} }
	local function push(name: string, key: any)
		tracks[name] = tracks[name] or {}
		table.insert(tracks[name], key)
	end
	for _, t in samples do
		local pos, r = hipsAt(t)
		push("hips", { t = t, pos = pos, rot = r })
		local _, turn = hipsFrame(t)
		local back = transpose(turn)
		for side, l in legs do
			local ankle, faces, off = footAt(feet[side], l.g, t)
			if l.stick then
				local swung = swingStick(l.stick, ankle, apply(back, { 0, 1, 0 }), sideOf(back, faces or r[2], off))
				push(side .. "Leg", { t = t, rot = angles(swung) })
				continue
			elseif not l.g then
				push(side .. "Leg", { t = t, reach = ankle }) -- not hip, knee and ankle: the runtime reaches
				continue
			end
			local yaw = faces or r[2]
			local thigh, shin = solveLeg(l.g, ankle, sideOf(back, yaw, off))
			local flat = angles(mul(transpose(shin), mul(back, rot(0, yaw, 0))))
			local relaxed = { RELAXED[side], 0, 0 }
			push(side .. "Thigh", { t = t, rot = angles(thigh) })
			push(side .. "Shin", { t = t, rot = angles(mul(transpose(thigh), shin)) })
			push(side .. "Foot", { t = t, rot = lerp(flat, relaxed, off) })
		end
	end
	return tracks
end

-- Your lie-down on the lounger, built for this body (its anatomy, as the runtime reads it) and this
-- lounger, as two clips played one after the other:
-- - the stand: the stretch with a yawn, then stepping round to turn your back to the cushion
--   (IntroClips.turnSeconds long);
-- - the lie: sitting down on the cushion's edge, the legs up, lying back, watching the bacon-hair
--   and dozing off.
-- The hips and legs are solved by hand (`solved`): feet on the sand stay flat on it while the knees
-- bend and the hips turn, steps lift over a small arc, and lying down the heels rest on the cushion.
-- `seat` is the cushion in the clips' frame (studs from the root part, which stands beside it facing
-- -Z with the cushion to its right, +X): `edge` (the near edge's x), `centre` (its middle's x), `top`
-- (its height) and `hinge` (the z where the backrest rises), and `recline` (degrees the backrest
-- leans back). `watch` is where the bacon-hair walks in from and where he sits, in the same frame.
function IntroClips.lie(anatomy: any, seat: any, watch: any): (any, any)
	local rig = anatomy.rig
	local pivot: V = rig.joints[anatomy.body].world.p
	local left, right
	for _, leg in anatomy.legs do
		if leg.side < 0 then
			left = leg
		elseif leg.side > 0 then
			right = leg
		end
	end
	assert(left and right and anatomy.body, "the lie-down needs a body joint and two legs")
	local L = (left.reach + right.reach) / 2
	local ground = (left.contact.y + right.contact.y) / 2
	local hipY = (left.base.y + right.base.y) / 2
	local spread = (right.contact.x - left.contact.x) / 2
	local stick = stickOf(rig, left)
	-- what the hips sit on: half a thigh's thickness (a leg that can't bend: half the leg's)
	local thigh = if stick then stick.half else 0.12 * L
	local sitUp = pivot.y - hipY + thigh -- the pivot's height over a seat, sitting upright

	local function at(x: number, y: number, z: number): { number }
		return v(x - pivot.x, y - pivot.y, z - pivot.z) -- hips keys move the pivot
	end
	-- from a to b: `across` of the way in x and z, `down` of the way in y
	local function toward(a: { number }, b: { number }, across: number, down: number): { number }
		return v(a[1] + (b[1] - a[1]) * across, a[2] + (b[2] - a[2]) * down, a[3] + (b[3] - a[3]) * across)
	end

	-- standing: the feet where they are; turned round with the cushion behind you: in front of its
	-- edge, under the hips (the left a little ahead: nobody stands in a mirror), the knees soft, the
	-- heels clear of the lounger
	local fl, fr = v(left.contact.x, ground, left.contact.z), v(right.contact.x, ground, right.contact.z)
	local heelBack = 0
	for _, leg in { left, right } do
		local g = legOf(rig, leg)
		if g then
			for _, c in g.corners do
				heelBack = math.max(heelBack, apply(rot(0, 90, 0), sub(c, g.sole))[1])
			end
		end
	end
	local feetX = math.min(seat.edge - 0.3 * L, seat.edge - heelBack - 0.08 * L)
	local tl, tr = v(feetX - 0.06 * L, ground, spread * 1.05), v(feetX + 0.03 * L, ground, -spread)
	local soft = if stick then 0 else 1 -- straight legs can't soften: the hips stay up
	local standAt = at(feetX, pivot.y - 0.1 * L * soft, 0)
	-- on the edge; then legs up along the cushion, sitting up; then lying back into the backrest
	local sitAt = at(seat.edge + 0.16 * L, seat.top + sitUp, 0)
	local upAt = at(seat.centre, seat.top + sitUp, seat.hinge - 0.05 * L)
	local lieAt = at(seat.centre, seat.top + sitUp * 0.85, seat.hinge - 0.1 * L)
	local midAt = { (sitAt[1] + upAt[1]) / 2, (sitAt[2] + upAt[2]) / 2 + 0.04 * L, (sitAt[3] + upAt[3]) / 2 }
	-- the heels up on the cushion, as far down it as the thigh and shin reach lying back; on the way
	-- the knees come up with the hips (tucked), the right one first
	local reachLying = 0
	for _, leg in { left, right } do
		local g = legOf(rig, leg)
		local k = stickOf(rig, leg)
		reachLying += (if g then g.a + g.b elseif k then k.length else 0.8 * L) / 2
	end
	local footZ = seat.hinge - 0.1 * L - 0.9 * reachLying
	local hl = v(seat.centre - 0.75 * spread, seat.top, footZ + 0.03 * L)
	local hr = v(seat.centre + 0.75 * spread, seat.top, footZ - 0.02 * L)
	local recline = seat.recline

	-- where the bacon-hair is, as a head turn from lying back (yaw +left, degrees)
	local function yawTo(p: { number }): number
		return math.deg(math.atan2(-(p[1] - seat.centre), -(p[3] - seat.hinge)))
	end
	local enters, sits = yawTo(watch.from), yawTo(watch.at)

	local still = { 0, 0, 0 }
	-- a hair below standing from the start: a body whose rest pose stands on its toes (its legs a
	-- touch short of the ground) still reaches its planted feet; then stepping round, the right foot
	-- first, each planted foot pivoting a little on the spot as the hips turn
	local standTracks = solved(anatomy, {
		{ t = 0, pos = v(0, -0.005 * L * soft, 0), rot = still },
		{ t = 0.35, pos = v(0, -0.02 * L * soft, 0), rot = still },
		{ t = 1.1, pos = v(0, -0.012 * L * soft, 0), rot = v(2, 0, 0) },
		{ t = 1.75, pos = v(0, -0.012 * L * soft, 0), rot = v(2.5, 0, 0) },
		{ t = 2.25, pos = v(0, -0.03 * L * soft, 0), rot = v(-2, 0, 0) },
		{ t = 2.45, pos = v(0, -0.06 * L * soft, 0), rot = still },
		{ t = 3.5, pos = standAt, rot = v(0, 90, 0) },
	}, {
		right = {
			{ t = 0, on = fr, yaw = 0 },
			{ t = 2.5, on = fr, yaw = 0 },
			{ t = 3.0, on = tr, yaw = 60 },
			{ t = 3.5, on = tr, yaw = 90 },
		},
		left = {
			{ t = 0, on = fl, yaw = 0 },
			{ t = 2.5, on = fl, yaw = 0 },
			{ t = 2.95, on = fl, yaw = 35 },
			{ t = 3.45, on = tl, yaw = 90 },
			{ t = 3.5, on = tl, yaw = 90 },
		},
	}, IntroClips.turnSeconds)
	standTracks.chest = {
		{ t = 0, rot = still },
		{ t = 0.35, rot = v(-4, 0, 0) },
		{ t = 1.1, rot = v(10, 0, 0) },
		{ t = 1.75, rot = v(12, 0, 0) },
		{ t = 2.25, rot = v(-7, 0, 0) },
		{ t = 3.5, rot = v(-3, 0, 0) },
	}
	standTracks.head = {
		{ t = 0, rot = still },
		{ t = 0.35, rot = v(-6, 0, 0) },
		{ t = 1.1, rot = v(14, 0, 0) },
		{ t = 1.75, rot = v(17, 0, 0) },
		{ t = 2.25, rot = v(-10, 0, 0) },
		{ t = 3.5, rot = v(-5, 0, 0) },
	}
	standTracks.rightArm = {
		{ t = 0, rot = still },
		{ t = 0.4, rot = v(6, 0, 0) },
		{ t = 1.1, rot = v(162, 0, 0) },
		{ t = 1.75, rot = v(167, 0, 0) },
		{ t = 2.3, rot = v(8, 0, 3) },
		{ t = 3.5, rot = v(4, 0, 2) },
	}
	standTracks.rightForearm = {
		{ t = 0, rot = still },
		{ t = 1.1, rot = v(10, 0, 0) },
		{ t = 1.75, rot = v(8, 0, 0) },
		{ t = 2.3, rot = v(12, 0, 0) },
		{ t = 3.5, rot = v(13, 0, 0) },
	}
	standTracks.leftArm = {
		{ t = 0, rot = still },
		{ t = 0.45, rot = v(5, 0, 0) },
		{ t = 1.15, rot = v(158, 0, 0) },
		{ t = 1.8, rot = v(164, 0, 0) },
		{ t = 2.35, rot = v(7, 0, -3) },
		{ t = 3.5, rot = v(3, 0, -2) },
	}
	standTracks.leftForearm = {
		{ t = 0, rot = still },
		{ t = 1.15, rot = v(12, 0, 0) },
		{ t = 1.8, rot = v(9, 0, 0) },
		{ t = 2.35, rot = v(14, 0, 0) },
		{ t = 3.5, rot = v(14, 0, 0) },
	}
	local stand = {
		name = "IntroStand",
		length = IntroClips.turnSeconds,
		units = "studs",
		-- the stretch and the turn are gestures, not strikes: the hips need not drive them
		waive = { "no-body-commitment" },
		tracks = standTracks,
		markers = { { t = 0.6, name = "Yawn" } },
		seed = "IntroStand",
	}

	-- Sitting down, the hips drop back and down onto the edge (the chest leaning over the knees). Then
	-- the legs swing up: leaning back, both knees come up until the feet clear the cushion, the hips
	-- swivel round to lie along it, and the legs stretch out onto it.
	local lieTracks = solved(anatomy, {
		{ t = 0, pos = standAt, rot = v(0, 90, 0) },
		{ t = 0.35, pos = toward(standAt, sitAt, 0.25, 0.4), rot = v(0, 90, 0) },
		{ t = 0.7, pos = toward(standAt, sitAt, 0.7, 0.85), rot = v(0, 90, 0) },
		{ t = 1.1, pos = sitAt, rot = v(0, 90, 0) },
		{ t = 1.45, pos = sitAt, rot = v(0, 90, 0) },
		{ t = 1.85, pos = add(sitAt, v(0.04 * L, 0, 0)), rot = v(11, 87, 0) },
		{ t = 2.4, pos = midAt, rot = v(13, 40, 0) },
		{ t = 2.85, pos = upAt, rot = v(12, 0, 0) },
		{ t = 3.5, pos = lieAt, rot = v(recline, 0, 0) },
		{ t = 9.1, pos = lieAt, rot = v(recline, 0, 0) },
		{ t = 10.5, pos = lieAt, rot = v(recline + 2, 0, 0) },
	}, {
		left = {
			{ t = 0, on = tl, yaw = 90 },
			{ t = 1.45, on = tl, yaw = 90 },
			{ t = 1.9, tuck = { 0.6, 0.04 } },
			{ t = 2.45, tuck = { 0.62, 0.05 } },
			{ t = 3.0, heel = hl },
			{ t = 3.5, heel = hl },
			{ t = 9.1, heel = hl },
			{ t = 10.5, heel = hl },
		},
		right = {
			{ t = 0, on = tr, yaw = 90 },
			{ t = 1.4, on = tr, yaw = 90 },
			{ t = 1.85, tuck = { 0.64, 0.06 } },
			{ t = 2.4, tuck = { 0.65, 0.06 } },
			{ t = 2.95, heel = hr },
			{ t = 3.5, heel = hr },
			{ t = 9.1, heel = hr },
			{ t = 10.5, heel = hr },
		},
	}, 3.5)
	lieTracks.chest = {
		{ t = 0, rot = v(-3, 0, 0) },
		{ t = 0.35, rot = v(-10, 0, 0) },
		{ t = 0.7, rot = v(-18, 0, 0) },
		{ t = 1.1, rot = v(-10, 0, 0) },
		{ t = 1.45, rot = v(-12, 0, 0) },
		{ t = 2.55, rot = v(-6, 0, 0) },
		{ t = 3.5, rot = v(-5, 0, 0) },
	}
	lieTracks.head = {
		{ t = 0, rot = v(-5, 0, 0) },
		{ t = 0.7, rot = v(-8, 0, 0) },
		{ t = 1.1, rot = v(-14, 0, 0) },
		{ t = 1.45, rot = v(-16, 0, 0) },
		{ t = 2.55, rot = v(-8, 0, 0) },
		{ t = 3.5, rot = v(-24, 0, 0) },
		{ t = 4.1, rot = v(-25, enters * 0.5, 0) },
		{ t = 5.1, rot = v(-27, enters * 0.6, 0) },
		{ t = 6.5, rot = v(-29, sits * 0.85, 0) },
		{ t = 8.9, rot = v(-28, sits * 0.75, 0) },
		{ t = 10.5, rot = v(-17, sits * 0.4, 7) },
	}
	-- the hands: forward for balance sitting down, onto the cushion's edge, bracing behind the hips
	-- as the legs come up, then along the body
	lieTracks.rightArm = {
		{ t = 0, rot = v(4, 0, 2) },
		{ t = 0.7, rot = v(22, 0, 10) },
		{ t = 1.1, rot = v(10, 0, 14) },
		{ t = 1.45, rot = v(8, 0, 15) },
		{ t = 2.55, rot = v(-20, 0, 14) },
		{ t = 3.5, rot = v(10, 0, 8) },
		{ t = 10.5, rot = v(8, 0, 10) },
	}
	lieTracks.rightForearm = {
		{ t = 0, rot = v(13, 0, 0) },
		{ t = 0.7, rot = v(20, 0, 0) },
		{ t = 1.1, rot = v(16, 0, 0) },
		{ t = 2.55, rot = v(10, 0, 0) },
		{ t = 3.5, rot = v(18, 0, 0) },
		{ t = 10.5, rot = v(14, 0, 0) },
	}
	lieTracks.leftArm = {
		{ t = 0, rot = v(3, 0, -2) },
		{ t = 0.7, rot = v(20, 0, -10) },
		{ t = 1.1, rot = v(9, 0, -14) },
		{ t = 1.45, rot = v(7, 0, -15) },
		{ t = 2.55, rot = v(-18, 0, -14) },
		{ t = 3.5, rot = v(9, 0, -8) },
		{ t = 10.5, rot = v(7, 0, -10) },
	}
	lieTracks.leftForearm = {
		{ t = 0, rot = v(14, 0, 0) },
		{ t = 0.7, rot = v(18, 0, 0) },
		{ t = 1.1, rot = v(14, 0, 0) },
		{ t = 2.55, rot = v(10, 0, 0) },
		{ t = 3.5, rot = v(16, 0, 0) },
		{ t = 10.5, rot = v(12, 0, 0) },
	}
	local lie = {
		name = "IntroLie",
		length = 15.3,
		units = "studs",
		-- the sitting about and the look are gestures, not strikes: the hips need not drive them
		waive = { "no-body-commitment" },
		tracks = lieTracks,
		seed = "IntroLie",
	}
	for _, name in { "rightForearm", "leftForearm" } do
		if not anatomy.parts[name] then -- arms that don't bend (R6)
			standTracks[name], lieTracks[name] = nil, nil
		end
	end
	if anatomy.chest == nil or anatomy.chest == anatomy.body then -- one-piece torso (R6): the hips turn it
		standTracks.chest, lieTracks.chest = nil, nil
	end
	return stand, lie
end

-- The bacon-hair (R6) sits down in the sand where his walk stops: hips down onto it, legs out in
-- front (lifted as he lowers, so they never dig in), leaning over them; his hands go to the sand.
-- Ends in IntroClips.sandPlay's first pose.
local SAND = {
	hips = { pos = { 0, -1.5, 0.25 }, rot = { -10, 0, 0 } },
	rightLeg = { rot = { 96, 0, 6 } },
	leftLeg = { rot = { 94, 0, -6 } },
	rightArm = { rot = { 48, 0, -6 } },
	leftArm = { rot = { 44, 0, 6 } },
	head = { rot = { -22, 0, 0 } },
}

IntroClips.sandSit = {
	name = "IntroSandSit",
	length = 1.2,
	plant = false, -- sitting down: the legs go out from under him
	keys = {
		{ t = 0, pose = { hips = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } }, rightLeg = { rot = { 0, 0, 0 } }, leftLeg = { rot = { 0, 0, 0 } }, rightArm = { rot = { 0, 0, 0 } }, leftArm = { rot = { 0, 0, 0 } }, head = { rot = { 0, 0, 0 } } } },
		{ t = 0.45, pose = with(SAND, { hips = { pos = { 0, -0.35, 0.05 }, rot = { -6, 0, 0 } }, rightLeg = { rot = { 50, 0, 4 } }, leftLeg = { rot = { 46, 0, -4 } }, rightArm = { rot = { 30, 0, -10 } }, leftArm = { rot = { 26, 0, 10 } }, head = { rot = { -10, 0, 0 } } }) },
		{ t = 0.85, pose = with(SAND, { hips = { pos = { 0, -1.5, 0.25 }, rot = { -8, 0, 0 } }, rightLeg = { rot = { 90, 0, 6 } }, leftLeg = { rot = { 88, 0, -6 } } }) },
		{ t = 1.2, pose = SAND },
	},
	seed = "IntroSandSit",
}

-- Playing in the sand, looped: pats with one hand then the other, a scoop with both, the head
-- following the hands.
IntroClips.sandPlay = {
	name = "IntroSandPlay",
	length = 2.6,
	loop = true,
	plant = false,
	tracks = {
		hips = {
			{ t = 0, pos = { 0, -1.5, 0.25 }, rot = { -10, 0, 0 } },
			{ t = 1.0, pos = { 0, -1.5, 0.25 }, rot = { -11, -3, 0 } },
			{ t = 1.9, pos = { 0, -1.5, 0.25 }, rot = { -11, 2, 0 } },
			{ t = 2.6, pos = { 0, -1.5, 0.25 }, rot = { -10, 0, 0 } },
		},
		rightLeg = { { t = 0, rot = { 96, 0, 6 } }, { t = 2.6, rot = { 96, 0, 6 } } },
		leftLeg = { { t = 0, rot = { 94, 0, -6 } }, { t = 2.6, rot = { 94, 0, -6 } } },
		rightArm = {
			{ t = 0, rot = { 48, 0, -6 } },
			{ t = 0.25, rot = { 62, 0, -8 } },
			{ t = 0.4, rot = { 78, 0, -8 }, ease = "snap" },
			{ t = 0.75, rot = { 58, 0, -6 } },
			{ t = 1.6, rot = { 56, 0, -12 } },
			{ t = 1.95, rot = { 82, 0, -14 } },
			{ t = 2.6, rot = { 48, 0, -6 } },
		},
		leftArm = {
			{ t = 0, rot = { 44, 0, 6 } },
			{ t = 0.8, rot = { 46, 0, 6 } },
			{ t = 1.05, rot = { 60, 0, 8 } },
			{ t = 1.2, rot = { 76, 0, 8 }, ease = "snap" },
			{ t = 1.55, rot = { 54, 0, 10 } },
			{ t = 1.95, rot = { 80, 0, 14 } },
			{ t = 2.6, rot = { 44, 0, 6 } },
		},
		head = {
			{ t = 0, rot = { -22, 0, 0 } },
			{ t = 0.45, rot = { -26, -6, 0 } },
			{ t = 1.25, rot = { -25, 7, 0 } },
			{ t = 2.0, rot = { -28, 0, 0 } },
			{ t = 2.6, rot = { -22, 0, 0 } },
		},
	},
	seed = "IntroSandPlay",
}

return IntroClips
