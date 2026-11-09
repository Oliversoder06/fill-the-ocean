--!strict
--[[
	GaitPlan: which feet go down when, for any number of legs, and how fast.

	Patterns by leg count (each leg's phase is when it touches down, as a fraction of a cycle;
	the duty factor is the share of a cycle a foot spends on the ground):
		1      pogo: one leg, a hop every cycle
		2      walk (left, right half a cycle apart) or run (the same with flight)
		3      rotating tripod: one leg at a time, round the body
		4      walk (hind left, fore left, hind right, fore right), trot (diagonal pairs), gallop
		6      alternating tripod: front and back of one side with the middle of the other
		8+     metachronal ripple: a wave from the back to the front, the sides half a cycle apart
		other  general: phases spread round the body with every mirror pair half a cycle apart;
		       several candidate orders are scored on how many feet stay down and how well the
		       body's centre stays inside them, and the best kept. The duty factor is then raised
		       until enough feet are down at every moment.

	Tempo comes from leg length by dynamic similarity: the Froude number Fr = v^2 / (g * H)
	(H = hip height) picks the gait, and the relative stride is about 2.3 * Fr^0.3 hip heights
	(Alexander's fit across animals), so a big creature strides long and slow, a small one short
	and quick, both at the same Fr. g is the game's gravity, capped at Roblox's own figure for
	Earth gravity at 1 stud = 28 cm (35 studs/s^2): the default 196.2 would make every leg step
	about 2.4 times faster than it reads as real. Airborne phases still use the full gravity.

	Cadence is held between readable bounds (no faster than about 5 cycles a second at 60 fps);
	when the requested speed needs more than the legs can reach, stride grows through flight
	time (a bound) rather than feet sliding.
]]

local M = require("./Math")
local Anatomy = require("./Anatomy")

local GaitPlan = {}

export type Plan = {
	kind: string,
	legs: number,
	speed: number,
	froude: number,
	period: number,
	duty: number,
	-- the lowest duty factor that keeps enough feet down with these phases
	dutyFloor: number,
	-- how far a planted foot may travel under its hip, and the crouch that makes room for it
	maxStance: number,
	crouch: number,
	-- a speed this body walks comfortably (the default when none is given)
	comfort: number,
	-- the requested speed is more than the legs can carry without overstretching
	overreach: boolean,
	phases: { number },
	stride: number,
	stepHeight: number,
	-- peak-to-peak body bob for supported gaits (flight gaits are ballistic instead), studs
	bob: number,
	-- where in a stance the body is lowest (0 = touchdown, 1 = lift-off)
	lowPoint: number,
	lean: number,
	flight: boolean,
	minSupport: number,
	margin: number,
	rigid: boolean,
	runFactor: number,
	reasons: { string },
}

export type Options = {
	speed: number?,
	gravity: number?,
	gaitGravity: number?,
	style: string?,
	duty: number?,
	period: number?,
	phases: { number }?,
	stepHeight: number?,
	bob: number?,
}

GaitPlan.EARTH = 35 -- studs/s^2: 9.81 m/s^2 at 1 stud = 0.28 m (Roblox's units page)
GaitPlan.GAME = 196.2 -- Workspace.Gravity's default
GaitPlan.MIN_PERIOD = 0.2

function GaitPlan.gaitGravity(opts: Options?): number
	local o: Options = opts or {}
	if type(o.gaitGravity) == "number" and M.finite(o.gaitGravity) and o.gaitGravity > 0 then
		return o.gaitGravity
	end
	local g = if type(o.gravity) == "number" and M.finite(o.gravity) and o.gravity > 0 then o.gravity else GaitPlan.GAME
	return math.min(g, GaitPlan.EARTH)
end

function GaitPlan.gravity(opts: Options?): number
	local o: Options = opts or {}
	if type(o.gravity) == "number" and M.finite(o.gravity) and o.gravity > 0 then
		return o.gravity
	end
	return GaitPlan.GAME
end

-- How many legs are down at the worst moment of a cycle, sampled finely.
function GaitPlan.support(phases: { number }, duty: number): number
	local n = #phases
	if n == 0 then
		return 0
	end
	local worst = n
	for s = 0, 359 do
		local phi = s / 360
		local down = 0
		for _, p in phases do
			if M.frac(phi - p) < duty then
				down += 1
			end
		end
		if down < worst then
			worst = down
		end
	end
	return worst
end

-- Share of a cycle with no foot down, and how many separate flights that makes.
function GaitPlan.flightShare(phases: { number }, duty: number): (number, number)
	local n = #phases
	if n == 0 then
		return 0, 0
	end
	local samples = 240
	local airborne = 0
	local flights = 0
	local prevAir: boolean? = nil
	local firstAir: boolean? = nil
	for s = 0, samples - 1 do
		local phi = s / samples
		local down = false
		for _, p in phases do
			if M.frac(phi - p) < duty then
				down = true
				break
			end
		end
		local air = not down
		if air then
			airborne += 1
		end
		if firstAir == nil then
			firstAir = air
		end
		if air and prevAir == false then
			flights += 1
		end
		prevAir = air
	end
	-- a flight that wraps the end of the cycle round to its start is one flight
	if firstAir and prevAir and flights == 0 then
		flights = 1
	elseif firstAir and not prevAir then
		flights += 1
	end
	return airborne / samples, flights
end

-- Signed distance from (0,0) to the convex hull of points (positive inside), in the XZ plane.
local function hullMargin(pts: { { number } }): number
	local n = #pts
	if n < 3 then
		return -math.huge
	end
	-- monotone chain hull
	local sorted = table.clone(pts)
	table.sort(sorted, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		end
		return a[2] < b[2]
	end)
	local function cross(o: { number }, a: { number }, b: { number }): number
		return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
	end
	local lower: { { number } } = {}
	for _, p in sorted do
		while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 0 do
			table.remove(lower)
		end
		table.insert(lower, p)
	end
	local upper: { { number } } = {}
	for i = #sorted, 1, -1 do
		local p = sorted[i]
		while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 0 do
			table.remove(upper)
		end
		table.insert(upper, p)
	end
	table.remove(lower)
	table.remove(upper)
	local hull: { { number } } = {}
	for _, p in lower do
		table.insert(hull, p)
	end
	for _, p in upper do
		table.insert(hull, p)
	end
	if #hull < 3 then
		return -math.huge
	end
	local margin = math.huge
	for i = 1, #hull do
		local a = hull[i]
		local b = hull[i % #hull + 1]
		local ex, ez = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(ex * ex + ez * ez)
		if len > 1e-9 then
			-- counter-clockwise hull: inside is to the left
			local d = (ex * (0 - a[2]) - ez * (0 - a[1])) / len
			if d < margin then
				margin = d
			end
		end
	end
	return margin
end

-- The worst static-stability margin across a cycle (studs; negative = the centre falls outside).
function GaitPlan.stability(anatomy: Anatomy.Anatomy, phases: { number }, duty: number): number
	local legs = anatomy.legs
	local cx, cz = 0, 0
	for _, l in legs do
		cx += l.contact.x
		cz += l.contact.z
	end
	if #legs > 0 then
		cx /= #legs
		cz /= #legs
	end
	local worst = math.huge
	for s = 0, 119 do
		local phi = s / 120
		local pts: { { number } } = {}
		for i, l in legs do
			if M.frac(phi - phases[i]) < duty then
				table.insert(pts, { l.contact.x - cx, l.contact.z - cz })
			end
		end
		local m = hullMargin(pts)
		if m < worst then
			worst = m
		end
	end
	return worst
end

-- Legs grouped by side and ordered front (index 1) to back.
local function bySide(legs: { Anatomy.Chain }): ({ number }, { number }, { number })
	local left, right, centre = {}, {}, {}
	for i, l in legs do
		if l.side < 0 then
			table.insert(left, i)
		elseif l.side > 0 then
			table.insert(right, i)
		else
			table.insert(centre, i)
		end
	end
	local function front(a: number, b: number): boolean
		local za, zb = legs[a].contact.z, legs[b].contact.z
		if math.abs(za - zb) > 1e-6 then
			return za < zb
		end
		return a < b
	end
	table.sort(left, front)
	table.sort(right, front)
	table.sort(centre, front)
	return left, right, centre
end

-- Symmetric layouts: as many left as right legs, each with a mirror partner.
local function symmetric(legs: { Anatomy.Chain }): boolean
	local left, right, centre = bySide(legs)
	if #centre > 0 or #left ~= #right then
		return false
	end
	for _, i in left do
		if not legs[i].pair then
			return false
		end
	end
	return true
end

-- Phases for a named pattern, in the anatomy's leg order.
function GaitPlan.pattern(anatomy: Anatomy.Anatomy, kind: string): { number }
	local legs = anatomy.legs
	local n = #legs
	local phases: { number } = table.create(n, 0)
	local left, right, centre = bySide(legs)
	if kind == "walk" or kind == "run" or kind == "pogo" then
		if n == 1 then
			return { 0 }
		end
		if #left == 1 and #right == 1 then
			phases[left[1]] = 0
			phases[right[1]] = 0.5
			return phases
		end
	elseif kind == "quadWalk" and #left == 2 and #right == 2 then
		-- lateral sequence: hind left, fore left, hind right, fore right
		phases[left[2]] = 0
		phases[left[1]] = 0.25
		phases[right[2]] = 0.5
		phases[right[1]] = 0.75
		return phases
	elseif kind == "trot" and #left == 2 and #right == 2 then
		phases[left[1]] = 0
		phases[right[2]] = 0
		phases[right[1]] = 0.5
		phases[left[2]] = 0.5
		return phases
	elseif kind == "gallop" and #left == 2 and #right == 2 then
		-- transverse gallop: hind pair, then fore pair, each pair slightly split
		phases[left[2]] = 0
		phases[right[2]] = 0.1
		phases[left[1]] = 0.45
		phases[right[1]] = 0.55
		return phases
	elseif kind == "tripod" and #left == #right and #centre == 0 then
		for r, i in left do
			phases[i] = if r % 2 == 1 then 0 else 0.5
		end
		for r, i in right do
			phases[i] = if r % 2 == 1 then 0.5 else 0
		end
		return phases
	elseif kind == "ripple" and #left == #right and #centre == 0 then
		local k = #left
		for r, i in left do
			-- the back leg steps first; the wave runs forward
			phases[i] = M.frac((k - r) / k)
		end
		for r, i in right do
			phases[i] = M.frac((k - r) / k + 0.5)
		end
		return phases
	end
	return GaitPlan.general(anatomy)
end

--[[
	The general solver: tries orders round the body (rotating), alternating halves and a back-to-
	front wave; pairs are always half a cycle apart. Picks the candidate keeping the most feet
	down, then the best stability margin, at a moderate duty factor.
]]
function GaitPlan.general(anatomy: Anatomy.Anatomy): { number }
	local legs = anatomy.legs
	local n = #legs
	if n == 0 then
		return {}
	end
	if n == 1 then
		return { 0 }
	end
	local cx, cz = 0, 0
	for _, l in legs do
		cx += l.contact.x
		cz += l.contact.z
	end
	cx /= n
	cz /= n
	local angleOrder: { number } = {}
	for i = 1, n do
		angleOrder[i] = i
	end
	local angles: { number } = {}
	for i, l in legs do
		angles[i] = math.atan2(l.contact.x - cx, -(l.contact.z - cz))
	end
	table.sort(angleOrder, function(a, b)
		if angles[a] ~= angles[b] then
			return angles[a] < angles[b]
		end
		return a < b
	end)
	local candidates: { { number } } = {}
	-- 1: rotating, evenly spaced
	local rot: { number } = table.create(n, 0)
	for k, i in angleOrder do
		rot[i] = (k - 1) / n
	end
	table.insert(candidates, rot)
	-- 2: alternating round the body (every other leg together)
	local alt: { number } = table.create(n, 0)
	for k, i in angleOrder do
		alt[i] = if k % 2 == 1 then 0 else 0.5
	end
	table.insert(candidates, alt)
	-- 3: a wave from back to front (by z), spread over the cycle
	local byZ: { number } = {}
	for i = 1, n do
		byZ[i] = i
	end
	table.sort(byZ, function(a, b)
		local za, zb = legs[a].contact.z, legs[b].contact.z
		if za ~= zb then
			return za > zb
		end
		return a < b
	end)
	local wave: { number } = table.create(n, 0)
	for k, i in byZ do
		wave[i] = M.frac((k - 1) * 0.5 / math.max(1, math.ceil(n / 2)))
	end
	table.insert(candidates, wave)
	-- pairs: the partner half a cycle after
	for _, c in candidates do
		local done: { [number]: boolean } = {}
		for i, l in legs do
			local p = l.pair
			if p and not done[i] and not done[p] and legs[p] then
				c[p] = M.frac(c[i] + 0.5)
				done[i] = true
				done[p] = true
			end
		end
	end
	local best, bestSupport, bestMargin = candidates[1], -1, -math.huge
	local duty = 0.75
	for _, c in candidates do
		local s = GaitPlan.support(c, duty)
		local m = if n >= 3 then GaitPlan.stability(anatomy, c, duty) else 0
		if s > bestSupport or (s == bestSupport and m > bestMargin + 1e-9) then
			best, bestSupport, bestMargin = c, s, m
		end
	end
	return best
end

-- The phase at which every leg has most recently touched down: a clean standing start.
function GaitPlan.startPhase(phases: { number }): number
	local bestPhi, bestMax = 0, math.huge
	for s = 0, 719 do
		local phi = s / 720
		local worst = 0
		for _, p in phases do
			local psi = M.frac(phi + p)
			if psi > worst then
				worst = psi
			end
		end
		if worst < bestMax - 1e-12 then
			bestPhi, bestMax = phi, worst
		end
	end
	return bestPhi
end

local function lerpClamp(a: number, b: number, t: number): number
	return a + (b - a) * M.clamp(t, 0, 1)
end

-- Duty factor for a gait kind at Froude number fr, whether it may fly, and how run-like it is.
local function dutyFor(kind: string, fr: number): (number, boolean, number)
	if kind == "pogo" then
		return 0.4, true, 1
	elseif kind == "run" then
		return lerpClamp(0.4, 0.28, (fr - 0.45) / 2.5), true, 1
	elseif kind == "walk" then
		return lerpClamp(0.66, 0.56, fr / 0.45), false, M.clamp(fr / 0.45, 0, 1) * 0.3
	elseif kind == "rotary" then
		return lerpClamp(0.82, 0.72, fr / 1.5), false, 0
	elseif kind == "gallop" then
		return lerpClamp(0.38, 0.3, (fr - 2.5) / 3), true, 1
	elseif kind == "trot" then
		local d = lerpClamp(0.55, 0.45, (fr - 0.4) / 2)
		return d, d < 0.5, 0.5
	elseif kind == "quadWalk" then
		return lerpClamp(0.8, 0.68, fr / 0.4), false, 0
	elseif kind == "tripod" then
		return lerpClamp(0.72, 0.52, fr / 1.5), false, 0
	elseif kind == "ripple" then
		return lerpClamp(0.85, 0.7, fr / 1.5), false, 0
	elseif kind == "general" then
		return lerpClamp(0.8, 0.7, fr / 1.5), false, 0
	end
	return 0, false, 0
end

-- How many feet a kind keeps down when it is not meant to fly.
local function supportNeeded(kind: string, n: number, flightOk: boolean): number
	if flightOk then
		return 0
	end
	if n == 2 then
		return 1
	elseif n == 3 then
		return 2
	elseif n >= 4 then
		return if kind == "trot" then 2 else 3
	end
	return 0
end

local function averageReach(anatomy: Anatomy.Anatomy): (number, boolean)
	local legs = anatomy.legs
	local n = #legs
	local rigid = n > 0
	local reach = 0
	for _, l in legs do
		if not l.rigid then
			rigid = false
		end
		reach += l.reach
	end
	reach = if n > 0 then reach / n else anatomy.hipHeight
	if reach < 1e-6 then
		reach = math.max(anatomy.hipHeight, 1e-3)
	end
	return reach, rigid
end

--[[
	Period, duty factor and stride for a planned gait at speed v, and whether flight had to be
	added. Cheap: the bake calls it every sample while the speed ramps, with the pattern (kind
	and phases) fixed by the plan.
]]
function GaitPlan.tempo(plan: Plan, anatomy: Anatomy.Anatomy, v: number, opts: Options?): (number, number, number, boolean, boolean)
	local o: Options = opts or {}
	local H = math.max(anatomy.hipHeight, 1e-3)
	local g = GaitPlan.gaitGravity(o)
	v = math.max(0, if M.finite(v) then v else 0)
	local fr = v * v / (g * H)
	local duty, flightOk = dutyFor(plan.kind, fr)
	if type(o.duty) == "number" and M.finite(o.duty) then
		duty = M.clamp(o.duty, 0.1, 0.95)
	end
	-- never below the floor that keeps the planned feet down (found once, in plan)
	if not flightOk and duty < plan.dutyFloor then
		duty = plan.dutyFloor
	end
	local reach, rigid = averageReach(anatomy)
	if plan.kind == "pogo" then
		--[[
			One leg hops: the rhythm comes from the hop, not from Froude. A flight rising a quarter
			of the hip height lasts sqrt(8h/g) under the game's gravity; the landing then sinks no
			deeper than 18% of the hip height, which fixes the time on the ground (a body landing
			at speed v and leaving again after Ds sinks v*Ds/4).
		]]
		local gGame = GaitPlan.gravity(o)
		local D = math.sqrt(8 * 0.25 * H / gGame)
		local vLand = gGame * D / 2
		local Ds = math.clamp(4 * 0.18 * H / math.max(vLand, 1e-6), 0.06, 0.6)
		-- faster than one hop's stance can carry: longer hops (more air), same landing
		if v > 1e-6 and v * Ds > plan.maxStance then
			Ds = math.max(0.06, plan.maxStance / v)
		end
		local period = D + Ds
		return period, Ds / period, v * period, false, false
	end
	local stride = if fr > 0 then H * M.clamp(2.3 * fr ^ 0.3, 0.6, 5) else 0
	local T0 = 2 * math.pi * math.sqrt(H / g)
	local minP = math.max(GaitPlan.MIN_PERIOD, 0.25 * T0)
	local period = if v > 1e-6 then stride / v else 0.7 * T0
	period = M.clamp(period, minP, math.max(1.5 * T0, GaitPlan.MIN_PERIOD))
	if type(o.period) == "number" and M.finite(o.period) and o.period > 0 then
		period = math.max(o.period, 0.05)
	end
	local maxStance = plan.maxStance
	local _ = reach
	local _r = rigid
	-- a foot cannot swing forward faster than about a third of its leg's pendulum period; a
	-- quicker swing snaps (and the jitter lint sees it). Trade stance share first, then cadence.
	local legLen = math.max(reach, 1e-3)
	local swingMin = math.max(0.1, 0.33 * math.pi * math.sqrt(legLen / g))
	if v > 1e-6 and (1 - duty) * period < swingMin then
		duty = math.max(plan.dutyFloor, 1 - swingMin / period)
		if (1 - duty) * period < swingMin then
			period = swingMin / math.max(1 - duty, 1e-3)
		end
	end
	-- A flight under the game's gravity rises g*D^2/8: cap each flight's height so a hop or a
	-- run never sails (a pogo up to 30% of its hip height, a run 12%, others 10%).
	local share, flights = GaitPlan.flightShare(plan.phases, duty)
	if share > 0 and flights > 0 then
		local apex = H * (if plan.kind == "pogo" then 0.3 elseif plan.kind == "run" then 0.12 else 0.1)
		local gGame = GaitPlan.gravity(o)
		local dMax = math.sqrt(8 * apex / gGame)
		local tMax = flights * dMax / share
		if period > tMax then
			period = math.max(tMax, minP)
			-- still too long in the air at the quickest readable cadence: spend longer on the ground
			local guard = 0
			while guard < 40 and duty < 0.9 do
				local sh, fl = GaitPlan.flightShare(plan.phases, duty)
				if sh <= 0 or fl == 0 or sh * period / fl <= dMax * 1.0001 then
					break
				end
				duty += 0.02
				guard += 1
			end
		end
	end
	local flew, over = false, false
	if v > 1e-6 and v * duty * period > maxStance then
		-- quicker steps first, down to the readable limit; then gaits that may leave the ground
		-- make up the distance in the air, and the others are simply asked to go too fast
		local p2 = maxStance / (v * duty)
		if p2 >= minP then
			period = p2
		else
			period = minP
			local d2 = maxStance / (v * period)
			local mayFly = plan.kind == "run" or plan.kind == "pogo" or plan.kind == "gallop" or plan.kind == "trot"
			if d2 < duty and mayFly then
				duty = math.max(0.12, d2)
				flew = true
			elseif d2 < duty then
				over = true
			end
		end
	end
	return period, duty, v * period, flew, over
end

--[[
	How far each planted foot can travel under its hip, from the rest pose: a foot already near
	full stretch at rest (splayed spider and tripod legs) gets a crouch first, then the stance
	length that keeps every leg inside 95% of its reach along the line of travel. Legs that cannot
	bend swing as pendulums through about +-28 degrees.
]]
function GaitPlan.reach(anatomy: Anatomy.Anatomy): (number, number, number, { number })
	local legs = anatomy.legs
	local H = math.max(anatomy.hipHeight, 1e-3)
	local rig = anatomy.rig
	local crouch = 0
	local entries: { { number } } = {}
	local rigidMin = math.huge
	local pulls: { number } = table.create(#legs, 1)
	for li, l in legs do
		-- a leg that does not reach the ground at rest carries nothing; it only steps along
		if l.gap > 0.05 * H then
			continue
		end
		local first = l.movable[1] or l.joints[1]
		local hip = rig.joints[first].world.p
		-- what IK actually places: the ankle for a foot-flat leg, the contact otherwise
		local point = M.vsub(l.contact, l.footVec)
		local cx, cz = point.x - hip.x, point.z - hip.z
		local h = hip.y - point.y
		-- planted feet stay inside 92% of the reach: near full stretch a knee's angle changes
		-- far faster than the foot moves, and the joint snaps at every lift-off
		local r = 0.92 * l.limbReach
		if l.rigid then
			local L = M.vdist(hip, l.contact)
			rigidMin = math.min(rigidMin, 2 * L * math.sin(math.rad(28)))
		elseif r > 1e-6 then
			table.insert(entries, { cx, cz, h, r, li })
			local ch2 = cx * cx + cz * cz
			local d0 = math.sqrt(ch2 + h * h)
			if d0 > 0.88 * r and h > 0 then
				local inner = (0.88 * r) ^ 2 - ch2
				local need = if inner > 0 then h - math.sqrt(inner) else 0.3 * h
				crouch = math.max(crouch, need)
			end
		end
	end
	crouch = math.min(crouch, 0.25 * H)
	local maxStance = math.huge
	local minReach = math.huge
	for _, e in entries do
		local cx, cz, h, r = e[1], e[2], e[3] - crouch, e[4]
		-- a leg still near full stretch once crouched (one lying flat, a starfish's arm) steps
		-- around a spot drawn in towards its hip, to give it room to move
		local dh = math.sqrt(cx * cx + cz * cz)
		local want = 0.88 * r
		if dh > 1e-6 and math.sqrt(dh * dh + h * h) > want then
			local k = math.max(math.sqrt(math.max(want * want - h * h, 0)) / dh, 0.5)
			pulls[e[5]] = k
			cx, cz = cx * k, cz * k
		end
		minReach = math.min(minReach, r)
		local inner = r * r - h * h - cx * cx
		local s = if inner > 0 then 2 * (math.sqrt(inner) - math.abs(cz)) else 0
		maxStance = math.min(maxStance, s)
	end
	if #entries > 0 then
		maxStance = math.max(maxStance, 0.15 * minReach)
	end
	if rigidMin < math.huge then
		maxStance = math.min(maxStance, rigidMin)
	end
	if maxStance == math.huge then
		maxStance = H
	end
	-- a comfortable speed: Froude 0.25, held to what the stance can carry at an easy cadence
	local g = GaitPlan.EARTH
	local T0 = 2 * math.pi * math.sqrt(H / g)
	local easy = math.max(GaitPlan.MIN_PERIOD * 1.5, 0.45 * T0)
	local comfort = math.min(math.sqrt(0.25 * g * H), maxStance / (0.7 * easy))
	return maxStance, crouch, comfort, pulls
end

--[[
	The plan at one speed. Legs that cannot bend (one joint or none) walk as pendulums: the
	planner marks them `rigid` and the body vaults over them instead of bobbing by itself.
]]
function GaitPlan.plan(anatomy: Anatomy.Anatomy, opts: Options?): Plan
	local o: Options = opts or {}
	local legs = anatomy.legs
	local n = #legs
	local H = math.max(anatomy.hipHeight, 1e-3)
	local g = GaitPlan.gaitGravity(o)
	local maxStance, crouch, comfort = GaitPlan.reach(anatomy)
	local v = if type(o.speed) == "number" and M.finite(o.speed) then math.max(0, o.speed) else comfort
	local fr = v * v / (g * H)
	local reasons: { string } = {}
	local reach, rigid = averageReach(anatomy)
	local style = if type(o.style) == "string" then o.style else "auto"
	local sym = symmetric(legs)
	local kind: string
	if n == 0 then
		kind = "none"
	elseif n == 1 then
		kind = "pogo"
		table.insert(reasons, "one leg: hops")
	elseif n == 2 then
		local run = (style == "run" or (style == "auto" and fr >= 0.45)) and not rigid and (style :: string) ~= "walk"
		kind = if run then "run" else "walk"
		table.insert(reasons, string.format("two legs at Froude %.2f: a %s", fr, kind))
		if rigid then
			table.insert(reasons, "legs cannot bend: a waddling pendulum walk")
		end
	elseif n == 3 then
		kind = "rotary"
		table.insert(reasons, "three legs: a rotating tripod, one foot moving at a time")
	elseif n == 4 and sym then
		if style == "gallop" or (style == "auto" and fr >= 2.5) then
			kind = "gallop"
		elseif style == "trot" or (style == "auto" and fr >= 0.4) then
			kind = "trot"
		else
			kind = "quadWalk"
			-- a walk keeps three feet down, so each swing gets a quarter of the cycle; legs that
			-- cannot carry this pace in a walk without snapping their swings trot instead
			if style == "auto" and v > 1e-6 then
				local swingMin = math.max(0.1, 0.33 * math.pi * math.sqrt(reach / g))
				local period = swingMin / 0.24
				if v * 0.76 * period > maxStance then
					kind = "trot"
					table.insert(reasons, "these legs cannot walk this fast without snapping their swings: a trot")
				end
			end
		end
		table.insert(reasons, string.format("four legs at Froude %.2f: %s", fr, kind))
	elseif n == 6 and sym then
		kind = "tripod"
		table.insert(reasons, "six legs: an alternating tripod")
	elseif n >= 8 and sym then
		kind = "ripple"
		table.insert(reasons, string.format("%d legs: a metachronal ripple from back to front", n))
	else
		kind = "general"
		table.insert(reasons, string.format("%d legs, %s: the general phase solver", n, if sym then "symmetric" else "asymmetric"))
	end

	local phases: { number }
	if type(o.phases) == "table" and #o.phases == n then
		phases = {}
		for i = 1, n do
			local p = o.phases[i]
			phases[i] = if M.finite(p) then M.frac(p) else 0
		end
		table.insert(reasons, "phases given")
	elseif kind == "none" then
		phases = {}
	elseif kind == "pogo" or kind == "walk" or kind == "run" then
		phases = GaitPlan.pattern(anatomy, "walk")
	else
		phases = GaitPlan.pattern(anatomy, kind)
	end

	-- The duty floor: the smallest duty with these phases that keeps enough feet down.
	local duty0, flightOk, runFactor = dutyFor(kind, fr)
	local need = supportNeeded(kind, n, flightOk)
	local floor = 0
	if need > 0 then
		local d = 0.1
		local guard = 0
		while GaitPlan.support(phases, d) < need and d < 0.95 and guard < 100 do
			guard += 1
			d += 0.01
		end
		floor = math.min(d, 0.95)
		if floor > duty0 + 1e-9 then
			table.insert(reasons, string.format("duty kept at %.2f or more so %d feet stay down", floor, need))
		end
	end

	local plan: Plan = {
		kind = kind,
		legs = n,
		speed = v,
		froude = fr,
		period = 0,
		duty = 0,
		dutyFloor = floor,
		maxStance = maxStance,
		crouch = crouch,
		comfort = comfort,
		overreach = false,
		phases = phases,
		stride = 0,
		stepHeight = 0,
		bob = 0,
		lowPoint = if kind == "walk" then 0.15 else 0.5,
		lean = 0,
		flight = false,
		minSupport = 0,
		margin = 0,
		rigid = rigid,
		runFactor = runFactor,
		reasons = reasons,
	}
	local period, duty, stride, flew, over = GaitPlan.tempo(plan, anatomy, v, o)
	plan.period, plan.duty, plan.stride = period, duty, stride
	plan.overreach = over
	if flew and n >= 2 then
		table.insert(reasons, string.format("too fast for its legs: flight added (duty %.2f)", duty))
	end
	if over then
		table.insert(
			reasons,
			string.format("%.3g studs/s is more than these legs carry at a readable cadence (about %.3g is comfortable): feet will over-reach", v, comfort)
		)
	end
	if crouch > 0 then
		table.insert(reasons, string.format("crouches %.3g studs while moving: the legs are near full stretch at rest", crouch))
	end
	plan.minSupport = GaitPlan.support(phases, duty)
	plan.flight = n > 0 and plan.minSupport == 0
	plan.margin = if n >= 3 then GaitPlan.stability(anatomy, phases, duty) else 0

	-- Feet lift by a share of the leg; quicker gaits lift more.
	local stepHeight = if n == 0 then 0 else math.min(0.4 * reach, H * lerpClamp(0.1, 0.2, runFactor + fr / 4))
	if n >= 6 then
		stepHeight = math.min(0.35 * reach, 0.18 * reach + 0.04 * H)
	end
	if type(o.stepHeight) == "number" and M.finite(o.stepHeight) then
		stepHeight = math.max(0, o.stepHeight)
	end
	plan.stepHeight = stepHeight

	-- Bob for gaits that stay supported (captured walks: about 4% of hip height, up to 8% brisk).
	local bobShare: number
	if kind == "walk" then
		bobShare = lerpClamp(0.043, 0.081, (fr - 0.25) / 0.2)
	elseif kind == "quadWalk" then
		bobShare = 0.03
	elseif kind == "trot" then
		bobShare = 0.05
	elseif kind == "tripod" or kind == "rotary" or kind == "general" then
		bobShare = 0.025
	elseif kind == "ripple" then
		bobShare = 0.01
	else
		bobShare = 0.04
	end
	if v < 1e-6 then
		bobShare = 0
	end
	plan.bob = bobShare * H
	if type(o.bob) == "number" and M.finite(o.bob) then
		plan.bob *= math.max(0, o.bob)
	end

	if n == 2 then
		plan.lean = math.rad(math.min(15, 9.5 * math.sqrt(math.max(fr, 0) / 3)))
		if kind == "walk" then
			plan.lean *= 0.3
		end
	elseif n == 1 then
		plan.lean = math.rad(math.min(8, 4 * math.sqrt(math.max(fr, 0))))
	elseif kind == "gallop" or kind == "trot" then
		plan.lean = math.rad(2)
	end
	return plan
end

return GaitPlan
