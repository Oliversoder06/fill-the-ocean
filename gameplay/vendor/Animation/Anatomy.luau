--!strict
--[[
	Anatomy: what a rig's chains are for. Legs (and how many), arms, spine, neck and head,
	tails, wings, and everything else (ears, antennae, hat brims).

	It reads geometry first and names second, because names lie in both directions: an imported
	pet's "Bone.012" says nothing, and R15's "LeftHip" is a leg joint while Mixamo's "Hips" is the
	pelvis. A chain that reaches the ground and runs downward is a leg whatever it is called; a
	name only breaks ties and raises confidence. Every chain carries a confidence (0-1) and the
	reason it was given its kind, so the agent can state what it found and the user can correct
	it with data (`overrides`) instead of code.

	How the tree is cut into chains: from the root, follow single-child links. A run that ends
	at a leaf is a limb candidate; a run that ends where the tree branches again is trunk
	(spine), and the branches are followed in turn. A limb whose end branches into short stubs
	(fingers, toes) keeps the stubs as "other" chains that ride along.

	Nothing here throws on a strange rig: zero joints is a valid anatomy (a single part: an egg),
	and every shape gets a sensible fallback with its reason.
]]

local M = require("./Math")
local Rig = require("./Rig")

type V3 = M.V3
type X = M.X

local Anatomy = {}

export type ChainKind = "leg" | "arm" | "spine" | "neck" | "head" | "tail" | "wing" | "other"
export type IkKind = "zero" | "aim" | "aimFoot" | "two" | "twoFoot" | "chain" | "chainFoot"

export type Chain = {
	kind: ChainKind,
	name: string,
	aliases: { string },
	index: number,
	joints: { number },
	movable: { number },
	side: number,
	confidence: number,
	reason: string,
	base: V3,
	tipPos: V3,
	length: number,
	pair: number?,
	-- legs (and anything planted): the contact point in the last joint's frame and at rest
	foot: V3,
	contact: V3,
	reach: number,
	ik: IkKind,
	-- the contact's height above the ground at rest (0 for a foot standing on it)
	gap: number,
	digit: boolean,
	-- reaches the ground at rest
	touches: boolean,
	-- the solved part of the leg: its reach, and (twoFoot) the contact's offset from the ankle
	-- pivot at rest in the root's frame, so planners can work on the ankle as IK does
	limbReach: number,
	footVec: V3,
	-- the closest the solved point can come to the hip (a leg cannot fold tighter than this)
	minReach: number,
	-- cannot bend between hip and foot (one joint, or one joint and a foot): it swings as a
	-- pendulum, and the body vaults over it
	rigid: boolean,
}

export type Part = {
	kind: string,
	joints: { number },
	chain: Chain?,
}

export type Anatomy = {
	rig: Rig.Rig,
	chains: { Chain },
	legs: { Chain },
	arms: { Chain },
	tails: { Chain },
	wings: { Chain },
	heads: { Chain },
	others: { Chain },
	spine: { number },
	body: number?,
	chest: number?,
	head: number?,
	neck: { number },
	hipHeight: number,
	ground: number,
	width: number,
	length: number,
	height: number,
	shape: string,
	flying: boolean,
	round: boolean,
	confidence: number,
	reasons: { string },
	warnings: { string },
	parts: { [string]: Part },
}

-- Names --------------------------------------------------------------------------------------------

-- Splits "LeftUpperLeg", "leg_L", "kneeF_L", "Bone.012", "tail01" into lower-case words.
function Anatomy.words(name: string): { string }
	local out: { string } = {}
	local s = string.gsub(name, "(%l)(%u)", "%1 %2")
	s = string.gsub(s, "(%u)(%u%l)", "%1 %2")
	s = string.gsub(s, "(%a)(%d)", "%1 %2")
	s = string.gsub(s, "(%d)(%a)", "%1 %2")
	for w in string.gmatch(string.lower(s), "%a+") do
		table.insert(out, w)
	end
	return out
end

local HINTS: { [string]: string } = {
	leg = "leg",
	legs = "leg",
	thigh = "leg",
	shin = "leg",
	calf = "leg",
	knee = "leg",
	ankle = "leg",
	foot = "leg",
	feet = "leg",
	toe = "leg",
	paw = "leg",
	hoof = "leg",
	hip = "leg",
	upleg = "leg",
	arm = "arm",
	arms = "arm",
	shoulder = "arm",
	elbow = "arm",
	forearm = "arm",
	wrist = "arm",
	hand = "arm",
	finger = "arm",
	fist = "arm",
	clavicle = "arm",
	head = "head",
	skull = "head",
	neck = "neck",
	tail = "tail",
	wing = "wing",
	wings = "wing",
	spine = "spine",
	chest = "spine",
	torso = "spine",
	waist = "spine",
	pelvis = "spine",
	hips = "spine",
	body = "spine",
	abdomen = "spine",
	belly = "spine",
	ear = "other",
	ears = "other",
	antenna = "other",
	horn = "other",
	jaw = "other",
	eye = "other",
	brim = "other",
	hat = "other",
	hair = "other",
	tongue = "other",
}

