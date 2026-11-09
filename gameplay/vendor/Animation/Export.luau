--!strict
--[[
	Export: a baked clip as keyframes, ready to become a KeyframeSequence (KeyframeExport does
	that in Roblox) and be published through the Animation Editor.

	Roblox's own packs are dense linear keys sampled from curves; this does the same and then
	thins them: per joint, a key is dropped wherever straight interpolation between its
	neighbours reproduces the curve within 0.3 degrees and 0.003 studs (scaled by the rig), by
	recursive splitting so the kept keys sit where the motion bends. Each joint keeps its own
	times; a keyframe holds poses only for the joints keyed at its time (Roblox interpolates each
	joint between the keyframes that pose it). Markers snap to the nearest kept time.

	The root channel cannot be exported as itself (an animation never moves the root part); on
	rigs with a body joint under the root it is folded into that joint, as R15's Root motor
	carries a clip's root motion. Without one it is dropped with a warning.
]]

local M = require("./Math")
local Rig = require("./Rig")
local Anatomy = require("./Anatomy")
local Baked = require("./Baked")

type X = M.X

local Export = {}

export type KeyPose = { joint: number, x: X }
export type Keyframe = { time: number, poses: { KeyPose } }
export type Result = {
	keyframes: { Keyframe },
	markers: { { name: string, time: number, value: string? } },
	length: number,
	loop: boolean,
	warnings: { string },
	keptKeys: number,
	totalKeys: number,
}

local function errorBetween(a: X, b: X, c: X, u: number): (number, number)
	local p = M.vlerp(a.p, c.p, u)
	local q = M.qnlerp(a.q, c.q, u)
	return M.qdiffAngle(q, b.q), M.vdist(p, b.p)
end

-- Indices kept for one channel's samples (recursive split on the worst error).
local function thin(samples: { X }, angTol: number, posTol: number): { number }
	local n = #samples
	if n <= 2 then
		local all = {}
		for i = 1, n do
			all[i] = i
		end
		return all
	end
	local keep: { [number]: boolean } = { [1] = true, [n] = true }
	local stack = { { 1, n } }
	while #stack > 0 do
		local seg = table.remove(stack) :: { number }
		local a, c = seg[1], seg[2]
		if c - a < 2 then
			continue
		end
		local worst, at = 0, 0
		for i = a + 1, c - 1 do
			local u = (i - a) / (c - a)
			local ea, ep = errorBetween(samples[a], samples[i], samples[c], u)
			local score = math.max(ea / angTol, ep / posTol)
			if score > worst then
				worst, at = score, i
			end
		end
		if worst > 1 then
			keep[at] = true
			table.insert(stack, { a, at })
			table.insert(stack, { at, c })
		end
	end
	local out: { number } = {}
	for i = 1, n do
		if keep[i] then
			table.insert(out, i)
		end
	end
	return out
end

