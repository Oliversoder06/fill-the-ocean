--!strict
--[[
	Ease: how a value travels between keys.

	The default ("natural") departs quickly and arrives gently: speed peaks about 38% of the way
	through a move and the peak is about 1.5 times the average speed, which is what captured
	human gestures do. A symmetric in-out (peak at 50%) is the most common tell of keyed motion,
	and linear (constant speed, a kink at every key) the second; both are available because
	sometimes they are right, but neither is the default.

	Multi-key curves use a monotone cubic (Fritsch-Carlson): it passes through every key, never
	overshoots between two (no invented wobble), stops only where the motion reverses, and keeps
	velocity continuous through keys that continue in the same direction, so a breakdown key does
	not make the limb pause.
]]

local Ease = {}

export type Name = "natural" | "linear" | "constant" | "in" | "out" | "inOut" | "snap" | "settle" | "smooth"

local function smoothstep(u: number): number
	return u * u * (3 - 2 * u)
end

--[[
	The natural ease integrates a speed profile u * (1 - u)^b, which starts and ends at rest and
	peaks at u = 1 / (1 + b). With b = 1/0.38 - 1 the peak sits 38% of the way through, and the
	peak is about 1.65 times the average speed. In closed form:
		e(u) = 1 - (1 - u)^(b + 1) * (1 + (b + 1) * u)
	(b = 3 gives the strike ease, peaking at 25%.)
]]
local NATURAL_B = 1 / 0.38 - 1
local function earlyPeak(u: number, b: number): number
	local v = 1 - u
	return 1 - v ^ (b + 1) * (1 + (b + 1) * u)
end

local curves: { [string]: (number) -> number } = {
	linear = function(u)
		return u
	end,
	constant = function(u)
		return if u >= 1 then 1 else 0
	end,
	-- cubic in and out. "out" starts at full speed and "in" ends at it: for impacts and
	-- releases (a blow landing, a drop), never between two held poses
	["in"] = function(u)
		return u * u * u
	end,
	out = function(u)
		local v = 1 - u
		return 1 - v * v * v
	end,
	inOut = smoothstep,
	smooth = smoothstep,
	natural = function(u)
		return earlyPeak(u, NATURAL_B)
	end,
	-- a strike: speed peaks a quarter of the way (twice the average) and decelerates long;
	-- still starts and ends at rest, so it leaves the previous key without a jolt
	snap = function(u)
		return earlyPeak(u, 3)
	end,
	-- arrives very gently, for coming to rest after a big move
	settle = function(u)
		local v = 1 - u
		return 1 - v * v * v * v
	end,
}

Ease.names = { "natural", "linear", "constant", "in", "out", "inOut", "snap", "settle", "smooth" }

function Ease.known(name: any): boolean
	return type(name) == "string" and curves[name] ~= nil
end

-- Eases u in [0, 1] by the named curve (unknown names use "natural").
function Ease.apply(name: string?, u: number): number
	if u <= 0 then
		return 0
	elseif u >= 1 then
		return 1
	end
	local f = curves[name or "natural"] or curves.natural
	return f(u)
end

--[[
	Fritsch-Carlson tangents for values v at strictly increasing times t (one component). Zero
	at local extremes and at the ends of a non-looping curve; harmonic-mean elsewhere, limited
	so the cubic stays monotone between keys.
]]
function Ease.tangents(t: { number }, v: { number }, loop: boolean?): { number }
	local n = #t
	local m: { number } = table.create(n, 0)
	if n < 2 then
		return m
	end
	local d: { number } = table.create(n - 1, 0)
	for i = 1, n - 1 do
		local h = t[i + 1] - t[i]
		d[i] = if h > 1e-12 then (v[i + 1] - v[i]) / h else 0
	end
	for i = 2, n - 1 do
		if d[i - 1] * d[i] <= 0 then
			m[i] = 0
		else
			local h0 = t[i] - t[i - 1]
			local h1 = t[i + 1] - t[i]
			local w0 = 2 * h1 + h0
			local w1 = h1 + 2 * h0
			m[i] = (w0 + w1) / (w0 / d[i - 1] + w1 / d[i])
		end
	end
	if loop and n >= 3 then
		-- the seam: the last key repeats the first
		local da, db = d[n - 1], d[1]
		local edge = 0
		if da * db > 0 then
			local h0 = t[n] - t[n - 1]
			local h1 = t[2] - t[1]
			local w0 = 2 * h1 + h0
			local w1 = h1 + 2 * h0
			edge = (w0 + w1) / (w0 / da + w1 / db)
		end
		m[1] = edge
		m[n] = edge
	end
	return m
end

-- Cubic Hermite between (t0, v0, m0) and (t1, v1, m1) at time x.
function Ease.hermite(t0: number, v0: number, m0: number, t1: number, v1: number, m1: number, x: number): number
	local h = t1 - t0
	if h <= 1e-12 then
		return v1
	end
	local s = (x - t0) / h
	if s <= 0 then
		return v0
	elseif s >= 1 then
		return v1
	end
	local s2 = s * s
	local s3 = s2 * s
	return (2 * s3 - 3 * s2 + 1) * v0 + (s3 - 2 * s2 + s) * h * m0 + (-2 * s3 + 3 * s2) * v1 + (s3 - s2) * h * m1
end

--[[
	Where a segment between two keys is, as a fraction 0..1 of the way, at local time u, for a
	segment that starts and ends at rest under the monotone spline (zero tangents both ends):
	the natural ease. Segments that flow through a key keep the plain Hermite.
]]
function Ease.restToRest(u: number): number
	return Ease.apply("natural", u)
end

return Ease
