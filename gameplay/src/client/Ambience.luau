-- Ambience: one looping bed per stage (birds in the pool's backyard, a lakeside dock, surf and
-- gulls at the ocean) and a heat layer (cicadas). A dry basin sounds hot and quiet; as it fills,
-- the heat fades and the bed comes back to life (Cues.ambienceMix). Beds crossfade when the stage
-- changes. Names and volumes in shared/Cues; the sounds are baked into ReplicatedStorage.Audio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)

local Ambience = {}

function Ambience.start()
	local cue = Cues.ambience
	local audio = ReplicatedStorage:WaitForChild("Audio", 10)
	assert(audio, "ReplicatedStorage.Audio is missing (the sounds are baked into the place)")

	local function loop(name: string): Sound
		local template = audio:WaitForChild(name, 10)
		assert(template and template:IsA("Sound"), `Audio is missing {name} (a Sound)`)
		assert(template.SoundGroup, `Audio.{name} has no SoundGroup`)
		local sound = template:Clone()
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = SoundService
		sound:Play()
		return sound
	end

	local beds: { [string]: Sound } = {}
	for _, stage in Config.stages do
		local name = cue.beds[stage.name]
		assert(name, `Cues.ambience.beds has no bed for {stage.name}`)
		beds[stage.name] = loop(name)
	end
	local heat = loop(cue.heat)
	local lastStage = Config.stages[1].name

	RunService.Heartbeat:Connect(function(dt)
		local index = ReplicatedStorage:GetAttribute("Stage")
		local stage = type(index) == "number" and Config.stages[index]
		if stage then
			lastStage = stage.name -- before the run: the pool; after it: stay where it ended
		end
		local fill = ReplicatedStorage:GetAttribute("Fill")
		local life, hot = Cues.ambienceMix(if type(fill) == "number" then fill else 0)
		local k = 1 - math.exp(-dt * 3 / cue.fadeSeconds) -- about 95% of the way in fadeSeconds
		local function ease(sound: Sound, target: number)
			local v = sound.Volume + (target - sound.Volume) * k
			if math.abs(v - sound.Volume) > 1e-4 then
				sound.Volume = v
			end
		end
		for name, sound in beds do
			ease(sound, if name == lastStage then cue.bedVolume * life else 0)
		end
		ease(heat, cue.heatVolume * hot)
	end)
end

return Ambience
