--!strict
--[[
	Rig: the abstract skeleton every other module works on. Plain data, no Instances, so the
	whole core runs under Lune and a rig read from any Roblox model (RigReader) looks the same as
	one written by hand in a test.

	One joint frame model covers all three animatable joint types Roblox has:

		frame(j) = frame(parent(j)) * rest(j) * Transform(j)

	- Motor6D:             rest = C1(parent joint)^-1 * C0(j); Part1 = frame(j) * C1(j)^-1
	- AnimationConstraint: the same with Attachment0.CFrame / Attachment1.CFrame for C0 / C1
	- Bone:                rest = the bone's CFrame (relative to its parent bone, or to its part)

	The root is the model's root part (or the single part a rig is): frame(root) = the pivot.
	Joints that cannot move (welds) are kept, with kind "weld", so positions stay right.

	Rig.build never errors. Whatever arrives -- cycles, duplicate or missing names, parents that
	do not exist, several roots, NaN or infinite numbers, zero sizes, inverted limits, thousands
	of joints -- it returns a usable rig plus a list of warnings saying what it repaired. A
	broken rig should make a character stand still, not throw in the middle of a cutscene.
]]

local M = require("./Math")

type V3 = M.V3
type Q = M.Q
type X = M.X

local Rig = {}

export type JointKind = "motor" | "bone" | "constraint" | "weld"

export type JointSpec = {
	name: string?,
	-- the parent joint's name or index in this list; nil (or 0) means the root
	parent: (string | number)?,
	-- this joint's pivot frame in its parent's frame: a CFrame or { pos = {x,y,z}, rot = {deg} }
	rest: any?,
	kind: string?,
	-- the part this joint moves: its size, and its centre in this joint's frame
	size: any?,
	center: any?,
	-- the end of this segment in the joint's frame, when the parts do not say
	tip: any?,
	-- Euler limits in degrees about the joint's own X, Y and Z: { min = {..}, max = {..} }
	limits: any?,
	-- the moved part's (or bone's) name, used only as a naming hint
	part: string?,
}

export type RigSpec = {
	name: string?,
	joints: { JointSpec }?,
	rootSize: any?,
	rootName: string?,
	-- ground height in the root's frame (usually negative); default: the rig's lowest point
	ground: number?,
	-- extra extents in the root's frame, e.g. a skinned mesh's bounding box
	bounds: { min: any, max: any }?,
	flying: boolean?,
	round: boolean?,
	-- degrees of yaw from -Z to where the rig's face points
	facing: number?,
}

export type Limits = { min: V3, max: V3 }

export type Joint = {
	index: number,
	-- position in the spec's joint list (what a RigReader binding is keyed by)
	source: number,
	name: string,
	part: string,
	kind: JointKind,
	animated: boolean,
	parent: number, -- 0 is the root
	children: { number },
	depth: number,
	rest: X,
	size: V3?,
	center: X?,
	limits: Limits?,
	-- rest pivot frame in the root's frame
	world: X,
	-- end of the segment in the joint's frame, and its length
	tip: V3,
	length: number,
	-- rest bounding box of the moved part, in the root's frame
	boxMin: V3?,
	boxMax: V3?,
}

export type Rig = {
	name: string,
	joints: { Joint },
	count: number,
	byName: { [string]: number },
	-- source index -> rig index
	fromSource: { [number]: number },
	rootName: string,
	rootSize: V3,
	boundsMin: V3,
	boundsMax: V3,
	ground: number,
	height: number,
	flying: boolean,
	round: boolean,
	facing: number,
	warnings: { string },
}

Rig.MAX_JOINTS = 4096

local KINDS: { [string]: JointKind } = {
	motor = "motor",
	motor6d = "motor",
	bone = "bone",
	constraint = "constraint",
	animationconstraint = "constraint",
	weld = "weld",
	static = "weld",
}

local DEG = math.pi / 180

local function warnf(list: { string }, fmt: string, ...: any)
	if #list < 200 then
		table.insert(list, string.format(fmt, ...))
	elseif #list == 200 then
		table.insert(list, "(more warnings dropped)")
	end
end

