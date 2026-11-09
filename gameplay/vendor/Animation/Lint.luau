--!strict
--[[
	Lint: reads a baked clip or gait the way a critical animator would, and reports the tells
	that make motion read as machine-made, each with a reason and a fix.

	It works on any rig: speeds are measured in hip heights (H; studs scale with the creature),
	parts come from Anatomy, and rules that need a part the rig lacks are skipped. Severity
	"fix" must be dealt with (or waived in the clip with a reason); "consider" is a judgement
	call; "info" is a measurement.

	Rules and their thresholds are in Lint.RULES; references/lint.md explains each.
]]

local M = require("./Math")
local Rig = require("./Rig")
local Anatomy = require("./Anatomy")
local Baked = require("./Baked")

type V3 = M.V3
type Q = M.Q
type X = M.X

local Lint = {}

export type Severity = "fix" | "consider" | "info"
export type Finding = { rule: string, severity: Severity, message: string, time: number? }

local DEG = 180 / math.pi

--[[
	Thresholds, in one place so docs and tests can read them. Distances are in units of U, half
	the hip height (1 stud on a standard R15, whose hip height is about 2), and speeds in hip
	heights per second, so the same rule judges a 0.1-stud bug and a 100-stud golem alike.
]]
Lint.RULES = {
	["constant-spacing"] = { severity = "fix", share = 0.3, ratio = 1.15 },
	["even-easing"] = { severity = "consider", lo = 0.46, hi = 0.54, moves = 4 },
	["no-overlap"] = { severity = "fix", lagFrames = 0.3, pairs = 2, speed = 60 },
	["mirroring"] = { severity = "fix", sweep = 25, within = 6, corr = 0.9 },
	["frozen-hold"] = { severity = "fix", angular = 1, root = 0.02, seconds = 0.4 },
	["straight-path"] = { severity = "consider", deviation = 0.04, chord = 0.6 },
	["no-body-commitment"] = { severity = "fix", strike = 3, drop = 0.02, travel = 0.05 },
	["no-wind-up"] = { severity = "consider", strike = 3, pullBack = 0.05, drop = 0.02 },
	["arm-leads"] = { severity = "consider", strike = 3.5 },
	["rushed-recovery"] = { severity = "consider", ratio = 0.6 },
	["gliding-gait"] = { severity = "fix", walk = 0.015, run = 0.05 },
	["even-key-timing"] = { severity = "consider", keys = 5, cv = 0.08 },
	["default-linear"] = { severity = "fix", keys = 2 },
	["joint-range"] = { severity = "fix", tolerance = 2 },
	["joint-speed"] = { severity = "fix", limit = 2500 },
	["root-drift"] = { severity = "fix", stray = 1.0, finish = 0.25 },
	["loop-seam"] = { severity = "fix", degrees = 3, root = 0.05 },
	["ground-penetration"] = { severity = "fix", depth = 0.1 },
	["foot-slide"] = { severity = "fix", drift = 0.25, hold = 0.1 },
	["gait-symmetry"] = { severity = "fix", swing = 5, ratio = 0.6, lo = 0.4, hi = 0.6 },
	["jitter"] = { severity = "fix", reversals = 3, window = 0.18, speed = 15, sweep = 4 },
	["twist"] = { severity = "fix", degrees = 35, spin = 180 },
	["pops"] = { severity = "fix", jump = 360, share = 0.6, isolation = 3 },
	["hip-bob"] = { severity = "info" },
	["flat-slither"] = { severity = "fix", share = 0.08 },
}

export type Measure = {
	n: number,
	dt: number,
	H: number,
	unit: number,
	gait: boolean,
	loop: boolean,
	frames: { { X } },
	root: { X },
	-- per channel: angular speed (deg/s) and velocity (rad/s, local) per sample
	speed: { { number } },
	vel: { { V3 } },
	effectors: { { name: string, kind: string, k: number, local_: V3, pos: { V3 } } },
	body: { V3 },
}

