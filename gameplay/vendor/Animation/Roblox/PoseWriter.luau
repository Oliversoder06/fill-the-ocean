--!strict
--[[
	PoseWriter (Roblox only): puts a sampled pose on a real model.

	Joints: each channel's seven numbers become CFrame.new(x, y, z, qx, qy, qz, qw) on the
	Motor6D, Bone or AnimationConstraint the rig joint was read from. Writes belong in
	RunService.PreSimulation (or a track's pose step), which runs after the Animator has written
	the frame's animation and right before Roblox applies Transforms: anything written earlier in
	the frame is overwritten by a playing Animator (measured in Studio; Roblox's Motor6D docs
	say the same).

	Modes:
	- replace   the joint shows this pose, blended over what is there by `weight` (fades)
	- add       this pose's rotation is layered on top of what is there (a look on top of a
	            walk). It remembers what it built on: if nothing rewrote the joint since its last
	            write, it builds on the same base again instead of compounding.

	The root: "world" bakes are pivots in the world, "offset" bakes move the model relative to
	an anchor (its pivot when playback started). The model always moves by PivotTo, so a camera
	framing it sees the move the same frame.

	restore() puts back every Transform it touched, as it found them.
]]

local Rig = require("../Rig")
local Baked = require("../Baked")
local RigReader = require("./RigReader")

local PoseWriter = {}

export type Writer = {
	read: RigReader.Result,
	rig: Rig.Rig,
	baked: Baked.Baked,
	-- channel -> binding index (0 when the joint has nothing to write to)
	map: { number },
	mode: string,
	touched: { [Instance]: CFrame },
	lastWritten: { [Instance]: CFrame },
	base: { [Instance]: CFrame },
	destroyed: boolean,
}

function PoseWriter.new(read: RigReader.Result, rig: Rig.Rig, baked: Baked.Baked, mode: string?): Writer
	local map: { number } = table.create(baked.nch, 0)
	for c = 1, baked.nch do
		local k = baked.joints[c]
		local j = rig.joints[k]
		local b = if j then read.bindings[j.source] else nil
		map[c] = if b and b.instance then j.source else 0
	end
	return {
		read = read,
		rig = rig,
		baked = baked,
		map = map,
		mode = if mode == "add" then "add" else "replace",
		touched = {},
		lastWritten = {},
		base = {},
		destroyed = false,
	}
end

local function transformOf(inst: Instance): CFrame
	local ok, v = pcall(function()
		return (inst :: any).Transform
	end)
	if ok and typeof(v) == "CFrame" then
		return v
	end
	return CFrame.identity
end

local function setTransform(inst: Instance, cf: CFrame)
	(inst :: any).Transform = cf
end

--[[
	Writes the joints of a sampled buffer (Baked.sample's output). `weight` 0..1 blends over the
	current value in replace mode and scales the layer in add mode.
]]
function PoseWriter.write(w: Writer, buf: { number }, weight: number?)
	if w.destroyed then
		return
	end
	local wt = if weight == nil then 1 else math.clamp(weight, 0, 1)
	local bindings = w.read.bindings
	for c = 1, w.baked.nch do
		local bi = w.map[c]
		if bi == 0 then
			continue
		end
		local b = bindings[bi]
		local inst = b.instance :: Instance
		if not inst.Parent then
			continue
		end
		local o = c * 7
		local cf = CFrame.new(buf[o + 1], buf[o + 2], buf[o + 3], buf[o + 4], buf[o + 5], buf[o + 6], buf[o + 7])
		if b.invert then
			cf = cf:Inverse()
		end
		if not w.touched[inst] then
			w.touched[inst] = b.original
		end
		if w.mode == "add" then
			local cur = transformOf(inst)
			local last: CFrame? = w.lastWritten[inst]
			if last and cur == last then
				cur = w.base[inst] or cur
			else
				w.base[inst] = cur
			end
			local layer = if wt < 1 then CFrame.identity:Lerp(cf, wt) else cf
			local out = cur * layer
			setTransform(inst, out)
			w.lastWritten[inst] = out
		else
			if wt < 1 then
				cf = transformOf(inst):Lerp(cf, wt)
			end
			setTransform(inst, cf)
		end
	end
end

-- The root part's world CFrame for a sampled buffer, given the anchor ("offset" mode only).
function PoseWriter.rootCFrame(w: Writer, buf: { number }, anchor: CFrame): CFrame
	local cf = CFrame.new(buf[1], buf[2], buf[3], buf[4], buf[5], buf[6], buf[7])
	if w.baked.rootMode == "world" then
		return cf
	end
	return anchor * cf
end

-- Moves the model so its root part sits at `rootCF`.
function PoseWriter.place(w: Writer, rootCF: CFrame)
	if w.destroyed then
		return
	end
	local model = w.read.model
	if not model.Parent then
		return
	end
	local pivot = rootCF * w.read.pivotToRoot:Inverse()
	if model:IsA("Model") then
		model:PivotTo(pivot)
	elseif model:IsA("BasePart") then
		model:PivotTo(pivot)
	end
end

-- Puts back every Transform this writer changed. Safe to call more than once.
function PoseWriter.restore(w: Writer)
	for inst, original in w.touched do
		if inst.Parent then
			pcall(setTransform, inst, original)
		end
	end
	table.clear(w.touched)
	table.clear(w.lastWritten)
	table.clear(w.base)
end

function PoseWriter.destroy(w: Writer)
	PoseWriter.restore(w)
	w.destroyed = true
end

return PoseWriter