local function readSize(value: any, warnings: { string }, where: string): V3?
	if value == nil then
		return nil
	end
	local v, bad = M.readV3(value)
	if not v then
		warnf(warnings, "%s: size is not a vector; ignored", where)
		return nil
	end
	if bad then
		warnf(warnings, "%s: size had NaN or infinite parts; they were set to 0", where)
	end
	return { x = math.abs(v.x), y = math.abs(v.y), z = math.abs(v.z) }
end

local function readLimits(value: any, warnings: { string }, where: string): Limits?
	if type(value) ~= "table" then
		if value ~= nil then
			warnf(warnings, "%s: limits must be { min = {...}, max = {...} }; ignored", where)
		end
		return nil
	end
	local lo, badLo = M.readV3(value.min)
	local hi, badHi = M.readV3(value.max)
	if not lo or not hi or badLo or badHi then
		warnf(warnings, "%s: limits need finite min and max vectors; ignored", where)
		return nil
	end
	local function order(a: number, b: number): (number, number)
		if a > b then
			return b, a
		end
		return a, b
	end
	local x0, x1 = order(lo.x, hi.x)
	local y0, y1 = order(lo.y, hi.y)
	local z0, z1 = order(lo.z, hi.z)
	if lo.x > hi.x or lo.y > hi.y or lo.z > hi.z then
		warnf(warnings, "%s: a limit's min was above its max; swapped", where)
	end
	return {
		min = { x = x0 * DEG, y = y0 * DEG, z = z0 * DEG },
		max = { x = x1 * DEG, y = y1 * DEG, z = z1 * DEG },
	}
end

-- Axis-aligned bounds (root frame) of a box of `size` placed at frame `f`.
local function boxBounds(f: X, size: V3): (V3, V3)
	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = M.qmatrix(f.q)
	local hx, hy, hz = size.x / 2, size.y / 2, size.z / 2
	local ex = math.abs(r00) * hx + math.abs(r01) * hy + math.abs(r02) * hz
	local ey = math.abs(r10) * hx + math.abs(r11) * hy + math.abs(r12) * hz
	local ez = math.abs(r20) * hx + math.abs(r21) * hy + math.abs(r22) * hz
	return { x = f.p.x - ex, y = f.p.y - ey, z = f.p.z - ez }, { x = f.p.x + ex, y = f.p.y + ey, z = f.p.z + ez }
end

-- Distance from the centre of a box (`size` at frame `c`) to where a ray along unit d leaves it,
-- so a derived segment end lies on the part's surface rather than past a corner.
local function exitAlong(c: X, size: V3, d: V3): number
	local best = math.huge
	local axes = { M.qrot(c.q, M.RIGHT), M.qrot(c.q, M.UP), M.qrot(c.q, { x = 0, y = 0, z = 1 }) }
	local halves = { size.x / 2, size.y / 2, size.z / 2 }
	for i = 1, 3 do
		local k = math.abs(M.vdot(axes[i], d))
		if k > 1e-9 then
			local t = halves[i] / k
			if t < best then
				best = t
			end
		end
	end
	return if best == math.huge then 0 else best
end

