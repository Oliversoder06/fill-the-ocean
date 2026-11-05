-- Footsteps. Yours land on each dip of the camera bob (client/CameraFeel), so the sound and the
-- view move together; other players step every Steps.STRIDE studs they walk. The sound follows
-- the floor (shared/Steps), and carrying water makes your steps heavier. Dry floors puff dust
-- (Footsteps.dust, also used by client/Bodies on landing). Roblox's default running
-- sound is muted on every character so it doesn't play under ours. Names and volumes in
-- shared/Cues; the sounds are baked into ReplicatedStorage.Audio, the dust into ReplicatedStorage.Vfx.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Cues = require(ReplicatedStorage.Shared.Cues)
local Steps = require(ReplicatedStorage.Shared.Steps)
local CameraFeel = require(script.Parent.CameraFeel)

local OTHERS_RANGE = 120 -- studs; farther players' steps are skipped
local SOUND_SECONDS = 2
local DUST_SECONDS = 1.5
local DEFAULT_RUNNING = "Running" -- the sound Roblox's character sounds script adds to the root

local player = Players.LocalPlayer
local Footsteps = {}

-- A puff of dust at a humanoid's feet if the floor is dry; `scale` multiplies a step's puff.
function Footsteps.dust(humanoid: Humanoid, scale: number)
	local cue = Cues.steps
	local root = humanoid.RootPart
	local vfx = ReplicatedStorage:FindFirstChild("Vfx")
	local template = vfx and vfx:FindFirstChild(cue.dust)
	if not (root and template and cue.dustSurfaces[Steps.surface(humanoid.FloorMaterial.Name)]) then
		return
	end
	local effect = (template :: Attachment):Clone()
	effect.Parent = workspace.Terrain
	effect.WorldPosition = root.Position - Vector3.new(0, root.Size.Y / 2 + humanoid.HipHeight, 0)
	for _, emitter in effect:GetChildren() do
		if emitter:IsA("ParticleEmitter") then
			emitter:Emit(math.max(1, math.floor(emitter:GetAttribute("Burst") * scale + 0.5)))
		end
	end
	task.delay(DUST_SECONDS, effect.Destroy, effect)
end

function Footsteps.start()
	local cue = Cues.steps
	local audio = ReplicatedStorage:WaitForChild("Audio", 10)
	assert(audio, "ReplicatedStorage.Audio is missing (the sounds are baked into the place)")
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local dust = vfx:WaitForChild(cue.dust, 10)
	assert(dust and dust:IsA("Attachment"), `Vfx is missing {cue.dust} (an Attachment)`)
	for _, emitter in dust:GetChildren() do
		if emitter:IsA("ParticleEmitter") then
			assert(type(emitter:GetAttribute("Burst")) == "number", `Vfx.{cue.dust} needs a number attribute Burst on {emitter.Name}`)
		end
	end
	local sounds: { [string]: Sound } = {}
	for _, list in cue.surfaces do
		for _, name in list do
			local sound = audio:WaitForChild(name, 10)
			assert(sound and sound:IsA("Sound"), `Audio is missing {name} (a Sound)`)
			assert(sound.SoundGroup, `Audio.{name} has no SoundGroup`)
			sounds[name] = sound
		end
	end
	local rng = Random.new()
	local lastName: string? = nil

	local function step(material: Enum.Material, parent: Instance, volume: number, pitch: number)
		local list = cue.surfaces[Steps.surface(material.Name)]
		local name = Cues.pickNext(list, rng:NextNumber(), lastName)
		lastName = name
		local sound = sounds[name]:Clone()
		sound.Volume = volume * sounds[name].Volume -- the template's Volume evens out its set
		sound.PlaybackSpeed = Cues.between(cue.pitchMin, cue.pitchMax, rng:NextNumber()) * pitch
		sound.Parent = parent
		sound:Play()
		task.delay(SOUND_SECONDS, sound.Destroy, sound)
	end

	CameraFeel.onStep(function(humanoid)
		local carrying = (player:GetAttribute("Carried") or 0) > 0
		step(
			humanoid.FloorMaterial,
			SoundService,
			cue.volume * (if carrying then cue.carryVolume else 1),
			if carrying then cue.carryPitch else 1
		)
		Footsteps.dust(humanoid, 1)
	end)

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

	-- Other players: a step every stride they walk on the ground.
	local walked: { [Player]: number } = {}
	local lastPos: { [Player]: Vector3 } = {}
	Players.PlayerRemoving:Connect(function(other)
		walked[other], lastPos[other] = nil, nil
	end)
	RunService.Heartbeat:Connect(function()
		local camera = workspace.CurrentCamera
		for _, other in Players:GetPlayers() do
			if other == player then
				continue
			end
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
			walked[other] = (walked[other] or 0) + Vector3.new(pos.X - before.X, 0, pos.Z - before.Z).Magnitude
			if walked[other] >= Steps.STRIDE then
				walked[other] = 0
				if camera and (camera.CFrame.Position - pos).Magnitude <= OTHERS_RANGE then
					step(humanoid.FloorMaterial, root, cue.otherVolume, 1)
					Footsteps.dust(humanoid, 1)
				end
			end
		end
	end)
end

return Footsteps
