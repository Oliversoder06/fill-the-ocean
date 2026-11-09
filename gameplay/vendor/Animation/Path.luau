--!strict
--[[
	Path: where a moving body is at every moment: position on the ground plane, heading, speed.

	A path is data: points to pass through, a cruise speed, and optionally a heading to face at
	the end. It becomes a sampled track with physical motion: speed ramps up and down with
	smooth acceleration (never a jump from standing to full speed), corners are rounded by a
	centripetal Catmull-Rom curve (it cannot loop or overshoot between points), and when the
	body has to face a new way before setting off or after arriving it turns on the spot at a
	steady rate. The heading leads the path by a moment (about 0.13 s, as walking people's hips
	do), so the body turns into a corner rather than being dragged round it.
]]

local M = require("./Math")

type V3 = M.V3

local Path = {}

export type Spec = {
	points: { any }?,
	speed: number?,
	accel: number?,
	decel: number?,
	-- final heading in degrees, CFrame.Angles(0, rad(face), 0) convention (0 faces -Z)
	face: number?,
	-- degrees per second for turns on the spot
	turnRate: number?,
	-- seconds standing still before setting off, and after the end
	wait: number?,
	hold: number?,
	-- how far ahead along the path the heading looks, seconds
	lead: number?,
}

export type Track = {
	rate: number,
	count: number,
	duration: number,
	x: { number },
	y: { number },
	z: { number },
	yaw: { number },
	speed: { number },
	accel: { number },
	yawRate: { number },
	-- the time the body stops travelling (turns and holds may follow)
	arrive: number,
	length: number,
	cruise: number,
	warnings: { string },
	-- distance travelled along the path by each sample, and the path's heading by distance
	dist: { number },
	headS: { number },
	headYaw: { number },
}

local DEG = math.pi / 180

-- Centripetal Catmull-Rom point between p1 and p2 (alpha 0.5).
local function catmull(p0: V3, p1: V3, p2: V3, p3: V3, u: number): V3
	local function tj(ti: number, a: V3, b: V3): number
		local d = math.sqrt(M.vdist(a, b))
		return ti + math.max(d, 1e-6)
	end
	local t0 = 0
	local t1 = tj(t0, p0, p1)
	local t2 = tj(t1, p1, p2)
	local t3 = tj(t2, p2, p3)
	local t = t1 + (t2 - t1) * u
	local function mix(a: V3, b: V3, ta: number, tb: number): V3
		local k = (t - ta) / (tb - ta)
		return M.vlerp(a, b, k)
	end
	local a1 = mix(p0, p1, t0, t1)
	local a2 = mix(p1, p2, t1, t2)
	local a3 = mix(p2, p3, t2, t3)
	local b1 = mix(a1, a2, t0, t2)
	local b2 = mix(a2, a3, t1, t3)
	return mix(b1, b2, t1, t2)
end

-- Distance travelled by time t of a move of length S at cruise V with smooth ramps Ta, Td.
local function profile(t: number, S: number, V: number, Ta: number, Td: number, T: number): (number, number, number)
	if t <= 0 then
		return 0, 0, 0
	end
	if t >= T then
		return S, 0, 0
	end
	if t < Ta then
		local u = t / Ta
		return V * Ta * (u * u * u - u * u * u * u / 2), V * (3 * u * u - 2 * u * u * u), V * (6 * u - 6 * u * u) / Ta
	end
	if t > T - Td then
		local w = (T - t) / Td
		return S - V * Td * (w * w * w - w * w * w * w / 2), V * (3 * w * w - 2 * w * w * w), -V * (6 * w - 6 * w * w) / Td
	end
	return V * Ta / 2 + V * (t - Ta), V, 0
end

