-- Music: one looping track per stage, a faster one for the final push and a calm one for waiting
-- and results (which one: Cues.musicTrack). Tracks crossfade over Cues.music.fadeSeconds; a track
-- that fades out pauses and picks up where it left off next time. The music ducks under stage
-- cards and, through Music.duck, under purchases. Sounds are baked into ReplicatedStorage.Audio
-- and play through SoundService.Music.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)

local SILENT = 0.005 -- a fade snaps to its target within this volume; silent tracks pause

local Music = {}

local duckUntil = -math.huge

-- Lowers the music for `seconds` so a big moment reads over it.
function Music.duck(seconds: number)
	duckUntil = math.max(duckUntil, os.clock() + seconds)
end

function Music.start()
	local cue = Cues.music
	local audio = ReplicatedStorage:WaitForChild("Audio", 10)
	assert(audio, "ReplicatedStorage.Audio is missing (the sounds are baked into the place)")
	local tracks: { [string]: Sound } = {}
	for key, name in cue.tracks do
		local template = audio:WaitForChild(name, 10)
		assert(template and template:IsA("Sound"), `Audio is missing {name} (a Sound)`)
		assert(template.SoundGroup, `Audio.{name} has no SoundGroup`)
		local sound = template:Clone()
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = SoundService
		tracks[key] = sound
	end
	for _, stage in Config.stages do
		assert(tracks[stage.name], `Cues.music.tracks has no track for {stage.name}`)
	end

	local duckLevel = 1
	RunService.Heartbeat:Connect(function(dt)
		local phase = ReplicatedStorage:GetAttribute("Phase")
		local index = ReplicatedStorage:GetAttribute("Stage")
		local stage = type(index) == "number" and Config.stages[index] or nil
		local fill = ReplicatedStorage:GetAttribute("Fill")
		local want = Cues.musicTrack(
			if type(phase) == "string" then phase else nil,
			if stage then stage.name else nil,
			index == #Config.stages,
			if type(fill) == "number" then fill else 0
		)

		local ducked = phase == "card" or os.clock() < duckUntil
		local k = 1 - math.exp(-dt * 3 / cue.fadeSeconds) -- about 95% of the way in fadeSeconds
		duckLevel += ((if ducked then cue.duck else 1) - duckLevel) * math.min(1, k * 4) -- ducking is quicker than a crossfade
		for key, sound in tracks do
			local target = if key == want then cue.volume * duckLevel else 0
			local v = sound.Volume + (target - sound.Volume) * k
			if math.abs(target - v) < SILENT then
				v = target -- snap, or the tail of the fade never quite arrives
			end
			if v ~= sound.Volume then
				sound.Volume = v
			end
			if v > 0 and not sound.IsPlaying then
				sound:Resume()
			elseif v == 0 and sound.IsPlaying then
				sound:Pause()
			end
		end
	end)
end

return Music
