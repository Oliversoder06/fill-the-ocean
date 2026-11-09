--!strict
--[[
	Moves: helpers that write clip data (Performance format) for any rig.

	Key editing:
	- toTracks(clip)          the same clip with every key moved into per-part tracks
	- anticipate(clip, opts)  a wind-up before a move: the part draws back against the move,
	                          the hips dip, then the move leaves from there faster
	- followThrough(clip, opts)  the part carries on past its target a little and settles back

	Whole clips:
	- strike(anatomy, opts)   a strike with any limb (an arm, a leg, the head for a creature with
	                          neither), timed by class from fighting-game frame data: light,
	                          medium, heavy, or npc (telegraphed so a player can answer)
	- idle(anatomy, opts)     a long idle loop: breathing, one weight shift, one glance away

	They produce data, so the result can be read, linted, edited and saved like a hand-written
	clip.
]]

local Anatomy = require("./Anatomy")

local Moves = {}

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

-- Every key, from `keys` (poses at times) and `tracks`, as per-part tracks sorted by time.
function Moves.toTracks(clip: any): any
	local out = copy(clip)
	local tracks: { [string]: { any } } = {}
	if type(clip.tracks) == "table" then
		for part, list in clip.tracks do
			tracks[part] = copy(list)
		end
	end
	if type(clip.keys) == "table" then
		for _, key in clip.keys do
			if type(key) == "table" and type(key.pose) == "table" then
				for part, spec in key.pose do
					local k = copy(spec)
					k.t = key.t
					k.ease = k.ease or key.ease
					local list = tracks[part]
					if not list then
						list = {}
						tracks[part] = list
					end
					table.insert(list, k)
				end
			end
		end
	end
	for _, list in tracks do
		table.sort(list, function(a, b)
			return a.t < b.t
		end)
	end
	out.keys = nil
	out.tracks = tracks
	return out
end

local function field(k: any): string?
	if k.reach then
		return "reach"
	elseif k.rot then
		return "rot"
	elseif k.pos then
		return "pos"
	elseif k.look then
		return "look"
	end
	return nil
end

local function lerp3(a: { number }, b: { number }, t: number): { number }
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- The key of `part` at time `at` and the key before it.
local function around(list: { any }, at: number): (number?, number?)
	local bi: number? = nil
	for i, k in list do
		if math.abs(k.t - at) < 1e-6 then
			bi = i
		end
	end
	if not bi or (bi :: number) < 2 then
		return nil, bi
	end
	return (bi :: number) - 1, bi
end

--[[
	opts: part, at (the time the move arrives), amount (share of the move to draw back,
	default 0.15), when (how far into the move's time the wind-up peaks, default 0.4), hips (a dip
	in rig units, default 0.04; 0 for none).
]]
function Moves.anticipate(clip: any, opts: { [string]: any }): any
	local c = Moves.toTracks(clip)
	local list = c.tracks[opts.part]
	if not list then
		return c
	end
	local ai, bi = around(list, opts.at)
	if not ai or not bi then
		return c
	end
	local A, B = list[ai :: number], list[bi :: number]
	local f = field(B)
	if not f or not A[f] then
		return c
	end
	local amount = opts.amount or 0.15
	local when = opts.when or 0.4
	local t = A.t + (B.t - A.t) * when
	local back = lerp3(A[f], B[f], -amount)
	local key = { t = t }
	key[f] = back
	table.insert(list, bi :: number, key)
	-- leave the wind-up fast
	B.ease = B.ease or "snap"
	local dip = if opts.hips == nil then 0.04 else opts.hips
	if dip ~= 0 then
		local hips = c.tracks.hips
		if not hips then
			hips = { { t = 0, pos = { 0, 0, 0 } } }
			c.tracks.hips = hips
		end
		table.insert(hips, { t = t, pos = { 0, -dip, 0.3 * dip } })
		table.sort(hips, function(x, y)
			return x.t < y.t
		end)
	end
	return c
end

