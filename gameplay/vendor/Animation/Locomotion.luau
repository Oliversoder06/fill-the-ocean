--!strict
--[[
	Locomotion: legged walking, running and crawling for any number of legs, baked.

	The order of work, and why:
	1. The body's path comes first (Path): where the creature is and which way it faces at
	   every moment, with real acceleration. Everything else serves it.
	2. Footsteps are planned against that path. A foot lands where its hip will be in the middle
	   of its stance (so it is planted as far ahead as it ends behind), and stays exactly there
	   in the world until it lifts: a planted foot cannot slide, by construction. The swing
	   lifts first, travels, and sets down from above, so the foot never scrapes or skates in.
	3. The body's height and tilt come from the contacts: the walking dip just after each
	   touchdown, ballistic arcs under the game's gravity whenever no foot is down, a pendulum
	   vault over legs that cannot bend, a lean into speed and acceleration, a bank into turns,
	   a shift of weight over the supporting feet. Each is smoothed (no corners, so no pops),
	   then the body is lowered just enough that every planted foot stays within reach, and never
	   so far that the body touches the ground.
	4. IK puts each foot on its target from the body's actual pose. Head, arms and tail follow:
	   the head stays level and looks into turns ahead of the body, arms swing against the legs
	   with the forearm trailing the upper arm, a tail sways a little behind the hips.
	5. Everything bakes to joint Transforms at 60 Hz (Baked).

	Nothing random: the same rig, path and options give the same numbers everywhere.
]]

local M = require("./Math")
local Rig = require("./Rig")
local Anatomy = require("./Anatomy")
local IK = require("./IK")
local GaitPlan = require("./GaitPlan")
local Path = require("./Path")
local Signal = require("./Signal")
local Baked = require("./Baked")

type V3 = M.V3
type Q = M.Q
type X = M.X

local Locomotion = {}

export type Options = {
	path: Path.Spec?,
	speed: number?,
	style: string?,
	gravity: number?,
	gaitGravity: number?,
	rate: number?,
	-- the model's pivot at the start (CFrame, or { pos = {..}, rot = {..} }); default: standing
	-- on y = 0 at the origin facing -Z
	start: any?,
	-- ground height under (x, z); default flat under the start
	ground: ((number, number) -> number)?,
	-- bake one in-place cycle that loops (gameplay), instead of travelling the path
	loop: boolean?,
	duty: number?,
	period: number?,
	phases: { number }?,
	stepHeight: number?,
	-- multipliers on the natural amounts (1 = as measured; 0 = none)
	bob: number?,
	lean: number?,
	sway: number?,
	arms: number?,
	tail: number?,
	head: number?,
	-- longest bake allowed, seconds (settling included)
	maxDuration: number?,
	name: string?,
	-- turn the head to a world point between two times (seconds into the bake)
	look: { target: any, from: number?, to: number? }?,
}