local function hintOf(rig: Rig.Rig, joints: { number }): (string?, number)
	-- Counts each hinted kind over the chain's joint and part names; the most named wins.
	local count: { [string]: number } = {}
	for _, k in joints do
		local j = rig.joints[k]
		local seen: { [string]: boolean } = {}
		for _, text in { j.name, j.part } do
			for _, w in Anatomy.words(text) do
				local h = HINTS[w]
				if h and not seen[h] then
					seen[h] = true
					count[h] = (count[h] or 0) + 1
				end
			end
		end
	end
	local best, bestN = nil, 0
	for _, kind in { "leg", "arm", "wing", "tail", "head", "neck", "spine", "other" } do
		local c = count[kind] or 0
		if c > bestN then
			best, bestN = kind, c
		end
	end
	return best, bestN
end

local function sideHint(rig: Rig.Rig, joints: { number }): number
	for _, k in joints do
		local j = rig.joints[k]
		for _, text in { j.name, j.part } do
			for _, w in Anatomy.words(text) do
				if w == "left" or w == "l" then
					return -1
				elseif w == "right" or w == "r" then
					return 1
				end
			end
		end
	end
	return 0
end

-- Geometry -----------------------------------------------------------------------------------------

local function chainPoints(rig: Rig.Rig, joints: { number }): ({ V3 }, V3)
	local pts: { V3 } = {}
	for _, k in joints do
		table.insert(pts, rig.joints[k].world.p)
	end
	local last = rig.joints[joints[#joints]]
	return pts, M.xpoint(last.world, last.tip)
end

local function pathLength(pts: { V3 }, tip: V3): number
	local l = 0
	for i = 2, #pts do
		l += M.vdist(pts[i - 1], pts[i])
	end
	l += M.vdist(pts[#pts], tip)
	return l
end

local function lowestOf(rig: Rig.Rig, joints: { number }, tip: V3): number
	local low = tip.y
	for _, k in joints do
		local j = rig.joints[k]
		if j.world.p.y < low then
			low = j.world.p.y
		end
		if j.boxMin and (j.boxMin :: V3).y < low then
			low = (j.boxMin :: V3).y
		end
	end
	return low
end

-- Contact point for a planted chain: the bottom of the last part's box when it has one,
-- else the end point, carried down to the ground when it stops just short of it (a skinned
-- leg whose last bone sits in the ankle while the mesh reaches the floor).
local function contactOf(rig: Rig.Rig, joints: { number }, tip: V3, length: number): (V3, number)
	local last = rig.joints[joints[#joints]]
	local c: V3
	if last.boxMin and last.boxMax then
		local lo, hi = last.boxMin :: V3, last.boxMax :: V3
		c = { x = (lo.x + hi.x) / 2, y = lo.y, z = (lo.z + hi.z) / 2 }
		if tip.y < c.y then
			c = tip
		end
	else
		c = { x = tip.x, y = tip.y, z = tip.z }
	end
	local gap = c.y - rig.ground
	if gap > 1e-6 and gap <= math.max(0.35 * length, 0.08 * rig.height) then
		c = { x = c.x, y = rig.ground, z = c.z }
	end
	return c, math.max(0, c.y - rig.ground)
end

-- Decomposition ------------------------------------------------------------------------------------

type Run = { joints: { number }, endsInBranch: boolean, fromRoot: boolean }

local function decompose(rig: Rig.Rig): { Run }
	local runs: { Run } = {}
	local rootKids: { number } = {}
	for k, j in rig.joints do
		if j.parent == 0 then
			table.insert(rootKids, k)
		end
	end
	local stack: { { number } } = { rootKids }
	local fromRootFlags: { boolean } = { true }
	while #stack > 0 do
		local starts = table.remove(stack) :: { number }
		local fromRoot = table.remove(fromRootFlags) :: boolean
		for _, s in starts do
			local run: { number } = { s }
			local cur = s
			while #rig.joints[cur].children == 1 do
				cur = rig.joints[cur].children[1]
				table.insert(run, cur)
			end
			local kids = rig.joints[cur].children
			local branch = #kids >= 2
			table.insert(runs, { joints = run, endsInBranch = branch, fromRoot = fromRoot })
			if branch then
				table.insert(stack, kids)
				table.insert(fromRootFlags, false)
			end
		end
	end
	-- Deterministic order: by first joint index.
	table.sort(runs, function(a, b)
		return a.joints[1] < b.joints[1]
	end)
	return runs
end

-- The longest single path under joint k (in joints), for digit detection.
local function subtreeSpan(rig: Rig.Rig, k: number): number
	local best = 0
	local stack = { { k, 0 } }
	local guard = 0
	while #stack > 0 and guard < 100000 do
		guard += 1
		local top = table.remove(stack) :: { number }
		local j = rig.joints[top[1]]
		local d = top[2] + j.length
		if d > best then
			best = d
		end
		for _, c in j.children do
			table.insert(stack, { c, top[2] + M.vlen(rig.joints[c].rest.p) })
		end
	end
	return best
end

local function newChain(rig: Rig.Rig, kind: ChainKind, joints: { number }, confidence: number, reason: string): Chain
	local pts, tip = chainPoints(rig, joints)
	local length = pathLength(pts, tip)
	local movable: { number } = {}
	for _, k in joints do
		if rig.joints[k].animated then
			table.insert(movable, k)
		end
	end
	local contact, gap = contactOf(rig, joints, tip, length)
	local last = rig.joints[joints[#joints]]
	local foot = M.qinvrot(last.world.q, M.vsub(contact, last.world.p))
	-- reach: from the first movable pivot to the contact, along the chain
	local reach = 0
	local first = movable[1]
	if first then
		local started = false
		local prev: V3? = nil
		for _, k in joints do
			if k == first then
				started = true
			end
			if started then
				local p = rig.joints[k].world.p
				if prev then
					reach += M.vdist(prev, p)
				end
				prev = p
			end
		end
		if prev then
			reach += M.vdist(prev :: V3, contact)
		end
	end
	local ik: IkKind
	local m = #movable
	local limbReach = reach
	local footVec = { x = 0, y = 0, z = 0 }
	if m == 0 then
		ik = "zero"
	elseif m == 1 then
		ik = "aim"
	elseif m == 2 then
		ik = "two"
		-- one leg segment and a foot (a stub leg ending in a flat foot part): the leg swings as a
		-- pendulum and the foot is held to the ground, never bent as a knee
		local lastPivot = rig.joints[movable[2]].world.p
		local footLen = M.vdist(lastPivot, contact)
		-- (a second segment under 30% of the leg is too short to be a shin: bending it as a knee
		-- would spin it round to make up the leg's length)
		if footLen < 0.3 * math.max(reach, 1e-6) then
			ik = "aimFoot"
			limbReach = M.vdist(rig.joints[movable[1]].world.p, lastPivot)
			footVec = M.vsub(contact, lastPivot)
		end
	else
		local lastPivot = rig.joints[movable[m]].world.p
		local footLen = M.vdist(lastPivot, contact)
		-- a foot is short, or lies along the ground (R15's runs forward); a last segment that
		-- points down at the ground is a shin or a tarsus and swings with the leg
		local fdir = M.vnorm(M.vsub(contact, lastPivot), { x = 0, y = -1, z = 0 })
		local flat = math.abs(fdir.y) < math.cos(math.rad(40))
		local footLike = footLen < 0.35 * math.max(reach, 1e-6) and (footLen < 0.15 * math.max(reach, 1e-6) or flat)
		ik = if m == 3 and footLike then "twoFoot" else "chain"
		if ik == "twoFoot" then
			local p1 = rig.joints[movable[1]].world.p
			local p2 = rig.joints[movable[2]].world.p
			limbReach = M.vdist(p1, p2) + M.vdist(p2, lastPivot)
			footVec = M.vsub(contact, lastPivot)
		else
			-- a long chain ending in a stub of a foot (a vine's tip): solve to the stub's pivot
			local upper = 0
			for si = 1, m - 1 do
				upper += M.vdist(rig.joints[movable[si]].world.p, rig.joints[movable[si + 1]].world.p)
			end
			if footLen < 0.25 * upper / (m - 1) then
				ik = "chainFoot"
				limbReach = upper
				footVec = M.vsub(contact, lastPivot)
			end
		end
	end
	-- fold limit: two bones fold to |a - b|; a longer chain to its longest segment minus the rest
	local minReach = 0
	if m >= 2 then
		local segs: { number } = {}
		local stop = if ik == "twoFoot" then 3 elseif ik == "chainFoot" then m else m + 1
		for si = 1, math.min(stop, m + 1) - 1 do
			local a = rig.joints[movable[si]].world.p
			local b = if si < m then rig.joints[movable[si + 1]].world.p else contact
			if ik == "twoFoot" and si == 2 then
				b = rig.joints[movable[3]].world.p
			end
			table.insert(segs, M.vdist(a, b))
		end
		local total, longest = 0, 0
		for _, l in segs do
			total += l
			longest = math.max(longest, l)
		end
		minReach = math.max(0, 2 * longest - total)
	elseif m == 1 then
		minReach = M.vdist(rig.joints[movable[1]].world.p, contact)
	end
	if ik == "aimFoot" then
		minReach = limbReach
	end
	return {
		kind = kind,
		name = "",
		aliases = {},
		index = 0,
		joints = joints,
		movable = movable,
		side = 0,
		confidence = confidence,
		reason = reason,
		base = pts[1],
		tipPos = tip,
		length = length,
		pair = nil,
		foot = foot,
		contact = contact,
		reach = reach,
		ik = ik,
		gap = gap,
		digit = false,
		touches = gap <= math.max(0.12 * rig.height, 0.15 * length),
		limbReach = limbReach,
		footVec = footVec,
		minReach = minReach,
		rigid = ik == "zero" or ik == "aim" or ik == "aimFoot",
	}
end

-- Classification -----------------------------------------------------------------------------------

type Feature = {
	run: Run,
	base: V3,
	tip: V3,
	length: number,
	low: number,
	dir: V3,
	hint: string?,
	hintN: number,
}

local function classifyRun(rig: Rig.Rig, f: Feature, centreX: number, width: number, onlyRun: boolean, rootSpan: number): (ChainKind, number, string)
	local ground = rig.ground
	local H = rig.height
	local L = math.max(f.length, 1e-6)
	local lowGap = f.low - ground
	local touches = lowGap <= math.max(0.12 * H, 0.15 * L)
	local down = -f.dir.y
	local back = f.dir.z
	local lateral = math.abs(f.dir.x)
	local up = f.dir.y
	local upper = f.base.y > ground + 0.45 * H
	local centred = math.abs(f.base.x - centreX) <= math.max(0.12 * width, 1e-3)
	local hint = f.hint

	-- A long run straight from the root with nothing beside it is the body itself (a snake).
	if onlyRun and #f.run.joints >= 3 and L > 1.5 * math.max(rootSpan, 1e-6) and math.abs(f.dir.y) < 0.5 then
		return "spine", 0.8, "the only chain, long next to the root part: the body bends along it"
	end
	if touches and (down > 0.3 or hint == "leg") then
		local c = if hint == "leg" then 0.95 elseif hint and hint ~= "leg" then 0.6 else 0.8
		return "leg", c, "reaches the ground and runs downward" .. (if hint == "leg" then ", named like a leg" else "")
	end
	if touches and hint ~= "arm" and hint ~= "tail" and hint ~= "wing" and hint ~= "head" and hint ~= "neck" then
		return "leg", 0.45, "lies on the ground (a sprawling limb); treated as a leg"
	end
	if (hint :: string?) == "other" then
		return "other", 0.85, "named like an accessory (ear, hat, antenna, horn); it rides along"
	end
	if hint == "wing" or (rig.flying and lateral > 0.5 and upper) then
		return "wing", if hint == "wing" then 0.9 else 0.55, if hint == "wing" then "named like a wing" else "spreads sideways on a flier"
	end
	if hint == "tail" or (back > 0.45 and centred and not touches) then
		return "tail", if hint == "tail" then 0.9 else 0.65, if hint == "tail" then "named like a tail" else "runs backward from the body's centre line"
	end
	if hint == "head" or hint == "neck" then
		return "head", 0.9, "named like a head or neck"
	end
	if centred and upper and (up > 0.3 or f.tip.y >= rig.boundsMax.y - 0.2 * H) and not touches then
		return "head", 0.6, "rises from the top of the body on its centre line"
	end
	if hint == "arm" then
		return "arm", 0.9, "named like an arm"
	end
	if hint == "leg" then
		return "leg", 0.4, "named like a leg but does not reach the ground"
	end
	if not centred and upper and not touches then
		return "arm", 0.55, "hangs or reaches from the upper body, off the centre line"
	end
	if hint == "spine" then
		return "spine", 0.6, "named like a body part"
	end
	return "other", 0.5, "none of the limb patterns fit; it rides along"
end

-- Joint indices from a list of names or indices (overrides).
local function resolveJoints(rig: Rig.Rig, list: any, warnings: { string }, what: string, asChain: boolean?): { number }?
	if type(list) ~= "table" then
		return nil
	end
	local src = list.joints or list
	if type(src) ~= "table" then
		return nil
	end
	local out: { number } = {}
	for _, item in src do
		local k: number? = nil
		if type(item) == "number" and rig.joints[item] then
			k = item
		elseif type(item) == "string" then
			k = Rig.find(rig, item)
		end
		if k then
			table.insert(out, k)
		else
			table.insert(warnings, string.format("override %s: no joint %s", what, tostring(item)))
		end
	end
	if #out == 0 then
		return nil
	end
	-- A chain must run parent to child. Given its ends (or a gappy list), fill in the path
	-- between the first and the last; when the last does not hang below the first, keep the
	-- longest run that does.
	local consecutive = true
	for i = 2, if asChain then #out else 0 do
		if rig.joints[out[i]].parent ~= out[i - 1] then
			consecutive = false
			break
		end
	end
	if not consecutive then
		local first, last = out[1], out[#out]
		local path: { number } = {}
		local cur = last
		local guard = 0
		while cur ~= 0 and guard <= rig.count do
			guard += 1
			table.insert(path, 1, cur)
			if cur == first then
				break
			end
			cur = rig.joints[cur].parent
		end
		if path[1] == first then
			out = path
		else
			local run = { out[1] }
			for i = 2, #out do
				if rig.joints[out[i]].parent == run[#run] then
					table.insert(run, out[i])
				else
					break
				end
			end
			out = run
		end
		table.insert(warnings, string.format("override %s: joints were not a parent-to-child run; used %d of them", what, #out))
	end
	return out
end

local function sortLegs(legs: { Chain })
	table.sort(legs, function(a, b)
		-- front (more -Z) first; left before right at the same depth; then by joint index
		local dz = a.contact.z - b.contact.z
		if math.abs(dz) > 1e-3 then
			return dz < 0
		end
		if a.side ~= b.side then
			return a.side < b.side
		end
		return a.joints[1] < b.joints[1]
	end)
end

local function sideOf(c: Chain, rig: Rig.Rig, centreX: number, width: number): number
	local x = (c.base.x + c.tipPos.x) / 2 - centreX
	if math.abs(x) > math.max(0.03 * width, 1e-4) then
		return if x > 0 then 1 else -1
	end
	return sideHint(rig, c.joints)
end

local function pairUp(list: { Chain }, width: number)
	for i, a in list do
		if a.pair or a.side == 0 then
			continue
		end
		local best, bestD = nil, math.huge
		for k, b in list do
			if k ~= i and not b.pair and b.side == -a.side then
				local d = math.abs(a.base.x + b.base.x) + math.abs(a.base.y - b.base.y) + math.abs(a.base.z - b.base.z)
				d += math.abs(a.contact.x + b.contact.x) + math.abs(a.contact.z - b.contact.z)
				if d < bestD then
					best, bestD = k, d
				end
			end
		end
		local tol = math.max(0.25 * math.max(a.length, 1e-6), 0.1 * width)
		if best and bestD <= tol * 2 then
			a.pair = best
			list[best].pair = i
		end
	end
end

--[[
	Classifies a rig. `overrides` (all optional):
		legs, arms, tails, wings, heads = { { "HipA", "KneeA", "FootA" }, ... } or { { joints = {...} } }
		body = "Root" | false, flying = true, round = true, shape = "long", hipHeight = 2
]]
function Anatomy.classify(rig: Rig.Rig, overrides: any?): Anatomy
	local o = if type(overrides) == "table" then overrides else {}
	local warnings: { string } = {}
	local reasons: { string } = {}
	local width = math.max(rig.boundsMax.x - rig.boundsMin.x, 1e-6)
	local length = math.max(rig.boundsMax.z - rig.boundsMin.z, 1e-6)
	local height = rig.height
	local centreX = (rig.boundsMax.x + rig.boundsMin.x) / 2
	local rootSpan = math.max(rig.rootSize.x, rig.rootSize.y, rig.rootSize.z)

	local runs = decompose(rig)
	local chains: { Chain } = {}
	local trunk: { number } = {}
	local claimed: { [number]: boolean } = {}

	-- Overrides claim their joints first.
	local forced: { [string]: boolean } = {}
	for _, kind in { "leg", "arm", "tail", "wing", "head" } do
		local key = kind .. "s"
		local list = o[key]
		if type(list) == "table" then
			forced[kind] = true
			for i, item in list do
				local js = resolveJoints(rig, item, warnings, key .. "[" .. i .. "]", true)
				if js then
					local c = newChain(rig, kind :: ChainKind, js, 1, "given by override")
					if type(item) == "table" and item.foot ~= nil then
						local f = M.readV3(item.foot)
						if f then
							c.foot = f
							local last = rig.joints[js[#js]]
							c.contact = M.xpoint(last.world, f)
							if c.ik == "twoFoot" or c.ik == "chainFoot" or c.ik == "aimFoot" then
								c.footVec = M.vsub(c.contact, rig.joints[c.movable[#c.movable]].world.p)
							end
						end
					end
					table.insert(chains, c)
					for _, k in js do
						claimed[k] = true
					end
				end
			end
		end
	end

	local leafRuns = 0
	for _, run in runs do
		if not run.endsInBranch then
			leafRuns += 1
		end
	end

	for _, run in runs do
		-- Drop joints an override already took; what is left of the run is classified as usual.
		local js: { number } = {}
		for _, k in run.joints do
			if not claimed[k] then
				table.insert(js, k)
			end
		end
		if #js == 0 then
			continue
		end
		local endsInBranch = run.endsInBranch
		local digitsFrom: number? = nil
		if endsInBranch then
			-- A limb whose end splits into short stubs (fingers, toes) is still a limb.
			local last = js[#js]
			local kids = rig.joints[last].children
			local pts, tip = chainPoints(rig, js)
			local runLen = pathLength(pts, tip)
			local stubs = true
			for _, c in kids do
				if #rig.joints[c].children > 1 or subtreeSpan(rig, c) > 0.45 * math.max(runLen, 1e-6) then
					stubs = false
					break
				end
			end
			if stubs and runLen > 0 and #js >= 2 then
				endsInBranch = false
				digitsFrom = last
			end
		end
		if endsInBranch then
			for _, k in js do
				table.insert(trunk, k)
			end
			continue
		end
		local pts, tip = chainPoints(rig, js)
		local len = pathLength(pts, tip)
		local f: Feature = {
			run = run,
			base = pts[1],
			tip = tip,
			length = len,
			low = lowestOf(rig, js, tip),
			dir = M.vnorm(M.vsub(tip, pts[1]), { x = 0, y = -1, z = 0 }),
			hint = nil,
			hintN = 0,
		}
		f.hint, f.hintN = hintOf(rig, js)
		local kind, conf, why = classifyRun(rig, f, centreX, width, run.fromRoot and leafRuns == 1 and #runs == 1, rootSpan)
		if forced[kind] then
			-- The caller listed this kind in full; anything else that looks like one rides along.
			kind, conf, why = "other", 0.5, why .. ", but the overrides list every " .. kind
		end
		if kind == "spine" then
			for _, k in js do
				table.insert(trunk, k)
			end
			table.insert(reasons, string.format("spine %s: %s", rig.joints[js[1]].name, why))
		else
			table.insert(chains, newChain(rig, kind :: any, js, conf, why))
		end
		if digitsFrom then
			for _, c in rig.joints[digitsFrom :: number].children do
				local digit: { number } = {}
				local cur = c
				local guard = 0
				while guard < 64 do
					guard += 1
					if not claimed[cur] then
						table.insert(digit, cur)
					end
					local kids = rig.joints[cur].children
					if #kids ~= 1 then
						break
					end
					cur = kids[1]
				end
				if #digit > 0 then
					local d = newChain(rig, "other", digit, 0.7, "a digit at the end of a limb; follows it")
					d.digit = true
					table.insert(chains, d)
				end
			end
		end
	end

	-- Nothing classified as a leg, but limbs lie on the ground (a starfish whose "arms" it walks
	-- on): those carry it.
	local anyLeg = false
	for _, c in chains do
		if c.kind == "leg" then
			anyLeg = true
		end
	end
	if not anyLeg and not forced.leg then
		for _, c in chains do
			if c.touches and not c.digit and (c.kind == "arm" or c.kind == "other") then
				c.kind = "leg"
				c.confidence = math.min(c.confidence, 0.5)
				c.reason ..= "; nothing else reaches the ground, so it carries the body"
			end
		end
	end

	-- Sides, kinds, pairs.
	local byKind: { [string]: { Chain } } = { leg = {}, arm = {}, tail = {}, wing = {}, head = {}, other = {} }
	for _, c in chains do
		c.side = sideOf(c, rig, centreX, width)
		local list = byKind[c.kind]
		if not list then
			list = byKind.other
			c.kind = "other"
		end
		table.insert(list, c)
	end

	-- Heads: keep the best; the rest are "other" (a second head is a creature for overrides).
	local heads = byKind.head
	if #heads > 1 then
		table.sort(heads, function(a, b)
			if a.confidence ~= b.confidence then
				return a.confidence > b.confidence
			end
			return a.tipPos.y > b.tipPos.y
		end)
		for i = 2, #heads do
			heads[i].kind = "other"
			heads[i].reason ..= "; another chain was chosen as the head"
			table.insert(byKind.other, heads[i])
		end
		heads = { heads[1] }
		byKind.head = heads
	end

	sortLegs(byKind.leg)
	for kind, list in byKind do
		if kind ~= "leg" then
			table.sort(list, function(a, b)
				if a.side ~= b.side then
					return a.side < b.side
				end
				return a.joints[1] < b.joints[1]
			end)
		end
		pairUp(list, width)
	end

	-- Names and aliases.
	local sideWord = { [-1] = "left", [0] = "", [1] = "right" }
	local function cap(s: string): string
		return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
	end
	for kind, list in byKind do
		for i, c in list do
			c.index = i
			c.name = kind .. "[" .. i .. "]"
			c.aliases = {}
			if kind == "leg" then
				local n = #list
				if n == 2 and c.side ~= 0 then
					table.insert(c.aliases, sideWord[c.side] .. "Leg")
				elseif n == 4 and c.side ~= 0 then
					local front = i <= 2
					table.insert(c.aliases, (if front then "front" else "back") .. cap(sideWord[c.side]) .. "Leg")
				elseif n == 1 then
					table.insert(c.aliases, "leg")
				end
			elseif kind == "arm" or kind == "wing" then
				if c.side ~= 0 then
					local word = sideWord[c.side] .. cap(kind)
					local taken = false
					for k = 1, i - 1 do
						if table.find(list[k].aliases, word) then
							taken = true
						end
					end
					if not taken then
						table.insert(c.aliases, word)
					end
				end
				if #list == 1 then
					table.insert(c.aliases, kind)
				end
			elseif kind == "tail" and i == 1 then
				table.insert(c.aliases, "tail")
			end
		end
	end

	-- Trunk order: by depth then index, so the spine reads from the root outward.
	table.sort(trunk, function(a, b)
		local da, db = rig.joints[a].depth, rig.joints[b].depth
		if da ~= db then
			return da < db
		end
		return a < b
	end)
	if type(o.spine) == "table" then
		local js = resolveJoints(rig, o.spine, warnings, "spine")
		if js then
			trunk = js
		end
	end

	-- The body joint: the trunk joint nearest the root that everything else hangs from.
	local body: number? = nil
	local rootKids = 0
	for _, j in rig.joints do
		if j.parent == 0 then
			rootKids += 1
		end
	end
	if #trunk > 0 and rig.joints[trunk[1]].parent == 0 and rootKids == 1 and rig.joints[trunk[1]].animated then
		body = trunk[1]
	end
	if o.body ~= nil then
		if o.body == false then
			body = nil
		elseif type(o.body) == "string" or type(o.body) == "number" then
			local k = if type(o.body) == "number" then o.body else Rig.find(rig, o.body)
			if k and rig.joints[k] then
				body = k
			else
				table.insert(warnings, "override body: no joint " .. tostring(o.body))
			end
		end
	end
	if body then
		table.insert(reasons, string.format("body joint %s carries bob and lean", rig.joints[body :: number].name))
	else
		table.insert(reasons, "no single body joint: bob and lean move the model's pivot")
	end

	-- Chest: the trunk joint the arms or the head hang from, else the last trunk joint.
	local chest: number? = nil
	local function parentInTrunk(c: Chain): number?
		local p = rig.joints[c.joints[1]].parent
		if p > 0 and table.find(trunk, p) then
			return p
		end
		return nil
	end
	for _, c in byKind.arm do
		chest = chest or parentInTrunk(c)
	end
	if not chest and heads[1] then
		chest = parentInTrunk(heads[1])
	end
	if not chest and #trunk > 0 then
		chest = trunk[#trunk]
	end

	local head: number? = nil
	local neck: { number } = {}
	if heads[1] then
		local js = heads[1].movable
		if #js == 0 then
			js = heads[1].joints
		end
		head = js[#js]
		for i = 1, #js - 1 do
			table.insert(neck, js[i])
		end
	end
	if type(o.head) == "string" then
		local k = Rig.find(rig, o.head)
		if k then
			head = k
		end
	end

	-- Hip height: the average height of the legs' first movable pivots above the ground.
	-- A body slung low between long sprawled legs (a starfish's arms lying flat, a lizard) moves
	-- at the pace of its legs, not of its height: the size the gait scales by is never less than
	-- 0.4 of the legs' reach.
	local hip = 0
	local nh = 0
	local reachSum = 0
	for _, c in byKind.leg do
		if c.gap <= 0.1 * height then
			local first = c.movable[1] or c.joints[1]
			hip += rig.joints[first].world.p.y - rig.ground
			reachSum += c.limbReach
			nh += 1
		end
	end
	local hipHeight: number
	if nh > 0 then
		hipHeight = math.max(hip / nh, 0.4 * reachSum / nh)
	else
		hipHeight = (rig.boundsMax.y + rig.boundsMin.y) / 2 - rig.ground
	end
	if type(o.hipHeight) == "number" and M.finite(o.hipHeight) and o.hipHeight > 0 then
		hipHeight = o.hipHeight
	end
	if not (hipHeight > 1e-6) then
		hipHeight = math.max(height * 0.5, 1e-3)
	end

	-- Shape, for legless motion and reports.
	local bodyHeight = height
	local shape: string
	local maxXZ = math.max(width, length)
	local spineLen = 0
	for i = 2, #trunk do
		spineLen += M.vdist(rig.joints[trunk[i - 1]].world.p, rig.joints[trunk[i]].world.p)
	end
	local round = rig.round or o.round == true
	if round then
		shape = "round"
	elseif (length >= 2.2 * math.max(width, bodyHeight)) or (#trunk >= 3 and spineLen >= 2.2 * math.max(width, 1e-6) and #byKind.leg == 0) then
		shape = "long"
	elseif bodyHeight < 0.35 * maxXZ then
		shape = "flat"
	elseif bodyHeight > 2 * maxXZ then
		shape = "tall"
	elseif #rig.joints == 0 and math.max(width, length, bodyHeight) <= 1.15 * math.min(width, length, bodyHeight) then
		shape = "round"
		round = true
	else
		shape = "compact"
	end
	if type(o.shape) == "string" then
		shape = o.shape
	end

	-- Overall confidence: the weakest leg and head count most, the rest a little.
	local conf = 1
	for _, c in chains do
		local weight = if c.kind == "leg" or c.kind == "head" then 1 else 0.5
		conf = math.min(conf, 1 - weight * (1 - c.confidence))
	end
	if #chains == 0 then
		conf = if #rig.joints == 0 then 1 else 0.6
	end

	local n = #byKind.leg
	table.insert(reasons, 1, string.format(
		"%d leg%s, %d arm%s, %d tail%s, %d wing%s, %s head; shape %s",
		n,
		if n == 1 then "" else "s",
		#byKind.arm,
		if #byKind.arm == 1 then "" else "s",
		#byKind.tail,
		if #byKind.tail == 1 then "" else "s",
		#byKind.wing,
		if #byKind.wing == 1 then "" else "s",
		if head then "a" else "no",
		shape
	))
	for _, c in chains do
		if not c.digit then
			table.insert(reasons, string.format("%s (%s): %s, confidence %.2f", c.name, rig.joints[c.joints[1]].name, c.reason, c.confidence))
		end
	end
	for _, w in rig.warnings do
		table.insert(warnings, w)
	end

	local all: { Chain } = {}
	for _, kind in { "leg", "arm", "head", "tail", "wing", "other" } do
		for _, c in byKind[kind] do
			table.insert(all, c)
		end
	end

	local a: Anatomy = {
		rig = rig,
		chains = all,
		legs = byKind.leg,
		arms = byKind.arm,
		tails = byKind.tail,
		wings = byKind.wing,
		heads = heads,
		others = byKind.other,
		spine = trunk,
		body = body,
		chest = chest,
		head = head,
		neck = neck,
		hipHeight = hipHeight,
		ground = rig.ground,
		width = width,
		length = length,
		height = height,
		shape = shape,
		flying = rig.flying or o.flying == true,
		round = round,
		confidence = conf,
		reasons = reasons,
		warnings = warnings,
		parts = {},
	}
	Anatomy.buildParts(a)
	return a
end

-- Semantic parts ------------------------------------------------------------------------------------

local SEGMENT_ALIASES: { [string]: { string } } = {
	-- humanoid-style names for segments of a two-sided limb: { chain alias, segment }
}

local function addPart(a: Anatomy, name: string, part: Part)
	if a.parts[name] == nil then
		a.parts[name] = part
	end
end

--[[
	The names a performance can key: "root", "body"/"hips"/"pelvis", "chest", "spine", "neck",
	"head", every chain by name and alias ("leg[3]", "leftArm", "tail"), a chain's segments as
	"<chain>.<n>" (1 = the joint nearest the body), humanoid segment names on two-sided limbs
	("rightUpperArm", "rightForearm", "rightHand", "leftThigh", "leftShin", "leftFoot"), and any
	joint as "joint:<Name>".
]]
function Anatomy.buildParts(a: Anatomy)
	local _ = SEGMENT_ALIASES
	a.parts = {}
	addPart(a, "root", { kind = "root", joints = {} })
	local bodyJ = a.body or a.spine[1]
	if bodyJ then
		for _, n in { "body", "hips", "pelvis" } do
			addPart(a, n, { kind = "spine", joints = { bodyJ } })
		end
	else
		-- no joint carries the body (Jack's pumpkin is his root): the hips are the whole model
		for _, n in { "body", "hips", "pelvis" } do
			addPart(a, n, { kind = "root", joints = {} })
		end
	end
	if a.chest then
		for _, n in { "chest", "torso", "upperBody" } do
			addPart(a, n, { kind = "spine", joints = { a.chest :: number } })
		end
	end
	if #a.spine > 0 then
		addPart(a, "spine", { kind = "spine", joints = table.clone(a.spine) })
		for i, k in a.spine do
			addPart(a, "spine[" .. i .. "]", { kind = "spine", joints = { k } })
		end
	end
	if #a.neck > 0 then
		addPart(a, "neck", { kind = "neck", joints = { a.neck[#a.neck] } })
	end
	if a.head then
		addPart(a, "head", { kind = "head", joints = { a.head :: number }, chain = a.heads[1] })
	end
	for _, c in a.chains do
		local whole: Part = { kind = c.kind, joints = { c.movable[1] or c.joints[1] }, chain = c }
		local names = { c.name }
		for _, al in c.aliases do
			table.insert(names, al)
		end
		for _, n in names do
			addPart(a, n, whole)
			for s, k in c.movable do
				addPart(a, n .. "." .. s, { kind = c.kind, joints = { k }, chain = c })
			end
		end
		-- humanoid segment names
		local sideName = if c.side < 0 then "left" elseif c.side > 0 then "right" else nil
		if sideName and (c.kind == "arm" or c.kind == "leg") then
			local segs = c.movable
			local function seg(i: number): Part?
				local k = segs[i]
				if not k then
					return nil
				end
				return { kind = c.kind :: string, joints = { k }, chain = c } :: Part
			end
			local count = #segs
			if c.kind == "arm" then
				local p1, p2 = seg(1), seg(2)
				if p1 then
					addPart(a, sideName .. "UpperArm", p1)
					addPart(a, sideName .. "Shoulder", p1)
				end
				if p2 then
					addPart(a, sideName .. "Forearm", p2)
					addPart(a, sideName .. "LowerArm", p2)
					addPart(a, sideName .. "Elbow", p2)
				end
				if count >= 3 then
					local pl = seg(count) :: Part
					addPart(a, sideName .. "Hand", pl)
					addPart(a, sideName .. "Wrist", pl)
				end
			else
				local p1, p2 = seg(1), seg(2)
				if p1 then
					addPart(a, sideName .. "Thigh", p1)
					addPart(a, sideName .. "UpperLeg", p1)
					addPart(a, sideName .. "Hip", p1)
				end
				if p2 then
					addPart(a, sideName .. "Shin", p2)
					addPart(a, sideName .. "LowerLeg", p2)
					addPart(a, sideName .. "Knee", p2)
				end
				if count >= 3 then
					local pl = seg(count) :: Part
					addPart(a, sideName .. "Foot", pl)
					addPart(a, sideName .. "Ankle", pl)
				end
			end
		end
	end
end

-- Resolves a semantic part name (see buildParts), or "joint:<Name>"; nil when the rig has none.
function Anatomy.part(a: Anatomy, name: string): Part?
	local p = a.parts[name]
	if p then
		return p
	end
	if string.sub(name, 1, 6) == "joint:" then
		local k = Rig.find(a.rig, string.sub(name, 7))
		if k then
			return { kind = "joint", joints = { k } }
		end
		return nil
	end
	-- case-insensitive fallback
	local lower = string.lower(name)
	for key, part in a.parts do
		if string.lower(key) == lower then
			return part
		end
	end
	return nil
end

-- One paragraph for the agent to show the user: what was found and how sure.
function Anatomy.describe(a: Anatomy): string
	local lines = { string.format("%s: %s (confidence %.2f)", a.rig.name, a.reasons[1] or "", a.confidence) }
	table.insert(lines, string.format("hip height %.3g studs, size %.3g wide x %.3g tall x %.3g long", a.hipHeight, a.width, a.height, a.length))
	for i = 2, #a.reasons do
		table.insert(lines, "  " .. a.reasons[i])
	end
	if #a.warnings > 0 then
		table.insert(lines, string.format("  %d warning(s): %s", #a.warnings, a.warnings[1]))
	end
	return table.concat(lines, "\n") :: string
end

return Anatomy
