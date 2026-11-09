--!strict
--[[
	Baked: what every performance and gait becomes before it plays. One flat array of numbers:
	for each sample, the root channel and then each joint channel, seven numbers apiece
	(px, py, pz, qx, qy, qz, qw: the arguments of CFrame.new in that order).

	Why baked: playback is then a pure function of time. sample(t) reads two samples and blends
	them, with no allocation and no yield, so a frame costs the same whatever made the motion
	(keys, IK, springs, a gait planner), every client shows the same pose at the same time, and a
	seek, a late join or a hold for a screenshot lands on exactly the right frame.

	Channel 0 is the root. In "offset" mode it is a transform applied on top of the model's
	starting pivot (a clip's root motion); in "world" mode it is the pivot itself (a gait along a
	path in the world). Joint channels are Transforms in each joint's own frame.
]]

local M = require("./Math")
local Rig = require("./Rig")

type X = M.X

local Baked = {}

export type Marker = { name: string, time: number, value: string? }
export type Contact = { leg: number, from: number, to: number }

export type Baked = {
	name: string,
	kind: string,
	rate: number,
	count: number,
	length: number,
	loop: boolean,
	rootMode: string,
	-- rig joint index of each joint channel (channel c is joints[c])
	joints: { number },
	nch: number,
	stride: number,
	data: { number },
	markers: { Marker },
	contacts: { Contact },
	warnings: { string },
	-- the authored key times and easing facts the lint wants (clips only)
	keyTimes: { number },
	linearKeys: number,
	spline: boolean,
	travel: boolean,
	waive: { [string]: boolean },
	info: { [string]: any },
}

Baked.RATE = 60

--[[
	A baked clip of `count` samples at `rate` for the given joint channels, every channel at
	identity. Fill it with Baked.set, then call Baked.finish.
]]
function Baked.new(name: string, kind: string, rate: number, count: number, loop: boolean, joints: { number }, rootMode: string?): Baked
	local n = math.max(2, math.floor(count))
	local nch = #joints
	local stride = (nch + 1) * 7
	local data: { number } = table.create(n * stride, 0)
	for s = 0, n - 1 do
		for c = 0, nch do
			data[s * stride + c * 7 + 7] = 1
		end
	end
	return {
		name = name,
		kind = kind,
		rate = rate,
		count = n,
		length = (n - 1) / rate,
		loop = loop,
		rootMode = rootMode or "offset",
		joints = joints,
		nch = nch,
		stride = stride,
		data = data,
		markers = {},
		contacts = {},
		warnings = {},
		keyTimes = {},
		linearKeys = 0,
		spline = true,
		travel = false,
		waive = {},
		info = {},
	}
end

-- Writes transform x into sample s (0-based) of channel c (0 = root). Non-finite becomes identity.
function Baked.set(b: Baked, s: number, c: number, x: X)
	local i = s * b.stride + c * 7
	local d = b.data
	if not M.xfinite(x) then
		d[i + 1], d[i + 2], d[i + 3], d[i + 4], d[i + 5], d[i + 6], d[i + 7] = 0, 0, 0, 0, 0, 0, 1
		return
	end
	local q = M.qnorm(x.q)
	d[i + 1], d[i + 2], d[i + 3] = x.p.x, x.p.y, x.p.z
	d[i + 4], d[i + 5], d[i + 6], d[i + 7] = q.x, q.y, q.z, q.w
end

function Baked.get(b: Baked, s: number, c: number): X
	local i = s * b.stride + c * 7
	local d = b.data
	return { p = { x = d[i + 1], y = d[i + 2], z = d[i + 3] }, q = { x = d[i + 4], y = d[i + 5], z = d[i + 6], w = d[i + 7] } }
end

--[[
	Seals a bake: quaternion signs made continuous (so blending two samples never takes the long
	way round, the classic 360-degree flip), and for loops the last sample set equal to the first.
]]
function Baked.finish(b: Baked)
	local d = b.data
	local stride = b.stride
	for c = 0, b.nch do
		for s = 1, b.count - 1 do
			local i = s * stride + c * 7
			local j = (s - 1) * stride + c * 7
			local dot = d[i + 4] * d[j + 4] + d[i + 5] * d[j + 5] + d[i + 6] * d[j + 6] + d[i + 7] * d[j + 7]
			if dot < 0 then
				d[i + 4], d[i + 5], d[i + 6], d[i + 7] = -d[i + 4], -d[i + 5], -d[i + 6], -d[i + 7]
			end
		end
	end
	if b.loop and b.count >= 2 then
		local last = (b.count - 1) * stride
		for k = 1, stride do
			d[last + k] = d[k]
		end
	end
end

-- The sample position for time t: wrapped for loops, clamped otherwise.
local function locate(b: Baked, t: number): (number, number)
	local length = b.length
	if t ~= t then
		t = 0
	end
	if b.loop and length > 0 then
		t = t - length * math.floor(t / length)
	elseif t < 0 then
		t = 0
	elseif t > length then
		t = length
	end
	local x = t * b.rate
	local i0 = math.floor(x)
	if i0 >= b.count - 1 then
		return b.count - 2, 1
	end
	if i0 < 0 then
		return 0, 0
	end
	return i0, x - i0