--[[
	opts: part, at (the time the move arrives), overshoot (share of the move to carry past,
	default 0.08), settle (seconds to come back, default 0.25).
]]
function Moves.followThrough(clip: any, opts: { [string]: any }): any
	local c = Moves.toTracks(clip)
	local list = c.tracks[opts.part]
	if not list then
		return c
	end
	local ai, bi = around(list, opts.at)
	if not ai or not bi then
		return c
	end
	local A, B = list[ai :: number], list[bi :: number]
	local f = field(B)
	if not f or not A[f] then
		return c
	end
	local over = opts.overshoot or 0.08
	local settle = opts.settle or 0.25
	local nextKey = list[(bi :: number) + 1]
	local t1 = B.t + 2 / 30
	local t2 = B.t + settle
	if nextKey and nextKey.t <= t2 then
		t2 = math.max(t1 + 1 / 30, nextKey.t - 1 / 30)
	end
	local past = { t = t1 }
	past[f] = lerp3(A[f], B[f], 1 + over)
	local back = { t = t2, ease = "settle" }
	back[f] = copy(B[f])
	table.insert(list, (bi :: number) + 1, past)
	if not nextKey or nextKey.t > t2 + 1e-6 then
		table.insert(list, (bi :: number) + 2, back)
	end
	return c
end

local CLASSES = {
	-- startup to contact, active hold, recovery (seconds); wind-up share of the startup
	light = { startup = 0.09, active = 0.06, recovery = 0.18 },
	medium = { startup = 0.13, active = 0.08, recovery = 0.26 },
	heavy = { startup = 0.19, active = 0.08, recovery = 0.34 },
	npc = { startup = 0.36, active = 0.1, recovery = 0.45 },
}

