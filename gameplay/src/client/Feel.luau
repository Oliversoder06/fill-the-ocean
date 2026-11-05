-- Sounds and splashes for scooping and pouring. Your own come from client/Action as they happen;
-- other players' come from their Carried attribute (up = a scoop landed, down = a pour landed).
-- All numbers live in shared/Cues. Sounds are baked into ReplicatedStorage.Audio and effects into
-- ReplicatedStorage.Vfx (Attachments whose ParticleEmitters carry a number attribute "Burst").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Cues = require(ReplicatedStorage.Shared.Cues)
local Hud = require(script.Parent.Hud)
local Action = require(script.Parent.Action)

local CLEANUP_SECONDS = 3
local OTHERS_RANGE = 150 -- studs; farther splashes from other players are skipped
local OTHERS_REACH = 30 -- studs the look ray from another player's head searches for the water

local player = Players.LocalPlayer
local Feel = {}

local rng = Random.new()

-- Waits for the baked folders, then checks every name the cues use. A missing one is a place bug.
local function checkAssets(): (Instance, Instance)
	local audio = ReplicatedStorage:WaitForChild("Audio", 10)
	assert(audio, "ReplicatedStorage.Audio is missing (the sounds are baked into the place)")
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	for _, cue in { Cues.scoop, Cues.pour } do
		local names = table.clone(cue.splashSounds)
		if (cue :: any).holdSound then
			table.insert(names, (cue :: any).holdSound)
		end
		for _, name in names do
			local sound = audio:WaitForChild(name, 10)
			assert(sound and sound:IsA("Sound"), `Audio is missing {name}`)
			assert(sound.SoundGroup, `Audio.{name} has no SoundGroup`)
		end
		local effect = vfx:WaitForChild(cue.vfx, 10)
		assert(effect and effect:IsA("Attachment"), `Vfx is missing {cue.vfx} (an Attachment)`)
		for _, emitter in effect:GetChildren() do
			if emitter:IsA("ParticleEmitter") then
				assert(type(emitter:GetAttribute("Burst")) == "number", `Vfx.{cue.vfx} needs a number attribute Burst on {emitter.Name}`)
			end
		end
	end
	return audio, vfx
end

local function scaled(sequence: NumberSequence, factor: number): NumberSequence
	local points = {}
	for _, k in sequence.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(k.Time, k.Value * factor, k.Envelope * factor))
	end
	return NumberSequence.new(points)
end

function Feel.start()
	local audio, vfx = checkAssets()

	local function splash(cue, at: Vector3, tier: number, own: boolean)
		local effect = (vfx :: any)[cue.vfx]:Clone() :: Attachment
		effect.Parent = workspace.Terrain
		effect.WorldPosition = at
		local size = Cues.size(tier) * cue.sizeScale
		local burstScale = if own then 1 else cue.otherBurstScale
		for _, emitter in effect:GetChildren() do
			if emitter:IsA("ParticleEmitter") then
				emitter.Size = scaled(emitter.Size, size)
				emitter:Emit(math.max(1, math.floor(emitter:GetAttribute("Burst") * size * burstScale + 0.5)))
			end
		end
		local sound = (audio :: any)[Cues.pick(cue.splashSounds, rng:NextNumber())]:Clone() :: Sound
		sound.PlaybackSpeed = Cues.between(cue.pitchMin, cue.pitchMax, rng:NextNumber()) * Cues.pitch(tier)
		sound.Volume = if own then cue.splashVolume else cue.otherVolume
		sound.Parent = if own then SoundService else effect -- own: flat and close; others: in the world
		sound:Play()
		task.delay(CLEANUP_SECONDS, function()
			sound:Destroy()
			effect:Destroy()
		end)
	end

	-- Own actions: a slosh that rises in pitch through each sweep, a splash where you aimed.
	local hold: Sound? = nil
	local holdAction: Action.Current? = nil
	local function stopHold()
		if hold then
			hold:Destroy()
			hold, holdAction = nil, nil
		end
	end
	Action.onStarted(function(action)
		stopHold()
		if action.kind == "scoop" then
			local sound = (audio :: any)[Cues.scoop.holdSound]:Clone() :: Sound
			sound.Looped = true
			sound.Volume = Cues.scoop.holdVolume
			sound.PlaybackSpeed = Cues.scoop.holdPitchFrom
			sound.Parent = SoundService
			sound:Play()
			hold, holdAction = sound, action
		end
	end)
	Action.onFinished(function(action)
		stopHold()
		local tier = player:GetAttribute("ToolTier") or 1
		splash(if action.kind == "scoop" then Cues.scoop else Cues.pour, action.hit, tier, true)
	end)
	RunService.RenderStepped:Connect(function()
		if hold and holdAction then
			local cue = Cues.scoop
			local p = math.clamp((os.clock() - holdAction.started) / holdAction.duration, 0, 1)
			hold.PlaybackSpeed = cue.holdPitchFrom + (cue.holdPitchTo - cue.holdPitchFrom) * p
		end
	end)

	-- Other players: splash where they are looking (their tool faces the water when it lands).
	local seeParams = RaycastParams.new()
	seeParams.FilterType = Enum.RaycastFilterType.Exclude
	local function othersPoint(character: Model, root: BasePart): Vector3?
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - root.Position).Magnitude > OTHERS_RANGE then
			return nil
		end
		local stage = Hud.currentStage()
		local ignore: { Instance } = { character }
		if camera then
			table.insert(ignore, camera)
		end
		if stage then
			for _, name in { "Source", "PourPoint" } do
				local part = stage:FindFirstChild(name)
				if part then
					table.insert(ignore, part)
				end
			end
		end
		seeParams.FilterDescendantsInstances = ignore
		local origin = root.Position + Vector3.new(0, 1.5, 0)
		local direction = (root.CFrame.LookVector - Vector3.new(0, 0.8, 0)).Unit * OTHERS_REACH
		local hit = workspace:Raycast(origin, direction, seeParams)
		return if hit then hit.Position else nil
	end

	local function watch(other: Player)
		if other == player then
			return
		end
		local last = other:GetAttribute("Carried") or 0
		other:GetAttributeChangedSignal("Carried"):Connect(function()
			local carried = other:GetAttribute("Carried") or 0
			local before = last
			last = carried
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (character and root and root:IsA("BasePart")) or math.abs(carried - before) <= 1e-9 then
				return
			end
			local at = othersPoint(character, root)
			if at then
				splash(if carried > before then Cues.scoop else Cues.pour, at, other:GetAttribute("ToolTier") or 1, false)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, other in Players:GetPlayers() do
		watch(other)
	end
end

return Feel
