--!strict
--[[
	Performance: keyed acting (a punch, a flinch, a look round) as data, on any rig.

	A clip names parts, not joints: "hips", "chest", "head", "rightArm", "rightForearm",
	"leg[3]", "tail", "leftWing", or any joint as "joint:<Name>" (Anatomy.part has the list).
	The same clip plays on R15, R6, a golem or a pet; a part the rig lacks is skipped with a
	warning.

	Keys say where, never how a joint's axes happen to point:
		rot   = { pitch, yaw, roll } degrees about the character's right (X), up (Y) and back (Z)
		        axes at rest, applied at the part's own pivot. +pitch lifts a hanging arm
		        forward, +yaw turns left, +roll tips the top to the left. Converted into each
		        joint's own frame, so R6's quarter-turned shoulders and an imported pet's bones
		        all respond the same way.
		pos   = { x, y, z } studs in the character's frame (hips and root), scaled by the rig's
		        hip height over 2 unless the clip says units = "studs"
		reach = { x, y, z } a target for the end of the part's chain (a fist, a paw), in the
		        character's frame where it stood when the clip began; solved by IK each frame
		look  = { x, y, z } a point for the head to face, same frame
		ease  = "natural" (default) | "linear" | "constant" | "in" | "out" | "inOut" | "snap" | "settle"

	What happens between keys, by default (each can be switched off in `polish`):
	- spline: a monotone cubic through the keys, no overshoot, moves that start and end at rest
	  depart quickly and arrive gently (speed peaks near 38% of the move);
	- overlap: each joint trails the one it hangs from by a frame at 30 fps (elbow 1, wrist 2,
	  neck and chest 1, tail segments 1 each);
	- arcs: a reach that travels far bows out from the body instead of sliding straight;
	- plant: legs nobody keyed keep their feet where they stood, by IK, while the body moves;
	- drift: holds keep breathing-sized motion (captured "still" people still move);
	- mirror: left and right keyed as exact mirrors at the same times get one side 2-4 frames
	  later and a little smaller (symmetry reads as stiff; `symmetric = true` keeps it).
	Breathing, settle springs and secondary motion are off unless asked for.

	Bake once (Baked), then sample.
]]

local M = require("./Math")
local Rig = require("./Rig")
local Anatomy = require("./Anatomy")
local IK = require("./IK")
local Ease = require("./Ease")
local Spring = require("./Spring")
local Rng = require("./Rng")
local Baked = require("./Baked")

type V3 = M.V3
type Q = M.Q
type X = M.X

local Performance = {}

export type Key = {
	t: number,
	rot: { number }?,
	pos: { number }?,
	reach: { number }?,
	pole: { number }?,
	look: { number }?,
	ease: string?,
}

export type Clip = {
	name: string?,
	length: number?,
	loop: boolean?,
	rate: number?,
	keys: { any }?,
	tracks: { [string]: { Key } }?,
	markers: { any }?,
	plant: any?,
	polish: { [string]: any }?,
	springs: { any }?,
	secondary: any?,
	units: string?,
	travel: boolean?,
	waive: { string }?,
	seed: any?,
	symmetric: boolean?,
	rig: any?,
}

export type ValidationError = { path: string, expected: string, got: string }

local DEG = math.pi / 180
local FRAME30 = 1 / 30

local function describe(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) == "table" then
		return "a table"
	end
	return tostring(v)
end

local function vec3ok(v: any): boolean
	return type(v) == "table" and M.finite(v[1]) and M.finite(v[2]) and M.finite(v[3])
end

