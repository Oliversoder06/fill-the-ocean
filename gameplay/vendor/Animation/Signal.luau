--!strict
--[[
	Signal: smoothing and windowed filters over sampled curves, used at bake time.

	Body signals (height, sway, lean) are computed per sample from contacts and limits, which
	leaves corners. A corner in a curve is a velocity jump on screen: a pop. These filters remove
	them without shifting anything in time (the Gaussian is symmetric), wrapping round for loops
	so the seam stays smooth.

	A limit must stay a limit after smoothing, so a ceiling is first spread with a min filter
	over the blur's radius and then blurred: the result never rises above the original anywhere.
]]

local Signal = {}

local function at(a: { number }, i: number, n: number, loop: boolean): number
	if loop then
		-- the last sample repeats the first in a loop; wrap over n - 1 distinct samples
		local m = math.max(n - 1, 1)
		local k = (i - 1) % m + 1
		return a[k]
	end
	if i < 1 then
		return a[1]
	elseif i > n then
		return a[n]
	end
	return a[i]
end

-- Gaussian blur with standard deviation `sigma` samples (0 or less returns a copy).
function Signal.gauss(a: { number }, sigma: number, loop: boolean?): { number }
	local n = #a
	local out: { number } = table.create(n, 0)
	if n == 0 then
		return out
	end
	if not (sigma > 0.25) then
		for i = 1, n do
			out[i] = a[i]
		end
		return out
	end
	local r = math.ceil(3 * sigma)
	local w: { number } = table.create(2 * r + 1, 0)
	local sum = 0
	for k = -r, r do
		local v = math.exp(-(k * k) / (2 * sigma * sigma))
		w[k + r + 1] = v
		sum += v
	end
	for k = 1, #w do
		w[k] /= sum
	end
	local lp = loop == true
	for i = 1, n do
		local acc = 0
		for k = -r, r do
			acc += w[k + r + 1] * at(a, i + k, n, lp)
		end
		out[i] = acc
	end
	if lp and n >= 2 then
		out[n] = out[1]
	end
	return out
end

local function window(a: { number }, radius: number, loop: boolean?, pickMax: boolean): { number }
	local n = #a
	local out: { number } = table.create(n, 0)
	local r = math.max(0, math.floor(radius))
	local lp = loop == true
	for i = 1, n do
		local best = a[i]
		for k = -r, r do
			local v = at(a, i + k, n, lp)
			if (pickMax and v > best) or (not pickMax and v < best) then
				best = v
			end
		end
		out[i] = best
	end
	return out
end

function Signal.dilate(a: { number }, radius: number, loop: boolean?): { number }
	return window(a, radius, loop, true)
end

function Signal.erode(a: { number }, radius: number, loop: boolean?): { number }
	return window(a, radius, loop, false)
end

-- A smooth curve that never exceeds `ceiling` (min filter, then blur of the same reach).
function Signal.smoothCeiling(ceiling: { number }, sigma: number, loop: boolean?): { number }
	local r = math.ceil(3 * math.max(sigma, 0))
	return Signal.gauss(Signal.erode(ceiling, r, loop), sigma, loop)
end

-- A smooth curve that never falls below `floor`.
function Signal.smoothFloor(floor: { number }, sigma: number, loop: boolean?): { number }
	local r = math.ceil(3 * math.max(sigma, 0))
	return Signal.gauss(Signal.dilate(floor, r, loop), sigma, loop)
end

-- Value at fractional sample position x (1-based), clamped or wrapped.
function Signal.sampleAt(a: { number }, x: number, loop: boolean?): number
	local n = #a
	if n == 0 then
		return 0
	end
	local i0 = math.floor(x)
	local f = x - i0
	local lp = loop == true
	return at(a, i0, n, lp) * (1 - f) + at(a, i0 + 1, n, lp) * f
end

-- The curve delayed by `samples` (fractional), so a child can trail its parent.
function Signal.delay(a: { number }, samples: number, loop: boolean?): { number }
	local n = #a
	local out: { number } = table.create(n, 0)
	for i = 1, n do
		out[i] = Signal.sampleAt(a, i - samples, loop)
	end
	return out
end

function Signal.range(a: { number }, from: number?, to: number?): (number, number)
	local lo, hi = math.huge, -math.huge
	for i = from or 1, to or #a do
		local v = a[i]
		if v < lo then
			lo = v
		end
		if v > hi then
			hi = v
		end
	end
	return lo, hi
end

return Signal
