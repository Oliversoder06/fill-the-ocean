--!strict
--[[
	Templates: stand-in rigs as plain data, for linting a clip offline (the Analyzer has no
	model to read) and for the tests. The proportions are those of Roblox's blocky R15 and R6
	characters, measured by eye and rounded: close enough to judge timing, spacing, arcs and
	weight, not a substitute for reading the real rig in Studio (RigReader does that).

	Both face -Z with the root part's centre at the origin and the floor 3 studs below, as a
	standing Roblox character does. R6 keeps the quarter-turned joint frames its real shoulders
	and hips have, which is exactly the kind of rig that breaks code assuming joint axes line up
	with the body's.
]]

local Templates = {}

local function j(name: string, parent: string?, pos: { number }, size: { number }?, center: { number }?, rot: { number }?, part: string?): any
	return {
		name = name,
		parent = parent,
		rest = { pos = pos, rot = rot },
		size = size,
		center = if center then { pos = center } else nil,
		part = part,
		kind = "motor",
	}
end

-- R15: pivots in each parent's frame (all rest rotations are identity, so offsets add up).
function Templates.R15(): any
	return {
		name = "R15",
		rootName = "HumanoidRootPart",
		rootSize = { 2, 2, 1 },
		ground = -3,
		joints = {
			j("Root", nil, { 0, -1, 0 }, { 2, 0.4, 1 }, { 0, 0.2, 0 }, nil, "LowerTorso"),
			j("Waist", "Root", { 0, 0.4, 0 }, { 2, 1.6, 1 }, { 0, 0.8, 0 }, nil, "UpperTorso"),
			j("Neck", "Waist", { 0, 1.6, 0 }, { 1.2, 1.2, 1.2 }, { 0, 0.6, 0 }, nil, "Head"),
			j("LeftShoulder", "Waist", { -1.5, 1.4, 0 }, { 1, 1.1, 1 }, { 0, -0.45, 0 }, nil, "LeftUpperArm"),
			j("LeftElbow", "LeftShoulder", { 0, -0.95, 0 }, { 1, 1, 1 }, { 0, -0.45, 0 }, nil, "LeftLowerArm"),
			j("LeftWrist", "LeftElbow", { 0, -0.95, 0 }, { 1, 0.4, 1 }, { 0, -0.2, 0 }, nil, "LeftHand"),
			j("RightShoulder", "Waist", { 1.5, 1.4, 0 }, { 1, 1.1, 1 }, { 0, -0.45, 0 }, nil, "RightUpperArm"),
			j("RightElbow", "RightShoulder", { 0, -0.95, 0 }, { 1, 1, 1 }, { 0, -0.45, 0 }, nil, "RightLowerArm"),
			j("RightWrist", "RightElbow", { 0, -0.95, 0 }, { 1, 0.4, 1 }, { 0, -0.2, 0 }, nil, "RightHand"),
			j("LeftHip", "Root", { -0.5, -0.2, 0 }, { 1, 0.9, 1 }, { 0, -0.425, 0 }, nil, "LeftUpperLeg"),
			j("LeftKnee", "LeftHip", { 0, -0.85, 0 }, { 1, 0.8, 1 }, { 0, -0.375, 0 }, nil, "LeftLowerLeg"),
			j("LeftAnkle", "LeftKnee", { 0, -0.75, 0 }, { 1, 0.2, 1.2 }, { 0, -0.1, -0.1 }, nil, "LeftFoot"),
			j("RightHip", "Root", { 0.5, -0.2, 0 }, { 1, 0.9, 1 }, { 0, -0.425, 0 }, nil, "RightUpperLeg"),
			j("RightKnee", "RightHip", { 0, -0.85, 0 }, { 1, 0.8, 1 }, { 0, -0.375, 0 }, nil, "RightLowerLeg"),
			j("RightAnkle", "RightKnee", { 0, -0.75, 0 }, { 1, 0.2, 1.2 }, { 0, -0.1, -0.1 }, nil, "RightFoot"),
		},
	}
end

--[[
	R6: one part per limb. The shoulders' and hips' frames are turned a quarter about Y (left
	-90, right +90), so a pose authored about the joint's own X would swing the arm sideways.
	Pivots are on the limb's top centre so the part hangs straight down at rest.
]]
function Templates.R6(): any
	local function limb(name: string, pos: { number }, yaw: number, part: string): any
		return {
			name = name,
			parent = "RootJoint",
			rest = { pos = pos, rot = { 0, yaw, 0 } },
			size = { 1, 2, 1 },
			center = { pos = { 0, -1, 0 } },
			part = part,
			kind = "motor",
		}
	end
	return {
		name = "R6",
		rootName = "HumanoidRootPart",
		rootSize = { 2, 2, 1 },
		ground = -3,
		joints = {
			j("RootJoint", nil, { 0, 0, 0 }, { 2, 2, 1 }, { 0, 0, 0 }, nil, "Torso"),
			j("Neck", "RootJoint", { 0, 1, 0 }, { 2, 1, 1 }, { 0, 0.5, 0 }, nil, "Head"),
			limb("Left Shoulder", { -1.5, 1, 0 }, -90, "Left Arm"),
			limb("Right Shoulder", { 1.5, 1, 0 }, 90, "Right Arm"),
			limb("Left Hip", { -0.5, -1, 0 }, -90, "Left Leg"),
			limb("Right Hip", { 0.5, -1, 0 }, 90, "Right Leg"),
		},
	}
end

Templates.names = { "R15", "R6" }

-- A template spec by name (case-insensitive), or nil.
function Templates.get(name: string): any?
	local lower = string.lower(name)
	if lower == "r15" then
		return Templates.R15()
	elseif lower == "r6" then
		return Templates.R6()
	end
	return nil
end

return Templates