--[[
	Builds a rig from a spec. Always returns one; `rig.warnings` says what was repaired.
]]
function Rig.build(spec: any): Rig
	local warnings: { string } = {}
	if type(spec) ~= "table" then
		warnf(warnings, "the rig spec is a %s, not a table: built an empty rig", typeof(spec))
		spec = {}
	end
	local name = if type(spec.name) == "string" and spec.name ~= "" then spec.name else "Rig"
	local list: { any } = if type(spec.joints) == "table" then spec.joints else {}
	if spec.joints ~= nil and type(spec.joints) ~= "table" then
		warnf(warnings, "joints must be a list; ignored")
	end
	local n = 0
	for i in ipairs(list) do
		n = i
	end
	if n > Rig.MAX_JOINTS then
		warnf(warnings, "%d joints is more than the %d supported; the rest were dropped", n, Rig.MAX_JOINTS)
		n = Rig.MAX_JOINTS
	end

	-- Names: unique, non-empty. The first holder of a name keeps it.
	local names: { string } = table.create(n, "")
	local taken: { [string]: boolean } = {}
	local firstByName: { [string]: number } = {}
	for i = 1, n do
		local js = list[i]
		if type(js) ~= "table" then
			warnf(warnings, "joints[%d] is not a table; it became a fixed placeholder", i)
			list[i] = {}
			js = list[i]
		end
		local raw = js.name
		local base = if type(raw) == "string" and raw ~= "" then raw else ("joint" .. i)
		if firstByName[base] == nil then
			firstByName[base] = i
		end
		local unique = base
		local k = 2
		while taken[unique] do
			unique = base .. "#" .. k
			k += 1
		end
		if unique ~= base then
			warnf(warnings, "joints[%d]: the name %q is used twice; this one is %q", i, base, unique)
		end
		taken[unique] = true
		names[i] = unique
	end

	-- Parents, by name or index; anything unresolvable hangs from the root.
	local parentOf: { number } = table.create(n, 0)
	for i = 1, n do
		local p = list[i].parent
		local pi = 0
		if type(p) == "number" then
			if p % 1 == 0 and p >= 1 and p <= n then
				pi = p
			elseif p ~= 0 then
				warnf(warnings, "joints[%d] (%s): parent index %s does not exist; attached to the root", i, names[i], tostring(p))
			end
		elseif type(p) == "string" then
			local found = firstByName[p] or (if taken[p] then table.find(names, p) else nil)
			if found then
				pi = found
			elseif p ~= "" and p ~= name and p ~= spec.rootName then
				warnf(warnings, "joints[%d] (%s): parent %q is not a joint; attached to the root", i, names[i], p)
			end
		elseif p ~= nil then
			warnf(warnings, "joints[%d] (%s): parent must be a name or an index; attached to the root", i, names[i])
		end
		if pi == i then
			warnf(warnings, "joints[%d] (%s) is its own parent; attached to the root", i, names[i])
			pi = 0
		end
		parentOf[i] = pi
	end

	-- Cycles: a joint whose parent chain never reaches the root sits in (or under) a loop.
	-- Cut each loop at its lowest-numbered joint, which then hangs from the root.
	local state: { number } = table.create(n, 0) -- 0 unknown, 1 reaches root
	for i = 1, n do
		if state[i] ~= 0 then
			continue
		end
		local path: { number } = {}
		local onPath: { [number]: number } = {}
		local j = i
		while true do
			if j == 0 or state[j] == 1 then
				for _, k in path do
					state[k] = 1
				end
				break
			end
			if onPath[j] then
				-- the loop is path[onPath[j]] .. end
				local lowest = j
				for k = onPath[j], #path do
					if path[k] < lowest then
						lowest = path[k]
					end
				end
				warnf(warnings, "joints form a loop through %s; cut it there and attached %s to the root", names[j], names[lowest])
				parentOf[lowest] = 0
				-- start over from the same joint; the loop is open now
				path = {}
				onPath = {}
				j = i
				continue
			end
			table.insert(path, j)
			onPath[j] = #path
			j = parentOf[j]
		end
	end

	-- Breadth-first order from the root: every parent comes before its children, which is the
	-- order forward kinematics and the solvers walk in. Children keep their spec order.
	local kids: { { number } } = table.create(n + 1)
	for i = 0, n do
		kids[i + 1] = {}
	end
	for i = 1, n do
		table.insert(kids[parentOf[i] + 1], i)
	end
	local order: { number } = {}
	local depthOf: { [number]: number } = { [0] = 0 }
	local queue = { 0 }
	local head = 1
	while head <= #queue do
		local u = queue[head]
		head += 1
		for _, c in kids[u + 1] do
			depthOf[c] = depthOf[u] + 1
			table.insert(order, c)
			table.insert(queue, c)
		end
	end
	local newIndex: { [number]: number } = { [0] = 0 }
	for k, src in order do
		newIndex[src] = k
	end

	local rootSize = readSize(spec.rootSize, warnings, "rootSize") or { x = 0, y = 0, z = 0 }
	local joints: { Joint } = table.create(#order)
	local byName: { [string]: number } = {}
	local fromSource: { [number]: number } = {}
	for k, src in order do
		local js = list[src]
		local where = string.format("joints[%d] (%s)", src, names[src])
		local rest, badRest = M.readX(js.rest)
		if badRest then
			warnf(warnings, "%s: rest is not a usable CFrame (or has NaN); used identity", where)
		end
		local kindRaw = if type(js.kind) == "string" then string.lower(js.kind) else "motor"
		local kind = KINDS[kindRaw]
		if not kind then
			warnf(warnings, "%s: unknown kind %q; treated as a motor", where, tostring(js.kind))
			kind = "motor"
		end
		local size = readSize(js.size, warnings, where)
		local center: X? = nil
		if js.center ~= nil then
			local c, badC = M.readX(js.center)
			if badC then
				warnf(warnings, "%s: center is not usable; used the pivot", where)
			end
			center = c
		elseif size then
			center = M.xid()
		end
		local joint: Joint = {
			index = k,
			source = src,
			name = names[src],
			part = if type(js.part) == "string" then js.part else names[src],
			kind = kind :: JointKind,
			animated = kind ~= "weld",
			parent = newIndex[parentOf[src]],
			children = {},
			depth = depthOf[src],
			rest = rest,
			size = size,
			center = center,
			limits = readLimits(js.limits, warnings, where),
			world = M.xid(),
			tip = { x = 0, y = 0, z = 0 },
			length = 0,
			boxMin = nil,
			boxMax = nil,
		}
		joints[k] = joint
		byName[joint.name] = k
		fromSource[src] = k
	end
	for k, j in joints do
		if j.parent > 0 then
			table.insert(joints[j.parent].children, k)
		end
	end

	-- Rest pose in the root's frame.
	for _, j in joints do
		local parentWorld = if j.parent > 0 then joints[j.parent].world else M.xid()
		j.world = M.xmul(parentWorld, j.rest)
		if not M.xfinite(j.world) then
			-- only reachable through overflow (a 1e308 offset chain); flatten rather than spread NaN
			warnf(warnings, "%s: its rest position overflowed; placed at its parent", j.name)
			j.rest = M.xid()
			j.world = M.xcopy(parentWorld)
		end
	end

	-- Segment ends: an explicit tip, else towards the children, else the far end of the part.
	for _, j in joints do
		local js = list[j.source]
		local tip: V3? = nil
		if js.tip ~= nil then
			local v, bad = M.readV3(js.tip)
			if v and not bad then
				tip = v
			else
				warnf(warnings, "%s: tip is not a usable vector; derived instead", j.name)
			end
		end
		if not tip and #j.children > 0 then
			local sx, sy, sz = 0, 0, 0
			for _, c in j.children do
				local p = joints[c].rest.p
				sx += p.x
				sy += p.y
				sz += p.z
			end
			local m = #j.children
			tip = { x = sx / m, y = sy / m, z = sz / m }
		end
		if not tip and j.size and j.center then
			local c = j.center :: X
			local size = j.size :: V3
			local d = c.p
			local dir: V3
			if M.vlen(d) > 1e-6 then
				dir = M.vnorm(d)
			else
				-- Pivot at the part's centre: continue the way the chain was heading.
				local fromParent = j.rest.p
				dir = M.vnorm(M.qinvrot(j.rest.q, fromParent), { x = 0, y = -1, z = 0 })
			end
			tip = M.vmad(c.p, dir, exitAlong(c, size, dir))
		end
		j.tip = tip or { x = 0, y = 0, z = 0 }
		j.length = M.vlen(j.tip)
		if not M.finite(j.length) then
			j.tip = { x = 0, y = 0, z = 0 }
			j.length = 0
		end
		if j.size and j.center then
			local f = M.xmul(j.world, j.center :: X)
			local lo, hi = boxBounds(f, j.size :: V3)
			j.boxMin, j.boxMax = lo, hi
		end
	end

	-- Bounds: the root part, every part box, pivots and segment ends, and any given extents.
	local lo = { x = -rootSize.x / 2, y = -rootSize.y / 2, z = -rootSize.z / 2 }
	local hi = { x = rootSize.x / 2, y = rootSize.y / 2, z = rootSize.z / 2 }
	local function grow(p: V3)
		if not M.vfinite(p) then
			return
		end
		if p.x < lo.x then
			lo.x = p.x
		end
		if p.y < lo.y then
			lo.y = p.y
		end
		if p.z < lo.z then
			lo.z = p.z
		end
		if p.x > hi.x then
			hi.x = p.x
		end
		if p.y > hi.y then
			hi.y = p.y
		end
		if p.z > hi.z then
			hi.z = p.z
		end
	end
	for _, j in joints do
		grow(j.world.p)
		grow(M.xpoint(j.world, j.tip))
		if j.boxMin and j.boxMax then
			grow(j.boxMin :: V3)
			grow(j.boxMax :: V3)
		end
	end
	if type(spec.bounds) == "table" then
		local bmin = M.readV3(spec.bounds.min)
		local bmax = M.readV3(spec.bounds.max)
		if bmin and bmax then
			grow(bmin)
			grow(bmax)
		end
	end

	local ground = lo.y
	if spec.ground ~= nil then
		if M.finite(spec.ground) then
			ground = spec.ground
		else
			warnf(warnings, "ground is not a finite number; used the rig's lowest point")
		end
	end
	local height = hi.y - ground
	local span = math.max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
	if not (height > 1e-6) then
		height = if span > 1e-6 then span else 1
		if #joints > 0 or rootSize.y > 0 then
			warnf(warnings, "the rig has no height above its ground; used %.3g as its size", height)
		end
	end

	local facing = 0
	if spec.facing ~= nil then
		if M.finite(spec.facing) then
			facing = spec.facing * DEG
		else
			warnf(warnings, "facing is not a finite number; assumed -Z")
		end
	end

	return {
		name = name,
		joints = joints,
		count = #joints,
		byName = byName,
		fromSource = fromSource,
		rootName = if type(spec.rootName) == "string" then spec.rootName else "Root",
		rootSize = rootSize,
		boundsMin = lo,
		boundsMax = hi,
		ground = ground,
		height = height,
		flying = spec.flying == true,
		round = spec.round == true,
		facing = facing,
		warnings = warnings,
	}
end

--[[
	Forward kinematics: world frames of every joint for local Transforms `locals` (nil entries
	are identity) under the root frame `root`. Fills and returns `out` (one X per joint).
]]
function Rig.fk(rig: Rig, locals: { [number]: X? }, root: X, out: { X }?): { X }
	local frames: { X } = out or table.create(rig.count)
	for k, j in rig.joints do
		local parentWorld = if j.parent > 0 then frames[j.parent] else root
		local f = M.xmul(parentWorld, j.rest)
		local l = locals[k]
		if l then
			f = M.xmul(f, l)
		end
		frames[k] = f
	end
	return frames
end

-- World position of joint k's segment end under frames from fk.
function Rig.tipOf(rig: Rig, frames: { X }, k: number): V3
	return M.xpoint(frames[k], rig.joints[k].tip)
end

-- The joint's parent's world frame (the root for top joints).
function Rig.parentFrame(rig: Rig, frames: { X }, root: X, k: number): X
	local p = rig.joints[k].parent
	return if p > 0 then frames[p] else root
end

-- Joint index by name (exact, then case-insensitive), or nil.
function Rig.find(rig: Rig, name: string): number?
	local k = rig.byName[name]
	if k then
		return k
	end
	local lower = string.lower(name)
	for i, j in rig.joints do
		if string.lower(j.name) == lower or string.lower(j.part) == lower then
			return i
		end
	end
	return nil
end

--[[
	A copy of a spec with every length multiplied by `factor` (for the scale tests and for
	authoring at one size and playing at another). Rotations and limits are unchanged.
]]
function Rig.scaleSpec(spec: RigSpec, factor: number): RigSpec
	local function sv(v: any): any
		local r = M.readV3(v)
		if not r then
			return v
		end
		return { r.x * factor, r.y * factor, r.z * factor }
	end
	local function sx(v: any): any
		if v == nil then
			return nil
		end
		local x = M.readX(v)
		return { p = M.vmul(x.p, factor), q = x.q }
	end
	local joints = {}
	local list: { JointSpec } = spec.joints or {}
	for i, js in list do
		joints[i] = {
			name = js.name,
			parent = js.parent,
			rest = sx(js.rest),
			kind = js.kind,
			size = sv(js.size),
			center = sx(js.center),
			tip = sv(js.tip),
			limits = js.limits,
			part = js.part,
		}
	end
	return {
		name = spec.name,
		joints = joints,
		rootSize = sv(spec.rootSize),
		rootName = spec.rootName,
		ground = if spec.ground then spec.ground * factor else nil,
		bounds = if spec.bounds then { min = sv(spec.bounds.min), max = sv(spec.bounds.max) } else nil,
		flying = spec.flying,
		round = spec.round,
		facing = spec.facing,
	}
end

return Rig
