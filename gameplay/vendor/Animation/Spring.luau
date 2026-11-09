--!strict
--[[
	Spring: damped second-order responses in closed form, for secondary motion (an antenna, a
	tail tip, a hat brim) and settles.

	Why closed form: a spring stepped by a simulation depends on the frame rate and on every
	frame before it, so two clients, a seek and a late joiner would disagree. Here the response to
	an impulse is an explicit function of time, and a driven response uses the exact solution of
	the spring between samples (the input held over each sample), so the same input gives the same
	output whatever the rate and wherever playback starts.

	Restraint: the house style keeps springs off unless a performance asks for them. Overshoot is
	the cartoon tell; damping ratios here default to 0.7 (one small overshoot of about 5%).
]]

local Spring = {}

export type Params = { hz: number, damping: number }

-- Displacement at time t after a unit velocity impulse at t = 0 (zero before it).
function Spring.impulse(t: number, hz: number, damping: number): number
	if t <= 0 then
		return 0
	end
	local w = 2 * math.pi * math.max(hz, 1e-3)
	local z = math.max(damping, 0)
	if z < 1 then
		local wd = w * math.sqrt(1 - z * z)
		return math.exp(-z * w * t) * math.sin(wd * t) / wd
	elseif z == 1 then
		return t * math.exp(-w * t)
	else
		local r = w * math.sqrt(z * z - 1)
		local a, b = -z * w + r, -z * w - r
		return (math.exp(a * t) - math.exp(b * t)) / (a - b)
	end
end

--[[
	The exact one-step transition of x'' + 2 z w x' + w^2 x = w^2 u over dt with u held:
	returns the 2x2 matrix and input vector so x1 = A x0 + B u. Computed once per bake.
]]
local function transition(dt: number, hz: number, damping: number): (number, number, number, number, number, number)
	local w = 2 * math.pi * math.max(hz, 1e-3)
	local z = math.max(damping, 0)
	-- homogeneous solutions from x(0)=1,v(0)=0 and x(0)=0,v(0)=1
	local function step(x0: number, v0: number): (number, number)
		if z < 1 then
			local wd = w * math.sqrt(1 - z * z)
			local e = math.exp(-z * w * dt)
			local c, s = math.cos(wd * dt), math.sin(wd * dt)
			local x = e * (x0 * c + (v0 + z * w * x0) / wd * s)
			local v = e * (v0 * c - (w * w * x0 + z * w * v0) / wd * s)
			return x, v
		elseif z == 1 then
			local e = math.exp(-w * dt)
			local x = e * (x0 + (v0 + w * x0) * dt)
			local v = e * (v0 - w * (v0 + w * x0) * dt)
			return x, v
		else
			local r = w * math.sqrt(z * z - 1)
			local a, b = -z * w + r, -z * w - r
			local c1 = (v0 - b * x0) / (a - b)
			local c2 = (a * x0 - v0) / (a - b)
			local ea, eb = math.exp(a * dt), math.exp(b * dt)
			return c1 * ea + c2 * eb, c1 * a * ea + c2 * b * eb
		end
	end
	local a11, a21 = step(1, 0)
	local a12, a22 = step(0, 1)
	-- with u held, x settles towards u: x1 - u = A (x0 - u)  =>  B = (I - A) [1, 0]^T ... per row
	local b1 = 1 - a11
	local b2 = -a21
	return a11, a12, a21, a22, b1, b2
end

--[[
	Follows the input series (one value per sample at `rate`) with a spring, starting at rest on
	the first input. Returns a new series. For loops, the series is run twice and the second pass
	kept, so the seam carries the settled motion rather than a start-up transient.
]]
function Spring.follow(input: { number }, rate: number, hz: number, damping: number, loop: boolean?): { number }
	local n = #input
	local out: { number } = table.create(n, 0)
	if n == 0 then
		return out
	end
	local dt = 1 / math.max(rate, 1e-3)
	local a11, a12, a21, a22, b1, b2 = transition(dt, hz, damping)
	local x, v = input[1], 0
	local passes = if loop then 2 else 1
	for pass = 1, passes do
		for i = 1, n do
			if pass == passes then
				out[i] = x
			end
			local u = input[i]
			local nx = a11 * x + a12 * v + b1 * u
			local nv = a21 * x + a22 * v + b2 * u
			x, v = nx, nv
		end
	end
	return out
end

return Spring
