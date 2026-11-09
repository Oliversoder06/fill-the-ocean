--!strict
--[[
	Legless: how a body with no legs gets along a path, chosen by its shape.

		hop      compact (an egg): rock back, launch, a ballistic arc under the game's gravity,
		         land and settle. The body is still while on the ground (a rigid shell cannot
		         slide) and turns in the air to face its next landing.
		slither  long with a jointed body (a snake): lateral undulation. The wave is fixed to
		         the ground, not to the body, so every segment travels down the same curve: no
		         segment slides sideways, which is what makes a slither read as real.
		hover    flagged as flying: glides at its height with a slow swell, pitches into
		         acceleration, banks into turns; wings, if any, beat.
		roll     round (a ball): rolls without slipping, turning distance into rotation.
		slide    anything else (a long rigid body): glides along the ground with a faint sway.

	And a wing beat (wingPose, flap) for any wing chains: the down-stroke a little longer than the
	up, the outer joints trailing the shoulder and folding on the way up.
]]

local M = require("./Math")
local Rig = require("./Rig")
local Anatomy = require("./Anatomy")
local GaitPlan = require("./GaitPlan")
local Path = require("./Path")
local Signal = require("./Signal")
local Baked = require("./Baked")

type V3 = M.V3
type Q = M.Q
type X = M.X

local Legless = {}