--[[
	Checks a clip's shape. Every problem is one { path, expected, got }, worded for whoever
	wrote the clip; nothing here needs a rig.
]]
function Performance.validate(clip: any, base: string?): { ValidationError }
	local errs: { ValidationError } = {}
	local root = base or "clip"
	local function fail(path: string, expected: string, got: any)
		table.insert(errs, { path = path, expected = expected, got = describe(got) })
	end
	if type(clip) ~= "table" then
		fail(root, "a clip table", clip)
		return errs
	end
	if clip.length ~= nil and (not M.finite(clip.length) or clip.length <= 0) then
		fail(root .. ".length", "a positive number of seconds", clip.length)
	end
	if clip.rate ~= nil and (not M.finite(clip.rate) or clip.rate < 10 or clip.rate > 240) then
		fail(root .. ".rate", "samples per second between 10 and 240", clip.rate)
	end
	local function checkKey(path: string, k: any)
		if type(k) ~= "table" then
			fail(path, "a key table", k)
			return
		end
		if not M.finite(k.t) or k.t < 0 then
			fail(path .. ".t", "a time of 0 or more seconds", k.t)
		end
		for _, field in { "rot", "pos", "reach", "pole", "look" } do
			if k[field] ~= nil and not vec3ok(k[field]) then
				fail(path .. "." .. field, "{ x, y, z } with three finite numbers", k[field])
			end
		end
		if k.ease ~= nil and not Ease.known(k.ease) then
			fail(path .. ".ease", "one of " .. table.concat(Ease.names, ", "), k.ease)
		end
	end
	if clip.keys ~= nil then
		if type(clip.keys) ~= "table" then
			fail(root .. ".keys", "a list of { t =, pose = { part = {...} } }", clip.keys)
		else
			local last = -math.huge
			for i, key in clip.keys do
				local path = string.format("%s.keys[%d]", root, i)
				if type(key) ~= "table" then
					fail(path, "a key table", key)
					continue
				end
				if not M.finite(key.t) or key.t < 0 then
					fail(path .. ".t", "a time of 0 or more seconds", key.t)
				elseif key.t < last then
					fail(path .. ".t", "times in increasing order", key.t)
				else
					last = key.t
				end
				if key.ease ~= nil and not Ease.known(key.ease) then
					fail(path .. ".ease", "one of " .. table.concat(Ease.names, ", "), key.ease)
				end
				if type(key.pose) ~= "table" then
					fail(path .. ".pose", "a table of part = { rot/pos/reach/look }", key.pose)
				else
					for part, spec in key.pose do
						if type(part) ~= "string" then
							fail(path .. ".pose", "part names as strings", part)
						else
							local k = if type(spec) == "table" then table.clone(spec) else spec
							if type(k) == "table" then
								k.t = key.t
							end
							checkKey(path .. ".pose." .. part, k)
						end
					end
				end
			end
		end
	end
	if clip.tracks ~= nil then
		if type(clip.tracks) ~= "table" then
			fail(root .. ".tracks", "a table of part = { keys }", clip.tracks)
		else
			for part, list in clip.tracks do
				local path = root .. ".tracks." .. tostring(part)
				if type(list) ~= "table" then
					fail(path, "a list of keys", list)
				else
					local last = -math.huge
					for i, k in list do
						checkKey(path .. "[" .. i .. "]", k)
						if type(k) == "table" and M.finite(k.t) then
							if k.t < last then
								fail(path .. "[" .. i .. "].t", "times in increasing order", k.t)
							end
							last = k.t
						end
					end
				end
			end
		end
	end
	if clip.keys == nil and clip.tracks == nil then
		fail(root, "keys or tracks", "neither")
	end
	if clip.markers ~= nil then
		if type(clip.markers) ~= "table" then
			fail(root .. ".markers", "a list of { t =, name = }", clip.markers)
		else
			for i, mk in clip.markers do
				if type(mk) ~= "table" or not M.finite(mk.t) or type(mk.name) ~= "string" then
					fail(string.format("%s.markers[%d]", root, i), "{ t = seconds, name = string }", mk)
				end
			end
		end
	end
	if clip.springs ~= nil then
		if type(clip.springs) ~= "table" then
			fail(root .. ".springs", "a list of { part =, at =, impulse = {x,y,z} }", clip.springs)
		else
			for i, sp in clip.springs do
				local path = string.format("%s.springs[%d]", root, i)
				if type(sp) ~= "table" or type(sp.part) ~= "string" or not M.finite(sp.at) or not vec3ok(sp.impulse) then
					fail(path, "{ part = string, at = seconds, impulse = { x, y, z } degrees per second }", sp)
				end
			end
		end
	end
	if clip.units ~= nil and clip.units ~= "rig" and clip.units ~= "studs" then
		fail(root .. ".units", '"rig" or "studs"', clip.units)
	end
	return errs
