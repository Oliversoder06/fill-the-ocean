--!strict
--[[
	RigReader (Roblox only): any Model or part becomes an abstract rig (Rig.RigSpec) plus the
	bindings that say which Instance each rig joint writes to.

	What it reads, starting from the root part (PrimaryPart, Humanoid.RootPart, the part no joint
	moves, or the largest part) and walking outward:
	- Motor6D           Part0 -> Part1, rest from C0/C1. A motor found from its Part1 side is
	                    walked in reverse and written inverted.
	- AnimationConstraint  Attachment0/1 (the joint type of upgraded R15 avatars), same frames.
	- Bone              under any part or bone, rest from Bone.CFrame (skinned meshes).
	- Weld, ManualWeld, WeldConstraint, other JointInstances: fixed links, so welded parts
	                    and their boxes still count for size and ground.

	It never errors on a strange model: loops and parts reached twice are cut with a warning,
	parts nothing connects are left out (they are not part of the rig), duplicate names are
	renamed by Rig.build. Rest offsets come from C0/C1 and Bone.CFrame, never from where the
	parts are drawn now, so a rig read while an Animator is playing still reads at rest.
]]

local Rig = require("../Rig")

local RigReader = {}

export type Binding = {
	instance: Instance?,
	kind: string,
	-- write Transform:Inverse() (a motor walked from its Part1 side)
	invert: boolean,
	-- the Transform when read, to put back on stop
	original: CFrame,
	-- the part this joint moves (motors and constraints), for previews and trails
	part: BasePart?,
}

export type Result = {
	spec: Rig.RigSpec,
	bindings: { Binding },
	root: BasePart?,
	model: Instance,
	humanoid: Humanoid?,
	animator: Animator?,
	warnings: { string },
	-- the root part's CFrame relative to the model's pivot (to move the model by its pivot)
	pivotToRoot: CFrame,
}

local function isA(inst: Instance, class: string): boolean
	local ok, r = pcall(function()
		return inst:IsA(class)
	end)
	return ok and r == true
end

local function within(inst: Instance?, model: Instance): boolean
	return inst ~= nil and (inst == model or (inst :: Instance):IsDescendantOf(model))
end

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local function chooseRoot(model: Instance, parts: { BasePart }, movedParts: { [BasePart]: boolean }): BasePart?
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") and model.PrimaryPart and within(model.PrimaryPart, model) then
		return model.PrimaryPart
	end
	local hum = model:FindFirstChildWhichIsA("Humanoid")
	if hum and hum.RootPart and within(hum.RootPart, model) then
		return hum.RootPart
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	-- the biggest part that no joint moves
	local best: BasePart? = nil
	local bestVol = -1
	for _, p in parts do
		if not movedParts[p] then
			local s = p.Size
			local vol = s.X * s.Y * s.Z
			if vol > bestVol then
				best, bestVol = p, vol
			end
		end
	end
	if best then
		return best
	end
	for _, p in parts do
		local s = p.Size
		local vol = s.X * s.Y * s.Z
		if vol > bestVol then
			best, bestVol = p, vol
		end
	end
	return best
end

type Edge = {
	inst: Instance,
	kind: string,
	a: BasePart,
	b: BasePart,
	c0: CFrame,
	c1: CFrame,
}

