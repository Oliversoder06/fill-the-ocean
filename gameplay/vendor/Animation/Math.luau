--!strict
--[[
	Math: vectors, quaternions and rigid transforms as plain Luau tables.

	Why not CFrame and Vector3: the whole core has to run under Lune for the tests, where the
	Roblox datatypes are userdata with float32 components, and CFrame.lookAt misbehaves when
	looking along -Z. Plain tables with doubles behave the same in both places, so a bake on a
	client is bit-for-bit the bake in a test. CFrames appear only at the edges: reading a rig
	(fromCFrame) and writing a joint (the Roblox modules).

	Conventions (Roblox's own): +X right, +Y up, a model faces -Z. Quaternions are { x, y, z, w }.
	Euler angles follow CFrame.Angles(rx, ry, rz), which is Rx * Ry * Rz. A transform X is
	{ p = V3, q = Q } and maps a point v to p + q * v, like a CFrame.

	Everything here is pure and total: degenerate input (zero vectors, NaN) comes back as a
	sensible fallback instead of NaN, because one NaN in a joint turns a whole character invisible.
]]

local M = {}

export type V3 = { x: number, y: number, z: number }
export type Q = { x: number, y: number, z: number, w: number }
export type X = { p: V3, q: Q }

local sqrt, abs, sin, cos, acos, atan2 = math.sqrt, math.abs, math.sin, math.cos, math.acos, math.atan2
local huge = math.huge

M.EPS = 1e-9

-- Numbers ----------------------------------------------------------------------------------------

function M.finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= huge and n ~= -huge
end

function M.clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

function M.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function M.smoothstep(t: number): number
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return t * t * (3 - 2 * t)
end

-- The fractional part, always in [0, 1), for phases.
function M.frac(x: number): number
	return x - math.floor(x)
end

-- Wraps an angle in radians to (-pi, pi].
function M.wrapAngle(a: number): number
	local tau = 2 * math.pi
	a = a - tau * math.floor((a + math.pi) / tau)
	if a <= -math.pi then
		a += tau
	end
	return a
end

-- Vectors ----------------------------------------------------------------------------------------

function M.v(x: number, y: number, z: number): V3
	return { x = x, y = y, z = z }
end

M.ZERO = table.freeze({ x = 0, y = 0, z = 0 }) :: V3
M.UP = table.freeze({ x = 0, y = 1, z = 0 }) :: V3
M.RIGHT = table.freeze({ x = 1, y = 0, z = 0 }) :: V3
M.FORWARD = table.freeze({ x = 0, y = 0, z = -1 }) :: V3

function M.vadd(a: V3, b: V3): V3
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

function M.vsub(a: V3, b: V3): V3
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

function M.vmul(a: V3, s: number): V3
	return { x = a.x * s, y = a.y * s, z = a.z * s }
end

-- a + b * s, the most common pattern in the solvers.
function M.vmad(a: V3, b: V3, s: number): V3
	return { x = a.x + b.x * s, y = a.y + b.y * s, z = a.z + b.z * s }
end

function M.vdot(a: V3, b: V3): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

function M.vcross(a: V3, b: V3): V3
	return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end

function M.vlen(a: V3): number
	return sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end

function M.vdist(a: V3, b: V3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return sqrt(dx * dx + dy * dy + dz * dz)
end

-- Unit vector, or `fallback` (default +Y) when `a` is too short to have a direction.
function M.vnorm(a: V3, fallback: V3?): V3
	local l = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
	if l < 1e-12 or l ~= l then
		local f = fallback or M.UP
		return { x = f.x, y = f.y, z = f.z }
	end
	return { x = a.x / l, y = a.y / l, z = a.z / l }
end

function M.vlerp(a: V3, b: V3, t: number): V3
	return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t }
end

function M.vfinite(a: V3): boolean
	return M.finite(a.x) and M.finite(a.y) and M.finite(a.z)
end

-- Removes the component along unit vector n.
function M.vreject(a: V3, n: V3): V3
	local d = a.x * n.x + a.y * n.y + a.z * n.z
	return { x = a.x - n.x * d, y = a.y - n.y * d, z = a.z - n.z * d }
end

-- Any unit vector perpendicular to a (deterministic: the axis least aligned with a, crossed).
function M.vperp(a: V3): V3
	local ax, ay, az = abs(a.x), abs(a.y), abs(a.z)
	local other: V3
	if ax <= ay and ax <= az then
		other = M.RIGHT
	elseif ay <= az then
		other = M.UP
	else
		other = { x = 0, y = 0, z = 1 }
	end
	return M.vnorm(M.vcross(a, other), M.RIGHT)
end

-- Quaternions ------------------------------------------------------------------------------------

function M.q(x: number, y: number, z: number, w: number): Q
	return { x = x, y = y, z = z, w = w }
end

M.QID = table.freeze({ x = 0, y = 0, z = 0, w = 1 }) :: Q

function M.qid(): Q
	return { x = 0, y = 0, z = 0, w = 1 }
end

function M.qmul(a: Q, b: Q): Q
	return {
		x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
		z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
		w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
	}
end

function M.qconj(a: Q): Q
	return { x = -a.x, y = -a.y, z = -a.z, w = a.w }
end

function M.qdot(a: Q, b: Q): number
	return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
end

-- Unit quaternion; the identity when the input has no usable length or is not finite.
function M.qnorm(a: Q): Q
	local l = sqrt(a.x * a.x + a.y * a.y + a.z * a.z + a.w * a.w)
	if l < 1e-12 or l ~= l or l == huge then
		return M.qid()
	end
	return { x = a.x / l, y = a.y / l, z = a.z / l, w = a.w / l }
end

function M.qfinite(a: Q): boolean
	return M.finite(a.x) and M.finite(a.y) and M.finite(a.z) and M.finite(a.w)
end

-- Rotates v by q.
function M.qrot(q: Q, v: V3): V3
	-- t = 2 * cross(q.xyz, v); v' = v + w * t + cross(q.xyz, t)
	local tx = 2 * (q.y * v.z - q.z * v.y)
	local ty = 2 * (q.z * v.x - q.x * v.z)
	local tz = 2 * (q.x * v.y - q.y * v.x)
	return {
		x = v.x + q.w * tx + (q.y * tz - q.z * ty),
		y = v.y + q.w * ty + (q.z * tx - q.x * tz),
		z = v.z + q.w * tz + (q.x * ty - q.y * tx),
	}
end

-- Rotates v by the inverse of q.
function M.qinvrot(q: Q, v: V3): V3
	return M.qrot({ x = -q.x, y = -q.y, z = -q.z, w = q.w }, v)
end

-- Rotation of `angle` radians about `axis` (normalised here; a zero axis gives the identity).
function M.qaxis(axis: V3, angle: number): Q
	local l = M.vlen(axis)
	if l < 1e-12 or not M.finite(angle) then
		return M.qid()
	end
	local s = sin(angle / 2) / l
	return { x = axis.x * s, y = axis.y * s, z = axis.z * s, w = cos(angle / 2) }
end

-- The shortest rotation taking direction u onto direction v: a pure swing, no twist about
-- either. Antiparallel input turns half a turn about a deterministic perpendicular axis.
function M.qbetween(u: V3, v: V3): Q
	local a = M.vnorm(u)
	local b = M.vnorm(v)
	local d = a.x * b.x + a.y * b.y + a.z * b.z
	if d >= 1 - 1e-12 then
		return M.qid()
	end
	if d <= -1 + 1e-9 then
		local p = M.vperp(a)
		return { x = p.x, y = p.y, z = p.z, w = 0 }
	end
	local c = M.vcross(a, b)
	return M.qnorm({ x = c.x, y = c.y, z = c.z, w = 1 + d })
end

-- Angle of the rotation, 0..pi.
function M.qangle(a: Q): number
	local w = abs(a.w)
	if w >= 1 then
		return 0
	end
	return 2 * acos(w)
end

-- The angle between two orientations, 0..pi.
function M.qdiffAngle(a: Q, b: Q): number
	local d = abs(M.qdot(a, b))
	if d >= 1 then
		return 0
	end
	return 2 * acos(d)
end

-- Rotation vector (axis * angle), taking the short way (|angle| <= pi).
function M.qlog(a: Q): V3
	local q = a
	if q.w < 0 then
		q = { x = -q.x, y = -q.y, z = -q.z, w = -q.w }
	end
	local s = sqrt(q.x * q.x + q.y * q.y + q.z * q.z)
	if s < 1e-12 then
		return { x = 2 * q.x, y = 2 * q.y, z = 2 * q.z }
	end
	local angle = 2 * atan2(s, q.w)
	local k = angle / s
	return { x = q.x * k, y = q.y * k, z = q.z * k }
end

function M.qexp(r: V3): Q
	local angle = M.vlen(r)
	if angle < 1e-12 then
		return M.qnorm({ x = r.x / 2, y = r.y / 2, z = r.z / 2, w = 1 })
	end
	local s = sin(angle / 2) / angle
	return { x = r.x * s, y = r.y * s, z = r.z * s, w = cos(angle / 2) }
end

-- Normalised lerp along the short arc. Between samples a few degrees apart it is
-- indistinguishable from slerp and costs no trigonometry.
function M.qnlerp(a: Q, b: Q, t: number): Q
	local d = M.qdot(a, b)
	local s = if d < 0 then -1 else 1
	return M.qnorm({
		x = a.x + (b.x * s - a.x) * t,
		y = a.y + (b.y * s - a.y) * t,
		z = a.z + (b.z * s - a.z) * t,
		w = a.w + (b.w * s - a.w) * t,
	})
end

function M.qslerp(a: Q, b: Q, t: number): Q
	local d = M.qdot(a, b)
	local bx, by, bz, bw = b.x, b.y, b.z, b.w
	if d < 0 then
		d, bx, by, bz, bw = -d, -bx, -by, -bz, -bw
	end
	if d > 0.9995 then
		return M.qnlerp(a, { x = bx, y = by, z = bz, w = bw }, t)
	end
	local theta = acos(M.clamp(d, -1, 1))
	local s = sin(theta)
	local wa = sin((1 - t) * theta) / s
	local wb = sin(t * theta) / s
	return {
		x = a.x * wa + bx * wb,
		y = a.y * wa + by * wb,
		z = a.z * wa + bz * wb,
		w = a.w * wa + bw * wb,
	}
end

-- Roblox order: CFrame.Angles(rx, ry, rz) = Rx * Ry * Rz.
function M.qeuler(rx: number, ry: number, rz: number): Q
	local qx = M.qaxis(M.RIGHT, rx)
	local qy = M.qaxis(M.UP, ry)
	local qz = M.qaxis({ x = 0, y = 0, z = 1 }, rz)
	return M.qmul(M.qmul(qx, qy), qz)
end

-- Rotation matrix rows from a quaternion (r00, r01, r02, r10, ... r22), CFrame's order.
function M.qmatrix(q: Q): (number, number, number, number, number, number, number, number, number)
	local x, y, z, w = q.x, q.y, q.z, q.w
	local xx, yy, zz = x * x, y * y, z * z
	local xy, xz, yz = x * y, x * z, y * z
	local wx, wy, wz = w * x, w * y, w * z
	return 1 - 2 * (yy + zz),
		2 * (xy - wz),
		2 * (xz + wy),
		2 * (xy + wz),
		1 - 2 * (xx + zz),
		2 * (yz - wx),
		2 * (xz - wy),
		2 * (yz + wx),
		1 - 2 * (xx + yy)
end

-- The inverse of qeuler: (rx, ry, rz) with Rx * Ry * Rz = q, like CFrame:ToEulerAnglesXYZ.
function M.qtoeuler(q: Q): (number, number, number)
	local _r00, r01, r02, _r10, _r11, r12, _r20, _r21, r22 = M.qmatrix(q)
	local r00, r10 = _r00, _r10
	-- For Rx*Ry*Rz: r02 = sin(ry); r12 = -sin(rx)cos(ry); r22 = cos(rx)cos(ry);
	-- r01 = -cos(ry)sin(rz); r00 = cos(ry)cos(rz).
	local sy = M.clamp(r02, -1, 1)
	local ry = math.asin(sy)
	local rx, rz
	if abs(sy) < 0.999999 then
		rx = atan2(-r12, r22)
		rz = atan2(-r01, r00)
	else
		-- Gimbal lock: fold everything into rx.
		rx = atan2(_r21, _r11)
		rz = 0
	end
	local _ = r10
	return rx, ry, rz
end

-- Quaternion from rotation matrix rows; tolerates a slightly non-orthonormal matrix.
function M.qfrommatrix(
	r00: number,
	r01: number,
	r02: number,
	r10: number,
	r11: number,
	r12: number,
	r20: number,
	r21: number,
	r22: number
): Q
	local trace = r00 + r11 + r22
	local q: Q
	if trace > 0 then
		local s = sqrt(trace + 1) * 2
		q = { w = 0.25 * s, x = (r21 - r12) / s, y = (r02 - r20) / s, z = (r10 - r01) / s }
	elseif r00 > r11 and r00 > r22 then
		local s = sqrt(math.max(1 + r00 - r11 - r22, 1e-12)) * 2
		q = { w = (r21 - r12) / s, x = 0.25 * s, y = (r01 + r10) / s, z = (r02 + r20) / s }
	elseif r11 > r22 then
		local s = sqrt(math.max(1 + r11 - r00 - r22, 1e-12)) * 2
		q = { w = (r02 - r20) / s, x = (r01 + r10) / s, y = 0.25 * s, z = (r12 + r21) / s }
	else
		local s = sqrt(math.max(1 + r22 - r00 - r11, 1e-12)) * 2
		q = { w = (r10 - r01) / s, x = (r02 + r20) / s, y = (r12 + r21) / s, z = 0.25 * s }
	end
	return M.qnorm(q)
end

--[[
	Swing-twist split about unit `axis`: q = swing * twist, where twist turns about `axis` and
	swing moves `axis` without turning about it. The signed twist angle is what the twist lint
	measures, and swing-only rotations are how the solvers avoid inventing one.
]]
function M.qtwistAngle(q: Q, axis: V3): number
	local d = q.x * axis.x + q.y * axis.y + q.z * axis.z
	local tw = { x = axis.x * d, y = axis.y * d, z = axis.z * d, w = q.w }
	local l = sqrt(tw.x * tw.x + tw.y * tw.y + tw.z * tw.z + tw.w * tw.w)
	if l < 1e-9 then
		-- A half turn of swing: the twist is undefined; call it none.
		return 0
	end
	local w = tw.w / l
	local s = d / l
	return M.wrapAngle(2 * atan2(s, w))
end

function M.qswing(q: Q, axis: V3): Q
	local d = q.x * axis.x + q.y * axis.y + q.z * axis.z
	local tw = M.qnorm({ x = axis.x * d, y = axis.y * d, z = axis.z * d, w = q.w })
	return M.qnorm(M.qmul(q, M.qconj(tw)))
end

-- Transforms -------------------------------------------------------------------------------------

function M.x(p: V3, q: Q): X
	return { p = p, q = q }
end

function M.xid(): X
	return { p = { x = 0, y = 0, z = 0 }, q = M.qid() }
end

function M.xmul(a: X, b: X): X
	return { p = M.vadd(a.p, M.qrot(a.q, b.p)), q = M.qmul(a.q, b.q) }
end

function M.xinv(a: X): X
	local qi = M.qconj(a.q)
	return { p = M.vmul(M.qrot(qi, a.p), -1), q = qi }
end

-- a:Inverse() * b, without building the inverse.
function M.xrel(a: X, b: X): X
	local qi = M.qconj(a.q)
	return { p = M.qrot(qi, M.vsub(b.p, a.p)), q = M.qmul(qi, b.q) }
end

function M.xpoint(a: X, v: V3): V3
	return M.vadd(a.p, M.qrot(a.q, v))
end

function M.xdir(a: X, v: V3): V3
	return M.qrot(a.q, v)
end

function M.xlerp(a: X, b: X, t: number): X
	return { p = M.vlerp(a.p, b.p, t), q = M.qnlerp(a.q, b.q, t) }
end

function M.xfinite(a: X): boolean
	return M.vfinite(a.p) and M.qfinite(a.q)
end

function M.xcopy(a: X): X
	return { p = { x = a.p.x, y = a.p.y, z = a.p.z }, q = { x = a.q.x, y = a.q.y, z = a.q.z, w = a.q.w } }
end

-- Yaw about +Y, then the position: the frame of something standing at p facing `yaw`
-- (radians; 0 faces -Z, positive turns left as CFrame.Angles(0, yaw, 0) does).
function M.xyaw(p: V3, yaw: number): X
	return { p = p, q = M.qaxis(M.UP, yaw) }
end

-- Heading (yaw) of a horizontal direction, matching xyaw: dir = (-sin yaw, 0, -cos yaw).
function M.yawOf(dir: V3): number
	return atan2(-dir.x, -dir.z)
end

-- Reading data and Roblox values ----------------------------------------------------------------

local function num(v: any, default: number): number
	if M.finite(v) then
		return v
	end
	return default
end

-- A V3 from a Vector3, a { x, y, z } array or a { x =, y =, z = } table; nil otherwise. NaN and
-- infinite components become 0 and `bad` is returned true, so the caller can warn once.
function M.readV3(value: any): (V3?, boolean)
	local t = typeof(value)
	if t == "Vector3" or (t == "userdata" and pcall(function()
		return (value :: any).X
	end)) then
		local ok, x, y, z = pcall(function()
			return (value :: any).X, (value :: any).Y, (value :: any).Z
		end)
		if not ok then
			return nil, true
		end
		local bad = not (M.finite(x) and M.finite(y) and M.finite(z))
		return { x = num(x, 0), y = num(y, 0), z = num(z, 0) }, bad
	end
	if t == "table" then
		local x, y, z = value[1], value[2], value[3]
		if x == nil and value.x ~= nil then
			x, y, z = value.x, value.y, value.z
		end
		if type(x) ~= "number" and type(y) ~= "number" and type(z) ~= "number" then
			return nil, true
		end
		local bad = not (M.finite(x) and M.finite(y) and M.finite(z))
		return { x = num(x, 0), y = num(y, 0), z = num(z, 0) }, bad
	end
	return nil, value ~= nil
end

local DEG = math.pi / 180

--[[
	A transform from a CFrame, or from data: { pos = {x, y, z}, rot = {rx, ry, rz} } with the
	rotation in degrees (CFrame.Angles order). Returns the transform and whether anything was
	unusable (and replaced by identity), so the reader can warn rather than throw.
]]
function M.readX(value: any): (X, boolean)
	if value == nil then
		return M.xid(), false
	end
	local t = typeof(value)
	if t == "CFrame" or (t == "userdata" and pcall(function()
		return (value :: any).GetComponents
	end)) then
		local ok, c = pcall(function()
			return { (value :: any):GetComponents() }
		end)
		if not ok or #c < 12 then
			return M.xid(), true
		end
		for i = 1, 12 do
			if not M.finite(c[i]) then
				return M.xid(), true
			end
		end
		return { p = { x = c[1], y = c[2], z = c[3] }, q = M.qfrommatrix(c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]) },
			false
	end
	if t == "table" then
		if value.p ~= nil and value.q ~= nil then
			-- Already an X (from our own code).
			local p, badP = M.readV3(value.p)
			local q = value.q
			local okQ = type(q) == "table" and M.qfinite(q)
			return {
				p = p or { x = 0, y = 0, z = 0 },
				q = if okQ then M.qnorm(q) else M.qid(),
			},
				badP or not okQ
		end
		local p, badP = M.readV3(value.pos)
		local r, badR = M.readV3(value.rot)
		local q = M.qid()
		if r then
			q = M.qeuler(r.x * DEG, r.y * DEG, r.z * DEG)
		end
		return { p = p or { x = 0, y = 0, z = 0 }, q = q }, (value.pos ~= nil and badP) or (value.rot ~= nil and badR)
	end
	return M.xid(), true
end

-- Seven numbers for CFrame.new(x, y, z, qx, qy, qz, qw).
function M.components(a: X): (number, number, number, number, number, number, number)
	return a.p.x, a.p.y, a.p.z, a.q.x, a.q.y, a.q.z, a.q.w
end

return M
