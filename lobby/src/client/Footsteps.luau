-- Footsteps: in the lobby every character (yours too: the camera is third person here) steps once per
-- LobbyCues.steps.stride studs walked on the ground. The sound follows the floor: a part's string
-- attribute Footstep ("wood", "sand", "grass", "stone": the boardwalk's Plastic boards are "wood")
-- wins, else its material (LobbyCues.surface, the same as gameplay's shared/Steps).
-- Yours play 2D, others' 3D at their feet within LobbyCues.steps.range. Roblox's default running
-- sound is muted on every character so it doesn't play under ours.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LobbyCues = require(ReplicatedStorage.Shared.LobbyCues)
local Sfx = require(script.Parent.Sfx)

local DEFAULT_RUNNING = "Running" -- the sound Roblox's character sounds script adds to the root
local MAX_MOVE = 4 -- studs in one frame; more is a teleport (a pad pulling someone in), not a walk
local FLOOR_REACH = 1.5 -- studs below the feet the floor ray looks

local player = Players.LocalPlayer
local Footsteps = {}

function Footsteps.start()
	local cue = LobbyCues.steps
	for _, list in cue.surfaces do
		for _, name in list do
			Sfx.need(name)
		end
	end
	local rng = Random.new()
	local lastName: string? = nil
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	-- The surface under a character: its floor part's Footstep attribute, else the floor material.
	local function surfaceUnder(root: BasePart, humanoid: Humanoid): string
		local characters = {}
		for _, other in Players:GetPlayers() do
			if other.Character then
				table.insert(characters, other.Character)
			end
		end
		rayParams.FilterDescendantsInstances = characters
		local drop = root.Size.Y / 2 + humanoid.HipHeight + FLOOR_REACH
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -drop, 0), rayParams)
		local named = hit and hit.Instance:GetAttribute("Footstep")
		if type(named) == "string" and cue.surfaces[named] then
			return named
		end
		return LobbyCues.surface(humanoid.FloorMaterial.Name)
	end

	local function step(root: BasePart, humanoid: Humanoid, own: boolean)
		local name = LobbyCues.pickNext(cue.surfaces[surfaceUnder(root, humanoid)], rng:NextNumber(), lastName)
		lastName = name
		local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + humanoid.HipHeight, 0)
		Sfx.play(name, {
			volume = if own then cue.volume else cue.otherVolume,
			pitch = rng:NextNumber(cue.pitchMin, cue.pitchMax),
			at = if own then nil else feet,
		})
	end

	-- Mute the default running sound, and keep it muted if the default script resets it.
	local function mute(sound: Instance)
		if sound:IsA("Sound") and sound.Name == DEFAULT_RUNNING then
			sound.Volume = 0
			sound:GetPropertyChangedSignal("Volume"):Connect(function()
				if sound.Volume ~= 0 then
					sound.Volume = 0
				end
			end)
		end
	end
	local function watchCharacter(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return -- character removed before it finished loading
		end
		for _, child in root:GetChildren() do
			mute(child)
		end
		root.ChildAdded:Connect(mute)
	end
	local function watchPlayer(other: Player)
		other.CharacterAdded:Connect(watchCharacter)
		if other.Character then
			task.spawn(watchCharacter, other.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end

	local walked: { [Player]: number } = {}
	local lastPos: { [Player]: Vector3 } = {}
	Players.PlayerRemoving:Connect(function(other)
		walked[other], lastPos[other] = nil, nil
	end)
	RunService.Heartbeat:Connect(function()
		local camera = workspace.CurrentCamera
		for _, other in Players:GetPlayers() do
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not (root and root:IsA("BasePart") and humanoid) then
				lastPos[other] = nil
				continue
			end
			local pos = root.Position
			local before = lastPos[other]
			lastPos[other] = pos
			if not before or humanoid.FloorMaterial == Enum.Material.Air then
				continue
			end
			local moved = Vector3.new(pos.X - before.X, 0, pos.Z - before.Z).Magnitude
			if moved > MAX_MOVE then
				continue
			end
			walked[other] = (walked[other] or 0) + moved
			if walked[other] < cue.stride then
				continue
			end
			walked[other] = 0
			if other == player then
				step(root, humanoid, true)
			elseif camera and (camera.CFrame.Position - pos).Magnitude <= cue.range then
				step(root, humanoid, false)
			end
		end
	end)
end

return Footsteps