--[[
	A strike for any rig. opts: limb (a part name; default the last arm, else a front leg, else
	the head), class ("light" | "medium" | "heavy" | "npc"), target ({ x, y, z } in rig units in the
	character's frame; default straight ahead at the limb's height and reach), ready (false when
	the character already holds a guard; otherwise the clip raises into one first), name.
	Returns the clip and its contact time.
]]
function Moves.strike(anatomy: Anatomy.Anatomy, opts: { [string]: any }?): (any, number)
	local o: { [string]: any } = opts or {}
	local cls = CLASSES[o.class or "medium"] or CLASSES.medium
	local limb: string? = o.limb
	local chain: Anatomy.Chain? = nil
	if limb then
		local p = Anatomy.part(anatomy, limb)
		chain = if p then p.chain else nil
	end
	if not chain then
		local pick = anatomy.arms[#anatomy.arms] or anatomy.legs[1] or anatomy.heads[1]
		if pick then
			chain = pick
			limb = pick.aliases[1] or pick.name
		end
	end
	local unit = math.max(anatomy.hipHeight, 1e-3) / 2
	-- strikes leave from a guard: unless told the character is already in one (ready = false),
	-- the clip first raises the limb into it over 0.35 s
	local raise = if o.ready == false then 0 else 0.35
	local t0 = raise + 0.12
	local contact = t0 + cls.startup + (if o.class == "npc" then 0.2 else 0)
	local hold = contact + cls.active
	local back = hold + math.max(cls.recovery, 1.5 * (contact - t0))
	local keys: { [string]: { any } } = {}
	if chain then
		local c = chain :: Anatomy.Chain
		local base = c.base
		local reach = math.max(c.length, 1e-3)
		local side = if c.side ~= 0 then c.side else 1
		local rest = { c.tipPos.x / unit, c.tipPos.y / unit, c.tipPos.z / unit }
		-- the guard: the end of the limb in front of its base, about half extended
		local guard = { (base.x - side * 0.15 * reach) / unit, (base.y - 0.2 * reach) / unit, (base.z - 0.4 * reach) / unit }
		local tgt = o.target or { base.x / unit - side * 0.15 * reach / unit, base.y / unit, (base.z - 0.92 * reach) / unit }
		-- drawn back a little and in, before the strike
		local load = { guard[1] + 0.05 * side * reach / unit, guard[2] - 0.05 * reach / unit, guard[3] + 0.15 * reach / unit }
		local list = {}
		if raise > 0 then
			table.insert(list, { t = 0, reach = rest })
		end
		table.insert(list, { t = raise, reach = guard })
		table.insert(list, { t = t0 + 0.3 * (contact - t0), reach = load })
		table.insert(list, { t = contact, reach = tgt, ease = "snap" })
		table.insert(list, { t = hold, reach = lerp3(guard, tgt, 1.04) })
		table.insert(list, { t = back, reach = guard, ease = "settle" })
		keys[limb :: string] = list
	end
	-- force from the ground: hips first, then the chest, the limb last
	local side = if chain and (chain :: Anatomy.Chain).side ~= 0 then (chain :: Anatomy.Chain).side else 1
	keys.hips = {
		{ t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
		{ t = math.max(raise, 0.05), pos = { 0, -0.02, 0 }, rot = { 0, 0, 0 } },
		{ t = t0 + 0.35 * (contact - t0), pos = { 0, -0.06, 0.04 }, rot = { 0, -6 * side, 0 } },
		{ t = contact - 1 / 30, pos = { 0, -0.15, -0.28 }, rot = { 0, 20 * side, 0 } },
		{ t = hold, pos = { 0, -0.16, -0.31 }, rot = { 0, 22 * side, 0 } },
		{ t = back, pos = { 0, 0, 0 }, rot = { 0, 0, 0 }, ease = "settle" },
	}
	if anatomy.chest and anatomy.chest ~= anatomy.body then
		keys.chest = {
			{ t = 0, rot = { 0, 0, 0 } },
			{ t = math.max(raise, 0.05), rot = { 2, 0, 0 } },
			{ t = t0 + 0.3 * (contact - t0), rot = { 0, -5 * side, 0 } },
			{ t = contact, rot = { 4, 16 * side, 0 } },
			{ t = back, rot = { 0, 0, 0 }, ease = "settle" },
		}
	end
	if anatomy.head then
		-- eyes stay on the target while the body turns under them
		keys.head = {
			{ t = 0, rot = { 0, 0, 0 } },
			{ t = contact, rot = { -2, -16 * side, 0 } },
			{ t = back, rot = { 0, 0, 0 }, ease = "settle" },
		}
	end
	return {
		name = o.name or "Strike",
		length = back,
		tracks = keys,
		markers = { { t = contact, name = "Hit" } },
	}, contact
end

--[[
	A long idle loop (default 10 s): breathing, one slow weight shift, one glance away and back,
	keys deliberately uneven. opts: length, glance (degrees, default 18), name.
]]
function Moves.idle(anatomy: Anatomy.Anatomy, opts: { [string]: any }?): any
	local o: { [string]: any } = opts or {}
	local L = o.length or 10
	local glance = o.glance or 18
	local tracks: { [string]: { any } } = {
		hips = {
			{ t = 0, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
			{ t = 0.31 * L, pos = { 0.05, -0.02, 0 }, rot = { 0, 0, -1.4 } },
			{ t = 0.58 * L, pos = { 0.04, -0.015, 0 }, rot = { 0, 1, -1.1 } },
			{ t = 0.86 * L, pos = { -0.01, 0, 0 }, rot = { 0, 0, 0.3 } },
			{ t = L, pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
		},
	}
	if anatomy.head then
		tracks.head = {
			{ t = 0, rot = { 0, 0, 0 } },
			{ t = 0.42 * L, rot = { 0, 0, 0 } },
			{ t = 0.47 * L, rot = { -3, glance, 0 } },
			{ t = 0.63 * L, rot = { -2, glance * 0.9, 1 } },
			{ t = 0.69 * L, rot = { 0, 0, 0 } },
			{ t = L, rot = { 0, 0, 0 } },
		}
	end
	return {
		name = o.name or "Idle",
		length = L,
		loop = true,
		tracks = tracks,
		polish = { breathing = true },
	}
end

return Moves
