--!strict
--[[
	IK: puts the end of a chain on a target and says how close it got.

	Four solvers, picked by how many joints in the chain can move (Anatomy sets chain.ik):
	- zero    nothing moves; the end is wherever the body puts it (the residual says how far off)
	- aim     one joint turns so its segment points at the target (a peg leg, a head)
	- two     the analytic two-bone solve (thigh and shin), bending towards a pole
	- twoFoot two bones to the ankle, then the foot turned to a given world orientation
	- chain   FABRIK over any number of joints from a smooth arc, then joint rotations
	- chainFoot  the same to the ankle of a chain ending in a small foot, then the foot turned

	Two rules keep the result from reading as machine-made:
	- Every rotation is the shortest swing that does the job (Math.qbetween), so no solver ever
	  adds a turn about a limb's own long axis. Unmotivated twist is one of the tells the owner
	  saw; it cannot come from here.
	- The bend side comes from the rest pose (where the knee points when standing), recomputed
	  in the body's current frame each call, so a knee never flips from front to back between
	  frames. A chain that is straight at rest bends forward (legs) or backward (arms).

	Near full extension a two-bone solve is hypersensitive (a hair of target motion swings the
	knee a long way) and pops. `soft` (default 0.985 of the reach) eases the last stretch so the
	end lags the target slightly rather than snapping; the gait planner keeps planted feet inside
	that range, so they still land exactly.

	Limits (per joint, Euler XYZ in the joint's frame) are applied as the chain is solved, so the
	joints after a clamped one make up what they can. Results report the residual distance and
	whether anything was clamped or out of reach. Nothing throws, and nothing returns NaN.
]]

local M = require("./Math")
local Rig = require("./Rig")
local Anatomy = require("./Anatomy")

type V3 = M.V3
type Q = M.Q
type X = M.X

local IK = {}

export type Options = {
	-- world direction the bend should face (a knee's front)
	pole: V3?,
	-- twoFoot: the foot's desired world orientation
	footRot: Q?,
	-- fraction of the reach where softening begins; 1 disables it
	soft: number?,
	-- FABRIK iterations at most (default 48; it stops early once within 1e-5 of the reach)
	iterations: number?,
	-- treat the chain as an arm (straight chains bend down and back) instead of a leg
	arm: boolean?,
	-- the chain's side (-1 left, 1 right, 0 middle), to bend a little outward
	side: number?,
	-- solve a foot-flat leg as a plain chain, the foot following the shin (a kick, a paw swipe)
	freeEnd: boolean?,
	-- the body's frame, for the default bend side of straight chains
	body: X?,
}

export type Result = {
	residual: number,
	clamped: boolean,
	reachable: boolean,
}

-- Clamps a local rotation to the joint's Euler limits. Returns it and whether it changed.
function IK.limit(joint: Rig.Joint, q: Q): (Q, boolean)
	local lim = joint.limits
	if not lim then
		return q, false
	end
	local rx, ry, rz = M.qtoeuler(q)
	local cx = M.clamp(rx, lim.min.x, lim.max.x)
	local cy = M.clamp(ry, lim.min.y, lim.max.y)
	local cz = M.clamp(rz, lim.min.z, lim.max.z)
	if cx == rx and cy == ry and cz == rz then
		return q, false
	end
	return M.qeuler(cx, cy, cz), true
end

local function untransformed(parent: X, joint: Rig.Joint): X
	return M.xmul(parent, joint.rest)
end

-- Sets local `q` on joint k with limits; writes locals[k] and frames[k]. Returns clamped.
local function setJoint(rig: Rig.Rig, k: number, parent: X, worldRot: Q, locals: { [number]: X }, frames: { X }): boolean
	local joint = rig.joints[k]
	local f0 = untransformed(parent, joint)
	-- f0.q * T = worldRot
	local q = M.qnorm(M.qmul(M.qconj(f0.q), worldRot))
	local clamped = false
	q, clamped = IK.limit(joint, q)
	locals[k] = { p = { x = 0, y = 0, z = 0 }, q = q }
	frames[k] = { p = f0.p, q = M.qmul(f0.q, q) }
	return clamped
end

-- Sets every chain joint to identity and recomputes their frames (welds stay fixed).
local function resetChain(rig: Rig.Rig, chain: Anatomy.Chain, base: X, locals: { [number]: X }, frames: { X })
	local parent = base
	for _, k in chain.joints do
		local joint = rig.joints[k]
		local f = untransformed(parent, joint)
		if joint.animated then
			locals[k] = M.xid()
			frames[k] = f
		else
			-- a weld keeps whatever fixed offset it has (identity unless something set it)
			frames[k] = M.xmul(f, locals[k] or M.xid())
		end
		parent = frames[k]
	end
end

local function parentFrameOf(rig: Rig.Rig, k: number, base: X, frames: { X }, chain: Anatomy.Chain): X
	local p = rig.joints[k].parent
	if p == 0 then
		return base
	end
	if p == rig.joints[chain.joints[1]].parent then
		return base
	end
	return frames[p]
end

local function contactNow(rig: Rig.Rig, chain: Anatomy.Chain, frames: { X }): V3
	local last = chain.joints[#chain.joints]
	return M.xpoint(frames[last], chain.foot)
end

-- The side a straight chain bends towards: forward for legs, backward for arms.
local function defaultPole(opts: Options, dir: V3): V3
	--[[
		Where a straight limb bends: a knee forward (a little outward), an elbow down, back and a
		little out. Each preferred side is chosen so that the reaches a limb usually makes (a foot
		below, a hand forward) are far from parallel to it: near parallel, the part of it across the
		limb is tiny and its direction swings wildly with the target, and the joint flips. When it
		does get close, a second direction at right angles is blended in smoothly, never switched.
	]]
	local bodyQ = if opts.body then (opts.body :: X).q else M.qid()
	local side = opts.side or 0
	local primary: V3
	local secondary: V3
	if opts.arm then
		primary = M.qrot(bodyQ, M.vnorm({ x = 0.35 * side, y = -1, z = 0.6 }))
		secondary = M.qrot(bodyQ, M.vnorm({ x = side, y = 0, z = 0.2 }))
	else
		-- a leg reaching down bends its knee forward; one reaching out along the ground (an arm
		-- lying flat, a sprawled leg) arches up off it, the way a starfish's or a lizard's does.
		-- In between the two are blended by how level the reach is, so the bend never swaps
		-- sides as the foot sweeps past the front.
		local level = math.abs(M.qinvrot(bodyQ, dir).y)
		local b = M.clamp((0.75 - level) / 0.5, 0, 1)
		b = b * b * (3 - 2 * b)
		local fwd = M.vnorm({ x = 0.15 * side, y = 0, z = -1 })
		primary = M.qrot(bodyQ, M.vnorm(M.vadd(M.vmul(fwd, 1 - b), M.vmul(M.UP, b))))
		secondary = M.qrot(bodyQ, M.vnorm(M.vadd(M.vmul(M.UP, 1 - b), M.vmul(fwd, b))))
	end
	local p1 = M.vreject(primary, dir)
	local p2 = M.vreject(secondary, dir)
	local l1 = M.vlen(p1)
	-- full weight on the secondary only as the primary runs along the limb
	local w = M.clamp(1 - l1 / 0.5, 0, 1)
	local p = M.vadd(p1, M.vmul(p2, w * w * (3 - 2 * w)))
	if M.vlen(p) < 1e-6 then
		p = M.vperp(dir)
	end
	return M.vnorm(p)
end

local function soften(d: number, reach: number, soft: number): number
	local d0 = soft * reach
	if d <= d0 or soft >= 1 then
		return math.min(d, reach)
	end
	-- exponential approach to the full reach from d0
	local span = reach - d0
	return d0 + span * (1 - math.exp(-(d - d0) / math.max(span, 1e-9)))
end

-- Zero bones: nothing to move.
local function solveZero(rig: Rig.Rig, chain: Anatomy.Chain, base: X, target: V3, locals: { [number]: X }, frames: { X }): Result
	resetChain(rig, chain, base, locals, frames)
	local c = contactNow(rig, chain, frames)
	local r = M.vdist(c, target)
	return { residual = r, clamped = false, reachable = r < 1e-3 }
end

--[[
	Turns joint k so the point `local` (in its frame) points at `target`. Returns whether a limit
	clamped it. Used by aim chains and by look-at.
]]
function IK.aimJoint(rig: Rig.Rig, k: number, parent: X, pointLocal: V3, target: V3, share: number, locals: { [number]: X }, frames: { X }): boolean
	local joint = rig.joints[k]
	local f0 = untransformed(parent, joint)
	local from = M.qrot(f0.q, pointLocal)
	local to = M.vsub(target, f0.p)
	if M.vlen(from) < 1e-9 or M.vlen(to) < 1e-9 then
		locals[k] = M.xid()
		frames[k] = f0
		return false
	end
	local r = M.qbetween(from, to)
	if share < 1 then
		r = M.qslerp(M.qid(), r, math.max(0, share))
	end
	return setJoint(rig, k, parent, M.qmul(r, f0.q), locals, frames)
end

local function solveAim(rig: Rig.Rig, chain: Anatomy.Chain, base: X, target: V3, locals: { [number]: X }, frames: { X }): Result
	resetChain(rig, chain, base, locals, frames)
	local k = chain.movable[1]
	-- the contact expressed in the movable joint's frame (welds after it ride along)
	local last = chain.joints[#chain.joints]
	local cWorld = M.xpoint(frames[last], chain.foot)
	local pointLocal = M.qinvrot(frames[k].q, M.vsub(cWorld, frames[k].p))
	local parent = parentFrameOf(rig, k, base, frames, chain)
	local clamped = IK.aimJoint(rig, k, parent, pointLocal, target, 1, locals, frames)
	-- carry the frames of anything after it
	local after = false
	local p = frames[k]
	for _, j in chain.joints do
		if after then
			local joint = rig.joints[j]
			frames[j] = M.xmul(untransformed(p, joint), locals[j] or M.xid())
			p = frames[j]
		elseif j == k then
			after = true
		end
	end
	local c = contactNow(rig, chain, frames)
	local r = M.vdist(c, target)
	local reach = M.vlen(pointLocal)
	local d = M.vdist(frames[k].p, target)
	return { residual = r, clamped = clamped, reachable = math.abs(d - reach) < 1e-3 }
end

--[[
	One leg segment and a foot: the leg turns to point its ankle where the foot's pivot must be
	for the contact to land on target with the foot turned to `footRot`, then the foot is turned.
	The foot is never used as a knee (it would spin wildly to make up the leg's length).
]]
local function solveAimFoot(rig: Rig.Rig, chain: Anatomy.Chain, base: X, target: V3, opts: Options, locals: { [number]: X }, frames: { X }): Result
	resetChain(rig, chain, base, locals, frames)
	local k = chain.movable[1]
	local foot = chain.movable[2]
	local fRest = frames[foot]
	local footRot = opts.footRot or fRest.q
	local contact = contactNow(rig, chain, frames)
	local contactInFoot = M.qinvrot(fRest.q, M.vsub(contact, fRest.p))
	local ankleTarget = M.vsub(target, M.qrot(footRot, contactInFoot))
	local pointLocal = M.qinvrot(frames[k].q, M.vsub(fRest.p, frames[k].p))
	local parent = parentFrameOf(rig, k, base, frames, chain)
	local clamped = IK.aimJoint(rig, k, parent, pointLocal, ankleTarget, 1, locals, frames)
	-- carry the frames down to the foot's parent, set the foot, then anything after it
	local p = frames[k]
	local after = false
	for _, j in chain.joints do
		if j == k then
			after = true
		elseif after and j == foot then
			if setJoint(rig, foot, p, footRot, locals, frames) then
				clamped = true
			end
			p = frames[foot]
		elseif after then
			frames[j] = M.xmul(untransformed(p, rig.joints[j]), locals[j] or M.xid())
			p = frames[j]
		end
	end
	local c = contactNow(rig, chain, frames)
	local residual = M.vdist(c, target)
	local L = M.vlen(pointLocal)
	local d = M.vdist(frames[k].p, ankleTarget)
	return { residual = residual, clamped = clamped, reachable = math.abs(d - L) < math.max(1e-3, 1e-3 * L) }
end

--[[
	Two bones: joint A (hip) and B (knee), end point E given in B's frame. The bend plane holds
	the pole; the angle comes from the law of cosines. Both rotations are then the shortest
	swings that carry the rest directions onto the solved ones, with A's also lining up the bend
	plane, so the result has no twist the rest pose did not have.
]]
local function twoBone(
	rig: Rig.Rig,
	a: number,
	b: number,
	baseA: X,
	endLocalB: V3,
	target: V3,
	pole: V3?,
	opts: Options,
	locals: { [number]: X },
	frames: { X }
): (V3, boolean, boolean)
	local ja, jb = rig.joints[a], rig.joints[b]
	local fa0 = untransformed(baseA, ja)
	local A = fa0.p
	-- rest positions with both identity
	local fb0 = untransformed(fa0, jb)
	local B0 = fb0.p
	local E0 = M.xpoint(fb0, endLocalB)
	local la = M.vdist(A, B0)
	local lb = M.vdist(B0, E0)
	local toT = M.vsub(target, A)
	local dRaw = M.vlen(toT)
	local reach = la + lb
	local u = M.vnorm(toT, M.vnorm(M.vsub(E0, A), { x = 0, y = -1, z = 0 }))
	-- soften only past the rest pose's own stretch, so standing still reproduces the rest pose
	local soft = math.max(opts.soft or 0.985, M.vdist(A, E0) / math.max(reach, 1e-12) + 1e-9)
	local d = soften(dRaw, reach, soft)
	local reachable = dRaw <= reach * soft + 1e-9 and dRaw >= math.abs(la - lb) - 1e-9
	d = math.max(d, math.abs(la - lb) + 1e-6 * math.max(reach, 1e-6))
	if la < 1e-9 or lb < 1e-9 then
		-- a zero-length bone: aim the whole thing instead
		local pointLocal = M.qinvrot(fa0.q, M.vsub(E0, A))
		local clamped = IK.aimJoint(rig, a, baseA, pointLocal, target, 1, locals, frames)
		frames[b] = untransformed(frames[a], jb)
		locals[b] = M.xid()
		return M.xpoint(frames[b], endLocalB), clamped, false
	end
	-- the pole: the rest knee's offset from the A-E line, else the given or default side
	local restDir = M.vnorm(M.vsub(E0, A))
	local p = M.vreject(M.vsub(B0, A), restDir)
	local poleW: V3
	if pole then
		poleW = M.vnorm(M.vreject(pole :: V3, u), defaultPole(opts, u))
	elseif M.vlen(p) > 1e-4 * reach then
		-- keep the rest bend side, carried by the shortest swing from the rest line to the target line
		local swing = M.qbetween(restDir, u)
		poleW = M.vnorm(M.vreject(M.qrot(swing, p), u), defaultPole(opts, u))
	else
		poleW = defaultPole(opts, u)
	end
	local cosA = M.clamp((la * la + d * d - lb * lb) / (2 * la * d), -1, 1)
	local sinA = math.sqrt(math.max(0, 1 - cosA * cosA))
	local Bt = M.vadd(A, M.vadd(M.vmul(u, la * cosA), M.vmul(poleW, la * sinA)))
	local Et = M.vmad(A, u, d)
	-- A: the shortest swing of the thigh onto its new direction. Not a full frame alignment:
	-- matching the bend plane exactly would turn the thigh about its own axis as the plane
	-- swings through a stride, a twist that reads as random on any mesh. The knee bends in the
	-- right plane anyway because B is placed there.
	local v0 = M.vsub(B0, A)
	local v1 = M.vsub(Bt, A)
	local rA = M.qbetween(v0, v1)
	local clampedA = setJoint(rig, a, baseA, M.qmul(rA, fa0.q), locals, frames)
	-- B: the shortest swing of its segment onto B -> E
	local fb1 = untransformed(frames[a], jb)
	local Ecur = M.xpoint(fb1, endLocalB)
	local rB = M.qbetween(M.vsub(Ecur, fb1.p), M.vsub(Et, fb1.p))
	local clampedB = setJoint(rig, b, frames[a], M.qmul(rB, fb1.q), locals, frames)
	return M.xpoint(frames[b], endLocalB), clampedA or clampedB, reachable
end

--[[
	The rotation taking the frame spanned by (v0, n0) onto the one spanned by (v1, n1): v0 maps
	exactly onto v1's direction and n0 as near n1 as that allows.
]]
function IK.align(v0: V3, n0: V3, v1: V3, n1: V3): Q
	local e1 = M.vnorm(v0)
	local e2 = M.vnorm(M.vreject(n0, e1), M.vperp(e1))
	local e3 = M.vcross(e1, e2)
	local f1 = M.vnorm(v1)
	local f2 = M.vnorm(M.vreject(n1, f1), M.vperp(f1))
	local f3 = M.vcross(f1, f2)
	-- R = F * E^T, as a matrix, then a quaternion
	local r00 = f1.x * e1.x + f2.x * e2.x + f3.x * e3.x
	local r01 = f1.x * e1.y + f2.x * e2.y + f3.x * e3.y
	local r02 = f1.x * e1.z + f2.x * e2.z + f3.x * e3.z
	local r10 = f1.y * e1.x + f2.y * e2.x + f3.y * e3.x
	local r11 = f1.y * e1.y + f2.y * e2.y + f3.y * e3.y
	local r12 = f1.y * e1.z + f2.y * e2.z + f3.y * e3.z
	local r20 = f1.z * e1.x + f2.z * e2.x + f3.z * e3.x
	local r21 = f1.z * e1.y + f2.z * e2.y + f3.z * e3.y
	local r22 = f1.z * e1.z + f2.z * e2.z + f3.z * e3.z
	return M.qfrommatrix(r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

local function consecutive(rig: Rig.Rig, js: { number }): boolean
	for i = 2, #js do
		if rig.joints[js[i]].parent ~= js[i - 1] then
			return false
		end
	end
	return true
end

local function solveTwo(rig: Rig.Rig, chain: Anatomy.Chain, base: X, target: V3, opts: Options, locals: { [number]: X }, frames: { X }): Result
	resetChain(rig, chain, base, locals, frames)
	local a, b = chain.movable[1], chain.movable[2]
	local endLocal = M.qinvrot(frames[b].q, M.vsub(contactNow(rig, chain, frames), frames[b].p))
	local parent = parentFrameOf(rig, a, base, frames, chain)
	local _, clamped, reachable = twoBone(rig, a, b, parent, endLocal, target, opts.pole, opts, locals, frames)
	-- anything after b (welds) rides along
	local after = false
	local p = frames[b]
	for _, j in chain.joints do
		if after then
			frames[j] = M.xmul(untransformed(p, rig.joints[j]), locals[j] or M.xid())
			p = frames[j]
		elseif j == b then
			after = true
		end
	end
	local c = contactNow(rig, chain, frames)
	local residual = M.vdist(c, target)
	return { residual = residual, clamped = clamped, reachable = reachable and residual <= math.min(1e-3 * chain.reach, 0.02) + 1e-4 }
end

local function solveTwoFoot(rig: Rig.Rig, chain: Anatomy.Chain, base: X, target: V3, opts: Options, locals: { [number]: X }, frames: { X }): Result
	resetChain(rig, chain, base, locals, frames)
	local a, b, f = chain.movable[1], chain.movable[2], chain.movable[3]
	local jf = rig.joints[f]
	-- the foot's wanted world orientation: given, or as it stands at rest under the body
	local fRest = frames[f]
	local footRot = opts.footRot or fRest.q
	-- with the foot turned to footRot, where must the ankle be for the contact to land on target?
	local last = chain.joints[#chain.joints]
	local contactInFoot = M.qinvrot(fRest.q, M.vsub(M.xpoint(frames[last], chain.foot), fRest.p))
	local contactW = M.qrot(footRot, contactInFoot)
	local ankleTarget = M.vsub(target, contactW)
	-- the ankle pivot in b's frame
	local ankleLocal = jf.rest.p
	local parent = parentFrameOf(rig, a, base, frames, chain)
	local _, clamped, reachable = twoBone(rig, a, b, parent, ankleLocal, ankleTarget, opts.pole, opts, locals, frames)
	local clampedF = setJoint(rig, f, frames[b], footRot, locals, frames)
	local after = false
	local p = frames[f]
	for _, j in chain.joints do
		if after then
			frames[j] = M.xmul(untransformed(p, rig.joints[j]), locals[j] or M.xid())
			p = frames[j]
		elseif j == f then
			after = true
		end
	end
	local c = contactNow(rig, chain, frames)
	local residual = M.vdist(c, target)
	return { residual = residual, clamped = clamped or clampedF, reachable = reachable and residual <= math.min(1e-3 * chain.reach, 0.02) + 1e-4 }
end

--[[
	Many joints (a vine, a tentacle, an insect leg): FABRIK started from a smooth arc.

	The start matters more than the iterations. A chain with more joints than it needs can
	reach the same point in endless shapes, and FABRIK keeps whichever is nearest its start, so
	starting from the last frame lets the shape wander from frame to frame: jitter. Starting
	instead from one deterministic shape per target (the circular arc of the chain's length from
	the base to the target, bowed the way the chain bends at rest) gives the same answer for the
	same target every time and a smooth one as the target moves. FABRIK then only corrects the
	arc's chords to the true segment lengths.

	`upTo` solves only the first upTo movable joints, to put the next joint's pivot on the target
	(a foot-flat chain solves to its ankle, then turns the foot).
]]
local function arcPoint(c: V3, x: V3, y: V3, r: number, angle: number): V3
	return M.vadd(c, M.vadd(M.vmul(x, r * math.cos(angle)), M.vmul(y, r * math.sin(angle))))
end

local function solveNodes(
	rig: Rig.Rig,
	chain: Anatomy.Chain,
	mov: { number },
	endLocal: V3,
	base: X,
	target: V3,
	opts: Options,
	locals: { [number]: X },
	frames: { X }
): (boolean, boolean, number)
	local m = #mov
	-- nodes: each movable pivot, then the end point (at identity, under the current base)
	local pts: { V3 } = table.create(m + 1)
	for i = 1, m do
		pts[i] = frames[mov[i]].p
	end
	pts[m + 1] = M.xpoint(frames[mov[m]], endLocal)
	local lens: { number } = table.create(m)
	local total = 0
	for i = 1, m do
		lens[i] = M.vdist(pts[i], pts[i + 1])
		total += lens[i]
	end
	local origin = pts[1]
	if total < 1e-9 then
		return false, false, 0
	end
	local restEnd = pts[m + 1]
	local restDir = M.vnorm(M.vsub(restEnd, origin))
	local restStretch = M.vdist(origin, restEnd)
	local toT = M.vsub(target, origin)
	local dT = M.vlen(toT)
	local u = M.vnorm(toT, restDir)
	local soft = math.max(opts.soft or 0.985, restStretch / total + 1e-9)
	local dS = soften(dT, total, soft)
	local longest = 0
	for i = 1, m do
		longest = math.max(longest, lens[i])
	end
	local fold = math.max(0, 2 * longest - total)
	local reachable = dT <= total * soft + 1e-9 and dT >= fold - 1e-6 * total
	dS = math.max(dS, fold)
	-- the bend side: the rest shape's overall bow off its own line (offsets weighted towards the
	-- middle, as an arc bows), carried round onto the target line. A zig-zag rest shape bows
	-- nowhere overall and takes the default side: picking its largest kink instead would flip
	-- the bend from frame to frame as different kinks took the lead.
	local bow = { x = 0, y = 0, z = 0 }
	local acc0 = 0
	for i = 2, m do
		acc0 += lens[i - 1]
		local off = M.vreject(M.vsub(pts[i], origin), restDir)
		bow = M.vmad(bow, off, math.sin(math.pi * acc0 / total))
	end
	if M.vlen(bow) < 0.02 * total then
		bow = { x = 0, y = 0, z = 0 }
	end
	local pole: V3
	if opts.pole then
		pole = M.vnorm(M.vreject(opts.pole :: V3, u), defaultPole(opts, u))
	elseif M.vlen(bow) > 1e-4 * total then
		pole = M.vnorm(M.vreject(M.qrot(M.qbetween(restDir, u), bow), u), defaultPole(opts, u))
	else
		pole = defaultPole(opts, u)
	end
	-- the arc of length `total` from origin to origin + u * dS, bowing towards the pole
	if dS >= total * (1 - 1e-7) then
		for i = 2, m + 1 do
			pts[i] = M.vmad(pts[i - 1], u, lens[i - 1])
		end
	else
		local ratio = math.max(dS / total, 1e-6)
		-- sin(t/2) / (t/2) = ratio, for the arc's angle t in (0, 2 pi): bisection
		local lo, hi = 1e-9, 2 * math.pi - 1e-9
		for _ = 1, 50 do
			local mid = (lo + hi) / 2
			local f = math.sin(mid / 2) / (mid / 2)
			if f > ratio then
				lo = mid
			else
				hi = mid
			end
		end
		local theta = (lo + hi) / 2
		local r = total / theta
		local cMid = M.vmad(origin, u, dS / 2)
		local centre = M.vmad(cMid, pole, -r * math.cos(theta / 2))
		local a0 = math.atan2(r * math.cos(theta / 2), -dS / 2)
		local acc = 0
		for i = 2, m + 1 do
			acc += lens[i - 1]
			pts[i] = arcPoint(centre, u, pole, r, a0 - acc / r)
		end
	end
	local goal = M.vmad(origin, u, dS)
	-- A fixed number of passes, never "until close enough": stopping early after a different
	-- number of passes on neighbouring frames lands on visibly different shapes of a redundant
	-- chain (a shoulder that wobbles while the hand moves smoothly). The same passes every
	-- frame make the result a smooth function of the target.
	local iterations = opts.iterations or 64
	local tol = 0
	local px: { number } = table.create(m + 1, 0)
	local py: { number } = table.create(m + 1, 0)
	local pz: { number } = table.create(m + 1, 0)
	for i = 1, m + 1 do
		px[i], py[i], pz[i] = pts[i].x, pts[i].y, pts[i].z
	end
	local gx, gy, gz = goal.x, goal.y, goal.z
	local ox, oy, oz = origin.x, origin.y, origin.z
	local lx, ly, lz = u.x, u.y, u.z
	local tol2 = tol * tol
	local _ = tol2
	for _ = 1, iterations do
		-- backward: from the goal
		px[m + 1], py[m + 1], pz[m + 1] = gx, gy, gz
		for i = m, 1, -1 do
			local dx, dy, dz = px[i] - px[i + 1], py[i] - py[i + 1], pz[i] - pz[i + 1]
			local l = math.sqrt(dx * dx + dy * dy + dz * dz)
			if l < 1e-12 then
				dx, dy, dz, l = -lx, -ly, -lz, 1
			end
			local k = lens[i] / l
			px[i], py[i], pz[i] = px[i + 1] + dx * k, py[i + 1] + dy * k, pz[i + 1] + dz * k
		end
		-- forward: from the fixed origin
		px[1], py[1], pz[1] = ox, oy, oz
		for i = 1, m do
			local dx, dy, dz = px[i + 1] - px[i], py[i + 1] - py[i], pz[i + 1] - pz[i]
			local l = math.sqrt(dx * dx + dy * dy + dz * dz)
			if l < 1e-12 then
				dx, dy, dz, l = lx, ly, lz, 1
			end
			local k = lens[i] / l
			px[i + 1], py[i + 1], pz[i + 1] = px[i] + dx * k, py[i] + dy * k, pz[i] + dz * k
		end
	end
	for i = 1, m + 1 do
		pts[i] = { x = px[i], y = py[i], z = pz[i] }
	end
	-- joint rotations: each the shortest swing of its rigid stretch onto the solved segment
	local clamped = false
	for i = 1, m do
		local k = mov[i]
		local parent = parentFrameOf(rig, k, base, frames, chain)
		local f0 = untransformed(parent, rig.joints[k])
		-- where the next node sits relative to this joint at identity: walk the rigid stretch
		local nextLocal: V3
		if i < m then
			local nk = mov[i + 1]
			local cur = M.xid()
			local walking = false
			for _, j in chain.joints do
				if j == k then
					walking = true
				elseif walking then
					cur = M.xmul(cur, rig.joints[j].rest)
					if j == nk then
						break
					end
					cur = M.xmul(cur, locals[j] or M.xid())
				end
			end
			nextLocal = cur.p
		else
			nextLocal = endLocal
		end
		local from = M.qrot(f0.q, nextLocal)
		local to = M.vsub(pts[i + 1], f0.p)
		local r = M.qbetween(from, to)
		if setJoint(rig, k, parent, M.qmul(r, f0.q), locals, frames) then
			clamped = true
		end
		-- frames of the welds after k, up to the next movable joint
		local walking = false
		local p = frames[k]
		for _, j in chain.joints do
			if j == k then
				walking = true
			elseif walking then
				if rig.joints[j].animated then
					break
				end
				frames[j] = M.xmul(untransformed(p, rig.joints[j]), locals[j] or M.xid())
				p = frames[j]
			end
		end
	end
	return reachable, clamped, total
end

-- The point `point` (world, under the chain at identity) in joint k's frame at identity, walking
-- any welds after k.
local function localUnder(chain: Anatomy.Chain, frames: { X }, k: number, point: V3): V3
	local f = frames[k]
	return M.qinvrot(f.q, M.vsub(point, f.p))
end

local function solveChain(rig: Rig.Rig, chain: Anatomy.Chain, base: X, target: V3, opts: Options, locals: { [number]: X }, frames: { X }): Result
	resetChain(rig, chain, base, locals, frames)
	local mov = chain.movable
	local m = #mov
	local contact = contactNow(rig, chain, frames)
	local endLocal = localUnder(chain, frames, mov[m], contact)
	local reachable, clamped, total = solveNodes(rig, chain, mov, endLocal, base, target, opts, locals, frames)
	local c = contactNow(rig, chain, frames)
	local residual = M.vdist(c, target)
	return { residual = residual, clamped = clamped, reachable = reachable and residual <= math.min(1e-3 * total, 0.02) + 1e-4 }
end

--[[
	A chain ending in a small foot: solve the rest of the chain to put the foot's pivot where it
	must be for the contact to land on target with the foot turned to `footRot`, then turn it.
	Without this the tiny last segment would be aimed like any other, and a tiny lever swings
	wildly for a hair of error: a whipping, buzzing foot.
]]
local function solveChainFoot(rig: Rig.Rig, chain: Anatomy.Chain, base: X, target: V3, opts: Options, locals: { [number]: X }, frames: { X }): Result
	resetChain(rig, chain, base, locals, frames)
	local mov = chain.movable
	local m = #mov
	local foot = mov[m]
	local fRest = frames[foot]
	local footRot = opts.footRot or fRest.q
	local contact = contactNow(rig, chain, frames)
	local contactInFoot = M.qinvrot(fRest.q, M.vsub(contact, fRest.p))
	local ankleTarget = M.vsub(target, M.qrot(footRot, contactInFoot))
	local upper = table.move(mov, 1, m - 1, 1, {})
	local ankleLocal = localUnder(chain, frames, upper[#upper], fRest.p)
	local reachable, clamped, total = solveNodes(rig, chain, upper, ankleLocal, base, ankleTarget, opts, locals, frames)
	local parent = parentFrameOf(rig, foot, base, frames, chain)
	-- the foot's parent may be a weld after the last solved joint: carry the frames down
	local pk = rig.joints[foot].parent
	if pk > 0 and pk ~= upper[#upper] and frames[pk] then
		parent = frames[pk]
	end
	local clampedF = setJoint(rig, foot, parent, footRot, locals, frames)
	local after = false
	local p = frames[foot]
	for _, j in chain.joints do
		if after then
			frames[j] = M.xmul(untransformed(p, rig.joints[j]), locals[j] or M.xid())
			p = frames[j]
		elseif j == foot then
			after = true
		end
	end
	local c = contactNow(rig, chain, frames)
	local residual = M.vdist(c, target)
	return { residual = residual, clamped = clamped or clampedF, reachable = reachable and residual <= math.min(1e-3 * total, 0.02) + 1e-4 }
end
--[[
	Solves `chain` so its contact point lands on `target` (world). `base` is the world frame of
	the first joint's parent (the body). Writes the chain joints' local transforms into `locals`
	and their world frames into `frames` (both keyed by joint index).
]]
function IK.solve(rig: Rig.Rig, chain: Anatomy.Chain, base: X, target: V3, opts: Options?, locals: { [number]: X }, frames: { X }): Result
	local o: Options = opts or {}
	if not M.vfinite(target) then
		local r = solveZero(rig, chain, base, M.vadd(base.p, M.ZERO), locals, frames)
		r.reachable = false
		return r
	end
	local kind = chain.ik
	if kind == "zero" then
		return solveZero(rig, chain, base, target, locals, frames)
	elseif kind == "aim" then
		return solveAim(rig, chain, base, target, locals, frames)
	elseif kind == "aimFoot" and not o.freeEnd then
		return solveAimFoot(rig, chain, base, target, o, locals, frames)
	elseif kind == "two" and consecutive(rig, chain.movable) then
		return solveTwo(rig, chain, base, target, o, locals, frames)
	elseif kind == "twoFoot" and consecutive(rig, chain.movable) and not o.freeEnd then
		return solveTwoFoot(rig, chain, base, target, o, locals, frames)
	elseif kind == "chainFoot" and #chain.movable >= 3 and not o.freeEnd then
		return solveChainFoot(rig, chain, base, target, o, locals, frames)
	end
	return solveChain(rig, chain, base, target, o, locals, frames)
end

-- The chain's contact point at rest, given the body's world frame (where a standing foot is).
function IK.restContact(rig: Rig.Rig, chain: Anatomy.Chain, base: X): V3
	local frames: { X } = {}
	local locals: { [number]: X } = {}
	resetChain(rig, chain, base, locals, frames)
	return contactNow(rig, chain, frames)
end

-- Frames of the chain's joints for given locals (forward kinematics along the chain only).
function IK.chainFrames(rig: Rig.Rig, chain: Anatomy.Chain, base: X, locals: { [number]: X }, frames: { X })
	local parent = base
	for _, k in chain.joints do
		local f = untransformed(parent, rig.joints[k])
		local l = locals[k]
		frames[k] = if l then M.xmul(f, l) else f
		parent = frames[k]
	end
end

return IK