--[[
	Reads `model` (a Model, a part, or anything holding parts). `opts.ignore` lists instances to
	leave out (held tools, effects).
]]
function RigReader.read(model: Instance, opts: { [string]: any }?): Result
	local o: { [string]: any } = opts or {}
	local warnings: { string } = {}
	local parts: { BasePart } = {}
	local edges: { Edge } = {}
	local bonesUnder: { [Instance]: { Bone } } = {}
	local ignore: { [Instance]: boolean } = {}
	if type(o.ignore) == "table" then
		for _, inst in o.ignore do
			if typeof(inst) == "Instance" then
				ignore[inst] = true
			end
		end
	end
	local all = model:GetDescendants()
	if model:IsA("BasePart") then
		table.insert(all, 1, model)
	end
	local movedParts: { [BasePart]: boolean } = {}
	for _, inst in all do
		local skip = false
		for ig in ignore do
			if inst == ig or inst:IsDescendantOf(ig) then
				skip = true
				break
			end
		end
		if skip then
			continue
		end
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		elseif inst:IsA("Motor6D") then
			local m = inst :: Motor6D
			if m.Part0 and m.Part1 and within(m.Part0, model) and within(m.Part1, model) then
				table.insert(edges, { inst = m :: Instance, kind = "motor", a = m.Part0 :: BasePart, b = m.Part1 :: BasePart, c0 = m.C0, c1 = m.C1 })
				movedParts[m.Part1 :: BasePart] = true
			end
		elseif isA(inst, "AnimationConstraint") then
			local ac = inst :: any
			local a0, a1 = ac.Attachment0, ac.Attachment1
			if a0 and a1 and a0.Parent and a1.Parent and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart") then
				if within(a0.Parent, model) and within(a1.Parent, model) then
					table.insert(edges, { inst = ac, kind = "constraint", a = a0.Parent, b = a1.Parent, c0 = a0.CFrame, c1 = a1.CFrame })
					movedParts[a1.Parent] = true
				end
			end
		elseif inst:IsA("JointInstance") then
			local j = inst :: JointInstance
			if j.Part0 and j.Part1 and within(j.Part0, model) and within(j.Part1, model) then
				table.insert(edges, { inst = j :: Instance, kind = "weld", a = j.Part0 :: BasePart, b = j.Part1 :: BasePart, c0 = j.C0, c1 = j.C1 })
			end
		elseif inst:IsA("WeldConstraint") then
			local w = inst :: WeldConstraint
			if w.Part0 and w.Part1 and within(w.Part0, model) and within(w.Part1, model) then
				-- no C0/C1: keep the parts where they are relative to each other
				local p0, p1 = w.Part0 :: BasePart, w.Part1 :: BasePart
				table.insert(edges, { inst = w :: Instance, kind = "weld", a = p0, b = p1, c0 = p0.CFrame:ToObjectSpace(p1.CFrame), c1 = CFrame.identity })
			end
		elseif inst:IsA("Bone") then
			local parent = inst.Parent
			if parent then
				local list = bonesUnder[parent]
				if not list then
					list = {}
					bonesUnder[parent] = list
				end
				table.insert(list, inst :: Bone)
			end
		end
	end

	local root = chooseRoot(model, parts, movedParts)
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	local animator: Animator? = nil
	if humanoid then
		animator = humanoid:FindFirstChildWhichIsA("Animator")
	else
		local ctrl = model:FindFirstChildWhichIsA("AnimationController")
		if ctrl then
			animator = ctrl:FindFirstChildWhichIsA("Animator")
		end
	end

	local joints: { any } = {}
	local bindings: { Binding } = {}
	-- the abstract joint that moves each reached part (0 = the root part itself)
	local partJoint: { [BasePart]: number } = {}
	-- each part's frame relative to the frame of the joint that moves it (C1^-1)
	local partInJoint: { [BasePart]: CFrame } = {}
	local function addJoint(spec: any, binding: Binding): number
		table.insert(joints, spec)
		table.insert(bindings, binding)
		return #joints
	end
	local function partName(p: Instance): string
		return p.Name
	end

	if not root then
		table.insert(warnings, "no parts: an empty rig")
	else
		partJoint[root] = 0
		partInJoint[root] = CFrame.identity
		-- breadth first over joints, so the nearest connection wins and loops are cut
		local byPart: { [BasePart]: { Edge } } = {}
		for _, e in edges do
			for _, p in { e.a, e.b } do
				local list = byPart[p]
				if not list then
					list = {}
					byPart[p] = list
				end
				table.insert(list, e)
			end
		end
		local used: { [Instance]: boolean } = {}
		local queue: { BasePart } = { root }
		local head = 1
		while head <= #queue do
			local p = queue[head]
			head += 1
			local parentJoint = partJoint[p]
			local inJoint = partInJoint[p]
			local list: { Edge } = byPart[p] or {}
			for _, e in list do
				if used[e.inst] then
					continue
				end
				used[e.inst] = true
				local forward = e.a == p
				local child = if forward then e.b else e.a
				if partJoint[child] ~= nil then
					table.insert(warnings, string.format("%s closes a loop between %s and %s; ignored", e.inst:GetFullName(), e.a.Name, e.b.Name))
					continue
				end
				-- joint frame = parentPart * C0 (forward) or parentPart * C1 (reversed)
				local rest: CFrame
				local center: CFrame
				local kind = e.kind
				local invert = false
				if forward then
					rest = inJoint * e.c0
					center = e.c1:Inverse()
				else
					rest = inJoint * e.c1
					center = e.c0:Inverse()
					invert = kind ~= "weld"
					if invert then
						table.insert(warnings, string.format("%s is reached from its Part1 side; it is driven inverted", e.inst:GetFullName()))
					end
				end
				local spec = {
					name = if kind == "weld" then child.Name .. "Weld" else e.inst.Name,
					parent = if parentJoint == 0 then nil else parentJoint,
					rest = rest,
					kind = kind,
					size = vec(child.Size),
					center = center,
					part = partName(child),
				}
				local min = e.inst:GetAttribute("AnimMin")
				local max = e.inst:GetAttribute("AnimMax")
				if typeof(min) == "Vector3" and typeof(max) == "Vector3" then
					spec.limits = { min = vec(min), max = vec(max) }
				end
				local original = CFrame.identity
				if kind ~= "weld" then
					local ok, tr = pcall(function()
						return (e.inst :: any).Transform
					end)
					if ok and typeof(tr) == "CFrame" then
						original = tr
					end
				end
				local index = addJoint(spec, {
					instance = if kind == "weld" then nil else e.inst,
					kind = kind,
					invert = invert,
					original = original,
					part = child,
				})
				partJoint[child] = index
				partInJoint[child] = center
				table.insert(queue, child)
			end
		end
		-- bones under every reached part, walked bone to bone
		local function addBones(parentInst: Instance, parentJoint: number, inJoint: CFrame)
			local under: { Bone } = bonesUnder[parentInst] or {}
			for _, bone in under do
				local spec = {
					name = bone.Name,
					parent = if parentJoint == 0 then nil else parentJoint,
					rest = inJoint * bone.CFrame,
					kind = "bone",
					part = bone.Name,
				}
				local min = bone:GetAttribute("AnimMin")
				local max = bone:GetAttribute("AnimMax")
				if typeof(min) == "Vector3" and typeof(max) == "Vector3" then
					spec.limits = { min = vec(min), max = vec(max) }
				end
				local index = addJoint(spec, { instance = bone, kind = "bone", invert = false, original = bone.Transform, part = nil })
				addBones(bone, index, CFrame.identity)
			end
		end
		for p, j in partJoint do
			addBones(p, j, partInJoint[p])
		end
		local unreached = 0
		for _, p in parts do
			if partJoint[p] == nil then
				unreached += 1
			end
		end
		if unreached > 0 then
			table.insert(warnings, string.format("%d part(s) are not joined to the root part and are left out", unreached))
		end
	end

	-- Ground: a Humanoid's hip height says it exactly; otherwise the rig's lowest rest point.
	local ground: number? = nil
	if humanoid and root and humanoid.RigType == Enum.HumanoidRigType.R15 then
		ground = -(humanoid.HipHeight + root.Size.Y / 2)
	end
	if type(o.ground) == "number" then
		ground = o.ground
	end
	local pivotToRoot = CFrame.identity
	if root and model:IsA("Model") then
		pivotToRoot = model:GetPivot():ToObjectSpace(root.CFrame)
	end
	local spec: Rig.RigSpec = {
		name = model.Name,
		rootName = if root then root.Name else "Root",
		rootSize = if root then vec(root.Size) else nil,
		joints = joints,
		ground = ground,
		flying = model:GetAttribute("Flying") == true or o.flying == true,
		round = model:GetAttribute("Round") == true or o.round == true,
		facing = if type(o.facing) == "number" then o.facing else (model:GetAttribute("AnimFacing") :: any),
	}
	return {
		spec = spec,
		bindings = bindings,
		root = root,
		model = model,
		humanoid = humanoid,
		animator = animator,
		warnings = warnings,
		pivotToRoot = pivotToRoot,
	}
end

return RigReader