-- Forward kinematics and derivatives for every sample (in the clip's own frame).
function Lint.measure(b: Baked.Baked, a: Anatomy.Anatomy): Measure
	local rig = a.rig
	local n = b.count
	local dt = 1 / b.rate
	local frames: { { X } } = table.create(n)
	local root: { X } = table.create(n)
	for s = 0, n - 1 do
		local r = Baked.get(b, s, 0)
		root[s + 1] = r
		frames[s + 1] = Rig.fk(rig, Baked.locals(b, rig, s), r)
	end
	local speed: { { number } } = {}
	local vel: { { V3 } } = {}
	for c = 1, b.nch do
		local sp: { number } = table.create(n, 0)
		local ve: { V3 } = table.create(n)
		local prev = Baked.get(b, 0, c).q
		ve[1] = M.ZERO
		for s = 1, n - 1 do
			local q = Baked.get(b, s, c).q
			local d = M.qlog(M.qmul(M.qconj(prev), q))
			local v = M.vmul(d, 1 / dt)
			ve[s + 1] = v
			sp[s + 1] = M.vlen(v) * DEG
			prev = q
		end
		sp[1] = if n > 1 then sp[2] else 0
		ve[1] = if n > 1 then ve[2] else M.ZERO
		speed[c] = sp
		vel[c] = ve
	end
	-- end points: hands, head, feet, tail tips, accessory tips
	local effectors = {}
	local function add(name: string, kind: string, k: number, localPoint: V3)
		local pos: { V3 } = table.create(n)
		for s = 1, n do
			pos[s] = M.xpoint(frames[s][k], localPoint)
		end
		table.insert(effectors, { name = name, kind = kind, k = k, local_ = localPoint, pos = pos })
	end
	for _, c in a.arms do
		local k = c.joints[#c.joints]
		add(c.name, "hand", k, rig.joints[k].tip)
	end
	if a.head then
		local k = a.head :: number
		add("head", "head", k, rig.joints[k].tip)
	end
	for _, c in a.legs do
		add(c.name, "foot", c.joints[#c.joints], c.foot)
	end
	for _, c in a.tails do
		local k = c.joints[#c.joints]
		add(c.name, "tail", k, rig.joints[k].tip)
	end
	for _, c in a.others do
		if not c.digit then
			local k = c.joints[#c.joints]
			add(c.name, "prop", k, rig.joints[k].tip)
		end
	end
	local body: { V3 } = table.create(n)
	for s = 1, n do
		body[s] = if a.body then frames[s][a.body :: number].p else root[s].p
	end
	local H = math.max(a.hipHeight, 1e-3)
	return {
		n = n,
		dt = dt,
		H = H,
		unit = H / 2,
		gait = b.kind == "gait",
		loop = b.loop,
		frames = frames,
		root = root,
		speed = speed,
		vel = vel,
		effectors = effectors,
		body = body,
	}
end

local function median(list: { number }): number
	if #list == 0 then
		return 0
	end
	local c = table.clone(list)
	table.sort(c)
	local m = #c
	if m % 2 == 1 then
		return c[(m + 1) // 2]
	end
	return (c[m // 2] + c[m // 2 + 1]) / 2
end

local function pointSpeed(pos: { V3 }, dt: number): { number }
	local n = #pos
	local out: { number } = table.create(n, 0)
	for s = 2, n do
		out[s] = M.vdist(pos[s], pos[s - 1]) / dt
	end
	if n >= 2 then
		out[1] = out[2]
	end
	return out
end

-- Moves of one joint: runs above a speed floor that peak and sweep enough to count.
type Move = { from: number, to: number, peak: number, mean: number, at: number }
-- (a move also ends where the joint turns back: one stroke there, another back)
local function movesOf(sp: { number }, dt: number, vel: { V3 }?): { Move }
	local n = #sp
	local peakAll = 0
	for _, v in sp do
		peakAll = math.max(peakAll, v)
	end
	local floor = math.max(20, 0.15 * peakAll)
	local minLen = math.max(4, math.floor(0.12 / dt + 0.5))
	local out: { Move } = {}
	local s = 1
	while s <= n do
		if sp[s] > floor then
			local a = s
			s += 1
			while s <= n and sp[s] > floor and not (vel and M.vdot((vel :: { V3 })[s], (vel :: { V3 })[s - 1]) < 0) do
				s += 1
			end
			local b = s - 1
			if b - a + 1 >= minLen then
				local peak, at, sum = 0, a, 0
				for i = a, b do
					sum += sp[i]
					if sp[i] > peak then
						peak, at = sp[i], i
					end
				end
				local sweep = sum * dt
				if peak >= 90 and sweep >= 12 then
					table.insert(out, { from = a, to = b, peak = peak, mean = sum / (b - a + 1), at = at })
				end
			end
		else
			s += 1
		end
	end
	return out
end

-- Correlation-based lag (in samples) of child after parent, searched in [lo, hi].
local function bestLag(p: { number }, c: { number }, lo: number, hi: number): (number?, number)
	local n = #p
	local best, bestR = nil, -1
	for lag = lo, hi do
		local sx, sy, sxx, syy, sxy, m = 0, 0, 0, 0, 0, 0
		for i = 1, n do
			local j = i + lag
			if j >= 1 and j <= n then
				local x, y = p[i], c[j]
				sx += x
				sy += y
				sxx += x * x
				syy += y * y
				sxy += x * y
				m += 1
			end
		end
		if m > 3 then
			local cov = sxy / m - (sx / m) * (sy / m)
			local vx = sxx / m - (sx / m) ^ 2
			local vy = syy / m - (sy / m) ^ 2
			if vx > 1e-12 and vy > 1e-12 then
				local r = cov / math.sqrt(vx * vy)
				if r > bestR then
					best, bestR = lag, r
				end
			end
		end
	end
	return best, bestR
end

--[[
	Runs every rule. `opts`: { gaitInfo = baked.info (default), waive = { rule = true } }.
	Returns findings sorted by severity then time, and the measurements.
]]
function Lint.run(b: Baked.Baked, a: Anatomy.Anatomy, opts: any?): ({ Finding }, Measure)
	local o = if type(opts) == "table" then opts else {}
	local rig = a.rig
	local m = Lint.measure(b, a)
	local findings: { Finding } = {}
	local waive: { [string]: boolean } = table.clone(b.waive)
	if type(o.waive) == "table" then
		for k, v in o.waive do
			if type(k) == "string" and v then
				waive[k] = true
			elseif type(v) == "string" then
				waive[v] = true
			end
		end
	end
	local function report(rule: string, message: string, time: number?)
		if waive[rule] then
			return
		end
		local r = Lint.RULES[rule]
		table.insert(findings, { rule = rule, severity = (if r then r.severity else "consider") :: Severity, message = message, time = time })
	end
	local n, dt, H, U = m.n, m.dt, m.H, m.unit
	local info: { [string]: any } = b.info or {}
	local isGait = m.gait
	local frame30 = 1 / 30
	local channelIndex: { [number]: number } = {}
	for c, k in b.joints do
		channelIndex[k] = c
	end
	local function chanSpeed(k: number?): { number }?
		if not k then
			return nil
		end
		local c = channelIndex[k :: number]
		return if c then m.speed[c] else nil
	end

	-- Spacing and easing (clips; gaits are cycles, not authored moves). Legs held by IK to
	-- planted feet move however the body makes them; only keyed joints say anything here.
	local ikHeld: { [number]: boolean } = {}
	local plantedNames: { [string]: any } = info.plantedLegs or {}
	for _, leg in a.legs do
		if plantedNames[leg.name] then
			for _, k in leg.joints do
				ikHeld[k] = true
			end
		end
	end
	if not isGait and n >= 8 then
		local all: { Move } = {}
		for c = 1, b.nch do
			if ikHeld[b.joints[c]] then
				continue
			end
			for _, mv in movesOf(m.speed[c], dt, m.vel[c]) do
				table.insert(all, mv)
			end
		end
		local long = 0
		local flat = 0
		local positions: { number } = {}
		for _, mv in all do
			local frames = (mv.to - mv.from + 1) * dt / frame30
			if frames >= 6 then
				long += 1
				if mv.peak / math.max(mv.mean, 1e-9) < Lint.RULES["constant-spacing"].ratio then
					flat += 1
				end
			end
			table.insert(positions, (mv.at - mv.from) / math.max(mv.to - mv.from, 1))
		end
		-- (judged over three moves or more: one flat move in two is not a pattern)
		if long >= 3 and flat / long >= Lint.RULES["constant-spacing"].share then
			report(
				"constant-spacing",
				string.format(
					"%d of %d moves run at nearly constant speed (peak under 1.15x the average). Captured gestures peak near 1.4x: keep the spline on, drop explicit linear eases, add a breakdown 60%% of the way at 40%% of the time",
					flat,
					long
				)
			)
		end
		if #positions >= Lint.RULES["even-easing"].moves then
			local med = median(positions)
			if med >= Lint.RULES["even-easing"].lo and med <= Lint.RULES["even-easing"].hi then
				report(
					"even-easing",
					string.format(
						"moves peak in speed at %.0f%% of their length (median): symmetric in-out easing. People depart quickly and arrive gently, peaking near 38%%: use the default ease, or 'snap' for strikes",
						med * 100
					)
				)
			end
		end
	end

	-- Overlap: children trail parents by a frame or two.
	if not isGait then
		local pairs: { { number } } = {}
		local function chainPairs(js: { number })
			for i = 2, #js do
				table.insert(pairs, { js[i - 1], js[i] })
			end
		end
		-- (a chain a reach target drives is solved whole each frame, so it is left out)
		local reached: { [string]: any } = info.reachChains or {}
		for _, c in a.arms do
			if not reached[c.name] then
				chainPairs(c.movable)
			end
		end
		if a.chest and a.head then
			local js = { a.chest :: number }
			for _, k in a.neck do
				table.insert(js, k)
			end
			table.insert(js, a.head :: number)
			chainPairs(js)
		end
		local lags: { number } = {}
		local counted = 0
		local lo = -math.floor(3 * frame30 / dt + 0.5)
		local hi = math.floor(6 * frame30 / dt + 0.5)
		for _, pr in pairs do
			local sp, sc = chanSpeed(pr[1]), chanSpeed(pr[2])
			if sp and sc then
				local pp, pc = 0, 0
				for s = 1, n do
					pp = math.max(pp, (sp :: { number })[s])
					pc = math.max(pc, (sc :: { number })[s])
				end
				if pp > Lint.RULES["no-overlap"].speed and pc > Lint.RULES["no-overlap"].speed then
					local lag, r = bestLag(sp :: { number }, sc :: { number }, lo, hi)
					if lag and r > 0.5 then
						table.insert(lags, lag * dt / frame30)
						counted += 1
					end
				end
			end
		end
		if counted >= Lint.RULES["no-overlap"].pairs and median(lags) <= Lint.RULES["no-overlap"].lagFrames then
			report(
				"no-overlap",
				string.format(
					"parent and child joints move in lockstep (median lag %.2f frames at 30 fps over %d pairs). Children trail by 1-2 frames: elbow 1, wrist 2, neck 1. Turn the overlap pass back on or key children later",
					median(lags),
					counted
				)
			)
		end
	end

	-- Mirroring: left and right doing the same thing at the same time.
	if not isGait then
		local function sideRot(k: number, s: number): Q
			-- the joint's rotation in the character's frame
			local q = Baked.get(b, s, channelIndex[k]).q
			local w = rig.joints[k].world.q
			return M.qmul(M.qmul(w, q), M.qconj(w))
		end
		local pairsChecked = 0
		local mirrored = 0
		local function checkPair(left: number?, right: number?)
			if not left or not right or not channelIndex[left :: number] or not channelIndex[right :: number] then
				return
			end
			local l, r = left :: number, right :: number
			local sweepL, sweepR = 0, 0
			local diffs: { number } = {}
			local magL: { number } = {}
			local magR: { number } = {}
			for s = 0, n - 1 do
				local ql, qr = sideRot(l, s), sideRot(r, s)
				-- mirror the right across the YZ plane: (x, y, z, w) -> (x, -y, -z, w)
				local mr = { x = qr.x, y = -qr.y, z = -qr.z, w = qr.w }
				table.insert(diffs, M.qdiffAngle(ql, mr) * DEG)
				table.insert(magL, M.qangle(ql) * DEG)
				table.insert(magR, M.qangle(qr) * DEG)
			end
			local spL, spR = chanSpeed(l) :: { number }, chanSpeed(r) :: { number }
			for s = 1, n do
				sweepL += spL[s] * dt
				sweepR += spR[s] * dt
			end
			if sweepL < Lint.RULES.mirroring.sweep or sweepR < Lint.RULES.mirroring.sweep then
				return
			end
			pairsChecked += 1
			local lag, corr = bestLag(magL, magR, -2, 2)
			if median(diffs) < Lint.RULES.mirroring.within and corr > Lint.RULES.mirroring.corr and lag ~= nil and math.abs(lag :: number) * dt < 0.5 * frame30 then
				mirrored += 1
			end
		end
		local function bySide(list: { Anatomy.Chain }): (Anatomy.Chain?, Anatomy.Chain?)
			local l, r = nil, nil
			for _, c in list do
				if c.side < 0 and not l then
					l = c
				elseif c.side > 0 and not r then
					r = c
				end
			end
			return l, r
		end
		local la, ra = bySide(a.arms)
		if la and ra then
			checkPair(la.movable[1], ra.movable[1])
			checkPair(la.movable[2], ra.movable[2])
		end
		-- legs held by IK to planted feet mirror whenever the body moves straight; only keyed
		-- legs say anything about the author's choices
		local ll, rl = bySide(a.legs)
		local plantedLegs: { [string]: any } = info.plantedLegs or {}
		if ll and rl and not plantedLegs[ll.name] and not plantedLegs[rl.name] then
			checkPair(ll.movable[1], rl.movable[1])
		end
		if mirrored > 0 then
			report(
				"mirroring",
				string.format(
					"%d left/right pair(s) move as exact mirrors at the same moment. Symmetry reads as stiff: let one side lead and the other follow 2-4 frames later in a slightly different shape (the mirror pass does this unless the clip says symmetric = true)",
					mirrored
				)
			)
		end
	end

	-- Frozen holds: only for bodies with something that breathes (a head, a chest, arms, a tail,
	-- an accessory). A jointless egg sitting still is simply sitting still.
	local breathes = a.head ~= nil or (a.chest ~= nil and a.chest ~= a.body) or #a.arms > 0 or #a.tails > 0 or #a.wings > 0
	for _, c in a.others do
		if not c.digit and #c.movable > 0 then
			breathes = true
		end
	end
	if n >= 3 and breathes then
		local still = Lint.RULES["frozen-hold"]
		local run, runStart = 0, 1
		local reported = false
		for s = 2, n do
			local quiet = true
			for c = 1, b.nch do
				if m.speed[c][s] > still.angular then
					quiet = false
					break
				end
			end
			if quiet then
				local rv = M.vdist(m.root[s].p, m.root[s - 1].p) / dt
				if rv > still.root * U then
					quiet = false
				end
			end
			if quiet then
				if run == 0 then
					runStart = s
				end
				run += 1
				if not reported and run * dt >= still.seconds then
					reported = true
					report(
						"frozen-hold",
						string.format(
							"everything stops dead for %.2f s or more from %.2f s. Still people still drift (head ~1 degree, hands a few cm): keep the drift pass on, or key a slow weight shift",
							still.seconds,
							(runStart - 1) * dt
						),
						(runStart - 1) * dt
					)
				end
			else
				run = 0
			end
		end
	end

	-- Straight paths of hands, head, props (and feet outside gaits).
	do
		for _, e in m.effectors do
			if e.kind == "foot" and isGait then
				continue
			end
			if e.kind == "tail" then
				continue
			end
			local sp = pointSpeed(e.pos, dt)
			local peak = 0
			for _, v in sp do
				peak = math.max(peak, v)
			end
			local floor = math.max(1.5 * U, 0.2 * peak)
			local minLen = math.max(4, math.floor(4 * frame30 / dt + 0.5))
			local s = 1
			local flagged = false
			while s <= n and not flagged do
				if sp[s] > floor then
					local a0 = s
					while s <= n and sp[s] > floor do
						s += 1
					end
					local b0 = s - 1
					if b0 - a0 + 1 >= minLen then
						local p0, p1 = e.pos[math.max(a0 - 1, 1)], e.pos[b0]
						local chord = M.vdist(p0, p1)
						if chord >= Lint.RULES["straight-path"].chord * U then
							local dir = M.vnorm(M.vsub(p1, p0))
							local dev = 0
							for i = a0, b0 do
								dev = math.max(dev, M.vlen(M.vreject(M.vsub(e.pos[i], p0), dir)))
							end
							if dev < Lint.RULES["straight-path"].deviation * chord then
								flagged = true
								report(
									"straight-path",
									string.format(
										"%s travels in a straight line from %.2f s (bow %.1f%% of a %.2f stud move). Real limbs swing in arcs (arm raises bow ~22%%, punches 6-12%%): add a breakdown key off the straight line, or use reach so the arcs pass bows it",
										e.name,
										(a0 - 1) * dt,
										100 * dev / math.max(chord, 1e-9),
										chord
									),
									(a0 - 1) * dt
								)
							end
						end
					end
				else
					s += 1
				end
			end
		end
	end

	-- Strikes: the fastest non-head end point, measured, then weight, wind-up, kinetic chain and recovery.
	if not isGait and not b.loop then
		local best, bestPeak, bestAt = nil, 0, 1
		local bestSp: { number } = {}
		for _, e in m.effectors do
			if e.kind == "head" or e.kind == "tail" then
				continue
			end
			local sp = pointSpeed(e.pos, dt)
			for s = 1, n do
				if sp[s] > bestPeak then
					best, bestPeak, bestAt, bestSp = e, sp[s], s, sp
				end
			end
		end
		if best and bestPeak > 2 * H then
			local sp = bestSp
			-- start: back from the peak while above 12%, stopping early at a low dip
			local st = bestAt
			while st > 1 and sp[st - 1] > 0.12 * bestPeak do
				if sp[st - 1] < 0.35 * bestPeak and sp[st - 1] <= sp[st] and st - 2 >= 1 and sp[st - 2] > sp[st - 1] then
					break
				end
				st -= 1
			end
			-- end: forward until it stops dropping and is below half the peak
			local en = bestAt
			while en < n and (sp[en + 1] < sp[en] or sp[en] >= 0.5 * bestPeak) do
				en += 1
			end
			local strikeT = (en - st) * dt
			local dir = M.vnorm(M.vsub(best.pos[en], best.pos[st]))
			local quiet = math.max(0.06 * bestPeak, 0.5 * U)
			-- follow-through, hold, recovery
			local f = en
			while f < n and sp[f + 1] > quiet and M.vdot(M.vsub(best.pos[f + 1], best.pos[f]), dir) > 0 do
				f += 1
			end
			local h = f
			while h < n and sp[h + 1] <= quiet do
				h += 1
			end
			local r = h
			local calm = 0
			while r < n and calm < 4 do
				r += 1
				if sp[r] <= quiet then
					calm += 1
				else
					calm = 0
				end
			end
			local recoveryT = (r - h) * dt
			-- weight: body drop and travel around the strike
			local w0 = math.max(1, st - math.floor(0.6 / dt))
			local startBody = m.body[st]
			local lowest = startBody.y
			local travel = 0
			for s = w0, en do
				lowest = math.min(lowest, m.body[s].y)
				local d = m.body[s]
				local dx, dz = d.x - m.body[w0].x, d.z - m.body[w0].z
				travel = math.max(travel, math.sqrt(dx * dx + dz * dz))
			end
			local drop = startBody.y - lowest
			if bestPeak > Lint.RULES["no-body-commitment"].strike * H then
				if drop < Lint.RULES["no-body-commitment"].drop * H and travel < Lint.RULES["no-body-commitment"].travel * H then
					report(
						"no-body-commitment",
						string.format(
							"%s strikes at %.1f hip heights/s while the body drops %.3f and travels %.3f studs. Punches drop the pelvis ~8%% of hip height and carry it forward: key the hips down and forward into the strike",
							best.name,
							bestPeak / H,
							drop,
							travel
						),
						(bestAt - 1) * dt
					)
				end
				-- wind-up: pull-back along the strike direction in the 0.6 s before it starts
				local pull = 0
				for s = w0, st do
					local back = -M.vdot(M.vsub(best.pos[s], best.pos[w0]), dir)
					pull = math.max(pull, back)
				end
				local turned = false
				for _, k in { a.body, a.chest } do
					local spk = chanSpeed(k)
					if spk then
						for s = w0, st do
							if (spk :: { number })[s] > 60 then
								turned = true
							end
						end
					end
				end
				if (pull < Lint.RULES["no-wind-up"].pullBack * H and drop < Lint.RULES["no-wind-up"].drop * H and not turned) or (st - 1) * dt <= 0.05 then
					report(
						"no-wind-up",
						string.format(
							"%s's strike starts with nothing loading it (pull-back %.3f studs, no hip dip or torso turn before %.2f s). Load in the 0.6 s before: dip the hips, counter-turn the torso, or draw the limb back; 0.07-0.1 s for a light player attack, 0.34 s or more for an NPC's. Reactions and blocks can waive this",
							best.name,
							pull,
							(st - 1) * dt
						),
						(st - 1) * dt
					)
				end
			end
			if bestPeak > Lint.RULES["arm-leads"].strike * H then
				local lateBoth = true
				local any = false
				for _, k in { a.body, a.chest } do
					local spk = chanSpeed(k)
					if spk then
						local pk, pat = 0, 0
						for s = math.max(1, st - math.floor(0.25 / dt)), math.min(n, en + 2) do
							if (spk :: { number })[s] > pk then
								pk, pat = (spk :: { number })[s], s
							end
						end
						if pk > 60 then
							any = true
							if pat <= bestAt then
								lateBoth = false
							end
						end
					end
				end
				if any and lateBoth then
					report(
						"arm-leads",
						"the hips and chest peak after the striking hand: force should travel up from the ground. Key the pelvis first, the chest 1-2 frames later and the limb last (pelvis ~50 ms, shoulders ~35 ms ahead of the hand)",
						(bestAt - 1) * dt
					)
				end
			end
			if r >= n and calm < 4 then
				recoveryT = (n - h) * dt
			end
			if strikeT > 0 and recoveryT < Lint.RULES["rushed-recovery"].ratio * strikeT then
				report(
					"rushed-recovery",
					string.format(
						"recovery %.2f s after a %.2f s strike: snapping back reads weightless. Recover for 1.1-2.6x the strike time at about half its speed; for a player move, mark where control returns instead of cutting the recovery",
						recoveryT,
						strikeT
					),
					(h - 1) * dt
				)
			end
		end
	end

	-- Gaits: bob, slide, symmetry.
	if isGait and #a.legs > 0 and info.footDown then
		local footDown = info.footDown :: { { boolean } }
		local moving: { number } = {}
		local cruise = info.speed or 0
		local spd: { number } = table.create(n, 0)
		for s = 2, n do
			local dx = m.root[s].p.x - m.root[s - 1].p.x
			local dz = m.root[s].p.z - m.root[s - 1].p.z
			spd[s] = math.sqrt(dx * dx + dz * dz) / dt
		end
		for s = 1, n do
			if spd[s] > 0.8 * cruise and cruise > 0 then
				table.insert(moving, m.body[s].y)
			end
		end
		if #moving >= math.floor((info.period or 1) / dt) and b.rootMode == "world" then
			local lo, hi = math.huge, -math.huge
			for _, y in moving do
				lo = math.min(lo, y)
				hi = math.max(hi, y)
			end
			local bob = hi - lo
			local isRun = info.gait == "run" or info.gait == "gallop" or (info.plan and info.plan.flight)
			table.insert(findings, {
				rule = "hip-bob",
				severity = "info",
				message = string.format("body bob %.3f studs peak to peak (%.1f%% of hip height) while cruising", bob, 100 * bob / H),
			})
			local floor = if isRun then Lint.RULES["gliding-gait"].run else Lint.RULES["gliding-gait"].walk
			local rigid = info.plan and info.plan.rigid
			if not rigid and bob < floor * H and (info.gait == "walk" or info.gait == "run") and not waive["gliding-gait"] then
				report(
					"gliding-gait",
					string.format(
						"the body glides: %.1f%% of hip height of bob. Walks dip about 4%% of hip height just after each footfall, runs 10-12%%: keep bob at 1 or more",
						100 * bob / H
					)
				)
			end
		end
		-- foot slide: a planted foot (down for 0.1 s or more) that drifts
		local worst, worstLeg, worstAt = 0, 0, 0
		for i, leg in a.legs do
			if leg.rigid then
				continue
			end
			local e: any = nil
			for _, ef in m.effectors do
				if ef.kind == "foot" and ef.name == leg.name then
					e = ef
				end
			end
			if not e or not footDown[i] then
				continue
			end
			-- an in-place loop runs on a treadmill: its planted feet travel back at the loop's
			-- speed, and only what is left after adding that back is a slide
			local treadmill = b.loop and b.rootMode == "offset" and (info.speed or 0) > 0
			local fwd = M.qrot(M.qaxis(M.UP, rig.facing), M.FORWARD)
			local function at(k: number): V3
				local p = e.pos[k]
				if treadmill then
					return M.vmad(p, fwd, (info.speed :: number) * (k - 1) * dt)
				end
				return p
			end
			local s = 1
			while s <= n do
				if footDown[i][s] then
					local a0 = s
					while s <= n and footDown[i][s] do
						s += 1
					end
					local b0 = s - 1
					if (b0 - a0) * dt >= Lint.RULES["foot-slide"].hold then
						local anchor = at(a0)
						for k = a0, b0 do
							local d = M.vdist(at(k), anchor)
							if d > worst then
								worst, worstLeg, worstAt = d, i, k
							end
						end
					end
				else
					s += 1
				end
			end
		end
		if worst > Lint.RULES["foot-slide"].drift * U then
			report(
				"foot-slide",
				string.format(
					"leg %d's planted foot slides %.3f studs at %.2f s (limit %.3f). A planted foot is locked to the ground: lower the speed to what the legs carry, or let the planner add steps",
					worstLeg,
					worst,
					(worstAt - 1) * dt,
					Lint.RULES["foot-slide"].drift * U
				),
				(worstAt - 1) * dt
			)
		end
		-- symmetry of a two-legged gait: equal strides, half a cycle apart. Measured on the feet
		-- (how far each runs ahead of and behind the hips), which reads the same for a thigh and
		-- shin, a pendulum peg or a five-bone vine.
		if (info.gait == "walk" or info.gait == "run") and #a.legs == 2 and info.period then
			local fwdAxis = M.qrot(M.qaxis(M.UP, rig.facing), M.FORWARD)
			local series: { { number } } = {}
			local swings: { number } = {}
			for li, leg in a.legs do
				local e: any = nil
				for _, ef in m.effectors do
					if ef.kind == "foot" and ef.name == leg.name then
						e = ef
					end
				end
				local list: { number } = {}
				if e then
					for s = 1, n do
						local local_ = M.qinvrot(m.root[s].q, M.vsub(e.pos[s], m.root[s].p))
						table.insert(list, M.vdot(local_, fwdAxis))
					end
				end
				series[li] = list
			end
			local from = math.floor(n * 0.25)
			local to = math.floor(n * 0.85)
			-- only while walking straight and not looking about: a turn or a turned body makes
			-- the feet's paths differ for good reason
			local steady: { boolean } = table.create(n, false)
			for k = 2, n do
				local y0 = M.yawOf(M.qrot(m.root[k - 1].q, M.FORWARD))
				local y1 = M.yawOf(M.qrot(m.root[k].q, M.FORWARD))
				local turning = math.abs(M.wrapAngle(y1 - y0)) / dt > math.rad(15)
				local looking = info.lookWeights and (info.lookWeights[k] or 0) > 0.02
				steady[k] = not turning and not looking
			end
			for li = 1, 2 do
				local list = series[li]
				local lo, hi = math.huge, -math.huge
				local mean, cnt = 0, 0
				for k = from, math.min(to, #list) do
					if steady[k] then
						lo = math.min(lo, list[k])
						hi = math.max(hi, list[k])
						mean += list[k]
						cnt += 1
					end
				end
				mean = if cnt > 0 then mean / cnt else 0
				for k = 1, #list do
					list[k] -= mean
				end
				swings[li] = if hi > lo then hi - lo else 0
			end
			local big = math.max(swings[1], swings[2])
			local small = math.min(swings[1], swings[2])
			local rule = Lint.RULES["gait-symmetry"]
			local steadyCount = 0
			for k = from, to do
				if steady[k] then
					steadyCount += 1
				end
			end
			if big > 0.05 * U and #series[1] == n and #series[2] == n and steadyCount * dt >= 1.5 * (info.period :: number) then
				if small < rule.ratio * big then
					report("gait-symmetry", string.format("the feet stride unequally (%.2f and %.2f studs): one leg works harder than the other", swings[1], swings[2]))
				else
					local period = info.period :: number
					local steps = math.max(2, math.floor(period / dt + 0.5))
					local bestLagS, bestR = 0, -math.huge
					for lag = 0, steps - 1 do
						local sum, cnt = 0, 0
						for k = from, to - lag do
							if steady[k] and steady[k + lag] then
								sum += series[1][k] * series[2][k + lag]
								cnt += 1
							end
						end
						if cnt > 0 and sum / cnt > bestR then
							bestLagS, bestR = lag, sum / cnt
						end
					end
					local share = bestLagS / steps
					if share < rule.lo or share > rule.hi then
						report(
							"gait-symmetry",
							string.format("the feet are %.0f%% of a cycle apart, not half: a limp. Give the two legs phases half a cycle apart", 100 * share)
						)
					end
				end
			end
		end
	end

	-- Slither: a body waving too little to read as a snake from where the audience stands.
	if isGait and info.mode == "slither" and b.rootMode == "world" then
		local L = math.max(a.length, 1e-6)
		local body: { number } = table.clone(a.spine)
		for _, c in a.tails do
			for _, k in c.joints do
				table.insert(body, k)
			end
		end
		local w = math.max(1, math.floor(0.25 / dt + 0.5))
		local peak, seen = 0, 0
		for s = 1 + w, n - w do
			local r0, r1 = m.root[s - w].p, m.root[s + w].p
			local dx, dz = r1.x - r0.x, r1.z - r0.z
			local len = math.sqrt(dx * dx + dz * dz)
			-- only while cruising: across the head's own line of travel
			if len > 1e-6 and len > (info.speed or 0) * w * dt then
				seen += 1
				local nx, nz = -dz / len, dx / len
				local hp = m.root[s].p
				for _, k in body do
					local p = m.frames[s][k].p
					peak = math.max(peak, math.abs((p.x - hp.x) * nx + (p.z - hp.z) * nz))
				end
			end
		end
		local rule = Lint.RULES["flat-slither"]
		if seen > 0 and #body >= 2 and peak < rule.share * L then
			report(
				"flat-slither",
				string.format(
					"the body swings at most %.2f studs off the head's line (%.1f%% of its %.2f-stud length): it reads as a stick sliding, not a snake. A slither is a clear S: raise `wave` (38 degrees by default) or check the spine was read",
					peak,
					100 * peak / L,
					L
				)
			)
		end
	end

	-- Ranges and speeds.
	do
		local worstSpeed, worstJoint = 0, 0
		for c = 1, b.nch do
			for s = 1, n do
				if m.speed[c][s] > worstSpeed then
					worstSpeed, worstJoint = m.speed[c][s], c
				end
			end
		end
		if worstSpeed > Lint.RULES["joint-speed"].limit then
			report(
				"joint-speed",
				string.format(
					"%s turns at %.0f degrees/s (limit 2,500; Roblox's fastest pack joint is ~2,100). Spread the move over another frame or two",
					rig.joints[b.joints[worstJoint]].name,
					worstSpeed
				)
			)
		end
		local tol = Lint.RULES["joint-range"].tolerance / DEG
		for c = 1, b.nch do
			local k = b.joints[c]
			local lim = rig.joints[k].limits
			if lim then
				for s = 0, n - 1 do
					local rx, ry, rz = M.qtoeuler(Baked.get(b, s, c).q)
					if
						rx < lim.min.x - tol
						or rx > lim.max.x + tol
						or ry < lim.min.y - tol
						or ry > lim.max.y + tol
						or rz < lim.min.z - tol
						or rz > lim.max.z + tol
					then
						report("joint-range", string.format("%s leaves its declared range at %.2f s", rig.joints[k].name, s * dt), s * dt)
						break
					end
				end
			end
		end
	end

	-- Root drift (clips that should end where they began).
	if not isGait and not b.loop and not b.travel then
		local stray, final = 0, M.vlen(m.root[n].p)
		for s = 1, n do
			stray = math.max(stray, M.vlen(m.root[s].p))
		end
		if stray > Lint.RULES["root-drift"].stray * H or final > Lint.RULES["root-drift"].finish * H then
			report(
				"root-drift",
				string.format(
					"the body strays %.2f studs and ends %.2f from where it began: when the clip stops it pops back. Bring it home, or mark the clip travel = true and move the model to the end pose when it finishes",
					stray,
					final
				)
			)
		end
	end

	-- Loop seams.
	if b.loop and n >= 3 then
		local bad: { string } = {}
		for c = 1, b.nch do
			local q0 = Baked.get(b, 0, c).q
			local qa = Baked.get(b, n - 2, c).q
			local q1 = Baked.get(b, 1, c).q
			local qb = Baked.get(b, math.max(n - 3, 0), c).q
			-- the motion just before and just after the seam, not across it
			local step = math.max(M.qdiffAngle(qb, qa), M.qdiffAngle(q0, q1)) * DEG
			-- the last sample repeats the first; the seam is between n-2 and 0
			local gap = M.qdiffAngle(qa, q0) * DEG
			if gap > math.max(Lint.RULES["loop-seam"].degrees, 6 * step) then
				table.insert(bad, rig.joints[b.joints[c]].name)
			end
		end
		local r0, ra = m.root[1].p, m.root[n - 1].p
		local rootGap = M.vdist(r0, ra)
		local rootStep = math.max(M.vdist(m.root[math.max(n - 2, 1)].p, m.root[n - 1].p), M.vdist(m.root[1].p, m.root[2].p))
		if rootGap > math.max(Lint.RULES["loop-seam"].root * H, 6 * rootStep) then
			table.insert(bad, "root")
		end
		if #bad > 0 then
			report("loop-seam", string.format("the loop jumps where it wraps (%s): the last pose must flow into the first", table.concat(bad, ", ", 1, math.min(#bad, 4))))
		end
	end

	-- Into the ground: feet, and the body itself.
	do
		local ground = if b.rootMode == "world" and info.ground then info.ground else (m.root[1].p.y + rig.ground - (if b.rootMode == "world" then 0 else m.root[1].p.y))
		local groundFn = info.groundFn
		local depthLimit = Lint.RULES["ground-penetration"].depth * U
		local worst, what, at = 0, "", 0
		for _, e in m.effectors do
			if e.kind == "foot" then
				for s = 1, n do
					local p = e.pos[s]
					local g = ground
					if groundFn then
						local ok, y = pcall(groundFn, p.x, p.z)
						if ok and type(y) == "number" then
							g = y
						end
					end
					local d = g - p.y
					if d > worst then
						worst, what, at = d, e.name, s
					end
				end
			end
		end
		if worst > depthLimit then
			report("ground-penetration", string.format("%s goes %.3f studs into the ground at %.2f s", what, worst, (at - 1) * dt), (at - 1) * dt)
		end
	end

	-- Jitter: fast back-and-forth.
	do
		local rule = Lint.RULES.jitter
		local window = rule.window
		local flagged: { string } = {}
		local firstAt: number? = nil
		-- a buzz is small and fast: reversals close together with little travel between them.
		-- Big quick swings (a hop's leg, a stamp) reverse fast too, but sweep far between turns.
		local function scan(name: string, vel: { V3 }, threshold: number, sweepLimit: number)
			local times: { number } = {}
			local swept: { number } = {}
			local travel = 0
			for s = 2, n do
				travel += M.vlen(vel[s]) * dt
				if s >= 3 then
					local a0, b0 = vel[s - 1], vel[s]
					if M.vlen(a0) > threshold and M.vlen(b0) > threshold and M.vdot(a0, b0) < 0 then
						table.insert(times, (s - 1) * dt)
						table.insert(swept, travel)
						travel = 0
					end
				end
			end
			for i = rule.reversals, #times do
				local first = i - rule.reversals + 1
				if times[i] - times[first] < window then
					local small = true
					for j = first + 1, i do
						if swept[j] > sweepLimit then
							small = false
							break
						end
					end
					if small then
						table.insert(flagged, name)
						firstAt = firstAt or times[first]
						return
					end
				end
			end
		end
		for c = 1, b.nch do
			scan(rig.joints[b.joints[c]].name, m.vel[c], rule.speed / DEG, rule.sweep / DEG)
		end
		for _, e in m.effectors do
			local v: { V3 } = table.create(n)
			v[1] = M.ZERO
			for s = 2, n do
				v[s] = M.vmul(M.vsub(e.pos[s], e.pos[s - 1]), 1 / dt)
			end
			scan(e.name, v, 0.5 * U, 0.04 * U)
		end
		if #flagged > 0 then
			report(
				"jitter",
				string.format(
					"%s reverse direction %d+ times inside %.2f s with only a few degrees between turns (from %.2f s): a buzz no body makes. Remove crowded keys, raise the ease, or check for fighting IK targets",
					table.concat(flagged, ", ", 1, math.min(#flagged, 4)),
					rule.reversals,
					window,
					firstAt or 0
				),
				firstAt
			)
		end
	end

	-- Twist: turning about a limb's own long axis without a reason.
	do
		local rule = Lint.RULES.twist
		local worst, worstName, worstAt = 0, "", 0
		local spinName: string? = nil
		-- limbs only: a torso turning about the spine and a head turning to look are how bodies
		-- wind up and attend, not twists
		local limb: { [number]: boolean } = {}
		-- (a foot or a paw at a leg's end is left out: it turns to face the way the next step
		-- goes, about an axis that for a short downward stub is its own)
		for _, c in a.chains do
			if c.kind == "arm" or c.kind == "leg" or c.kind == "tail" or c.kind == "wing" then
				for idx, k in c.movable do
					local isFoot = c.kind == "leg" and idx == #c.movable and #c.movable >= 2 and (c.ik == "twoFoot" or c.ik == "chainFoot" or c.ik == "aimFoot" or rig.joints[k].length < 0.3 * math.max(c.limbReach, 1e-6))
					if not isFoot then
						limb[k] = true
					end
				end
			end
		end
		for c = 1, b.nch do
			local k = b.joints[c]
			local j = rig.joints[k]
			if j.length <= 1e-6 or not limb[k] then
				continue
			end
			local axis = M.vnorm(j.tip)
			local prevTw = 0
			for s = 0, n - 1 do
				local q = Baked.get(b, s, c).q
				local tw = M.qtwistAngle(q, axis)
				local deg = math.abs(tw) * DEG
				if deg > worst then
					worst, worstName, worstAt = deg, j.name, s
				end
				if s > 0 then
					local rate = math.abs(M.wrapAngle(tw - prevTw)) * DEG / dt
					local sw = M.qswing(q, axis)
					local swPrev = M.qswing(Baked.get(b, s - 1, c).q, axis)
					local swingRate = M.qdiffAngle(sw, swPrev) * DEG / dt
					if rate > rule.spin and swingRate < 0.5 * rate and not spinName then
						spinName = j.name
					end
				end
				prevTw = tw
			end
		end
		if worst > rule.degrees then
			report(
				"twist",
				string.format(
					"%s turns %.0f degrees about its own long axis (at %.2f s). Limbs barely twist; this reads as a random twist: key the limb's swing instead, or waive if it is meant (a wrist turning a key)",
					worstName,
					worst,
					worstAt * dt
				),
				worstAt * dt
			)
		elseif spinName then
			report("twist", string.format("%s spins about its own axis faster than %d degrees/s while hardly moving otherwise", spinName :: string, rule.spin))
		end
		-- the body turning away from where a gait is going
		if isGait and b.rootMode == "world" and info.plan then
			local worstYaw = 0
			-- where it travels over a whole stride: a waddle's side-to-side sway is not a change
			-- of course
			local w = math.max(1, math.floor(0.5 * (info.period or 0) / dt + 0.5))
			for s = 1 + w, n - w do
				local f = m.frames[s]
				local bodyQ = if a.body then f[a.body :: number].q else m.root[s].q
				local fwd = M.qrot(bodyQ, M.qrot(M.qaxis(M.UP, rig.facing), M.FORWARD))
				local dx = (m.root[s + w].p.x - m.root[s - w].p.x) / (2 * w)
				local dz = (m.root[s + w].p.z - m.root[s - w].p.z) / (2 * w)
				local looking = info.lookWeights and (info.lookWeights[s] or 0) > 0.05
				if not looking and dx * dx + dz * dz > (0.5 * (info.speed or 0) * dt) ^ 2 and (info.speed or 0) > 0 then
					local heading = math.atan2(-dx, -dz)
					local yaw = M.yawOf(fwd)
					worstYaw = math.max(worstYaw, math.abs(M.wrapAngle(yaw - heading)) * DEG)
				end
			end
			if worstYaw > 30 then
				report("twist", string.format("the body faces up to %.0f degrees away from where it travels", worstYaw))
			end
		end
	end

	-- Pops: a sudden change of speed between two frames.
	do
		local rule = Lint.RULES.pops
		local exempt: { number } = {}
		for _, mk in b.markers do
			local lower = string.lower(mk.name)
			if string.find(lower, "hit", 1, true) or string.find(lower, "impact", 1, true) or string.find(lower, "contact", 1, true) then
				table.insert(exempt, mk.time)
			end
		end
		local function isExempt(t: number): boolean
			for _, e in exempt do
				if math.abs(e - t) <= 2 * frame30 then
					return true
				end
			end
			return false
		end
		local popped: { string } = {}
		local popAt: number? = nil
		local limit = rule.jump / DEG
		for c = 1, b.nch do
			local vel = m.vel[c]
			local jumps: { number } = table.create(n, 0)
			for s = 3, n do
				jumps[s] = M.vlen(M.vsub(vel[s], vel[s - 1]))
			end
			for s = 4, n - 2 do
				local j = jumps[s]
				local big = math.max(M.vlen(vel[s]), M.vlen(vel[s - 1]))
				if j > limit and j > rule.share * big then
					-- a kink: one jump with calm on both sides. A spike (a step in position):
					-- two big opposite jumps side by side with calm around them. A fast but
					-- smooth start (a strike's) changes speed over several frames, and is neither.
					local kink = j > rule.isolation * math.max(jumps[s - 1] or 0, jumps[s + 1] or 0, 1e-9)
					local d1 = M.vsub(vel[s], vel[s - 1])
					local d2 = M.vsub(vel[s + 1], vel[s])
					local spike = M.vdot(d1, d2) < 0
						and math.min(j, jumps[s + 1] or 0) > rule.isolation * math.max(jumps[s - 1] or 0, jumps[s + 2] or 0, 1e-9)
					if (kink or spike) and not isExempt((s - 1) * dt) then
						table.insert(popped, rig.joints[b.joints[c]].name)
						popAt = popAt or (s - 1) * dt
						break
					end
				end
			end
		end
		-- the root moving by itself
		local rootJ: { number } = table.create(n, 0)
		local rv: { V3 } = table.create(n)
		rv[1] = M.ZERO
		for s = 2, n do
			rv[s] = M.vmul(M.vsub(m.root[s].p, m.root[s - 1].p), 1 / dt)
		end
		for s = 3, n do
			rootJ[s] = M.vlen(M.vsub(rv[s], rv[s - 1]))
		end
		for s = 4, n - 2 do
			local around = math.max(rootJ[s - 1], rootJ[s + 1], 1e-9)
			local spike = math.min(rootJ[s], rootJ[s + 1]) > rule.isolation * math.max(rootJ[s - 1], rootJ[s + 2], 1e-9)
			if rootJ[s] > 4 * U and (rootJ[s] > rule.isolation * around or spike) and not isExempt((s - 1) * dt) then
				table.insert(popped, "root")
				popAt = popAt or (s - 1) * dt
				break
			end
		end
		if #popped > 0 then
			report(
				"pops",
				string.format(
					"%s jump in speed between two frames (first at %.2f s): a pop. Ease into and out of keys (no 'constant' or 'linear' between moving keys), or mark a deliberate impact with a 'hit' marker",
					table.concat(popped, ", ", 1, math.min(#popped, 4)),
					popAt or 0
				),
				popAt
			)
		end
	end

	-- Even key timing and default linear (authored clips).
	if not isGait then
		local kt = b.keyTimes
		if #kt >= Lint.RULES["even-key-timing"].keys then
			local gaps: { number } = {}
			for i = 2, #kt do
				table.insert(gaps, kt[i] - kt[i - 1])
			end
			local mean = 0
			for _, g in gaps do
				mean += g
			end
			mean /= #gaps
			local var = 0
			for _, g in gaps do
				var += (g - mean) ^ 2
			end
			local cv = if mean > 0 then math.sqrt(var / #gaps) / mean else 0
			if cv < Lint.RULES["even-key-timing"].cv then
				report(
					"even-key-timing",
					string.format(
						"%d keys spaced evenly (every %.2f s): metronome timing. Alternate a fast hit with slower set-ups and settles",
						#kt,
						mean
					)
				)
			end
		end
		if b.linearKeys > Lint.RULES["default-linear"].keys then
			report(
				"default-linear",
				string.format(
					"%d keys use linear easing: full speed at both ends and a kink at every key, the Animation Editor's default. Use the default ease (or 'inOut'); never the legacy cubic in/out, which plays backwards on Humanoids",
					b.linearKeys
				)
			)
		end
	end

	local order = { fix = 1, consider = 2, info = 3 }
	table.sort(findings, function(x, y)
		if x.severity ~= y.severity then
			return order[x.severity] < order[y.severity]
		end
		return (x.time or 0) < (y.time or 0)
	end)
	return findings, m
end

-- Findings as lines: "[fix] jitter: ...".
function Lint.format(findings: { Finding }): string
	local lines: { string } = {}
	for _, f in findings do
		table.insert(lines, string.format("[%s] %s: %s", f.severity, f.rule, f.message))
	end
	return table.concat(lines, "\n") :: string
end

-- Counts by severity.
function Lint.count(findings: { Finding }): (number, number, number)
	local fix, consider, info = 0, 0, 0
	for _, f in findings do
		if f.severity == "fix" then
			fix += 1
		elseif f.severity == "consider" then
			consider += 1
		else
			info += 1
		end
	end
	return fix, consider, info
end

return Lint