--[[
	Samples a path at `rate` for a body starting at `start` (position and yaw). `gaitGravity`
	sets the default ramp: a body reaches walking pace over a step or two, quicker for small
	things. Everything non-finite or missing falls back with a warning.
]]
function Path.track(spec: Spec?, start: V3, startYaw: number, rate: number, size: number, gaitGravity: number): Track
	local s: Spec = spec or {}
	local warnings: { string } = {}
	local pts: { V3 } = { { x = start.x, y = start.y, z = start.z } }
	if type(s.points) == "table" then
		for i, raw in s.points :: { any } do
			local v, bad = M.readV3(raw)
			if v and not bad then
				-- skip points on top of the previous one
				if M.vdist(v, pts[#pts]) > 1e-4 then
					table.insert(pts, v)
				end
			else
				table.insert(warnings, string.format("path point %d is not a usable position; skipped", i))
			end
		end
	end
	local g = math.max(gaitGravity, 1e-3)
	local H = math.max(size, 1e-3)
	local V = if type(s.speed) == "number" and M.finite(s.speed) and s.speed > 0 then s.speed else math.sqrt(0.25 * g * H)
	-- the ground plane path: densify the curve
	local poly: { V3 } = { pts[1] }
	if #pts >= 2 then
		local n = #pts
		for i = 1, n - 1 do
			local p0 = if i > 1 then pts[i - 1] else M.vsub(M.vmul(pts[1], 2), pts[2])
			local p1, p2 = pts[i], pts[i + 1]
			local p3 = if i + 2 <= n then pts[i + 2] else M.vsub(M.vmul(pts[n], 2), pts[n - 1])
			local steps = math.clamp(math.ceil(M.vdist(p1, p2) / math.max(0.05 * H, 1e-3)), 4, 256)
			for k = 1, steps do
				table.insert(poly, catmull(p0, p1, p2, p3, k / steps))
			end
		end
	end
	local cum: { number } = { 0 }
	for i = 2, #poly do
		local a, b = poly[i - 1], poly[i]
		local dx, dz = b.x - a.x, b.z - a.z
		cum[i] = cum[i - 1] + math.sqrt(dx * dx + dz * dz)
	end
	local S = cum[#cum]
	local function pointAt(dist: number): (number, number, number)
		if #poly == 1 or S <= 1e-9 then
			return poly[1].x, poly[1].y, poly[1].z
		end
		dist = M.clamp(dist, 0, S)
		local lo, hi = 1, #cum
		while hi - lo > 1 do
			local mid = (lo + hi) // 2
			if cum[mid] <= dist then
				lo = mid
			else
				hi = mid
			end
		end
		local seg = cum[hi] - cum[lo]
		local k = if seg > 1e-12 then (dist - cum[lo]) / seg else 0
		local a, b = poly[lo], poly[hi]
		return a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k, a.z + (b.z - a.z) * k
	end
	--[[
		The path's heading by distance, as a smooth table. A heading read off the dense polyline
		directly would step at every one of its corners; a body turning in steps buzzes (the
		jitter lint sees it). So it is measured over a baseline longer than the polyline's
		pieces, then smoothed.
	]]
	local headS: { number } = {}
	local headYaw: { number } = {}
	if S > 1e-6 then
		local maxSub = 0
		for i = 2, #cum do
			maxSub = math.max(maxSub, cum[i] - cum[i - 1])
		end
		local scale = math.min(math.max(0.1 * H, 1.5 * maxSub), S)
		local steps = math.clamp(math.ceil(S / math.max(scale / 3, 1e-4)), 2, 4000)
		local prev: number? = nil
		for k = 0, steps do
			local d = S * k / steps
			local d0 = math.clamp(d - scale / 2, 0, S)
			local d1 = math.clamp(d + scale / 2, 0, S)
			if d1 - d0 < scale * 0.5 then
				if d0 <= 0 then
					d1 = math.min(S, d0 + scale)
				else
					d0 = math.max(0, d1 - scale)
				end
			end
			local x0, _, z0 = pointAt(d0)
			local x1, _, z1 = pointAt(d1)
			local dx, dz = x1 - x0, z1 - z0
			local h = if dx * dx + dz * dz > 1e-14 then math.atan2(-dx, -dz) else (prev or startYaw)
			local unwrapped = if prev then (prev :: number) + M.wrapAngle(h - (prev :: number)) else h
			prev = unwrapped
			table.insert(headS, d)
			table.insert(headYaw, unwrapped)
		end
		-- smooth over about one baseline
		local n = #headYaw
		local sigma = 1.5
		local r = 5
		local smooth = table.create(n, 0)
		for i = 1, n do
			local acc, wsum = 0, 0
			for k2 = -r, r do
				local j = math.clamp(i + k2, 1, n)
				local w = math.exp(-(k2 * k2) / (2 * sigma * sigma))
				acc += w * headYaw[j]
				wsum += w
			end
			smooth[i] = acc / wsum
		end
		headYaw = smooth
	end
	local function headingAt(dist: number): number?
		local n = #headS
		if n == 0 then
			return nil
		end
		if dist <= headS[1] then
			return headYaw[1]
		elseif dist >= headS[n] then
			return headYaw[n]
		end
		local lo, hi = 1, n
		while hi - lo > 1 do
			local mid = (lo + hi) // 2
			if headS[mid] <= dist then
				lo = mid
			else
				hi = mid
			end
		end
		local span = headS[hi] - headS[lo]
		local k = if span > 1e-12 then (dist - headS[lo]) / span else 0
		return headYaw[lo] + (headYaw[hi] - headYaw[lo]) * k
	end

	local Ta = if type(s.accel) == "number" and M.finite(s.accel) and s.accel > 0 then s.accel else M.clamp(4 * V / g, 0.35, 1.5)
	local Td = if type(s.decel) == "number" and M.finite(s.decel) and s.decel > 0 then s.decel else 0.85 * Ta
	if S > 0 and S < V * (Ta + Td) / 2 then
		V = 2 * S / (Ta + Td)
	end
	local Tm = if S > 1e-9 then S / V + (Ta + Td) / 2 else 0
	local turnRate = (if type(s.turnRate) == "number" and M.finite(s.turnRate) and s.turnRate > 0 then s.turnRate else 140 * math.sqrt(2 / H)) * DEG
	turnRate = M.clamp(turnRate, 20 * DEG, 720 * DEG)
	local wait = if type(s.wait) == "number" and M.finite(s.wait) then math.max(0, s.wait) else 0
	local hold = if type(s.hold) == "number" and M.finite(s.hold) then math.max(0, s.hold) else 0
	local lead = if type(s.lead) == "number" and M.finite(s.lead) then math.max(0, s.lead) else 0.13

	-- turn on the spot to face the path first, when it starts off to one side
	local firstHeading = headingAt(0)
	local turn1 = 0
	if firstHeading then
		turn1 = M.wrapAngle(firstHeading - startYaw)
	end
	local turn1Time = if math.abs(turn1) > 20 * DEG then math.max(0.35, math.abs(turn1) / turnRate) else 0
	local endHeading = headingAt(S) or startYaw
	local turn2 = 0
	if type(s.face) == "number" and M.finite(s.face) then
		turn2 = M.wrapAngle(s.face * DEG - (if S > 1e-6 then endHeading else startYaw + turn1))
	end
	local turn2Time = if math.abs(turn2) > 1e-3 then math.max(0.35, math.abs(turn2) / turnRate) else 0

	local tMove0 = wait + turn1Time
	local tMove1 = tMove0 + Tm
	local tTurn2 = tMove1
	local duration = tTurn2 + turn2Time + hold
	local count = math.max(2, math.floor(duration * rate + 0.5) + 1)

	local track: Track = {
		rate = rate,
		count = count,
		duration = (count - 1) / rate,
		x = table.create(count, 0),
		y = table.create(count, 0),
		z = table.create(count, 0),
		yaw = table.create(count, 0),
		speed = table.create(count, 0),
		accel = table.create(count, 0),
		yawRate = table.create(count, 0),
		arrive = tMove1,
		length = S,
		cruise = V,
		warnings = warnings,
		dist = table.create(count, 0),
		headS = {},
		headYaw = {},
	}
	-- heading by distance, for bodies that follow the path along their length
	do
		local base = startYaw + turn1
		for k, d in headS do
			table.insert(track.headS, d)
			-- keep the table on the same turn count as the body's own heading
			table.insert(track.headYaw, headYaw[k] + 2 * math.pi * math.floor((base - headYaw[1]) / (2 * math.pi) + 0.5))
		end
	end
	local lastYaw = startYaw
	-- unwrapped heading so yaw rates never see a 2*pi jump
	local function unwrapTo(prev: number, a: number): number
		return prev + M.wrapAngle(a - prev)
	end
	for i = 1, count do
		local t = (i - 1) / rate
		local x, y, z, yaw, spd, acc
		if t < tMove0 then
			x, y, z = pts[1].x, pts[1].y, pts[1].z
			if turn1Time > 0 and t >= wait then
				local u = M.smoothstep((t - wait) / turn1Time)
				yaw = startYaw + turn1 * u
			else
				yaw = startYaw
			end
			spd, acc = 0, 0
		elseif t <= tMove1 then
			local d, v, a = profile(t - tMove0, S, V, Ta, Td, Tm)
			track.dist[i] = d
			x, y, z = pointAt(d)
			yaw = headingAt(math.min(S, d + lead * v)) or lastYaw
			spd, acc = v, a
		else
			track.dist[i] = S
			x, y, z = pointAt(S)
			local base = if S > 1e-6 then endHeading else startYaw + turn1
			if turn2Time > 0 then
				local u = M.smoothstep((t - tTurn2) / turn2Time)
				yaw = base + turn2 * u
			else
				yaw = base
			end
			spd, acc = 0, 0
		end
		yaw = unwrapTo(lastYaw, yaw)
		lastYaw = yaw
		track.x[i], track.y[i], track.z[i] = x, y, z
		track.yaw[i], track.speed[i], track.accel[i] = yaw, spd, acc
	end
	for i = 1, count do
		local a = track.yaw[math.max(1, i - 1)]
		local b = track.yaw[math.min(count, i + 1)]
		local span = (math.min(count, i + 1) - math.max(1, i - 1)) / rate
		track.yawRate[i] = if span > 0 then (b - a) / span else 0
	end
	-- a heading sampled from a polyline has tiny steps; their derivative is noise, so the turn
	-- rate (which drives banking and the tail) is smoothed over a twentieth of a second
	local sigma = 0.05 * rate
	if sigma > 0.25 then
		local r = math.ceil(3 * sigma)
		local out = table.create(count, 0)
		for i = 1, count do
			local acc, wsum = 0, 0
			for k = -r, r do
				local j = math.clamp(i + k, 1, count)
				local w = math.exp(-(k * k) / (2 * sigma * sigma))
				acc += w * track.yawRate[j]
				wsum += w
			end
			out[i] = acc / wsum
		end
		track.yawRate = out
	end
	return track
end

-- Interpolated track values at time t (clamped to its ends).
function Path.at(track: Track, t: number): (number, number, number, number, number)
	local x = M.clamp(t, 0, track.duration) * track.rate
	local i0 = math.floor(x)
	if i0 >= track.count - 1 then
		local n = track.count
		return track.x[n], track.y[n], track.z[n], track.yaw[n], track.speed[n]
	end
	local f = x - i0
	local a, b = i0 + 1, i0 + 2
	local function lerp(arr: { number }): number
		return arr[a] + (arr[b] - arr[a]) * f
	end
	return lerp(track.x), lerp(track.y), lerp(track.z), lerp(track.yaw), lerp(track.speed)
end

-- The path's heading at distance d along it; straight on past either end.
function Path.headingAtDist(track: Track, d: number): number
	local S, Y = track.headS, track.headYaw
	local n = #S
	if n == 0 then
		return track.yaw[1]
	end
	if d <= S[1] then
		return Y[1]
	elseif d >= S[n] then
		return Y[n]
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if S[mid] <= d then
			lo = mid
		else
			hi = mid
		end
	end
	local span = S[hi] - S[lo]
	local k = if span > 1e-12 then (d - S[lo]) / span else 0
	return Y[lo] + (Y[hi] - Y[lo]) * k
end

-- Position (x, z) and path heading at distance d along the path, from the sampled track.
function Path.atDist(track: Track, d: number): (number, number, number)
	local D = track.dist
	local n = track.count
	local yaw = Path.headingAtDist(track, d)
	if n == 0 then
		return 0, 0, yaw
	end
	if d <= D[1] then
		return track.x[1], track.z[1], yaw
	end
	if d >= D[n] then
		-- the first sample that reached the end
		local lo = n
		while lo > 1 and D[lo - 1] >= D[n] do
			lo -= 1
		end
		return track.x[lo], track.z[lo], yaw
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if D[mid] < d then
			lo = mid
		else
			hi = mid
		end
	end
	local span = D[hi] - D[lo]
	local k = if span > 1e-12 then (d - D[lo]) / span else 0
	return track.x[lo] + (track.x[hi] - track.x[lo]) * k, track.z[lo] + (track.z[hi] - track.z[lo]) * k, yaw
end

-- Distance travelled by time t.
function Path.distAt(track: Track, t: number): number
	local x = M.clamp(t, 0, track.duration) * track.rate
	local i0 = math.floor(x)
	if i0 >= track.count - 1 then
		return track.dist[track.count]
	end
	local f = x - i0
	return track.dist[i0 + 1] + (track.dist[i0 + 2] - track.dist[i0 + 1]) * f
end

-- A straight track at constant speed along the heading `yaw`, for in-place cycles.
function Path.straight(start: V3, yaw: number, speed: number, duration: number, rate: number): Track
	local count = math.max(2, math.floor(duration * rate + 0.5) + 1)
	local dir = M.qrot(M.qaxis(M.UP, yaw), M.FORWARD)
	local track: Track = {
		rate = rate,
		count = count,
		duration = (count - 1) / rate,
		x = table.create(count, 0),
		y = table.create(count, 0),
		z = table.create(count, 0),
		yaw = table.create(count, yaw),
		speed = table.create(count, speed),
		accel = table.create(count, 0),
		yawRate = table.create(count, 0),
		arrive = (count - 1) / rate,
		length = speed * (count - 1) / rate,
		cruise = speed,
		warnings = {},
		dist = table.create(count, 0),
		headS = { 0, speed * (count - 1) / rate },
		headYaw = { yaw, yaw },
	}
	for i = 1, count do
		local t = (i - 1) / rate
		track.dist[i] = speed * t
		track.x[i] = start.x + dir.x * speed * t
		track.y[i] = start.y
		track.z[i] = start.z + dir.z * speed * t
	end
	return track
end

return Path