end

-- Channels ------------------------------------------------------------------------------------------

type Curve = {
	times: { number },
	-- per component, per key
	values: { { number } },
	tangents: { { number } },
	eases: { string? },
	dims: number,
}

local function buildCurve(times: { number }, values: { { number } }, eases: { string? }, loop: boolean): Curve
	local dims = #values
	local tangents: { { number } } = {}
	for d = 1, dims do
		tangents[d] = Ease.tangents(times, values[d], loop)
	end
	return { times = times, values = values, tangents = tangents, eases = eases, dims = dims }
end

-- Evaluates a curve at t into `out` (dims numbers).
local function evalCurve(c: Curve, t: number, out: { number })
	local times = c.times
	local n = #times
	if n == 0 then
		for d = 1, c.dims do
			out[d] = 0
		end
		return
	end
	if t <= times[1] or n == 1 then
		for d = 1, c.dims do
			out[d] = c.values[d][1]
		end
		return
	end
	if t >= times[n] then
		for d = 1, c.dims do
			out[d] = c.values[d][n]
		end
		return
	end
	local i = 1
	while i < n - 1 and t >= times[i + 1] do
		i += 1
	end
	local t0, t1 = times[i], times[i + 1]
	local ease = c.eases[i + 1]
	local u = (t - t0) / math.max(t1 - t0, 1e-9)
	if ease and ease ~= "natural" and ease ~= "smooth" then
		local e = Ease.apply(ease, u)
		for d = 1, c.dims do
			local a, b = c.values[d][i], c.values[d][i + 1]
			out[d] = a + (b - a) * e
		end
		return
	end
	-- a segment that starts and ends at rest (zero tangents both ends) takes the natural ease;
	-- one that flows through a key keeps the spline's continuous speed
	local rest = true
	for d = 1, c.dims do
		if math.abs(c.tangents[d][i]) > 1e-9 or math.abs(c.tangents[d][i + 1]) > 1e-9 then
			rest = false
			break
		end
	end
	if rest then
		local e = Ease.apply(if ease == "smooth" then "inOut" else "natural", u)
		for d = 1, c.dims do
			local a, b = c.values[d][i], c.values[d][i + 1]
			out[d] = a + (b - a) * e
		end
		return
	end
	for d = 1, c.dims do
		out[d] = Ease.hermite(t0, c.values[d][i], c.tangents[d][i], t1, c.values[d][i + 1], c.tangents[d][i + 1], t)
	end
end

type Channel = {
	part: string,
	kind: string, -- "fk" | "reach" | "look" | "root"
	joints: { number },
	chain: Anatomy.Chain?,
	rot: Curve?,
	pos: Curve?,
	target: Curve?,
	pole: V3?,
	delay: { [number]: number },
	arc: boolean,
}

-- Euler degrees in the character's frame -> rotation vector (for splining).
local function rotVector(r: { number }): { number }
	local q = M.qeuler(r[1] * DEG, r[2] * DEG, r[3] * DEG)
	local v = M.qlog(q)
	return { v.x, v.y, v.z }
end

-- Collect keys per part from both `keys` (poses at times) and `tracks` (keys per part).
local function collect(clip: Clip): ({ [string]: { Key } }, { number }, number)
	local byPart: { [string]: { Key } } = {}
	local keyTimes: { number } = {}
	local linear = 0
	local function push(part: string, k: Key)
		local list = byPart[part]
		if not list then
			list = {}
			byPart[part] = list
		end
		table.insert(list, k)
	end
	if type(clip.keys) == "table" then
		for _, key in clip.keys :: { any } do
			if type(key) == "table" and M.finite(key.t) and type(key.pose) == "table" then
				table.insert(keyTimes, key.t)
				for part, spec in key.pose do
					if type(part) == "string" and type(spec) == "table" then
						local k: Key = {
							t = key.t,
							rot = spec.rot,
							pos = spec.pos,
							reach = spec.reach,
							pole = spec.pole,
							look = spec.look,
							ease = spec.ease or key.ease,
						}
						if k.ease == "linear" then
							linear += 1
						end
						push(part, k)
					end
				end
			end
		end
	end
	if type(clip.tracks) == "table" then
		for part, list in clip.tracks :: { [string]: any } do
			if type(part) == "string" and type(list) == "table" then
				for _, k in list do
					if type(k) == "table" and M.finite(k.t) then
						table.insert(keyTimes, k.t)
						if k.ease == "linear" then
							linear += 1
						end
						push(part, {
							t = k.t,
							rot = k.rot,
							pos = k.pos,
							reach = k.reach,
							pole = k.pole,
							look = k.look,
							ease = k.ease,
						})
					end
				end
			end
		end
	end
	for _, list in byPart do
		table.sort(list, function(a, b)
			return a.t < b.t
		end)
	end
	table.sort(keyTimes)
	-- distinct times only
	local distinct: { number } = {}
	for _, tt in keyTimes do
		if #distinct == 0 or math.abs(tt - distinct[#distinct]) > 1e-6 then
			table.insert(distinct, tt)
		end
	end
	return byPart, distinct, linear