end

--[[
	The pose at time t, written into `out` (a flat array of b.stride numbers: channel c at
	c * 7 + 1 .. c * 7 + 7). Pure and allocation-free: positions lerp, rotations nlerp along the
	short arc. Any order of times gives the same answers.
]]
function Baked.sample(b: Baked, t: number, out: { number })
	local i0, f = locate(b, t)
	local d = b.data
	local stride = b.stride
	local a = i0 * stride
	local c = a + stride
	local g = 1 - f
	for k = 0, b.nch do
		local o = k * 7
		local ia, ic = a + o, c + o
		out[o + 1] = d[ia + 1] * g + d[ic + 1] * f
		out[o + 2] = d[ia + 2] * g + d[ic + 2] * f
		out[o + 3] = d[ia + 3] * g + d[ic + 3] * f
		local qx = d[ia + 4] * g + d[ic + 4] * f
		local qy = d[ia + 5] * g + d[ic + 5] * f
		local qz = d[ia + 6] * g + d[ic + 6] * f
		local qw = d[ia + 7] * g + d[ic + 7] * f
		local l = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
		if l > 1e-12 then
			out[o + 4], out[o + 5], out[o + 6], out[o + 7] = qx / l, qy / l, qz / l, qw / l
		else
			out[o + 4], out[o + 5], out[o + 6], out[o + 7] = 0, 0, 0, 1
		end
	end
end

-- A buffer sized for b's samples.
function Baked.buffer(b: Baked): { number }
	local out: { number } = table.create(b.stride, 0)
	for c = 0, b.nch do
		out[c * 7 + 7] = 1
	end
	return out
end

-- Channel c of a sampled buffer as an X (allocates; for tools and lint, not for frames).
function Baked.channel(out: { number }, c: number): X
	local i = c * 7
	return { p = { x = out[i + 1], y = out[i + 2], z = out[i + 3] }, q = { x = out[i + 4], y = out[i + 5], z = out[i + 6], w = out[i + 7] } }
end

--[[
	Drops joint channels that never leave identity (most joints of a big rig in most clips), so
	a thousand-joint creature that only moves its legs stores and plays only its legs.
]]
function Baked.compact(b: Baked, tolerance: number?): Baked
	local tol = tolerance or 1e-7
	local keep: { number } = {}
	local d = b.data
	for c = 1, b.nch do
		local moving = false
		for s = 0, b.count - 1 do
			local i = s * b.stride + c * 7
			if
				math.abs(d[i + 1]) > tol
				or math.abs(d[i + 2]) > tol
				or math.abs(d[i + 3]) > tol
				or math.abs(d[i + 4]) > tol
				or math.abs(d[i + 5]) > tol
				or math.abs(d[i + 6]) > tol
			then
				moving = true
				break
			end
		end
		if moving then
			table.insert(keep, c)
		end
	end
	if #keep == b.nch then
		return b
	end
	local joints: { number } = {}
	for _, c in keep do
		table.insert(joints, b.joints[c])
	end
	local nb = Baked.new(b.name, b.kind, b.rate, b.count, b.loop, joints, b.rootMode)
	for s = 0, b.count - 1 do
		local src = s * b.stride
		local dst = s * nb.stride
		for k = 1, 7 do
			nb.data[dst + k] = d[src + k]
		end
		for n, c in keep do
			for k = 1, 7 do
				nb.data[dst + n * 7 + k] = d[src + c * 7 + k]
			end
		end
	end
	nb.markers = b.markers
	nb.contacts = b.contacts
	nb.warnings = b.warnings
	nb.keyTimes = b.keyTimes
	nb.linearKeys = b.linearKeys
	nb.spline = b.spline
	nb.travel = b.travel
	nb.waive = b.waive
	nb.info = b.info
	return nb
end

-- Largest absolute difference between two bakes' numbers (math.huge when shaped differently).
function Baked.diff(a: Baked, b: Baked): number
	if a.count ~= b.count or a.nch ~= b.nch or a.rate ~= b.rate or #a.data ~= #b.data then
		return math.huge
	end
	for c = 1, a.nch do
		if a.joints[c] ~= b.joints[c] then
			return math.huge
		end
	end
	local worst = 0
	for i = 1, #a.data do
		local d = math.abs(a.data[i] - b.data[i])
		if d ~= d then
			return math.huge
		end
		if d > worst then
			worst = d
		end
	end
	return worst
end

-- True when every number is finite.
function Baked.finite(b: Baked): boolean
	for _, v in b.data do
		if v ~= v or v == math.huge or v == -math.huge then
			return false
		end
	end
	return true
end

--[[
	Full local Transforms for every rig joint at sample s (identity for joints without a
	channel), for forward kinematics in the lint and the tools.
]]
function Baked.locals(b: Baked, rig: Rig.Rig, s: number): { [number]: X }
	local locals: { [number]: X } = {}
	for c = 1, b.nch do
		locals[b.joints[c]] = Baked.get(b, s, c)
	end
	local _ = rig
	return locals
end

-- The channel index of rig joint k, or nil.
function Baked.channelOf(b: Baked, k: number): number?
	for c = 1, b.nch do
		if b.joints[c] == k then
			return c
		end
	end
	return nil
end

return Baked