type LegState = {
	stance: boolean,
	cycle: number,
	lifted: boolean,
	plant: V3,
	plantYaw: number,
	liftPos: V3,
	liftYaw: number,
	liftPhase: number,
	swingStart: number,
	swingDur: number,
	-- late stance: the foot rolls onto its toes (where its contact is now, and its pitch)
	rollPos: V3,
	rollPitch: number,
	liftPitch: number,
	waitFrom: number?,
	rollW: number,
	-- how fast the roll was lifting the foot and tipping it when it left the ground: the swing
	-- carries on at that speed, rather than stopping it dead for a frame
	rollVy: number,
	rollVp: number,
	liftVy: number,
	liftVp: number,
	-- the last sample the foot was down (where the roll's speed was measured)
	liftAt: number,
}

local function readStart(value: any, rig: Rig.Rig): X
	if value == nil then
		return { p = { x = 0, y = -rig.ground, z = 0 }, q = M.qid() }
	end
	local x, bad = M.readX(value)
	if bad then
		return { p = { x = 0, y = -rig.ground, z = 0 }, q = M.qid() }
	end
	return x
end

local function headingOf(q: Q): number
	local f = M.qrot(q, M.FORWARD)
	if f.x * f.x + f.z * f.z < 1e-12 then
		return 0
	end
	return M.yawOf(f)
end

local function mult(v: any, default: number): number
	if type(v) == "number" and M.finite(v) then
		return math.max(0, v)
	end
	return default
end

--[[
	Bakes legged locomotion along opts.path (or one in-place cycle when opts.loop). Returns the
	bake; bake.info carries the plan, contacts, warnings and the facts the lint and the review
	tools read (feet per sample, the body's lowest gap).
]]
function Locomotion.bake(anatomy: Anatomy.Anatomy, opts: Options?): Baked.Baked
	local o: Options = opts or {}
	local rig = anatomy.rig
	local legs = anatomy.legs
	local nLegs = #legs
	local rate = if type(o.rate) == "number" and M.finite(o.rate) and o.rate >= 10 then math.min(o.rate, 240) else Baked.RATE
	local dt = 1 / rate
	local g = GaitPlan.gravity(o :: any)
	local gg = GaitPlan.gaitGravity(o :: any)
	local H = math.max(anatomy.hipHeight, 1e-3)
	local warnings: { string } = {}
	local start = readStart(o.start, rig)
	local startYaw = headingOf(start.q) + rig.facing
	local floor0 = start.p.y + rig.ground
	local groundFn = o.ground
	local function ground(x: number, z: number): number
		if groundFn then
			local ok, y = pcall(groundFn, x, z)
			if ok and type(y) == "number" and M.finite(y) then
				return y
			end
		end
		return floor0
	end

	-- 1. The plan and the body's track.
	local cruise: number
	local track: Path.Track
	local planOpts = {
		speed = o.speed,
		style = o.style,
		gravity = o.gravity,
		gaitGravity = o.gaitGravity,
		duty = o.duty,
		period = o.period,
		phases = o.phases,
		stepHeight = o.stepHeight,
		bob = o.bob,
	}
	local loopMode = o.loop == true
	local plan: GaitPlan.Plan
	if loopMode then
		plan = GaitPlan.plan(anatomy, planOpts)
		cruise = plan.speed
		if plan.overreach then
			table.insert(warnings, plan.reasons[#plan.reasons])
		end
		-- three cycles; the last one is cut out as the loop (by then every leg has stepped)
		-- six cycles; the fifth is cut out as the loop: by then every start-up step has washed
		-- out, and it ends a cycle before the bake does, clear of the smoothing's edge
		local cycles = 6
		track = Path.straight({ x = start.p.x, y = floor0, z = start.p.z }, startYaw, cruise, cycles * plan.period, rate)
	else
		local pathSpec: Path.Spec = if type(o.path) == "table" then table.clone(o.path :: Path.Spec) else {}
		if pathSpec.speed == nil then
			-- no speed given: what this body walks comfortably
			local _, _, comfort = GaitPlan.reach(anatomy)
			pathSpec.speed = if o.speed ~= nil then o.speed else comfort
		end
		track = Path.track(pathSpec, { x = start.p.x, y = floor0, z = start.p.z }, startYaw, rate, H, gg)
		for _, w in track.warnings do
			table.insert(warnings, w)
		end
		cruise = track.cruise
		planOpts.speed = cruise
		plan = GaitPlan.plan(anatomy, planOpts)
		if plan.overreach then
			for _, r in plan.reasons do
				if string.find(r, "over-reach", 1, true) then
					table.insert(warnings, r)
				end
			end
		end
	end

	-- 2. Leg facts at rest, in the root's frame.
	local rFeet = 0
	local hipRest: { V3 } = {}
	local contactRest: { V3 } = {}
	local _, _, _, pulls = GaitPlan.reach(anatomy)
	-- where each foot steps around: its rest contact, drawn in towards the hip for legs that
	-- stand near full stretch (GaitPlan.reach); the very first plant is the true rest contact
	local standRest: { V3 } = {}
	for i, leg in legs do
		local first = leg.movable[1] or leg.joints[1]
		hipRest[i] = rig.joints[first].world.p
		standRest[i] = leg.contact
		local k = pulls[i] or 1
		local hip = hipRest[i]
		contactRest[i] = { x = hip.x + (leg.contact.x - hip.x) * k, y = leg.contact.y, z = hip.z + (leg.contact.z - hip.z) * k }
		rFeet += math.sqrt(leg.contact.x ^ 2 + leg.contact.z ^ 2)
	end
	rFeet = if nLegs > 0 then rFeet / nLegs else 0
	rFeet = math.max(rFeet, 0.25 * H)

	-- Long bodies follow the path along their length: each trunk joint turns to the path's
	-- heading where it is, so a centipede rounds a corner instead of swinging its tail wide.
	local follow = (anatomy.shape == "long" or #anatomy.spine >= 3) and not loopMode
	local trunkSet: { [number]: boolean } = {}
	for _, k in anatomy.spine do
		trunkSet[k] = true
	end
	local legAnchor: { [number]: number } = {}
	local contactInAnchor: { [number]: V3 } = {}
	if follow then
		for i, leg in legs do
			local p = rig.joints[leg.joints[1]].parent
			if p > 0 and trunkSet[p] then
				legAnchor[i] = p
				contactInAnchor[i] = M.qinvrot(rig.joints[p].world.q, M.vsub(leg.contact, rig.joints[p].world.p))
			end
		end
	end
	-- the rig's own forward and right at rest (it may face any way, `facing`): a foot rolls about
	-- its right, toward its forward, whichever way the model was built
	local restFwd = M.qrot(M.qaxis(M.UP, rig.facing), M.FORWARD)
	local restRight = M.qrot(M.qaxis(M.UP, rig.facing), M.RIGHT)
	local function rootFrame(x: number, y: number, z: number, yaw: number): X
		return { p = { x = x, y = y, z = z }, q = M.qaxis(M.UP, yaw - rig.facing) }
	end
	-- local yaw offsets of trunk joints for path following at time t
	local function trunkYaws(t: number): { [number]: number }
		local out: { [number]: number } = {}
		if not follow then
			return out
		end
		local d0 = Path.distAt(track, t)
		local h0 = Path.headingAtDist(track, d0)
		local abs: { [number]: number } = {}
		for _, k in anatomy.spine do
			local j = rig.joints[k]
			local ahead = -j.world.p.z
			abs[k] = M.wrapAngle(Path.headingAtDist(track, d0 + ahead) - h0)
			local parentAbs = if j.parent > 0 and abs[j.parent] then abs[j.parent] else 0
			out[k] = abs[k] - parentAbs
		end
		return out
	end
	local function trunkLocal(k: number, yaw: number): X
		local w = rig.joints[k].world.q
		return { p = { x = 0, y = 0, z = 0 }, q = M.qnorm(M.qmul(M.qmul(M.qconj(w), M.qaxis(M.UP, yaw)), w)) }
	end
	local neutralCache: { [number]: { [number]: X } } = {}
	local function anchorFrameAt(t: number, k: number): X
		local key = math.floor(t * rate + 0.5)
		local cache: { [number]: X }? = neutralCache[key]
		if not cache then
			local tt = key / rate
			local x, _, z, yaw = Path.at(track, tt)
			local yaws = trunkYaws(tt)
			local locals: { [number]: X } = {}
			for kk, a in yaws do
				locals[kk] = trunkLocal(kk, a)
			end
			local frames = Rig.fk(rig, locals, rootFrame(x, 0, z, yaw))
			local fresh: { [number]: X } = {}
			for _, kk in anatomy.spine do
				fresh[kk] = frames[kk]
			end
			neutralCache[key] = fresh
			cache = fresh
		end
		return (cache :: { [number]: X })[k]
	end
	-- where leg i's foot belongs at time t (on the ground), and the body's heading then
	local function neutralAt(i: number, t: number): (V3, number)
		local x, _, z, yaw = Path.at(track, t)
		local p: V3
		local a = legAnchor[i]
		if a then
			local f = anchorFrameAt(t, a)
			p = M.xpoint(f, contactInAnchor[i])
		else
			p = M.xpoint(rootFrame(x, 0, z, yaw), contactRest[i])
		end
		return { x = p.x, y = ground(p.x, p.z) + legs[i].gap, z = p.z }, yaw
	end
	-- where leg i's hip is at time t, in the root's frame: on a long body bending along the path
	-- a hip rides on its own trunk joint, not where it sits at rest
	local hipInAnchor: { [number]: V3 } = {}
	for i, a in legAnchor do
		local aw = rig.joints[a].world
		hipInAnchor[i] = M.qinvrot(aw.q, M.vsub(hipRest[i], aw.p))
	end
	local function hipLocalAt(i: number, t: number): V3
		local a = legAnchor[i]
		if not a then
			return hipRest[i]
		end
		local x, _, z, yaw = Path.at(track, t)
		local w = M.xpoint(anchorFrameAt(t, a), hipInAnchor[i])
		return M.qinvrot(rootFrame(x, 0, z, yaw).q, M.vsub(w, { x = x, y = 0, z = z }))
	end

	-- 3. Footsteps.
	local phi = GaitPlan.startPhase(plan.phases)
	local states: { LegState } = {}
	for i = 1, nLegs do
		local _, yaw = neutralAt(i, 0)
		local x0, _, z0, yaw0 = Path.at(track, 0)
		local q = M.xpoint(rootFrame(x0, 0, z0, yaw0), standRest[i])
		local p = { x = q.x, y = ground(q.x, q.z) + legs[i].gap, z = q.z }
		states[i] = {
			stance = true,
			cycle = math.floor(phi + plan.phases[i]),
			lifted = false,
			plant = p,
			plantYaw = yaw,
			liftPos = p,
			liftYaw = yaw,
			liftPhase = 0,
			swingStart = 0,
			swingDur = 1,
			rollPos = p,
			rollPitch = 0,
			liftPitch = 0,
			rollW = 0,
			rollVy = 0,
			rollVp = 0,
			liftVy = 0,
			liftVp = 0,
			liftAt = 0,
		}
	end
	local maxDuration = if type(o.maxDuration) == "number" and M.finite(o.maxDuration) then math.max(o.maxDuration, 0.1) else 120
	local settleSpeed = math.max(0.5 * cruise, math.sqrt(0.05 * gg * H))
	local cruisePeriod, _, cruiseStride = GaitPlan.tempo(plan, anatomy, cruise, planOpts)
	local placeTol = math.max(0.12 * cruiseStride, 0.06 * H, 0.01)
	-- a planted foot this far from where it belongs takes a catch-up step, phase or not
	-- (a planned stance takes a foot at most half the longest stance from its spot)
	local catchUp = math.max(0.8 * plan.maxStance, 2 * placeTol)
	local needDown = if plan.flight then 0 elseif nLegs == 2 then 1 elseif nLegs == 3 then 2 elseif nLegs >= 4 then (if plan.kind == "trot" then 2 else 3) else 0
	local stepHeight = plan.stepHeight
	local footX: { { number } } = {}
	local footY: { { number } } = {}
	local footZ: { { number } } = {}
	local footYaw: { { number } } = {}
	local footDown: { { boolean } } = {}
	local footU: { { number } } = {}
	local footPitch: { { number } } = {}
	for i = 1, nLegs do
		footX[i], footY[i], footZ[i], footYaw[i], footDown[i], footU[i] = {}, {}, {}, {}, {}, {}
		footPitch[i] = {}
	end
	--[[
		Late in a stance the foot rolls onto its toes before it lifts: the heel rises about the toe
		(a foot with a part to measure), or the paw curls up off the ground (bones only). The knee
		starts bending before the foot leaves, as a walking leg's does; a foot held flat right up
		to lift-off would make the knee snap from straightening to bending in a frame.
	]]
	local toeLen: { number } = {}
	local rollable: { boolean } = {}
	for i, leg in legs do
		local last = rig.joints[leg.joints[#leg.joints]]
		local footed = leg.ik == "twoFoot" or leg.ik == "chainFoot"
		local toe = 0
		if footed and last.boxMin and last.boxMax then
			-- how far the foot reaches ahead of its contact, the way the rig faces
			local lo, hi = last.boxMin :: V3, last.boxMax :: V3
			for _, cx in { lo.x, hi.x } do
				for _, cz in { lo.z, hi.z } do
					toe = math.max(toe, (cx - leg.contact.x) * restFwd.x + (cz - leg.contact.z) * restFwd.z)
				end
			end
		end
		toeLen[i] = toe
		rollable[i] = not leg.rigid and leg.gap <= 0.05 * H
	end
	local rollMax = math.rad(if plan.runFactor >= 1 then 28 else 20)
	local function rollAt(i: number, st: LegState, w: number): (V3, number)
		local yq = M.qaxis(M.UP, st.plantYaw - rig.facing)
		if toeLen[i] > 1e-6 then
			local phi = rollMax * w
			local fwd = M.qrot(yq, restFwd)
			local right = M.qrot(yq, restRight)
			local toe = M.vmad(st.plant, fwd, toeLen[i])
			local pos = M.vadd(toe, M.qrot(M.qaxis(right, -phi), M.vsub(st.plant, toe)))
			return pos, -phi
		end
		return { x = st.plant.x, y = st.plant.y + 0.04 * legs[i].limbReach * w, z = st.plant.z }, -0.6 * rollMax * w
	end
	local phiAt: { number } = {}
	local settling: { boolean } = {}
	local catchUps = 0
	local s = 0
	local extraLimit = math.ceil(4 * math.max(plan.period, 0.3) * rate)
	local extra = 0
	-- tempo by speed, cached: the planner is asked every sample, and for every swinging leg
	local tempoCache: { [number]: { number } } = {}
	local function tempoAt(v: number): (number, number)
		local key = math.floor(v / math.max(cruise, 1e-6) * 2000 + 0.5)
		local hit = tempoCache[key]
		if hit then
			return hit[1], hit[2]
		end
		local p, d = GaitPlan.tempo(plan, anatomy, v, planOpts)
		tempoCache[key] = { p, d }
		return p, d
	end
	-- where a swinging foot should land: the middle of its coming stance, timed at the pace the
	-- body will have then (not now: a body speeding up from standing would otherwise throw its
	-- first steps far ahead), and never beyond the leg's reach from where the hip will be
	-- half a stance's time at each moment, smoothed: how far ahead a landing looks must not jump
	-- when the pace changes (stopping, starting a turn on the spot), or the landing spot jumps
	local halfStance: { number } = table.create(track.count, 0)
	for k = 1, track.count do
		local vk = math.max(track.speed[k], math.abs(track.yawRate[k]) * rFeet)
		local pk, dk = tempoAt(if vk > 1e-4 * H then vk else settleSpeed)
		halfStance[k] = 0.5 * pk * dk
	end
	halfStance = Signal.gauss(halfStance, 0.15 * rate, false)
	local function landing(i: number, tTouch: number): (V3, number)
		local hs = Signal.sampleAt(halfStance, math.clamp(tTouch * rate, 0, track.count - 1) + 1, false)
		local target, tyaw = neutralAt(i, tTouch + hs)
		local x, _, z, yaw = Path.at(track, tTouch)
		local hip = M.xpoint(rootFrame(x, 0, z, yaw), hipLocalAt(i, tTouch))
		local leg = legs[i]
		-- (measured to what IK places: the ankle of a foot-flat leg)
		local h = math.max(hipRest[i].y - (contactRest[i].y - leg.footVec.y) - plan.crouch, 1e-6)
		local r = 0.92 * leg.limbReach
		local horiz = math.sqrt(math.max(r * r - h * h, 0))
		local dx, dz = target.x - hip.x, target.z - hip.z
		local d = math.sqrt(dx * dx + dz * dz)
		-- the rest stance's own sideways reach is allowed; only the stride part is held in
		local restOff = math.sqrt((contactRest[i].x - hipRest[i].x) ^ 2 + (contactRest[i].z - hipRest[i].z) ^ 2)
		local limit = math.max(horiz, restOff)
		if d > limit and d > 1e-9 and not leg.rigid then
			local k = limit / d
			target = { x = hip.x + dx * k, y = ground(hip.x + dx * k, hip.z + dz * k) + leg.gap, z = hip.z + dz * k }
		end
		return target, tyaw
	end
	-- how far each planted foot may be from its hip (horizontally) before it must step, phase
	-- or not: past 92% of what the leg reaches it is nearly straight, where the joints turn far
	-- faster than the foot moves, and at full stretch it would drag. (A leg that stands at full
	-- stretch at rest, an arm lying flat, starts out there: it steps as soon as the body starts
	-- to move away from it.)
	local stepReach: { number } = table.create(nLegs, math.huge)
	-- (only legs the planner draws in: an upright leg is near full stretch by design and the
	-- body's crouch, worked out later, gives it its room)
	for i, leg in legs do
		if not leg.rigid and (pulls[i] or 1) < 0.999 then
			local h = math.max(hipRest[i].y - (standRest[i].y - leg.footVec.y) - plan.crouch, 0)
			local r = 0.92 * leg.limbReach
			stepReach[i] = math.sqrt(math.max(r * r - h * h, 0))
		end
	end
	local function hipDist2(i: number, plant: V3, t: number): number
		local x, _, z, yaw = Path.at(track, t)
		local hip = M.xpoint(rootFrame(x, 0, z, yaw), hipLocalAt(i, t))
		local dx, dz = plant.x - hip.x, plant.z - hip.z
		return dx * dx + dz * dz
	end
	-- beyond that reach and getting farther (a foot the body is coming back towards waits)
	local function outOfReach(i: number, plant: V3, t: number): boolean
		if stepReach[i] == math.huge then
			return false
		end
		local d2 = hipDist2(i, plant, t + 2 * dt)
		return d2 > stepReach[i] * stepReach[i] and d2 > hipDist2(i, plant, t)
	end
	-- no swing quicker than a third of the leg's pendulum period: faster reads as a snap
	local reachAvg = 0
	for _, leg in legs do
		reachAvg += leg.limbReach
	end
	reachAvg = if nLegs > 0 then reachAvg / nLegs else H
	local swingMin = math.max(0.1, 0.33 * math.pi * math.sqrt(math.max(reachAvg, 1e-3) / gg))
	local function lift(st: LegState, t: number, psi: number, dur: number, sampleT: number)
		-- (a hop's or a run's swing is its flight, timed by gravity: no floor there)
		if not plan.flight and plan.kind ~= "pogo" then
			dur = math.max(dur, swingMin)
		end
		st.stance = false
		st.lifted = true
		st.liftPos = st.rollPos
		st.liftPitch = st.rollPitch
		st.liftVy = st.rollVy
		st.liftVp = st.rollVp
		st.liftAt = sampleT - dt
		st.liftYaw = st.plantYaw
		st.liftPhase = psi
		st.swingStart = t
		st.swingDur = math.max(dur, 2 * dt)
	end
	while true do
		local t = s * dt
		local inTrack = s < track.count
		local v, w = 0, 0
		if inTrack then
			v = track.speed[s + 1]
			w = math.abs(track.yawRate[s + 1])
		end
		local vEff = math.max(v, w * rFeet)
		local moving = vEff > 1e-4 * H and inTrack
		-- settle: not travelling, but a foot is in the air or away from where it belongs
		local needSettle = false
		if not moving and nLegs > 0 then
			for i, st in states do
				if not st.stance then
					needSettle = true
					break
				end
				local p = neutralAt(i, t)
				if M.vdist(st.plant, p) > placeTol then
					needSettle = true
					break
				end
			end
		end
		local active = moving or needSettle
		local period, duty = tempoAt(if moving then vEff else settleSpeed)
		-- while setting off or slowing down, keep stepping at nearly the cruising rhythm with
		-- shorter steps (as people do), instead of slowing the cadence with the speed: a slow
		-- cadence leaves feet planted far behind a body that is already moving
		if moving then
			period = math.min(period, 1.25 * cruisePeriod)
		end
		local down = 0
		for _, st in states do
			if st.stance then
				down += 1
			end
		end
		for i = 1, nLegs do
			local st = states[i]
			local raw = phi + plan.phases[i]
			local c = math.floor(raw)
			local psi = raw - c
			if st.stance then
				if c > st.cycle then
					st.cycle = c
					st.lifted = false
				end
				if active and not st.lifted and psi >= duty then
					local go = moving
					if not go then
						local p = neutralAt(i, t)
						go = M.vdist(st.plant, p) > placeTol
					end
					-- a gait that keeps feet down waits a moment for another foot to land rather
					-- than leave the body unsupported (after a catch-up step or a change of pace),
					-- but never more than a quarter of a cycle: a foot held back too long would be
					-- left stretched behind
					if go and down - 1 < needDown then
						if st.waitFrom == nil then
							st.waitFrom = t
						end
						if t - (st.waitFrom :: number) < 0.25 * period then
							go = false
						end
					end
					if go then
						st.waitFrom = nil
						-- lift at the exact moment the phase crossed the duty factor (between two
						-- samples), so every cycle repeats exactly and an in-place loop closes
						local over = math.clamp(psi - duty, 0, dt / period)
						lift(st, t - over * period, duty, (1 - duty) * period, t)
						down -= 1
					end
				elseif active then
					-- left too far behind (a standing start, a sharp turn, a change of pace):
					-- step now rather than stretch, if the others can carry the body; a foot
					-- about to pass out of reach steps whatever the others do, since from then
					-- on it would only drag
					local p = neutralAt(i, t)
					local dx, dz = st.plant.x - p.x, st.plant.z - p.z
					local far = down - 1 >= needDown and math.sqrt(dx * dx + dz * dz) > catchUp
					if far or outOfReach(i, st.plant, t) then
						-- swing until this leg's phase comes round to touchdown, so the foot lands
						-- back in step with the others (within reason: never more than two
						-- ordinary swings)
						lift(st, t, psi, math.min((1 - psi) * period, 2 * (1 - duty) * period), t)
						down -= 1
						catchUps += 1
					end
				end
			end
			if not st.stance then
				local remaining = math.max(0, st.swingStart + st.swingDur - t)
				-- landed when its time is up (or, as a backstop, two cycles on)
				local landed = remaining <= 0.5 * dt or c > st.cycle + 1
				-- always the predicted landing: switching to "where it belongs now" when the body
				-- stops mid-swing would make the foot jump at touchdown (a pop); the prediction
				-- settles onto the same spot by itself once the body is still
				local target, tyaw = landing(i, t + remaining)
				if landed then
					st.stance = true
					st.rollW = 0
					st.rollPos = target
					st.rollPitch = 0
					st.plant = target
					st.plantYaw = tyaw
					if c > st.cycle then
						st.cycle = c
						st.lifted = psi >= duty
					end
					down += 1
				else
					local u = M.clamp((t - st.swingStart) / st.swingDur, 0, 1)
					-- forward from the first moment of the swing (a foot that rose straight up
					-- first would rock the hip back before throwing it forward: a wobble)
					local h = M.smoothstep(u)
					local lp = st.liftPos
					local fx = lp.x + (target.x - lp.x) * h
					local fz = lp.z + (target.z - lp.z) * h
					local baseY = lp.y + (target.y - lp.y) * h
					-- clear the ground along the way, not only at the ends
					local mx, mz = (lp.x + target.x) / 2, (lp.z + target.z) / 2
					local bump = math.max(0, ground(mx, mz) + legs[i].gap - math.max(lp.y, target.y))
					local dist = math.sqrt((target.x - lp.x) ^ 2 + (target.z - lp.z) ^ 2)
					local reachShare = M.clamp(dist / math.max(0.3 * cruiseStride, 1e-3), 0.35, 1)
					-- squared sine: rises and lands with zero vertical speed (no pop at lift-off or
					-- touchdown), peaking a little before halfway (quick lift, gentle set-down)
					local sa = math.sin(math.pi * (u ^ 0.9))
					local arch = sa * sa
					local liftH = (stepHeight * reachShare + bump) * arch
					-- the roll's speed at lift-off, carried on and faded out by touchdown
					local carry = math.max(0, t - st.liftAt) * (1 - u) * (1 - u)
					liftH += st.liftVy * carry
					footX[i][s + 1], footY[i][s + 1], footZ[i][s + 1] = fx, baseY + liftH, fz
					footYaw[i][s + 1] = st.liftYaw + M.wrapAngle(tyaw - st.liftYaw) * h
					footDown[i][s + 1] = false
					footU[i][s + 1] = u
					-- the toe-down it lifted with eases out over the first half of the swing
					footPitch[i][s + 1] = st.liftPitch * (1 - M.smoothstep(math.min(u / 0.5, 1))) + st.liftVp * carry
				end
			end
			if st.stance then
				local pos, pitch = st.plant, 0
				-- (not in a hop or a run: the foot is down too briefly to roll without snapping)
				if rollable[i] and not plan.flight and plan.kind ~= "pogo" then
					local want = 0
					if moving and duty * period >= 0.25 then
						-- how far through this stance: by the phase still to go before the next
						-- lift-off (a foot that landed early, before its phase wrapped, has more
						-- than a stance to go and does not roll yet)
						local nextLift = st.cycle + (if st.lifted then 1 else 0) + duty
						local toGo = nextLift - raw
						local progress = M.clamp(1 - toGo / math.max(duty, 1e-6), 0, 1)
						-- over the last 30% of the stance, or the last 0.15 s of a short one, so the
						-- roll is complete (and still) at the moment the swing takes the foot up
						local span = M.clamp(0.15 / (duty * period), 0.3, 0.6)
						want = M.clamp((progress - (1 - span)) / span, 0, 1)
					end
					-- the roll builds over at least 0.15 s (a foot that starts late in its stance,
					-- at a standing start, must not flick onto its toes in a few frames). The limit
					-- is on the linear progress and the eased curve is taken after it, so the roll
					-- always sets off from rest: limiting the eased value would start it at full
					-- rate in one frame, a pop. It unrolls at the same pace: a foot that rolled up
					-- but was held down (waiting for support, or the body stopped) settles back flat
					local r = M.clamp(want, st.rollW - dt / 0.15, st.rollW + dt / 0.15)
					st.rollW = r
					local rw = M.smoothstep(r)
					if rw > 0 then
						pos, pitch = rollAt(i, st, rw)
					end
				end
				st.rollVy = (pos.y - st.rollPos.y) / dt
				st.rollVp = (pitch - st.rollPitch) / dt
				st.rollPos, st.rollPitch = pos, pitch
				footX[i][s + 1], footY[i][s + 1], footZ[i][s + 1] = pos.x, pos.y, pos.z
				footYaw[i][s + 1] = st.plantYaw
				footDown[i][s + 1] = true
				footU[i][s + 1] = 0
				footPitch[i][s + 1] = pitch
			end
		end
		phiAt[s + 1] = phi
		settling[s + 1] = (not moving) and needSettle
		if active then
			phi += dt / period
		end
		s += 1
		if s >= track.count then
			if not needSettle or loopMode then
				break
			end
			extra += 1
			if extra > extraLimit then
				table.insert(warnings, "the feet did not settle within four steps after arriving; the bake stops there")
				break
			end
		end
		if s * dt > maxDuration then
			table.insert(warnings, string.format("stopped at the %.0f s limit", maxDuration))
			break
		end
	end
	local n = s

	-- Body pose at each sample (the track clamps past its end).
	local bx, bz, byaw, bspeed, baccel, byawRate = {}, {}, {}, {}, {}, {}
	for k = 1, n do
		local t = (k - 1) * dt
		local x, _, z, yaw, spd = Path.at(track, t)
		bx[k], bz[k], byaw[k], bspeed[k] = x, z, yaw, spd
		if k <= track.count then
			baccel[k] = track.accel[k]
			byawRate[k] = track.yawRate[k]
		else
			baccel[k] = 0
			byawRate[k] = 0
		end
	end

	-- 4. Body height, tilt and sway.
	local rootH = -rig.ground
	local runF = plan.runFactor
	local crouch = 0.02 + 0.05 * runF
	-- the body's own lowest point above the floor at rest (not counting the legs)
	local legJoint: { [number]: boolean } = {}
	for _, leg in legs do
		for _, k in leg.joints do
			legJoint[k] = true
		end
	end
	for _, c in anatomy.chains do
		if c.kind == "leg" or c.digit then
			for _, k in c.joints do
				legJoint[k] = true
			end
		end
	end
	local bodyLow = -rig.rootSize.y / 2
	if rig.rootSize.y <= 0 then
		bodyLow = 0
	end
	for _, k in anatomy.spine do
		local j = rig.joints[k]
		if j.boxMin and not legJoint[k] then
			bodyLow = math.min(bodyLow, (j.boxMin :: V3).y)
		end
	end
	local bodyGap = math.max(0, bodyLow - rig.ground)
	-- never into the ground, and never deeper than a real crouch (a third of the hip height):
	-- past that a leg folds onto itself and whips
	local maxDrop = math.min(math.max(0, bodyGap - 0.02 * H), 0.35 * H)

	local stanceCount: { number } = table.create(n, 0)
	for k = 1, n do
		local c = 0
		for i = 1, nLegs do
			if footDown[i][k] then
				c += 1
			end
		end
		stanceCount[k] = c
	end
	local loopSmooth = false
	-- speed share, for fading bob and sway in and out with motion
	local share: { number } = table.create(n, 0)
	for k = 1, n do
		share[k] = if cruise > 1e-6 then M.clamp(bspeed[k] / cruise, 0, 1) else 0
		if settling[k] then
			share[k] = math.max(share[k], 0.4)
		end
	end
	share = Signal.gauss(share, 0.08 * rate, loopSmooth)

	-- a look at something: eased in and out over 0.4 s at the ends of its window
	local lookTarget: V3? = nil
	local lookW: { number } = table.create(n, 0)
	if type(o.look) == "table" then
		local lt = M.readV3((o.look :: any).target)
		if lt then
			lookTarget = lt
			local from = if M.finite((o.look :: any).from) then (o.look :: any).from else 0
			local to = if M.finite((o.look :: any).to) then (o.look :: any).to else math.huge
			for k = 1, n do
				local t = (k - 1) * dt
				lookW[k] = M.smoothstep((t - from) / 0.4) * M.smoothstep((to - t) / 0.4) * mult(o.head, 1)
			end
		end
	end

	local dy: { number } = table.create(n, 0)
	-- tilt and sway
	local pitch: { number } = table.create(n, 0)
	local roll: { number } = table.create(n, 0)
	local sway: { number } = table.create(n, 0)
	local twist: { number } = table.create(n, 0)
	local leanMul = mult(o.lean, 1)
	local swayMul = mult(o.sway, 1)
	local isBiped = nLegs == 2 and legs[1].side ~= legs[2].side and legs[1].side ~= 0 and legs[2].side ~= 0
	local hipHalf = 0
	if isBiped then
		hipHalf = math.abs(hipRest[1].x - hipRest[2].x) / 2
	end
	for k = 1, n do
		local v = bspeed[k]
		local lean = plan.lean * share[k] + math.atan(baccel[k] / gg) * 0.5
		pitch[k] = M.clamp(lean * leanMul, -0.3, 0.3)
		roll[k] = M.clamp(math.atan(v * byawRate[k] / gg) * 0.5 * leanMul, -0.25, 0.25)
		if nLegs > 0 then
			-- weight over the supporting feet, in the body's sideways axis
			local frame = rootFrame(bx[k], 0, bz[k], byaw[k])
			local sum, cnt = 0, 0
			local fl, fr = 0, 0
			for i = 1, nLegs do
				if footDown[i][k] then
					local local_ = M.qinvrot(frame.q, M.vsub({ x = footX[i][k], y = 0, z = footZ[i][k] }, frame.p))
					sum += local_.x - contactRest[i].x * 0.5
					cnt += 1
				end
				if isBiped then
					local local_ = M.qinvrot(frame.q, M.vsub({ x = footX[i][k], y = 0, z = footZ[i][k] }, frame.p))
					if legs[i].side < 0 then
						fl = local_.z - contactRest[i].z
					else
						fr = local_.z - contactRest[i].z
					end
				end
			end
			if cnt > 0 then
				local k2 = if isBiped then (if plan.kind == "run" then 0.12 else 0.3) else 0.1
				sway[k] = k2 * sum / cnt * swayMul * share[k]
			end
			if isBiped then
				local half = math.max(0.5 * cruiseStride, 1e-3)
				-- the forward foot's hip comes forward: left foot ahead (more -z) => negative yaw
				twist[k] = -0.13 * M.clamp((fr - fl) / half, -1, 1) * share[k]
				if plan.rigid then
					-- waddle: lean over the planted foot so the free one clears the ground
					local l = if footDown[1][k] then (if legs[1].side < 0 then 1 else -1) else 0
					local r = if footDown[2][k] then (if legs[2].side < 0 then 1 else -1) else 0
					roll[k] += math.rad(8) * (l + r) * 0.5 * share[k] * swayMul
				end
			end
		end
	end
	-- a rig whose head is its body (Jack's pumpkin) looks by turning the body
	local headless = anatomy.head == nil or not rig.joints[anatomy.head :: number].animated
	if lookTarget and headless then
		for k = 1, n do
			if lookW[k] > 0 then
				local d = M.vsub(lookTarget :: V3, { x = bx[k], y = 0, z = bz[k] })
				local rel = M.clamp(M.wrapAngle(math.atan2(-d.x, -d.z) - byaw[k]), -1.0, 1.0)
				twist[k] += rel * lookW[k]
			end
		end
	end
	pitch = Signal.gauss(pitch, 0.1 * rate, false)
	roll = Signal.gauss(roll, 0.06 * rate, false)
	-- A long body leans less: the same angle that tips a biped's torso lifts a centipede's tail
	-- clean off its legs. Each tilt is held softly to the angle that raises the body's far end by
	-- a few percent of the hip height.
	do
		local halfLen = math.max(0.5 * anatomy.length, 1e-3)
		local halfWide = math.max(0.5 * anatomy.width, 1e-3)
		local pitchCap = math.min(0.3, math.atan(0.12 * H / halfLen))
		local rollCap = math.min(0.25, math.atan(0.12 * H / halfWide))
		for k = 1, n do
			pitch[k] = pitchCap * math.tanh(pitch[k] / pitchCap)
			roll[k] = rollCap * math.tanh(roll[k] / rollCap)
		end
	end
	sway = Signal.gauss(sway, 0.06 * rate, false)
	twist = Signal.gauss(twist, 0.05 * rate, false)
	if hipHalf > 0 then
		for k = 1, n do
			sway[k] = M.clamp(sway[k], -hipHalf, hipHalf)
		end
	elseif nLegs > 0 then
		-- many legs: a slight shift over the feet, never a lurch (held softly to 4% of the hip
		-- height), and none for a body that rests on the ground, which the ground carries
		local carry = M.clamp(bodyGap / (0.25 * H), 0, 1)
		local cap = 0.04 * H
		for k = 1, n do
			sway[k] = carry * cap * math.tanh(sway[k] / cap)
		end
	end

	-- the body's pivot and offset at sample k
	local bodyJ = anatomy.body
	local bodyRest = if bodyJ then rig.joints[bodyJ :: number].world else M.xid()
	local function offsetAt(k: number, extraDy: number): X
		local q = M.qmul(M.qmul(M.qaxis(M.UP, twist[k]), M.qaxis(M.RIGHT, -pitch[k])), M.qaxis({ x = 0, y = 0, z = 1 }, roll[k]))
		local pivot = bodyRest.p
		-- rotate about the body's pivot, then shift
		local moved = M.vsub(pivot, M.qrot(q, pivot))
		return { p = { x = moved.x + sway[k], y = moved.y + dy[k] + extraDy, z = moved.z }, q = q }
	end
	-- Tilting a body that sits low dips one edge: how far the body's lowest corner goes below
	-- its rest height under each sample's tilt is room the floor below has to keep (a starfish
	-- lying flat rises a hair onto the other edge rather than tipping into the ground)
	local bodyPts: { V3 } = {}
	local function corners(lo: V3, hi: V3)
		for _, cx in { lo.x, hi.x } do
			for _, cz in { lo.z, hi.z } do
				table.insert(bodyPts, { x = cx, y = lo.y, z = cz })
			end
		end
	end
	if rig.rootSize.y > 0 then
		local h = M.vmul(rig.rootSize, 0.5)
		corners(M.vmul(h, -1), h)
	end
	for _, k in anatomy.spine do
		local j = rig.joints[k]
		if j.boxMin and j.boxMax and not legJoint[k] then
			corners(j.boxMin :: V3, j.boxMax :: V3)
		end
	end
	local tiltDrop: { number } = table.create(n, 0)
	if #bodyPts > 0 then
		for k = 1, n do
			local off = offsetAt(k, 0)
			local low = math.huge
			for _, p in bodyPts do
				low = math.min(low, M.qrot(off.q, p).y + off.p.y)
			end
			tiltDrop[k] = math.max(0, bodyLow - low)
		end
	end
	-- vertical offset of the pivot from standing height (negative = lower)
	dy = table.create(n, 0)
	if plan.rigid and nLegs > 0 then
		-- pendulum legs: the body rides at the height the planted legs hold it
		local rigidHalf: { number } = table.create(nLegs, 0)
		for i, leg in legs do
			local last = rig.joints[leg.joints[#leg.joints]]
			if last.boxMin and last.boxMax then
				local lo, hi = last.boxMin :: V3, last.boxMax :: V3
				rigidHalf[i] = 0.5 * math.max(hi.x - lo.x, hi.z - lo.z)
			end
		end
		local need: { number } = table.create(n, -math.huge)
		for k = 1, n do
			local best = -math.huge
			local fx = bx[k]
			local fz = bz[k]
			local frame = M.xmul(rootFrame(fx, 0, fz, byaw[k]), offsetAt(k, 0))
			for i = 1, nLegs do
				if footDown[i][k] then
					local hip = M.xpoint(frame, hipLocalAt(i, (k - 1) * dt))
					local vert: number
					if legs[i].ik == "aimFoot" then
						-- a stub leg on a flat foot: the pendulum runs from the hip to the ankle,
						-- and the foot under it stays flat on the ground
						local fv = M.qrot(M.qaxis(M.UP, footYaw[i][k] - rig.facing), legs[i].footVec)
						local La = legs[i].limbReach
						local dx, dz = hip.x - (footX[i][k] - fv.x), hip.z - (footZ[i][k] - fv.z)
						vert = math.sqrt(math.max(La * La - dx * dx - dz * dz, 0)) - fv.y
					else
						local L = M.vdist(hipRest[i], contactRest[i])
						local dx, dz = hip.x - footX[i][k], hip.z - footZ[i][k]
						local dh2 = dx * dx + dz * dz
						vert = math.sqrt(math.max(L * L - dh2, 0))
						-- a leg swung off the vertical stands on the edge of its foot, not the
						-- middle of its sole: the edge reaches lower by the foot's half-length
						-- times the sine of the swing, and the body rides that much higher
						if L > 1e-6 then
							vert += rigidHalf[i] * math.sqrt(dh2) / L
						end
					end
					-- pivot height that puts this hip exactly L from its foot
					local pivotY = footY[i][k] - legs[i].gap + vert - hipRest[i].y + legs[i].gap
					local floorHere = ground(fx, fz)
					local off = pivotY - (floorHere + rootH)
					if off > best then
						best = off
					end
				end
			end
			if best == -math.huge then
				best = 0
			end
			-- (up a little too: a waddle rocks the body over the planted leg, and that side
			-- must not sink the foot into the floor)
			need[k] = math.min(best, 0.15 * H)
		end
		dy = Signal.smoothFloor(need, 0.02 * rate, false)
	elseif nLegs > 0 then
		-- flights: ballistic arcs; stances between flights: a dip that meets the arcs' speeds
		local air: { boolean } = table.create(n, false)
		local anyFlight = false
		local fliesHere = plan.flight or plan.kind == "pogo"
		for k = 1, n do
			air[k] = fliesHere and stanceCount[k] == 0 and bspeed[k] > 1e-4 * H
			if air[k] then
				anyFlight = true
			end
		end
		local kernel: { number } = table.create(n, 0)
		-- supported bob: a dip in each stance at its low point, summed over the legs
		for i = 1, nLegs do
			local k = 1
			while k <= n do
				if footDown[i][k] then
					local a = k
					while k <= n and footDown[i][k] do
						k += 1
					end
					local b = k - 1
					local len = b - a + 1
					if len >= 2 and (a > 1 or b < n) then
						local low = plan.lowPoint
						for m = a, b do
							local tau = (m - a) / math.max(len - 1, 1)
							-- warp so the dip bottoms out at `low`
							local w = if tau < low then 0.5 * tau / math.max(low, 1e-6) else 0.5 + 0.5 * (tau - low) / math.max(1 - low, 1e-6)
							kernel[m] += 0.5 * (1 - math.cos(2 * math.pi * w))
						end
					end
				else
					k += 1
				end
			end
		end
		local moving: { number } = {}
		for k = 1, n do
			if bspeed[k] > 0.5 * cruise then
				table.insert(moving, kernel[k])
			end
		end
		local mean, lo, hi = 0, math.huge, -math.huge
		for _, v in moving do
			mean += v
			lo = math.min(lo, v)
			hi = math.max(hi, v)
		end
		mean = if #moving > 0 then mean / #moving else 0
		local pp = hi - lo
		local supported: { number } = table.create(n, 0)
		if #moving > 0 and pp > 1e-9 then
			for k = 1, n do
				supported[k] = -plan.bob * share[k] * (kernel[k] - mean) / pp
			end
		end
		supported = Signal.gauss(supported, 0.03 * rate, false)
		if anyFlight then
			-- ballistic: find flight intervals and the stances between them
			local ballistic: { number } = table.create(n, 0)
			local flights: { { number } } = {}
			local k = 1
			while k <= n do
				if air[k] then
					local a = k
					while k <= n and air[k] do
						k += 1
					end
					table.insert(flights, { a - 1, k })
				else
					k += 1
				end
			end
			for _, f in flights do
				-- from the last sample on the ground (a) to the first back on it (b)
				local a, b = math.max(f[1], 1), math.min(f[2], n)
				local D = (b - a) * dt
				for m = a, b do
					local ta = (m - a) * dt
					ballistic[m] = 0.5 * g * ta * (D - ta)
				end
			end
			-- stances between flights: Hermite dips matching landing and take-off speeds. A long
			-- stretch on the ground (a pause between bounds) lands, settles flat and takes off
			-- again, instead of one dip as long as the pause and as deep as it is long.
			local typical = math.max(2, math.floor(1.5 * plan.duty * plan.period * rate + 0.5))
			for fi = 1, #flights - 1 do
				local a = math.min(flights[fi][2], n)
				local b = math.max(flights[fi + 1][1], 1)
				if b > a then
					local D1 = (flights[fi][2] - flights[fi][1]) * dt
					local D2 = (flights[fi + 1][2] - flights[fi + 1][1]) * dt
					local vLand = -0.5 * g * D1
					local vTake = 0.5 * g * D2
					if b - a <= typical then
						local Ds = (b - a) * dt
						for m = a, b do
							local u = (m - a) / (b - a)
							local h01 = u * u * u - 2 * u * u + u
							local h11 = u * u * u - u * u
							ballistic[m] = Ds * (h01 * vLand + h11 * vTake)
						end
					else
						local half = math.max(1, typical // 2)
						local Dh = half * dt
						for m = a, a + half do
							local u = (m - a) / half
							ballistic[m] = Dh * (u * u * u - 2 * u * u + u) * vLand
						end
						for m = b - half, b do
							local u = (m - (b - half)) / half
							ballistic[m] = Dh * (u * u * u - u * u) * vTake
						end
					end
				end
			end
			-- the first take-off and the last landing ease out of and into standing
			if #flights > 0 then
				local a = math.max(flights[1][1], 1)
				local D1 = (flights[1][2] - flights[1][1]) * dt
				local back = math.min(a - 1, math.floor(0.6 * plan.period * rate))
				if back >= 2 then
					local vTake = 0.5 * g * D1
					local Ds = back * dt
					for m = a - back, a do
						local u = (m - (a - back)) / back
						ballistic[m] = Ds * (u * u * u - u * u) * vTake
					end
				end
				local last = flights[#flights]
				local z0 = math.min(last[2], n)
				local D2 = (last[2] - last[1]) * dt
				local fwd = math.min(n - z0, math.floor(0.6 * plan.period * rate))
				if fwd >= 2 then
					local vLand = -0.5 * g * D2
					local Ds = fwd * dt
					for m = z0, z0 + fwd do
						local u = (m - z0) / fwd
						ballistic[m] = Ds * (u * u * u - 2 * u * u + u) * vLand
					end
				end
			end
			for m = 1, n do
				dy[m] = supported[m] * 0.35 + ballistic[m]
			end
		else
			dy = supported
		end
	end
	-- a slight crouch while moving lets the knees bend instead of locking straight, more for
	-- legs that stand near full stretch (the planner works out how much)
	-- (a hop or a run gets its bend from each landing; a standing crouch on top would sink it
	-- to the floor at every touchdown)
	if not plan.rigid then
		local standCrouch = if plan.flight or plan.kind == "pogo" then 0 else plan.crouch
		for k = 1, n do
			dy[k] -= (crouch * H + standCrouch) * share[k]
		end
	end

	local floorAt: { number } = table.create(n, 0)
	for k = 1, n do
		floorAt[k] = ground(bx[k], bz[k])
	end
	floorAt = Signal.gauss(floorAt, 0.1 * rate, false)

	-- 5. Keep planted feet in reach: lower the body where a leg would have to over-stretch.
	local lowerBy: { number } = table.create(n, 0)
	-- and how far down the body may go before a planted leg has to fold tighter than it can
	local foldRoom: { number } = table.create(n, math.huge)
	if not plan.rigid and nLegs > 0 then
		for k = 1, n do
			local frame = rootFrame(bx[k], floorAt[k] + rootH, bz[k], byaw[k])
			local off = offsetAt(k, 0)
			local body = M.xmul(frame, off)
			local need = 0
			for i = 1, nLegs do
				local leg = legs[i]
				-- planted feet, and feet just lifting off (the hip is still moving away from them
				-- while they pick up speed); a foot well into its swing can fold its leg instead
				if not leg.rigid and (footDown[i][k] or footU[i][k] < 0.2) then
					local hip = M.xpoint(body, hipLocalAt(i, (k - 1) * dt))
					-- the point IK places: the ankle of a foot-flat leg, the foot turned to its yaw
					-- and to its roll (a heel peeling up lifts the ankle with it)
					local yq = M.qaxis(M.UP, footYaw[i][k] - rig.facing)
					local fq = yq
					if footPitch[i][k] ~= 0 then
						fq = M.qmul(M.qaxis(M.qrot(yq, restRight), footPitch[i][k]), yq)
					end
					local fv = M.qrot(fq, leg.footVec)
					local fx, fy, fz = footX[i][k] - fv.x, footY[i][k] - fv.y, footZ[i][k] - fv.z
					local reach = 0.94 * leg.limbReach
					local dx, dz = hip.x - fx, hip.z - fz
					local dh2 = dx * dx + dz * dz
					local vert = hip.y - fy
					local allowed = math.sqrt(math.max(reach * reach - dh2, 0))
					local drop = vert - allowed
					if drop > need then
						need = drop
					end
					local m = 1.05 * leg.minReach
					if m > 0 and dh2 < m * m then
						local room = vert - math.sqrt(m * m - dh2)
						if room < foldRoom[k] then
							foldRoom[k] = math.max(room, 0)
						end
					end
				end
			end
			lowerBy[k] = math.min(need, maxDrop + math.max(0, dy[k]))
		end
		-- a smooth curve at or above every sample's need (so no foot is left over-reached)
		lowerBy = Signal.smoothFloor(lowerBy, 0.05 * rate, false)
		for k = 1, n do
			if foldRoom[k] == math.huge then
				foldRoom[k] = maxDrop + 10 * H
			end
		end
		-- and a smooth limit at or below every sample's room
		foldRoom = Signal.smoothCeiling(foldRoom, 0.05 * rate, false)
	end
	local squeezed = 0
	-- the floor of the body's travel is approached smoothly (a soft-plus knee a few percent of
	-- the hip height wide): a hard clamp would stop the body dead in one frame, a pop
	local knee = 0.03 * H
	for k = 1, n do
		local total = dy[k] - lowerBy[k]
		-- never so low a planted leg must fold past its limit, nor into the ground
		local floorDrop = math.min(maxDrop, foldRoom[k], bodyGap - tiltDrop[k])
		if -total - floorDrop > 0.02 * H then
			squeezed += 1
		end
		local z = (total + floorDrop) / knee
		if z < 20 then
			total = -floorDrop + knee * math.log(1 + math.exp(z))
		end
		dy[k] = total
	end
	if squeezed > 0 then
		table.insert(warnings, string.format("%d frame(s) where the legs could not all stay planted at this pace (some too short, some too long): the IK reports where", squeezed))
	end

	-- A swinging foot rides up with the body: in a hop or a run the body rises on its arc while
	-- the foot is in the air, and a foot left on the line between lift-off and landing would pull
	-- its leg straight and dead mid-flight. Each swing is lifted by how far the body has risen
	-- above the straight line between its heights at lift-off and at landing.
	local tuck: { { number } } = {}
	local flies = plan.flight or plan.kind == "pogo"
	-- a smooth ramp (no kink where the body crosses the line, which would be a pop)
	local kt = 0.01 * H
	for i = 1, nLegs do
		local list = table.create(n, 0)
		local k = if flies then 1 else n + 1
		while k <= n do
			if not footDown[i][k] then
				local a = k
				while k <= n and not footDown[i][k] do
					k += 1
				end
				local b = k - 1
				local ya = dy[math.max(a - 1, 1)]
				local yb = dy[math.min(b + 1, n)]
				local span = math.max(b - a + 2, 1)
				for m = a, b do
					local u = (m - a + 1) / span
					local x = dy[m] - (ya + (yb - ya) * u)
					list[m] = 0.5 * (x + math.sqrt(x * x + kt * kt)) - 0.5 * kt
				end
			else
				k += 1
			end
		end
		tuck[i] = list
	end

	-- 6. Pose every sample: body, legs, head, arms, tail.
	local animated: { number } = {}
	for k, j in rig.joints do
		if j.animated then
			table.insert(animated, k)
		end
	end
	local name = if type(o.name) == "string" then o.name else (if loopMode then "gait cycle" else "gait")
	local baked = Baked.new(name, "gait", rate, n, false, animated, if loopMode then "offset" else "world")
	local channelOf: { [number]: number } = {}
	for c, k in animated do
		channelOf[k] = c
	end

	local armMul = mult(o.arms, 1)
	local tailMul = mult(o.tail, 1)
	local headMul = mult(o.head, 1)
	-- arms: which leg each swings against
	local armLeg: { [number]: number } = {}
	if isBiped then
		for ai, arm in anatomy.arms do
			for li, leg in legs do
				if leg.side == arm.side and arm.side ~= 0 then
					armLeg[ai] = li
				end
			end
		end
	end
	local armSwing: { { number } } = {}
	for ai = 1, #anatomy.arms do
		local li = armLeg[ai]
		local sig: { number } = table.create(n, 0)
		if li then
			for k = 1, n do
				local frame = rootFrame(bx[k], 0, bz[k], byaw[k])
				local l = M.qinvrot(frame.q, M.vsub({ x = footX[li][k], y = 0, z = footZ[li][k] }, frame.p))
				local fwd = -(l.z - contactRest[li].z) / math.max(0.5 * cruiseStride, 1e-3)
				-- the arm swings against its own side's leg
				sig[k] = -M.clamp(fwd, -1, 1) * share[k]
			end
		end
		armSwing[ai] = Signal.gauss(sig, 0.04 * rate, false)
	end
	local runLike = plan.kind == "run" or plan.runFactor >= 1
	local fwdA = math.rad(if runLike then 14 else 26) * armMul
	local backA = math.rad(if runLike then 40 else 18) * armMul
	local elbowBase = math.rad(if runLike then 85 else 14) * math.min(armMul, 1)
	local lag1 = 1 / 30 * rate
	local lag2 = 2 / 30 * rate

	-- head look-ahead into turns
	local lookYaw: { number } = table.create(n, 0)
	for k = 1, n do
		local t = (k - 1) * dt
		local _, _, _, ahead = Path.at(track, t + 0.45)
		lookYaw[k] = M.clamp(M.wrapAngle(ahead - byaw[k]) * 0.6, -0.7, 0.7) * headMul
	end
	lookYaw = Signal.gauss(lookYaw, 0.08 * rate, false)
	local gaitPhase: { number } = phiAt

	local residualWorst = 0
	local residualSum = 0
	local residualCount = 0
	local unreachable = 0
	local footWorld: { { V3 } } = {}
	-- per sample: true where IK could not reach (a limit clamped it, or out of reach)
	local footClamped: { { boolean } } = {}
	for i = 1, nLegs do
		footWorld[i] = table.create(n)
		footClamped[i] = table.create(n, false)
	end

	local function axisFor(dirW: V3, around: V3): V3
		-- the axis that swings a limb pointing along dirW about `around`-ish without twisting it
		local a = M.vcross(dirW, around)
		if M.vlen(a) < 1e-4 then
			return M.RIGHT
		end
		return M.vnorm(a)
	end

	for k = 1, n do
		local t = (k - 1) * dt
		local s0 = k - 1
		local frame = rootFrame(bx[k], floorAt[k] + rootH, bz[k], byaw[k])
		local off = offsetAt(k, 0)
		local locals: { [number]: X } = {}
		local root: X
		if bodyJ then
			-- the body joint carries the offset: T = rest^-1 * O * rest
			local bj = rig.joints[bodyJ :: number]
			local parentRest = if bj.parent > 0 then rig.joints[bj.parent].world else M.xid()
			local restBody = M.xmul(parentRest, bj.rest)
			locals[bodyJ :: number] = M.xrel(restBody, M.xmul(off, restBody))
			root = frame
		else
			root = M.xmul(frame, off)
		end
		-- long bodies bend along the path
		if follow then
			for kk, a in trunkYaws(t) do
				if kk ~= bodyJ then
					locals[kk] = trunkLocal(kk, a)
				end
			end
		end
		-- the chest turns a little against the hips (bipeds)
		if isBiped and anatomy.chest and anatomy.chest ~= bodyJ then
			local ch = anatomy.chest :: number
			locals[ch] = trunkLocal(ch, -0.45 * twist[k])
		end
		local frames = Rig.fk(rig, locals, root)
		-- legs
		for i = 1, nLegs do
			local leg = legs[i]
			local target = { x = footX[i][k], y = footY[i][k] + tuck[i][k], z = footZ[i][k] }
			local first = leg.joints[1]
			local base = Rig.parentFrame(rig, frames, root, first)
			local footRot: Q? = nil
			if leg.ik == "twoFoot" or leg.ik == "chainFoot" or leg.ik == "aimFoot" then
				local fj = rig.joints[leg.movable[#leg.movable]]
				local restQ = fj.world.q
				local yq = M.qaxis(M.UP, footYaw[i][k] - rig.facing)
				local q = M.qmul(yq, restQ)
				-- the roll (late stance and early swing), plus a small toe-down through the swing
				-- that has zero slope at both ends, so the foot meets the ground without a pop
				local toe = footPitch[i][k]
				if not footDown[i][k] then
					local sb = math.sin(math.pi * footU[i][k])
					toe -= math.rad(6) * sb * sb
				end
				if toe ~= 0 then
					local right = M.qrot(yq, restRight)
					q = M.qmul(M.qaxis(right, toe), q)
				end
				footRot = q
			end
			local aimTarget = target
			if leg.rigid and not footDown[i][k] then
				-- a leg that cannot shorten swings slightly outward to clear the ground
				local outward = M.qrot(frame.q, { x = if leg.side ~= 0 then leg.side else 1, y = 0, z = 0 })
				local arch = math.sin(math.pi * footU[i][k])
				aimTarget = M.vmad(target, outward, 1.2 * stepHeight * arch)
			end
			local r = IK.solve(rig, leg, base, aimTarget, { footRot = footRot, body = root, side = leg.side }, locals, frames)
			footClamped[i][k] = r.clamped or not r.reachable
			-- the IK left this leg's frames current: where its contact actually is
			footWorld[i][k] = M.xpoint(frames[leg.joints[#leg.joints]], leg.foot)
			if footDown[i][k] and not leg.rigid then
				residualSum += r.residual
				residualCount += 1
				if r.residual > residualWorst then
					residualWorst = r.residual
				end
				if r.residual > 0.05 then
					unreachable += 1
				end
			end
		end
		-- head: level, looking into turns
		local headK = anatomy.head
		if headK and headMul > 0 then
			local chainJ: { number } = {}
			for _, nk in anatomy.neck do
				if rig.joints[nk].animated then
					table.insert(chainJ, nk)
				end
			end
			if rig.joints[headK :: number].animated then
				table.insert(chainJ, headK :: number)
			end
			if #chainJ > 0 then
				-- `frames` already holds the trunk as posed this sample (legs do not move it)
				local hk = headK :: number
				local cur = frames[hk].q
				local heading = byaw[k] - rig.facing
				local want = M.qmul(M.qaxis(M.UP, heading + lookYaw[k]), rig.joints[hk].world.q)
				local lw = lookW[k]
				if lookTarget and lw > 0 then
					-- face the target, within what a neck turns (75 degrees aside, 40 up or down)
					local hp = frames[hk].p
					local d = M.vsub(lookTarget :: V3, hp)
					local horiz = math.sqrt(d.x * d.x + d.z * d.z)
					local rel = M.clamp(M.wrapAngle(math.atan2(-d.x, -d.z) - heading), -1.3, 1.3)
					local lookPitch = M.clamp(math.atan2(d.y, math.max(horiz, 1e-6)), -0.7, 0.7)
					local yq = M.qaxis(M.UP, heading + rel)
					local wantLook = M.qmul(M.qmul(M.qaxis(M.qrot(yq, restRight), lookPitch), yq), rig.joints[hk].world.q)
					want = M.qslerp(want, wantLook, lw)
				end
				local fix = M.qmul(want, M.qconj(cur))
				fix = M.qslerp(M.qid(), fix, (0.75 + 0.25 * lw) * math.min(headMul, 1))
				local part = M.qslerp(M.qid(), fix, 1 / #chainJ)
				-- each joint takes an equal share, from the neck out, carrying its new frame down
				local carried: { [number]: X } = {}
				for _, nk in chainJ do
					local j = rig.joints[nk]
					local parent = if j.parent > 0 then (carried[j.parent] or frames[j.parent]) else root
					local f0 = M.xmul(parent, j.rest)
					local curL = locals[nk] or M.xid()
					local w = M.qmul(f0.q, curL.q)
					local newW = M.qmul(part, w)
					local q = M.qnorm(M.qmul(M.qconj(f0.q), newW))
					locals[nk] = { p = curL.p, q = q }
					carried[nk] = { p = M.vadd(f0.p, M.qrot(f0.q, curL.p)), q = M.qmul(f0.q, q) }
				end
			end
		end
		-- arms swing against the legs; the forearm and hand trail the upper arm
		for ai, arm in anatomy.arms do
			local sig = armSwing[ai]
			if #arm.movable == 0 then
				continue
			end
			local a0 = Signal.sampleAt(sig, k, false)
			local a1 = Signal.sampleAt(sig, k - lag1, false)
			local a2 = Signal.sampleAt(sig, k - lag2, false)
			local function angleOf(x: number): number
				return if x >= 0 then x * fwdA else x * backA
			end
			local m1 = arm.movable[1]
			local j1 = rig.joints[m1]
			-- the swing axis in the character's frame: perpendicular to the arm and to forward
			local dir = M.vnorm(M.vsub(M.xpoint(j1.world, j1.tip), j1.world.p), { x = 0, y = -1, z = 0 })
			local axis = axisFor(dir, M.FORWARD)
			local wq = j1.world.q
			local function bend(kk: number, ang: number)
				local jj = rig.joints[kk]
				local w = jj.world.q
				local axisL = M.qinvrot(w, axis)
				local cur = locals[kk] or M.xid()
				locals[kk] = { p = cur.p, q = M.qnorm(M.qmul(cur.q, M.qaxis(axisL, ang))) }
			end
			local _ = wq
			bend(m1, angleOf(a0) * share[k])
			if arm.movable[2] then
				local flex = elbowBase * share[k] + math.max(0, a1) * math.rad(18) * armMul
				bend(arm.movable[2], flex)
			end
			if arm.movable[3] then
				bend(arm.movable[3], angleOf(a2) * 0.25 * share[k])
			end
		end
		-- tails sway behind the hips, each segment a little later
		if tailMul > 0 then
			for _, tail in anatomy.tails do
				for si, kk in tail.movable do
					local jj = rig.joints[kk]
					local dir = M.vnorm(M.qrot(jj.world.q, jj.tip), { x = 0, y = 0, z = 1 })
					local up = M.vreject(M.UP, dir)
					local axis = if M.vlen(up) > 1e-3 then M.vnorm(up) else M.FORWARD
					local lagPhase = gaitPhase[k] - 0.08 * si
					local amp = math.rad(5) * share[k] * tailMul
					local turn = -byawRate[k] * 0.1 * tailMul
					local ang = amp * math.sin(2 * math.pi * lagPhase) + M.clamp(turn, -0.3, 0.3) / math.max(#tail.movable, 1)
					local axisL = M.qinvrot(jj.world.q, axis)
					local cur = locals[kk] or M.xid()
					locals[kk] = { p = cur.p, q = M.qnorm(M.qmul(cur.q, M.qaxis(axisL, ang))) }
				end
			end
		end
		-- write
		if loopMode then
			-- in-place: the root channel is the offset from the travelling path frame
			local pathFrame = rootFrame(bx[k], floor0 + rootH, bz[k], byaw[k])
			Baked.set(baked, s0, 0, M.xrel(pathFrame, root))
		else
			Baked.set(baked, s0, 0, root)
		end
		for kk, l in locals do
			local c = channelOf[kk]
			if c then
				Baked.set(baked, s0, c, l)
			end
		end

	end

	-- In a hop, a run or a gallop a foot strikes and leaves the ground in an instant: mark each
	-- touchdown and lift-off as a contact, so the pop lint takes the snap there for the impact
	-- it is. Walks get no marks: a walking foot must arrive and leave smoothly.
	if plan.flight or plan.kind == "pogo" then
		for i = 1, nLegs do
			for k = 2, n do
				if footDown[i][k] ~= footDown[i][k - 1] then
					table.insert(baked.markers, { name = "contact", time = (k - 1) * dt })
				end
			end
		end
	end
	-- contacts for the review timeline and the lint
	for i = 1, nLegs do
		local k = 1
		while k <= n do
			if footDown[i][k] then
				local a = k
				while k <= n and footDown[i][k] do
					k += 1
				end
				table.insert(baked.contacts, { leg = i, from = (a - 1) * dt, to = (k - 2) * dt })
			else
				k += 1
			end
		end
	end
	Baked.finish(baked)
	baked.info = {
		plan = plan,
		gait = plan.kind,
		speed = cruise,
		period = plan.period,
		duty = plan.duty,
		stride = cruiseStride,
		legs = nLegs,
		footDown = footDown,
		footWorld = footWorld,
		footClamped = footClamped,
		footTarget = { x = footX, y = footY, z = footZ },
		catchUps = catchUps,
		lookWeights = lookW,
		residualWorst = residualWorst,
		residualMean = if residualCount > 0 then residualSum / residualCount else 0,
		unreachable = unreachable,
		bodyGap = bodyGap,
		ground = floor0,
		groundFn = groundFn,
		start = start,
		hipHeight = H,
		warnings = warnings,
		reasons = plan.reasons,
	}
	for _, w in warnings do
		table.insert(baked.warnings, w)
	end
	if loopMode then
		return Locomotion.cutLoop(baked, plan.period, plan.period)
	end
	return baked
end

--[[
	Cuts the last full cycle out of a three-cycle in-place bake and resamples it so its length is
	exactly one period: a loop whose seam is the same pose on both sides.
]]
function Locomotion.cutLoop(b: Baked.Baked, period: number, endGap: number?): Baked.Baked
	local rate = b.rate
	local count = math.max(2, math.floor(period * rate + 0.5) + 1)
	local exactRate = (count - 1) / period
	local loop = Baked.new(b.name, "gait", exactRate, count, true, b.joints, "offset")
	local buf = Baked.buffer(b)
	local t0 = math.max(0, b.length - period - (endGap or 0))
	for s = 0, count - 1 do
		Baked.sample(b, t0 + s / exactRate, buf)
		for c = 0, b.nch do
			Baked.set(loop, s, c, Baked.channel(buf, c))
		end
	end
	Baked.finish(loop)
	loop.info = table.clone(b.info)
	loop.info.loopFrom = t0
	-- contacts inside the cut, shifted to the loop's clock
	for _, c in b.contacts do
		local from, to = c.from - t0, c.to - t0
		if to >= 0 and from <= period then
			table.insert(loop.contacts, { leg = c.leg, from = math.max(0, from), to = math.min(period, to) })
		end
	end
	loop.warnings = b.warnings
	return loop
end

return Locomotion