end

-- How many 30 fps frames a joint trails the one it hangs from, by what it is.
local function overlapFrames(a: Anatomy.Anatomy, part: Anatomy.Part, k: number): number
	local c = part.chain
	if c then
		local idx = table.find(c.movable, k) or 1
		if c.kind == "arm" or c.kind == "wing" then
			return math.min(idx - 1, 2)
		elseif c.kind == "tail" then
			return math.min(idx, 6)
		elseif c.kind == "head" then
			return math.min(idx, 2)
		elseif c.kind == "other" then
			return 2
		end
		return 0
	end
	if k == a.head then
		return 1
	end
	if k == a.chest and a.chest ~= a.body then
		return 1
	end
	return 0
end

local function vecOf(v: any, scale: number): { number }
	return { v[1] * scale, v[2] * scale, v[3] * scale }
end

-- Mirror check: two keys on a left/right pair that are mirror images (x kept, y and z negated).
-- (keys at rest on both sides count as mirrored: they do not break the symmetry)
local function mirrored(a: Key, b: Key): boolean
	if not a.rot or not b.rot or math.abs(a.t - b.t) > 1e-6 then
		return false
	end
	local ra, rb = a.rot :: { number }, b.rot :: { number }
	return math.abs(ra[1] - rb[1]) < 3 and math.abs(ra[2] + rb[2]) < 3 and math.abs(ra[3] + rb[3]) < 3
end

local function moving(k: Key): boolean
	local r = k.rot
	return r ~= nil and math.abs(r[1]) + math.abs(r[2]) + math.abs(r[3]) >= 5
end