--[[
	Keyframes for `baked` on `anatomy`'s rig. opts: degrees (0.3), studs (0.003 per unit of
	half hip height), rate (resample first, e.g. 30 to match the editor; default the bake's).
]]
function Export.keyframes(baked: Baked.Baked, anatomy: Anatomy.Anatomy, opts: { [string]: any }?): Result
	local o: { [string]: any } = opts or {}
	local rig = anatomy.rig
	local warnings: { string } = {}
	local unit = math.max(anatomy.hipHeight, 1e-3) / 2
	local angTol = math.rad(if type(o.degrees) == "number" then o.degrees else 0.3)
	local posTol = (if type(o.studs) == "number" then o.studs else 0.003) * unit
	local rate = if type(o.rate) == "number" and o.rate > 0 then o.rate else baked.rate
	local count = math.max(2, math.floor(baked.length * rate + 0.5) + 1)
	local step = baked.length / (count - 1)
	local buf = Baked.buffer(baked)
	-- per joint sample lists (root folded into the body joint)
	local series: { [number]: { X } } = {}
	local bodyJ = anatomy.body
	local bodyRest: X? = nil
	if bodyJ then
		local bj = rig.joints[bodyJ :: number]
		if bj.parent == 0 then
			bodyRest = bj.rest
		end
	end
	local rootMoves = false
	for s = 0, count - 1 do
		Baked.sample(baked, s * step, buf)
		local root = Baked.channel(buf, 0)
		if M.vlen(root.p) > 1e-6 or M.qangle(root.q) > 1e-6 then
			rootMoves = true
		end
		for c = 1, baked.nch do
			local k = baked.joints[c]
			local x = Baked.channel(buf, c)
			if k == bodyJ and bodyRest then
				-- rest^-1 * root * rest * T: the root's motion expressed at the body joint
				local r = bodyRest :: X
				x = M.xmul(M.xrel(r, M.xmul(root, r)), x)
			end
			local list = series[k]
			if not list then
				list = {}
				series[k] = list
			end
			table.insert(list, x)
		end
	end
	if rootMoves and not bodyRest then
		table.insert(warnings, "the clip moves its root, and this rig has no body joint under the root to carry it: root motion is not exported (move the model in code instead)")
	elseif rootMoves and bodyRest and not series[bodyJ :: number] then
		table.insert(warnings, "root motion could not be folded: the body joint has no channel")
	end
	-- thin each joint
	local times: { [number]: { [number]: boolean } } = {}
	local kept, total = 0, 0
	local keyedAt: { [number]: { [number]: X } } = {}
	for k, list in series do
		local idx = thin(list, angTol, posTol)
		-- a joint that never moves from identity needs no keys at all
		local moving = false
		for _, x in list do
			if M.vlen(x.p) > 1e-6 or M.qangle(x.q) > 1e-6 then
				moving = true
				break
			end
		end
		total += #list
		if not moving then
			continue
		end
		for _, i in idx do
			local s = i - 1
			local slot = times[s]
			if not slot then
				slot = {}
				times[s] = slot
			end
			slot[k] = true
			local row = keyedAt[s]
			if not row then
				row = {}
				keyedAt[s] = row
			end
			row[k] = list[i]
			kept += 1
		end
	end
	local order: { number } = {}
	for s in times do
		table.insert(order, s)
	end
	table.sort(order)
	if #order == 0 then
		order = { 0, count - 1 }
		keyedAt[0] = {}
		keyedAt[count - 1] = {}
	end
	local keyframes: { Keyframe } = {}
	for _, s in order do
		local poses: { KeyPose } = {}
		local joints: { number } = {}
		local keyed: { [number]: any } = keyedAt[s] or {}
		for k in keyed do
			table.insert(joints, k)
		end
		table.sort(joints)
		for _, k in joints do
			table.insert(poses, { joint = k, x = keyedAt[s][k] })
		end
		table.insert(keyframes, { time = s * step, poses = poses })
	end
	-- markers snap to the nearest keyframe time
	local markers = {}
	for _, mk in baked.markers do
		local best, bestD = 0, math.huge
		for _, kf in keyframes do
			local d = math.abs(kf.time - mk.time)
			if d < bestD then
				best, bestD = kf.time, d
			end
		end
		table.insert(markers, { name = mk.name, time = best, value = mk.value })
	end
	return {
		keyframes = keyframes,
		markers = markers,
		length = baked.length,
		loop = baked.loop,
		warnings = warnings,
		keptKeys = kept,
		totalKeys = total,
	}
end

-- Error of the thinned keys against the bake, in degrees and studs (for tests and reports).
function Export.error(result: Result, baked: Baked.Baked, anatomy: Anatomy.Anatomy): (number, number)
	local _ = anatomy
	local worstA, worstP = 0, 0
	local perJoint: { [number]: { { t: number, x: X } } } = {}
	for _, kf in result.keyframes do
		for _, p in kf.poses do
			local list = perJoint[p.joint]
			if not list then
				list = {}
				perJoint[p.joint] = list
			end
			table.insert(list, { t = kf.time, x = p.x })
		end
	end
	local buf = Baked.buffer(baked)
	for c = 1, baked.nch do
		local k = baked.joints[c]
		local list = perJoint[k]
		if not list or #list < 2 or k == anatomy.body then
			continue
		end
		for s = 0, baked.count - 1 do
			local t = s / baked.rate
			Baked.sample(baked, t, buf)
			local want = Baked.channel(buf, c)
			local i = 1
			while i < #list - 1 and list[i + 1].t <= t do
				i += 1
			end
			local a, b = list[i], list[i + 1]
			local u = M.clamp((t - a.t) / math.max(b.t - a.t, 1e-9), 0, 1)
			local got = M.xlerp(a.x, b.x, u)
			worstA = math.max(worstA, M.qdiffAngle(got.q, want.q) * 180 / math.pi)
			worstP = math.max(worstP, M.vdist(got.p, want.p))
		end
	end
	local _r = Rig
	return worstA, worstP
end

return Export
