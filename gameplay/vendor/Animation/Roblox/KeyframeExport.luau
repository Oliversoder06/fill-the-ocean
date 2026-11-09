--!strict
--[[
	KeyframeExport (Roblox only): a baked clip as a KeyframeSequence, to publish through the
	Animation Editor (or preview in Studio).

	Poses are named after the part each joint moves (Motor6D and AnimationConstraint) or the bone
	(skinned meshes), nested by the joint hierarchy under the root part's pose, which is how the
	Animation Editor stores them. A parent with no key at a keyframe gets a placeholder pose of
	weight 0, so its children can still sit under it. Keys are linear, like Roblox's own packs:
	the motion between them is already in the samples. Markers become KeyframeMarkers.

	preview() registers the sequence for this Studio session only (the id plays nowhere else);
	shipping needs a published animation id.
]]

local Anatomy = require("../Anatomy")
local Baked = require("../Baked")
local Export = require("../Export")
local RigReader = require("./RigReader")

local KeyframeExport = {}

function KeyframeExport.build(
	baked: Baked.Baked,
	anatomy: Anatomy.Anatomy,
	read: RigReader.Result,
	opts: { [string]: any }?
): (KeyframeSequence, { string })
	local o: { [string]: any } = opts or {}
	local result = Export.keyframes(baked, anatomy, o)
	local rig = anatomy.rig
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = if type(o.name) == "string" then o.name else baked.name
	kfs.Loop = baked.loop
	pcall(function()
		kfs.Priority = (o.priority or Enum.AnimationPriority.Action) :: any
	end)
	local rootName = if read.root then (read.root :: BasePart).Name else "HumanoidRootPart"
	local function poseName(k: number): string
		local j = rig.joints[k]
		local b = read.bindings[j.source]
		if b and b.part then
			return (b.part :: BasePart).Name
		end
		if b and b.instance then
			return (b.instance :: Instance).Name
		end
		return j.part
	end
	for _, kf in result.keyframes do
		local frame = Instance.new("Keyframe")
		frame.Time = kf.time
		local rootPose = Instance.new("Pose")
		rootPose.Name = rootName
		rootPose.Weight = 0
		rootPose.Parent = frame
		local made: { [number]: Pose } = {}
		local keyed: { [number]: any } = {}
		for _, p in kf.poses do
			keyed[p.joint] = p.x
		end
		local function ensure(k: number): Pose
			local existing = made[k]
			if existing then
				return existing
			end
			local j = rig.joints[k]
			local parentPose = if j.parent > 0 then ensure(j.parent) else rootPose
			local pose = Instance.new("Pose")
			pose.Name = poseName(k)
			local x = keyed[k]
			local b = read.bindings[j.source]
			if x then
				local cf = CFrame.new(x.p.x, x.p.y, x.p.z, x.q.x, x.q.y, x.q.z, x.q.w)
				if b and b.invert then
					cf = cf:Inverse()
				end
				pose.CFrame = cf
				pose.Weight = 1
			else
				pose.Weight = 0
			end
			pose.EasingStyle = Enum.PoseEasingStyle.Linear
			pose.EasingDirection = Enum.PoseEasingDirection.In
			pose.Parent = parentPose
			made[k] = pose
			return pose
		end
		for _, p in kf.poses do
			local j = rig.joints[p.joint]
			if j.animated then
				ensure(p.joint)
			end
		end
		frame.Parent = kfs
	end
	for _, mk in result.markers do
		for _, frame in kfs:GetChildren() do
			if frame:IsA("Keyframe") and math.abs(frame.Time - mk.time) < 1e-6 then
				local marker = Instance.new("KeyframeMarker")
				marker.Name = mk.name
				marker.Value = mk.value or ""
				marker.Parent = frame
				break
			end
		end
	end
	return kfs, result.warnings
end

-- A temporary content id for this Studio session (AnimationClipProvider), or nil and why.
function KeyframeExport.preview(kfs: KeyframeSequence): (string?, string?)
	local ok: boolean, id = pcall(function()
		local provider = game:GetService("AnimationClipProvider") :: any
		return provider:RegisterAnimationClip(kfs)
	end)
	if ok and id then
		return tostring(id), nil
	end
	local ok2, id2 = pcall(function()
		local provider = game:GetService("KeyframeSequenceProvider") :: any
		return provider:RegisterKeyframeSequence(kfs)
	end)
	if ok2 and id2 then
		return tostring(id2), nil
	end
	return nil, tostring(id)
end

return KeyframeExport