--[[
	Bakes a clip on an anatomy. `opts.start` (optional) places the character for reach and plant
	targets; a clip bakes relative to wherever it starts, so it is only needed for previews.
]]
function Performance.bake(anatomy: Anatomy.Anatomy, clip: Clip, opts: any?): Baked.Baked
	local o = if type(opts) == "table" then opts else {}
	local rig = anatomy.rig
	local warnings: { string } = {}
	local polish: { [string]: any } = if type(clip.polish) == "table" then clip.polish else {}
	local function on(name: string, default: boolean): boolean
		local v = polish[name]
		if v == nil then
			return default
		end
		return v ~= false and v ~= 0
	end
	local loop = clip.loop == true
	local rate = if M.finite(clip.rate) then M.clamp(clip.rate :: number, 10, 240) else Baked.RATE
	local units = if clip.units == "studs" then 1 else math.max(anatomy.hipHeight, 1e-3) / 2
	local seed = if clip.seed ~= nil then clip.seed else (clip.name or "clip")
	local rng = Rng.new(seed)
	local byPart, keyTimes, linearKeys = collect(clip)

	-- the clip's length: given, else the last key
	local lastKey = 0
	for _, list in byPart do
		for _, k in list do
			lastKey = math.max(lastKey, k.t)
		end
	end
	local length = if M.finite(clip.length) and (clip.length :: number) > 0 then clip.length :: number else math.max(lastKey, 1 / rate)

	-- Mirror break: one side of an exactly mirrored pair comes in a little later and smaller.
	local mirrorDelay: { [string]: number } = {}
	local mirrorScale: { [string]: number } = {}
	if on("mirror", true) and clip.symmetric ~= true then
		for part, list in byPart do
			local lower = string.lower(part)
			if string.sub(lower, 1, 4) == "left" then
				local other = "right" .. string.sub(part, 5)
				local olist = byPart[other]
				if olist and #olist == #list and #list > 0 then
					local all, any = true, false
					for i = 1, #list do
						if not mirrored(list[i], olist[i]) then
							all = false
							break
						end
						any = any or moving(list[i])
					end
					if all and any then
						local late = if Rng.chance(rng, 0.5) then part else other
						mirrorDelay[late] = (2 + Rng.int(rng, 0, 2)) * FRAME30
						mirrorScale[late] = 0.88
					end
				end
			end
		end
	end

	-- Channels.
	local channels: { Channel } = {}
	local rootChannels: { Channel } = {}
	local keyedLegs: { [Anatomy.Chain]: boolean } = {}
	local spline = on("spline", true)
	local partNames: { string } = {}
	for part in byPart do
		table.insert(partNames, part)
	end
	table.sort(partNames)
	for _, part in partNames do
		local list = byPart[part]
		local resolved: Anatomy.Part? = if part == "root" then nil else Anatomy.part(anatomy, part)
		local isRoot = part == "root" or (resolved ~= nil and (resolved :: Anatomy.Part).kind == "root")
		if not isRoot and not resolved then
			table.insert(warnings, string.format("the rig has no %q; its keys were skipped", part))
			continue
		end
		-- rest key at 0 when the part's first key comes later
		local keys = table.clone(list)
		if keys[1].t > 1e-6 then
			table.insert(keys, 1, { t = 0, rot = if keys[1].rot then { 0, 0, 0 } else nil, pos = if keys[1].pos then { 0, 0, 0 } else nil })
		end
		local delayExtra = mirrorDelay[part] or 0
		local scaleRot = mirrorScale[part] or 1
		local times: { number } = {}
		local eases: { string? } = {}
		local rv: { { number } } = { {}, {}, {} }
		local pv: { { number } } = { {}, {}, {} }
		local tv: { { number } } = { {}, {}, {} }
		local lv: { { number } } = { {}, {}, {} }
		local hasRot, hasPos, hasReach, hasLook = false, false, false, false
		local pole: V3? = nil
		local lastRot = { 0, 0, 0 }
		local lastPos = { 0, 0, 0 }
		local lastReach: { number }? = nil
		local lastLook: { number }? = nil
		for ki, k in keys do
			table.insert(times, k.t + delayExtra)
			-- by index: an ease may be nil, and table.insert of nil would shift the rest
			eases[ki] = if spline then k.ease else (k.ease or "linear")
			if k.rot then
				hasRot = true
				local r = k.rot :: { number }
				lastRot = rotVector({ r[1] * scaleRot, r[2] * scaleRot, r[3] * scaleRot })
			end
			if k.pos then
				hasPos = true
				lastPos = vecOf(k.pos, units)
			end
			if k.reach then
				hasReach = true
				lastReach = vecOf(k.reach, units)
			end
			if k.look then
				hasLook = true
				lastLook = vecOf(k.look, units)
			end
			if k.pole then
				local p = k.pole :: { number }
				pole = { x = p[1], y = p[2], z = p[3] }
			end
			for d = 1, 3 do
				table.insert(rv[d], lastRot[d])
				table.insert(pv[d], lastPos[d])
			end
		end
		-- reach and look: hold their first value before it (the first key's time)
		if hasReach or hasLook then
			local firstR, firstL = nil, nil
			for _, k in keys do
				if k.reach and not firstR then
					firstR = vecOf(k.reach, units)
				end
				if k.look and not firstL then
					firstL = vecOf(k.look, units)
				end
			end
			local curR, curL = firstR, firstL
			for _, k in keys do
				if k.reach then
					curR = vecOf(k.reach, units)
				end
				if k.look then
					curL = vecOf(k.look, units)
				end
				for d = 1, 3 do
					if curR then
						table.insert(tv[d], (curR :: { number })[d])
					end
					if curL then
						table.insert(lv[d], (curL :: { number })[d])
					end
				end
			end
		end
		local _ = lastReach
		local _l = lastLook
		local ch: Channel = {
			part = part,
			kind = if isRoot then "root" elseif hasReach then "reach" elseif hasLook then "look" else "fk",
			joints = if resolved then resolved.joints else {},
			chain = if resolved then resolved.chain else nil,
			rot = if hasRot or isRoot then buildCurve(times, rv, eases, loop) else nil,
			pos = if hasPos then buildCurve(times, pv, eases, loop) else nil,
			target = if hasReach then buildCurve(times, tv, eases, loop) elseif hasLook then buildCurve(times, lv, eases, loop) else nil,
			pole = pole,
			delay = {},
			arc = hasReach and on("arcs", true),
		}
		if isRoot then
			table.insert(rootChannels, ch)
			continue
		end
		-- a whole chain keyed by rot turns at its first joint; segments name their own joint
		if on("overlap", true) and resolved then
			for _, k in ch.joints do
				ch.delay[k] = overlapFrames(anatomy, resolved :: Anatomy.Part, k) * FRAME30
			end
		end
		if ch.chain and (ch.chain :: Anatomy.Chain).kind == "leg" then
			keyedLegs[ch.chain :: Anatomy.Chain] = true
		end
		table.insert(channels, ch)
	end

	-- Planted legs: unless the clip keys them or says otherwise, legs that stand on the ground
	-- keep their feet where they are while the body moves.
	local planted: { Anatomy.Chain } = {}
	local plantSpec = clip.plant
	for _, leg in anatomy.legs do
		local want = false
		if plantSpec == nil or plantSpec == true then
			want = not keyedLegs[leg] and leg.gap <= 0.05 * anatomy.hipHeight
		elseif type(plantSpec) == "table" then
			for _, nm in plantSpec :: { any } do
				local p = if type(nm) == "string" then Anatomy.part(anatomy, nm) else nil
				if p and p.chain == leg then
					want = true
				end
			end
		end
		if want then
			table.insert(planted, leg)
		end
	end

	-- Children inherit the overlap of the chain they sit in: an elbow keyed through "rightArm.2"
	-- trails the shoulder keyed through "rightArm".
	local maxDelay = 0
	for _, ch in channels do
		for _, d in ch.delay do
			maxDelay = math.max(maxDelay, d)
		end
	end
	for _, d in mirrorDelay do
		maxDelay = math.max(maxDelay, d)
	end
	local total = if loop then length else length + maxDelay
	local count = math.max(2, math.floor(total * rate + 0.5) + 1)
	local exactRate = if loop then (count - 1) / length else rate

	local animated: { number } = {}
	local channelOf: { [number]: number } = {}
	for k, j in rig.joints do
		if j.animated then
			table.insert(animated, k)
			channelOf[k] = #animated
		end
	end
	local baked = Baked.new(clip.name or "clip", "clip", exactRate, count, loop, animated, "offset")
	baked.keyTimes = keyTimes
	baked.linearKeys = linearKeys
	baked.spline = spline
	baked.travel = clip.travel == true
	if type(clip.waive) == "table" then
		for _, w in clip.waive :: { any } do
			if type(w) == "string" then
				baked.waive[w] = true
			end
		end
	end
	if type(clip.markers) == "table" then
		for _, mk in clip.markers :: { any } do
			if type(mk) == "table" and M.finite(mk.t) and type(mk.name) == "string" then
				table.insert(baked.markers, { name = mk.name, time = mk.t, value = if mk.value ~= nil then tostring(mk.value) else nil })
			end
		end
	end

	local start = M.xid()
	if o.start ~= nil then
		start = (M.readX(o.start))
	end
	local restFrames = Rig.fk(rig, {}, start)
	-- planted feet stay where they stood at the start
	local plantAt: { [Anatomy.Chain]: V3 } = {}
	for _, leg in planted do
		plantAt[leg] = M.xpoint(restFrames[leg.joints[#leg.joints]], leg.foot)
	end
	local bodyJ = anatomy.body
	local buf = { 0, 0, 0 }
	local tmp = { 0, 0, 0 }
	local function curveVec(c: Curve, t: number): V3
		local tt = t
		if loop and length > 0 then
			tt = t - length * math.floor(t / length)
		end
		evalCurve(c, tt, buf)
		return { x = buf[1], y = buf[2], z = buf[3] }
	end
	local _ = tmp
	-- character-frame rotation (as a rotation vector) to joint k's local rotation
	local function toLocal(k: number, rvec: V3): Q
		local w = rig.joints[k].world.q
		local qc = M.qexp(rvec)
		return M.qnorm(M.qmul(M.qmul(M.qconj(w), qc), w))
	end
	local function posLocal(k: number, p: V3): V3
		return M.qinvrot(rig.joints[k].world.q, p)
	end
	local unreached = 0
	for s = 0, count - 1 do
		local t = s / exactRate
		local locals: { [number]: X } = {}
		local root = M.xid()
		for _, rc in rootChannels do
			local rq = if rc.rot then M.qexp(curveVec(rc.rot :: Curve, t)) else M.qid()
			local rp = if rc.pos then curveVec(rc.pos :: Curve, t) else M.ZERO
			root = M.xmul(root, { p = { x = rp.x, y = rp.y, z = rp.z }, q = rq })
		end
		-- FK channels
		for _, ch in channels do
			if ch.kind ~= "fk" and ch.kind ~= "look" then
				continue
			end
			local js = ch.joints
			for _, k in js do
				local d = ch.delay[k] or 0
				local tt = t - d
				local q = if ch.rot then toLocal(k, curveVec(ch.rot :: Curve, tt)) else M.qid()
				local p = if ch.pos then posLocal(k, curveVec(ch.pos :: Curve, tt)) else M.ZERO
				local cur = locals[k]
				if cur then
					locals[k] = { p = M.vadd(cur.p, p), q = M.qmul(cur.q, q) }
				else
					locals[k] = { p = { x = p.x, y = p.y, z = p.z }, q = q }
				end
			end
		end
		-- "hips"/"body" on a rig with no body joint moves the whole model
		local frames = Rig.fk(rig, locals, M.xmul(start, root))
		local rootW = M.xmul(start, root)
		-- reach channels: IK to the target (character frame at the start), bowed into an arc
		for _, ch in channels do
			if ch.kind ~= "reach" or not ch.chain or not ch.target then
				continue
			end
			local chain = ch.chain :: Anatomy.Chain
			local target = curveVec(ch.target :: Curve, t)
			if ch.arc then
				-- bow the path between keys away from the chain's base, by 12% of the chord
				local c = ch.target :: Curve
				local times = c.times
				local nT = #times
				if nT >= 2 and t > times[1] and t < times[nT] then
					local i = 1
					while i < nT - 1 and t >= times[i + 1] do
						i += 1
					end
					local a = { x = c.values[1][i], y = c.values[2][i], z = c.values[3][i] }
					local b = { x = c.values[1][i + 1], y = c.values[2][i + 1], z = c.values[3][i + 1] }
					local chord = M.vdist(a, b)
					if chord > 0.3 * chain.length then
						local u = (t - times[i]) / math.max(times[i + 1] - times[i], 1e-9)
						local base = rig.joints[chain.joints[1]].world.p
						local mid = M.vlerp(a, b, 0.5)
						local out = M.vreject(M.vsub(mid, base), M.vnorm(M.vsub(b, a)))
						if M.vlen(out) < 1e-6 then
							out = M.UP
						end
						local bow = 4 * 0.12 * chord * u * (1 - u)
						target = M.vmad(target, M.vnorm(out), bow)
					end
				end
			end
			local world = M.xpoint(start, target)
			local base = Rig.parentFrame(rig, frames, rootW, chain.joints[1])
			local r = IK.solve(rig, chain, base, world, {
				pole = if ch.pole then M.xdir(start, ch.pole :: V3) else nil,
				arm = chain.kind ~= "leg",
				side = chain.side,
				freeEnd = true,
				body = rootW,
			}, locals, frames)
			if not r.reachable then
				unreached += 1
			end
		end
		-- planted legs
		for _, leg in planted do
			local base = Rig.parentFrame(rig, frames, rootW, leg.joints[1])
			local footRot: Q? = nil
			if leg.ik == "twoFoot" or leg.ik == "chainFoot" or leg.ik == "aimFoot" then
				footRot = restFrames[leg.movable[#leg.movable]].q
			end
			IK.solve(rig, leg, base, plantAt[leg], { footRot = footRot, body = rootW }, locals, frames)
		end
		-- look channels: the head (and neck) turn towards a point
		for _, ch in channels do
			if ch.kind ~= "look" or not ch.target then
				continue
			end
			local target = M.xpoint(start, curveVec(ch.target :: Curve, t))
			local hk = ch.joints[1]
			local js: { number } = {}
			for _, nk in anatomy.neck do
				table.insert(js, nk)
			end
			table.insert(js, hk)
			local share = 1 / #js
			local carried: { [number]: X } = {}
			for _, k in js do
				local j = rig.joints[k]
				local parent = if j.parent > 0 then (carried[j.parent] or frames[j.parent]) else rootW
				-- the head's forward at rest is the character's forward
				local fwdLocal = M.qinvrot(j.world.q, M.FORWARD)
				local cur = locals[k] or M.xid()
				local f0 = M.xmul(M.xmul(parent, j.rest), cur)
				local from = M.qrot(f0.q, fwdLocal)
				local to = M.vsub(target, f0.p)
				local r = M.qslerp(M.qid(), M.qbetween(from, to), share)
				local newQ = M.qnorm(M.qmul(M.qmul(M.qconj(f0.q), r), f0.q))
				locals[k] = { p = cur.p, q = M.qmul(cur.q, newQ) }
				carried[k] = M.xmul(M.xmul(parent, j.rest), locals[k])
			end
		end
		Baked.set(baked, s, 0, root)
		for k, l in locals do
			local c = channelOf[k]
			if c then
				Baked.set(baked, s, c, l)
			end
		end
	end
	if unreached > 0 then
		table.insert(warnings, string.format("%d frame(s) where a reach target was out of the chain's range", unreached))
	end
	Baked.finish(baked)

	-- Polish passes on the baked result.
	local Polish = require("./Polish")
	local drift = polish.drift
	local driftAmount = if drift == nil then 1 elseif drift == false then 0 elseif M.finite(drift) then math.max(0, drift :: number) else 1
	if driftAmount > 0 then
		Polish.drift(baked, anatomy, driftAmount, Rng.fork(rng, "drift"))
	end
	local breathe = polish.breathing
	local name = string.lower(clip.name or "")
	if breathe == true or (breathe == nil and loop and string.find(name, "idle", 1, true) ~= nil) then
		Polish.breathe(baked, anatomy, if M.finite(polish.breathPeriod) then polish.breathPeriod else 4)
	end
	if type(clip.springs) == "table" then
		Polish.impulses(baked, anatomy, clip.springs :: { any }, warnings)
	end
	if clip.secondary ~= nil and clip.secondary ~= false then
		Polish.secondary(baked, anatomy, if type(clip.secondary) == "table" then clip.secondary else {})
	end
	if M.finite(polish.settle) and (polish.settle :: number) > 0 then
		Polish.settle(baked, anatomy, polish.settle :: number)
	end
	local plantedLegs: { [string]: boolean } = {}
	for _, leg in planted do
		plantedLegs[leg.name] = true
	end
	-- chains a reach drives are solved whole each frame (no overlap to measure inside them)
	local reached: { [string]: boolean } = {}
	for _, ch in channels do
		if ch.kind == "reach" and ch.chain then
			reached[(ch.chain :: Anatomy.Chain).name] = true
		end
	end
	-- (merged: the polish passes have already written what they did)
	local info = baked.info
	info.clip = clip.name
	info.planted = #planted
	info.plantedLegs = plantedLegs
	info.reachChains = reached
	info.keyedParts = #channels
	info.mirrorBroken = next(mirrorDelay) ~= nil
	info.hipHeight = anatomy.hipHeight
	info.start = start
	info.reasons = info.reasons or {}
	for _, w in warnings do
		table.insert(baked.warnings, w)
	end
	local _b = bodyJ
	local _s = Spring
	return baked
end

return Performance