export type Options = {
	path: Path.Spec?,
	speed: number?,
	style: string?,
	gravity: number?,
	gaitGravity: number?,
	rate: number?,
	start: any?,
	ground: ((number, number) -> number)?,
	loop: boolean?,
	-- hop height as a share of the body's height (default 0.18)
	hop: number?,
	-- wing beats per second (default from the wing's length)
	flap: number?,
	-- slither wave amplitude in degrees (default 22)
	wave: number?,
	-- hover height above the ground or the path (default half the body's size)
	altitude: number?,
	name: string?,
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

-- The mode for a legless body, and why.
function Legless.choose(anatomy: Anatomy.Anatomy, style: string?): (string, string)
	if style == "hop" or style == "slither" or style == "hover" or style == "roll" or style == "slide" then
		return style :: string, "asked for"
	end
	if anatomy.flying then
		return "hover", "flagged as flying"
	end
	if anatomy.shape == "round" or anatomy.round then
		return "roll", "round"
	end
	local chainLen = #anatomy.spine
	for _, c in anatomy.tails do
		chainLen = math.max(chainLen, #c.movable)
	end
	if anatomy.shape == "long" then
		if chainLen >= 3 then
			return "slither", "long, with a jointed body to bend"
		end
		return "slide", "long but rigid: it cannot bend, so it glides"
	end
	return "hop", "compact: it hops"
end

-- The chain a slither bends: the spine if long enough, else the longest tail.
local function bendChain(anatomy: Anatomy.Anatomy): { number }
	local best: { number } = {}
	for _, k in anatomy.spine do
		if anatomy.rig.joints[k].animated then
			table.insert(best, k)
		end
	end
	for _, c in anatomy.tails do
		if #c.movable > #best then
			best = c.movable
		end
	end
	return best
end

local function wingAxis(rig: Rig.Rig, k: number): V3
	local j = rig.joints[k]
	local dir = M.vnorm(M.vsub(M.xpoint(j.world, j.tip), j.world.p), { x = 1, y = 0, z = 0 })
	local a = M.vcross(dir, M.UP)
	if M.vlen(a) < 1e-4 then
		return M.FORWARD
	end
	return M.vnorm(a)
end

-- Rotation about a character-space axis, as joint k's local Transform rotation.
local function localTurn(rig: Rig.Rig, k: number, axis: V3, angle: number): Q
	local w = rig.joints[k].world.q
	return M.qaxis(M.qinvrot(w, axis), angle)
end

--[[
	Wing beat: writes local rotations for every wing chain at phase u (0..1 of a beat) into
	`locals`. Down-stroke 55% of the beat; outer joints trail and fold on the up-stroke.
]]
function Legless.wingPose(anatomy: Anatomy.Anatomy, u: number, amount: number, locals: { [number]: X })
	local rig = anatomy.rig
	for _, wing in anatomy.wings do
		if #wing.movable == 0 then
			continue
		end
		local axis = wingAxis(rig, wing.movable[1])
		for si, k in wing.movable do
			-- each joint further out trails by 6% of a beat
			local w = M.frac(u - 0.06 * (si - 1))
			-- elevation: up at w = 0, down at 0.55, back up at 1 (two eased halves)
			local e: number
			if w < 0.55 then
				e = 1 - 2 * M.smoothstep(w / 0.55)
			else
				e = -1 + 2 * M.smoothstep((w - 0.55) / 0.45)
			end
			local ang: number
			if si == 1 then
				ang = math.rad(if e > 0 then 38 else 32) * e
			else
				-- outer joints follow, folding a little on the way up
				local fold = if w > 0.55 then math.sin(math.pi * (w - 0.55) / 0.45) else 0
				ang = math.rad(8) * e - math.rad(22) * fold
			end
			local cur = locals[k] or M.xid()
			locals[k] = { p = cur.p, q = M.qnorm(M.qmul(cur.q, localTurn(rig, k, axis, ang * amount))) }
		end
	end
end

-- Beats per second for the creature's wings: longer wings beat slower (pendulum scaling).
function Legless.flapRate(anatomy: Anatomy.Anatomy, gg: number): number
	local span = 0
	for _, w in anatomy.wings do
		span = math.max(span, w.length)
	end
	if span <= 1e-6 then
		span = math.max(anatomy.width / 2, 0.5)
	end
	return M.clamp(0.35 * math.sqrt(gg / span), 0.8, 6)
end

local function animatedJoints(rig: Rig.Rig): ({ number }, { [number]: number })
	local list: { number } = {}
	local map: { [number]: number } = {}
	for k, j in rig.joints do
		if j.animated then
			table.insert(list, k)
			map[k] = #list
		end
	end
	return list, map
end

--[[
	Bakes legless motion along opts.path (or one in-place cycle when opts.loop). bake.info.mode
	says which mode and why.
]]
function Legless.bake(anatomy: Anatomy.Anatomy, opts: Options?): Baked.Baked
	local o: Options = opts or {}
	local rig = anatomy.rig
	local rate = if type(o.rate) == "number" and M.finite(o.rate) and o.rate >= 10 then math.min(o.rate, 240) else Baked.RATE
	local dt = 1 / rate
	local g = GaitPlan.gravity(o :: any)
	local gg = GaitPlan.gaitGravity(o :: any)
	local size = math.max(anatomy.height, 1e-3)
	local mode, why = Legless.choose(anatomy, o.style)
	local start = readStart(o.start, rig)
	local startYaw = headingOf(start.q) + rig.facing
	local floor0 = start.p.y + rig.ground
	local rootH = -rig.ground
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
	local warnings: { string } = {}
	local animated, channelOf = animatedJoints(rig)
	local loopMode = o.loop == true

	-- default speeds by mode, scaled with size
	local bodyLen = math.max(anatomy.length, size)
	-- a slither's wavelength: about 0.9 of the body (one full S along it)
	local slitherLambda = 0.9 * bodyLen
	local defaultSpeed: number
	if mode == "hop" then
		defaultSpeed = 0.42 * math.sqrt(gg * size)
	elseif mode == "slither" then
		defaultSpeed = 0.5 * bodyLen
	elseif mode == "hover" then
		defaultSpeed = math.sqrt(0.3 * gg * size)
	elseif mode == "roll" then
		defaultSpeed = math.sqrt(0.5 * gg * size)
	else
		defaultSpeed = 0.4 * bodyLen
	end
	local speed = if type(o.speed) == "number" and M.finite(o.speed) and o.speed > 0 then o.speed else defaultSpeed

	-- hop timing is set by gravity: a hop of height h stays up sqrt(8h/g)
	local hopShare = if type(o.hop) == "number" and M.finite(o.hop) then M.clamp(o.hop, 0.02, 2) else 0.18
	local hopH = hopShare * size
	local flightT = math.sqrt(8 * hopH / g)
	local groundT = M.clamp(0.22 * math.sqrt(size / 2), 0.12, 0.6)

	local track: Path.Track
	local loopCycle = 1
	if loopMode then
		if mode == "hop" then
			loopCycle = flightT + groundT
		elseif mode == "slither" then
			loopCycle = slitherLambda / math.max(speed, 1e-3)
		elseif mode == "hover" then
			loopCycle = 1 / Legless.flapRate(anatomy, gg)
		elseif mode == "roll" then
			loopCycle = 2 * math.pi * math.max(size / 2, 1e-3) / math.max(speed, 1e-3)
		else
			loopCycle = 1.2
		end
		track = Path.straight({ x = start.p.x, y = floor0, z = start.p.z }, startYaw, speed, 4 * loopCycle, rate)
	else
		local pathSpec: Path.Spec = if type(o.path) == "table" then table.clone(o.path :: Path.Spec) else {}
		if pathSpec.speed == nil then
			pathSpec.speed = speed
		end
		track = Path.track(pathSpec, { x = start.p.x, y = floor0, z = start.p.z }, startYaw, rate, size, gg)
		for _, w in track.warnings do
			table.insert(warnings, w)
		end
		speed = track.cruise
	end

	local n = track.count
	local root: { X } = {}
	local jointQ: { { [number]: X } } = {}
	local hopMarks: { number } = {}

	if mode == "hop" then
		--[[
			Hops at even spacing along the path: ground time, then a flight, back to back. The
			track's standing start (and any turn to face the path) comes first; its turn to face
			and hold at the end come after the last landing.
		]]
		local total = track.length
		local hopT = flightT + groundT
		local hops = if total > 1e-6 then math.max(1, math.ceil(total / math.max(speed * hopT, 1e-6))) else 0
		local seg = if hops > 0 then total / hops else 0
		local tBegin = track.arrive
		for k = 1, track.count do
			if track.speed[k] > 1e-6 then
				tBegin = (k - 1) * dt
				break
			end
		end
		local tHopsEnd = tBegin + hops * hopT + (if hops > 0 then groundT else 0)
		if hops > 0 and not loopMode then
			local tail = math.max(0, track.duration - track.arrive)
			n = math.max(2, math.floor((tHopsEnd + tail) * rate + 0.5) + 1)
		end
		local tiltBack = math.rad(6)
		-- a rigid shell meets the ground in an instant: mark each take-off and landing as a
		-- contact, so the pop lint knows the sudden change of speed there is the impact itself
		for h = 0, hops - 1 do
			local up = tBegin + h * hopT + groundT
			table.insert(hopMarks, up)
			table.insert(hopMarks, up + flightT)
		end
		for k = 1, n do
			local t = (k - 1) * dt
			local x, z, yaw, y
			local pitchA = 0
			if hops == 0 or t < tBegin then
				local px, _, pz, pyaw = Path.at(track, t)
				x, z, yaw = px, pz, pyaw
				y = ground(x, z) + rootH
			elseif t >= tHopsEnd then
				local px, _, pz, pyaw = Path.at(track, track.arrive + (t - tHopsEnd))
				x, z, yaw = px, pz, pyaw
				y = ground(x, z) + rootH
			else
				local since = t - tBegin
				local h = math.min(math.floor(since / hopT), hops)
				local w = since - h * hopT
				local d0 = math.min(h * seg, total)
				local d1 = math.min((h + 1) * seg, total)
				if h >= hops or w < groundT then
					-- on the ground: settle from the last landing, then rock back to launch
					local px, pz, pyaw = Path.atDist(track, d0)
					x, z, yaw = px, pz, pyaw
					y = ground(x, z) + rootH
					local u = M.clamp(w / groundT, 0, 1)
					if h > 0 and u < 0.4 then
						pitchA = -tiltBack * 0.5 * math.sin(math.pi * u / 0.4)
					elseif u >= 0.4 and h < hops then
						pitchA = tiltBack * math.sin(math.pi * 0.5 * (u - 0.4) / 0.6)
					end
				else
					-- in the air: straight across, ballistic up and down, turning to the landing
					local u = (w - groundT) / flightT
					local ax, az, ayaw = Path.atDist(track, d0)
					local bx2, bz2, byaw2 = Path.atDist(track, d1)
					x = ax + (bx2 - ax) * u
					z = az + (bz2 - az) * u
					yaw = ayaw + M.wrapAngle(byaw2 - ayaw) * M.smoothstep(u)
					local ta = u * flightT
					local gy0 = ground(ax, az)
					local gy1 = ground(bx2, bz2)
					y = gy0 + (gy1 - gy0) * u + rootH + 0.5 * g * ta * (flightT - ta)
					pitchA = tiltBack * (1 - u) * (1 - u) - tiltBack * 0.4 * u * u
				end
			end
			local q = M.qaxis(M.UP, yaw - rig.facing)
			-- rock about the middle of its underside; the floor pass below then rolls the shell
			-- onto its curve. (Rocking about whichever bottom edge it tips onto swaps edges at
			-- level, and the jump from one pivot to the other is a pop.)
			local pr = M.qaxis(M.RIGHT, pitchA)
			local pivot = { x = 0, y = -rootH, z = 0 }
			local moved = M.vsub(pivot, M.qrot(pr, pivot))
			root[k] = M.xmul({ p = { x = x, y = y, z = z }, q = q }, { p = moved, q = pr })
			jointQ[k] = {}
		end
	elseif mode == "slither" then
		local chain = bendChain(anatomy)
		-- a clear travelling S: each segment swings up to 38 degrees off the line of travel, over
		-- a wave about 0.9 of the body long (one full S along the body), the head nearly steady
		-- and the swing growing toward the tail, as a snake's does
		local waveA = math.rad(if type(o.wave) == "number" and M.finite(o.wave) then M.clamp(o.wave, 0, 60) else 38)
		local lambda = slitherLambda
		-- each bending joint's distance behind the root along the body
		local behind: { number } = {}
		for i, k in chain do
			behind[i] = rig.joints[k].world.p.z
		end
		for k = 1, n do
			local t = (k - 1) * dt
			local x, _, z, yaw = Path.at(track, t)
			local d = Path.distAt(track, t)
			local headAbs = Path.headingAtDist(track, d)
			local share = M.clamp(track.speed[k] / math.max(speed, 1e-6), 0, 1)
			-- the wave is a shape on the ground: its phase goes by distance, not by time
			local function waveAt(dd: number, along: number): number
				local taper = 0.4 + 0.6 * M.clamp(along / math.max(bodyLen, 1e-6), 0, 1)
				return waveA * taper * share * math.sin(2 * math.pi * dd / lambda)
			end
			local rootWave = waveAt(d, 0) * 0.5
			local q = M.qaxis(M.UP, yaw + rootWave - rig.facing)
			root[k] = { p = { x = x, y = ground(x, z) + rootH, z = z }, q = q }
			local locals: { [number]: X } = {}
			local prevAbs = headAbs + rootWave
			for i, kk in chain do
				local along = behind[i]
				local abs = Path.headingAtDist(track, d - along) + waveAt(d - along, along)
				local rel = M.wrapAngle(abs - prevAbs)
				prevAbs = abs
				locals[kk] = { p = { x = 0, y = 0, z = 0 }, q = localTurn(rig, kk, M.UP, rel) }
			end
			jointQ[k] = locals
		end
	elseif mode == "hover" or mode == "slide" then
		local flapHz = if type(o.flap) == "number" and M.finite(o.flap) and o.flap > 0 then o.flap else Legless.flapRate(anatomy, gg)
		if loopMode and mode == "hover" then
			-- whole beats per loop
			flapHz = 1 / loopCycle
		end
		local swellT = if loopMode then loopCycle else M.clamp(1.8 * math.sqrt(size / 2), 0.8, 6)
		local swellA = (if mode == "hover" then 0.03 else 0) * size
		local hasWings = #anatomy.wings > 0 and mode == "hover"
		local bob: { number } = table.create(n, 0)
		local pitch: { number } = table.create(n, 0)
		local roll: { number } = table.create(n, 0)
		for k = 1, n do
			local t = (k - 1) * dt
			local v = track.speed[k]
			local a = track.accel[k]
			local w = track.yawRate[k]
			-- the swell; with wings, the body lifts on each down-stroke
			bob[k] = swellA * math.sin(2 * math.pi * t / swellT)
			if hasWings then
				local u = M.frac(t * flapHz)
				bob[k] += 0.015 * size * math.sin(2 * math.pi * (u - 0.1))
			end
			if mode == "hover" then
				pitch[k] = M.clamp(math.atan(a / gg) * 0.6 + 0.05 * v / math.max(speed, 1e-6), -0.35, 0.35)
				roll[k] = M.clamp(math.atan(v * w / gg) * 0.9, -0.45, 0.45)
			else
				roll[k] = math.rad(1.5) * math.sin(2 * math.pi * t / swellT) * M.clamp(v / math.max(speed, 1e-6), 0, 1)
			end
		end
		pitch = Signal.gauss(pitch, 0.12 * rate, loopMode)
		roll = Signal.gauss(roll, 0.12 * rate, loopMode)
		-- a hover takes off from where it stands to its height (default half its size above
		-- the ground, or the path's own height), and settles back down at the end
		local lift = if type((o :: any).altitude) == "number" then (o :: any).altitude else 0.5 * size
		local rise = M.clamp(0.9 * math.sqrt(size / 2), 0.5, 3)
		local total = (n - 1) * dt
		for k = 1, n do
			local t = (k - 1) * dt
			local x, py, z, yaw = Path.at(track, t)
			local base = start.p.y
			if mode == "slide" then
				base = ground(x, z) + rootH
			else
				local up = M.smoothstep(t / rise) * (if loopMode then 1 else M.smoothstep((total - t) / rise))
				if loopMode then
					up = 1
				end
				base = math.max(start.p.y, py + rootH) + lift * up
			end
			-- nose down into acceleration: rotate the front (-Z) downward, about +X negatively
			local q = M.qmul(M.qmul(M.qaxis(M.UP, yaw - rig.facing), M.qaxis(M.RIGHT, -pitch[k])), M.qaxis({ x = 0, y = 0, z = 1 }, roll[k]))
			root[k] = { p = { x = x, y = base + bob[k], z = z }, q = q }
			local locals: { [number]: X } = {}
			if hasWings then
				Legless.wingPose(anatomy, M.frac(t * flapHz), 1, locals)
			end
			jointQ[k] = locals
		end
	else -- roll
		local radius = math.max(size / 2, 1e-3)
		local spin = 0
		for k = 1, n do
			local t = (k - 1) * dt
			local x, _, z, yaw = Path.at(track, t)
			if k > 1 then
				spin += track.speed[k] * dt / radius
			end
			local q = M.qmul(M.qaxis(M.UP, yaw - rig.facing), M.qaxis(M.RIGHT, -spin))
			root[k] = { p = { x = x, y = ground(x, z) + rootH, z = z }, q = q }
			jointQ[k] = {}
		end
	end

	-- Never into the ground: a hop rocking on its shell, a hover settling with its swell, a
	-- slide's sway each tip the body. Each box is taken as the ellipsoid inside it (an egg, a
	-- pebble, a rounded segment): its lowest point moves smoothly as it tips, where a box's
	-- corners would swap over with a kink at level (a pop). Where that point would go under
	-- the floor the whole body is lifted, along a smooth curve at or above what every sample
	-- needs, so a tipped shell rolls onto its side instead of sinking through.
	if mode == "hop" or mode == "hover" or mode == "slide" then
		local blobs: { { c: V3, h: V3 } } = {}
		if rig.rootSize.y > 0 then
			table.insert(blobs, { c = M.ZERO, h = M.vmul(rig.rootSize, 0.5) })
		end
		for _, kk in anatomy.spine do
			local j = rig.joints[kk]
			if j.boxMin and j.boxMax then
				local lo, hi = j.boxMin :: V3, j.boxMax :: V3
				table.insert(blobs, { c = M.vmul(M.vadd(lo, hi), 0.5), h = M.vmul(M.vsub(hi, lo), 0.5) })
			else
				table.insert(blobs, { c = j.world.p, h = M.ZERO })
			end
		end
		if #blobs > 0 then
			local need: { number } = table.create(n, 0)
			local any = false
			for k = 1, n do
				local r = root[k]
				-- the world's up in the body's frame: an ellipsoid reaches down by the length of
				-- its half-extents weighted by it
				local u = M.qinvrot(r.q, M.UP)
				local low = math.huge
				for _, e in blobs do
					local depth = math.sqrt((e.h.x * u.x) ^ 2 + (e.h.y * u.y) ^ 2 + (e.h.z * u.z) ^ 2)
					low = math.min(low, M.qrot(r.q, e.c).y - depth)
				end
				local d = ground(r.p.x, r.p.z) - (r.p.y + low)
				if d > 1e-9 then
					need[k] = d
					any = true
				end
			end
			if any then
				need = Signal.smoothFloor(need, 0.06 * rate, loopMode)
				for k = 1, n do
					local r = root[k]
					root[k] = { p = { x = r.p.x, y = r.p.y + need[k], z = r.p.z }, q = r.q }
				end
			end
		end
	end

	local name = if type(o.name) == "string" then o.name else mode
	local baked = Baked.new(name, "gait", rate, n, false, animated, if loopMode then "offset" else "world")
	for k = 1, n do
		if loopMode then
			local x, _, z, yaw = Path.at(track, (k - 1) * dt)
			local pathFrame = { p = { x = x, y = floor0 + rootH, z = z }, q = M.qaxis(M.UP, yaw - rig.facing) }
			Baked.set(baked, k - 1, 0, M.xrel(pathFrame, root[k]))
		else
			Baked.set(baked, k - 1, 0, root[k])
		end
		for kk, l in jointQ[k] do
			local c = channelOf[kk]
			if c then
				Baked.set(baked, k - 1, c, l)
			end
		end
	end
	Baked.finish(baked)
	for _, tm in hopMarks do
		table.insert(baked.markers, { name = "contact", time = tm })
	end
	baked.info = {
		mode = mode,
		why = why,
		gait = mode,
		speed = speed,
		legs = 0,
		hopHeight = hopH,
		flightTime = flightT,
		ground = floor0,
		start = start,
		hipHeight = anatomy.hipHeight,
		warnings = warnings,
		reasons = { mode .. ": " .. why },
	}
	for _, w in warnings do
		table.insert(baked.warnings, w)
	end
	if loopMode then
		local Locomotion = require("./Locomotion")
		return Locomotion.cutLoop(baked, loopCycle, loopCycle)
	end
	return baked
end

--[[
	A wing beat in place: one looping beat for a creature's wing chains (a bird flapping on a
	perch, a dragon hovering). The body rises a little on each down-stroke.
]]
function Legless.flap(anatomy: Anatomy.Anatomy, opts: Options?): Baked.Baked
	local o: Options = opts or {}
	local rig = anatomy.rig
	local gg = GaitPlan.gaitGravity(o :: any)
	local hz = if type(o.flap) == "number" and M.finite(o.flap) and o.flap > 0 then o.flap else Legless.flapRate(anatomy, gg)
	local period = 1 / hz
	local rate = if type(o.rate) == "number" and M.finite(o.rate) and o.rate >= 10 then math.min(o.rate, 240) else Baked.RATE
	local count = math.max(2, math.floor(period * rate + 0.5) + 1)
	local exact = (count - 1) / period
	local animated, channelOf = animatedJoints(rig)
	local baked = Baked.new(if type(o.name) == "string" then o.name else "flap", "gait", exact, count, true, animated, "offset")
	local size = math.max(anatomy.height, 1e-3)
	for s = 0, count - 1 do
		local u = s / (count - 1)
		local locals: { [number]: X } = {}
		Legless.wingPose(anatomy, u, 1, locals)
		Baked.set(baked, s, 0, { p = { x = 0, y = 0.015 * size * math.sin(2 * math.pi * (u - 0.1)), z = 0 }, q = M.qid() })
		for k, l in locals do
			local c = channelOf[k]
			if c then
				Baked.set(baked, s, c, l)
			end
		end
	end
	Baked.finish(baked)
	baked.info = {
		mode = "flap",
		gait = "flap",
		hz = hz,
		legs = #anatomy.legs,
		wings = #anatomy.wings,
		reasons = { string.format("%d wing(s) beating at %.2f Hz", #anatomy.wings, hz) },
	}
	if #anatomy.wings == 0 then
		table.insert(baked.warnings, "no wings found: the beat is empty (flag wings with overrides.wings)")
	end
	return baked
end

return Legless
