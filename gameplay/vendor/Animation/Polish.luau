--!strict
--[[
	Polish: passes over a baked clip that keep it from reading as machine-made.

	drift      Holds keep moving a little. Where every joint turns slower than 6 degrees a
	           second for 0.3 s or more, a smooth, slow wander is faded in (three sines near
	           0.31, 0.53 and 0.97 Hz, their frequencies and phases drawn from the clip's seed),
	           sized by body part from measurements of people standing still: the head wanders
	           about a degree, the hips a quarter of one, the hands most. Seeded, so every client
	           drifts the same way.
	breathe    Chest rises on a 40% in, 60% out cycle; the head counters it at half strength.
	impulses   A keyed knock (an antenna flicked, a hat brim hit) rings out as a damped spring in
	           closed form: deterministic at any frame rate.
	secondary  Loose parts (tails, antennae, brims) lag and swing behind what carries them.
	settle     Ends of chains (hands, head, props) come to rest through a small spring instead of
	           stopping dead.

	The last three are off unless a clip asks: overshoot is the cartoon tell, and the house
	style is restraint.
]]

local M = require("./Math")
local Rig = require("./Rig")
local Anatomy = require("./Anatomy")
local Rng = require("./Rng")
local Spring = require("./Spring")
local Signal = require("./Signal")
local Baked = require("./Baked")

type V3 = M.V3
type Q = M.Q
type X = M.X

local Polish = {}

local DEG = math.pi / 180

-- Per-joint drift half-amplitudes (degrees about the character's X, Y, Z), by what the joint is.
local DRIFT = {
	head = { 1.0, 1.0, 0.4 },
	chest = { 0.5, 0.4, 0.3 },
	pelvis = { 0.25, 0.3, 0.2 },
	upperArm = { 1.0, 0.6, 0.8 },
	forearm = { 0.8, 0.4, 0.4 },
	hand = { 1.0, 0.8, 0.8 },
	loose = { 0.8, 0.8, 0.5 },
}

local function roleOf(a: Anatomy.Anatomy, k: number): { number }?
	if k == a.head then
		return DRIFT.head
	end
	if table.find(a.neck, k) then
		return DRIFT.head
	end
	if k == a.chest and k ~= a.body then
		return DRIFT.chest
	end
	if k == a.body then
		return DRIFT.pelvis
	end
	if table.find(a.spine, k) then
		return DRIFT.chest
	end
	for _, c in a.arms do
		local i = table.find(c.movable, k)
		if i then
			return if i == 1 then DRIFT.upperArm elseif i == 2 then DRIFT.forearm else DRIFT.hand
		end
	end
	for _, c in a.wings do
		if table.find(c.movable, k) then
			return DRIFT.forearm
		end
	end
	for _, c in a.tails do
		if table.find(c.movable, k) then
			return DRIFT.loose
		end
	end
	for _, c in a.others do
		if table.find(c.movable, k) and not c.digit then
			return DRIFT.loose
		end
	end
	return nil
end

-- Character-frame rotation (radians about X, Y, Z) as joint k's local rotation.
local function charToLocal(rig: Rig.Rig, k: number, rx: number, ry: number, rz: number): Q
	local w = rig.joints[k].world.q
	local q = M.qeuler(rx, ry, rz)
	return M.qnorm(M.qmul(M.qmul(M.qconj(w), q), w))
end

local function compose(b: Baked.Baked, s: number, c: number, q: Q)
	local cur = Baked.get(b, s, c)
	cur.q = M.qmul(cur.q, q)
	Baked.set(b, s, c, cur)
end

-- Per-sample weight 0..1 of being in a hold, feathered over `feather` seconds at each edge.
function Polish.holdMask(b: Baked.Baked, still: number, minHold: number, feather: number, rootStill: number): { number }
	local n = b.count
	local quiet: { boolean } = table.create(n, false)
	local dt = 1 / b.rate
	for s = 0, n - 1 do
		local a = math.max(s - 1, 0)
		local c = math.min(s + 1, n - 1)
		local span = (c - a) * dt
		local fast = false
		if span > 0 then
			for ch = 1, b.nch do
				local qa = Baked.get(b, a, ch).q
				local qc = Baked.get(b, c, ch).q
				if M.qdiffAngle(qa, qc) / span > still then
					fast = true
					break
				end
			end
			if not fast then
				local ra = Baked.get(b, a, 0)
				local rc = Baked.get(b, c, 0)
				if M.vdist(ra.p, rc.p) / span > rootStill or M.qdiffAngle(ra.q, rc.q) / span > still then
					fast = true
				end
			end
		end
		quiet[s + 1] = not fast
	end
	-- keep only runs long enough to be a hold
	local weight: { number } = table.create(n, 0)
	local i = 1
	local minRun = math.max(1, math.floor(minHold * b.rate + 0.5))
	while i <= n do
		if quiet[i] then
			local j = i
			while j <= n and quiet[j] do
				j += 1
			end
			if j - i >= minRun then
				for k = i, j - 1 do
					weight[k] = 1
				end
			end
			i = j
		else
			i += 1
		end
	end
	-- feather the edges: a smooth ramp in and out, never a step
	local r = math.max(1, math.floor(feather * b.rate + 0.5))
	local soft = Signal.gauss(weight, r / 2, b.loop)
	for k = 1, n do
		soft[k] = M.smoothstep(M.clamp(soft[k], 0, 1))
	end
	return soft
end

--[[
	Drift in holds. `amount` scales it (0 none, 0.5 composed, 1 normal, 2 fidgety).
]]
function Polish.drift(b: Baked.Baked, a: Anatomy.Anatomy, amount: number, rng: Rng.Rng, moveRoot: boolean?)
	if amount <= 0 or b.count < 3 then
		return
	end
	local rig = a.rig
	local H = math.max(a.hipHeight, 1e-3)
	local mask = Polish.holdMask(b, 6 * DEG, 0.3, 0.15, 0.02 * H)
	local any = false
	for _, w in mask do
		if w > 1e-3 then
			any = true
			break
		end
	end
	if not any then
		return
	end
	local length = math.max(b.length, 1e-3)
	local function freq(target: number): number
		local f = target * Rng.range(rng, 0.85, 1.15)
		if b.loop then
			-- whole cycles per loop, so the seam stays seamless
			return math.max(1, math.floor(f * length + 0.5)) / length
		end
		return f
	end
	local base = { 0.31, 0.53, 0.97 }
	local weights = { 1 / 1.9, 0.6 / 1.9, 0.3 / 1.9 }
	-- three sines per axis per joint
	local function wave(): { { number } }
		local w: { { number } } = {}
		for i = 1, 3 do
			w[i] = { freq(base[i]), Rng.range(rng, 0, 2 * math.pi), weights[i] }
		end
		return w
	end
	local function value(w: { { number } }, t: number): number
		local v = 0
		for _, c in w do
			v += c[3] * math.sin(2 * math.pi * c[1] * t + c[2])
		end
		return v
	end
	for c = 1, b.nch do
		local k = b.joints[c]
		local role = roleOf(a, k)
		if not role then
			continue
		end
		local r = role :: { number }
		local wx, wy, wz = wave(), wave(), wave()
		for s = 0, b.count - 1 do
			local m = mask[s + 1]
			if m > 1e-4 then
				local t = s / b.rate
				local rx = r[1] * DEG * amount * m * value(wx, t)
				local ry = r[2] * DEG * amount * m * value(wy, t)
				local rz = r[3] * DEG * amount * m * value(wz, t)
				compose(b, s, c, charToLocal(rig, k, rx, ry, rz))
			end
		end
	end
	-- the root sways a hair in X and Z (not in a gait: its feet are baked to the root's path)
	local px, pz = wave(), wave()
	local amp = if moveRoot == false then 0 else 0.012 * (H / 2) * amount
	for s = 0, b.count - 1 do
		local m = mask[s + 1]
		if m > 1e-4 then
			local t = s / b.rate
			local cur = Baked.get(b, s, 0)
			cur.p = { x = cur.p.x + amp * m * value(px, t), y = cur.p.y, z = cur.p.z + amp * m * value(pz, t) }
			Baked.set(b, s, 0, cur)
		end
	end
	Baked.finish(b)
	b.info.drift = amount
end

-- Breathing: an asymmetric cycle, 40% in and 60% out.
function Polish.breathe(b: Baked.Baked, a: Anatomy.Anatomy, period: number)
	local rig = a.rig
	local p = math.max(period, 0.5)
	if b.loop and b.length > 0 then
		local nB = math.max(1, math.floor(b.length / p + 0.5))
		p = b.length / nB
	end
	local chest = a.chest or a.body
	local function cycle(t: number): number
		local u = M.frac(t / p)
		if u < 0.4 then
			return (1 - math.cos(math.pi * u / 0.4)) / 2
		end
		return (1 + math.cos(math.pi * (u - 0.4) / 0.6)) / 2
	end
	local amp = 0.8 * DEG
	for s = 0, b.count - 1 do
		local t = s / b.rate
		local v = cycle(t)
		if chest then
			local c = Baked.channelOf(b, chest :: number)
			if c then
				compose(b, s, c, charToLocal(rig, chest :: number, amp * v, 0, 0))
			end
		end
		if a.head then
			local c = Baked.channelOf(b, a.head :: number)
			if c then
				compose(b, s, c, charToLocal(rig, a.head :: number, -0.5 * amp * v, 0, 0))
			end
		end
		for _, arm in a.arms do
			local k = arm.movable[1]
			if k then
				local c = Baked.channelOf(b, k)
				if c then
					compose(b, s, c, charToLocal(rig, k, 0, 0, -arm.side * 0.5 * amp * v))
				end
			end
		end
	end
	Baked.finish(b)
	b.info.breathing = p
end

-- Keyed impulses ringing out as springs.
function Polish.impulses(b: Baked.Baked, a: Anatomy.Anatomy, list: { any }, warnings: { string })
	local rig = a.rig
	for _, sp in list do
		if type(sp) ~= "table" or type(sp.part) ~= "string" or not M.finite(sp.at) or type(sp.impulse) ~= "table" then
			continue
		end
		local part = Anatomy.part(a, sp.part)
		if not part then
			table.insert(warnings, string.format("spring on %q: the rig has no such part", sp.part))
			continue
		end
		local js: { number } = if part.chain then (part.chain :: Anatomy.Chain).movable else part.joints
		local hz = if M.finite(sp.hz) then math.max(sp.hz, 0.2) else 3
		local damping = if M.finite(sp.damping) then math.max(sp.damping, 0) else 0.5
		local imp = sp.impulse
		local ix, iy, iz = (imp[1] or 0) * DEG, (imp[2] or 0) * DEG, (imp[3] or 0) * DEG
		for i, k in js do
			local c = Baked.channelOf(b, k)
			if not c then
				continue
			end
			-- looser towards the tip
			local w = i / #js
			for s = 0, b.count - 1 do
				local t = s / b.rate
				local h = Spring.impulse(t - sp.at, hz, damping)
				if h ~= 0 then
					compose(b, s, c, charToLocal(rig, k, ix * h * w, iy * h * w, iz * h * w))
				end
			end
		end
	end
	Baked.finish(b)
end

-- The world rotation (as a rotation vector, in the root's rest frame) of joint k per sample.
local function worldRotSeries(b: Baked.Baked, rig: Rig.Rig, k: number): { { number } }
	local out: { { number } } = { {}, {}, {} }
	for s = 0, b.count - 1 do
		local frames = Rig.fk(rig, Baked.locals(b, rig, s), M.xid())
		local q = M.qmul(frames[k].q, M.qconj(rig.joints[k].world.q))
		local v = M.qlog(q)
		out[1][s + 1], out[2][s + 1], out[3][s + 1] = v.x, v.y, v.z
	end
	return out
end

--[[
	Secondary motion for loose chains: each lags the joint that carries it through a damped
	spring. opts: parts (names; default every tail and accessory chain), hz (2.5), damping (0.55),
	gain (1).
]]
function Polish.secondary(b: Baked.Baked, a: Anatomy.Anatomy, opts: { [string]: any })
	local rig = a.rig
	local hz = if M.finite(opts.hz) then math.max(opts.hz, 0.2) else 2.5
	local damping = if M.finite(opts.damping) then math.max(opts.damping, 0) else 0.55
	local gain = if M.finite(opts.gain) then opts.gain else 1
	local chains: { Anatomy.Chain } = {}
	if type(opts.parts) == "table" then
		for _, nm in opts.parts do
			local p = if type(nm) == "string" then Anatomy.part(a, nm) else nil
			if p and p.chain then
				table.insert(chains, p.chain :: Anatomy.Chain)
			end
		end
	else
		for _, c in a.tails do
			table.insert(chains, c)
		end
		for _, c in a.others do
			if not c.digit then
				table.insert(chains, c)
			end
		end
	end
	for _, chain in chains do
		local first = chain.movable[1]
		if not first then
			continue
		end
		local carrier = rig.joints[first].parent
		local series: { { number } }
		if carrier > 0 then
			series = worldRotSeries(b, rig, carrier)
		else
			-- carried by the root channel
			series = { {}, {}, {} }
			for s = 0, b.count - 1 do
				local v = M.qlog(Baked.get(b, s, 0).q)
				series[1][s + 1], series[2][s + 1], series[3][s + 1] = v.x, v.y, v.z
			end
		end
		local lag: { { number } } = {}
		for d = 1, 3 do
			local followed = Spring.follow(series[d], b.rate, hz, damping, b.loop)
			lag[d] = {}
			for s = 1, b.count do
				lag[d][s] = (followed[s] - series[d][s]) * gain
			end
		end
		for i, k in chain.movable do
			local c = Baked.channelOf(b, k)
			if not c then
				continue
			end
			local w = i / #chain.movable
			for s = 0, b.count - 1 do
				local v = { x = lag[1][s + 1] * w, y = lag[2][s + 1] * w, z = lag[3][s + 1] * w }
				local qc = M.qexp(v)
				local wq = rig.joints[k].world.q
				compose(b, s, c, M.qnorm(M.qmul(M.qmul(M.qconj(wq), qc), wq)))
			end
		end
	end
	Baked.finish(b)
end

-- Ends of chains settle through a spring: preset 1 (7 Hz, 0.75), 2 (5 Hz, 0.55), 3 (3.5 Hz, 0.4).
function Polish.settle(b: Baked.Baked, a: Anatomy.Anatomy, preset: number)
	local p = math.clamp(math.floor(preset + 0.5), 1, 3)
	local hz = ({ 7, 5, 3.5 })[p]
	local damping = ({ 0.75, 0.55, 0.4 })[p]
	local targets: { number } = {}
	if a.head then
		table.insert(targets, a.head :: number)
	end
	for _, c in a.arms do
		local k = c.movable[#c.movable]
		if k and #c.movable >= 2 then
			table.insert(targets, k)
		end
	end
	for _, c in a.others do
		if c.movable[1] and not c.digit then
			table.insert(targets, c.movable[1])
		end
	end
	for _, k in targets do
		local c = Baked.channelOf(b, k)
		if not c then
			continue
		end
		local series: { { number } } = { {}, {}, {} }
		for s = 0, b.count - 1 do
			local v = M.qlog(Baked.get(b, s, c).q)
			series[1][s + 1], series[2][s + 1], series[3][s + 1] = v.x, v.y, v.z
		end
		local f = {}
		for d = 1, 3 do
			f[d] = Spring.follow(series[d], b.rate, hz, damping, b.loop)
		end
		for s = 0, b.count - 1 do
			local cur = Baked.get(b, s, c)
			cur.q = M.qexp({ x = f[1][s + 1], y = f[2][s + 1], z = f[3][s + 1] })
			Baked.set(b, s, c, cur)
		end
	end
	Baked.finish(b)
end

return Polish
