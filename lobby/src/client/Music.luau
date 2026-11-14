-- Music: the lobby's looping track (LobbyCues.music). It fades in once started, ducks under the
-- launch countdown (Music.duck), fades out as the party leaves (Music.fadeOut) and comes back when that
-- launch is called off (Music.resume). The sound is in ReplicatedStorage.Audio; it plays through its
-- SoundGroup.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local LobbyCues = require(ReplicatedStorage.Shared.LobbyCues)
local Sfx = require(script.Parent.Sfx)

local SILENT = 0.005 -- a fade snaps to its target within this volume; a silent track pauses

local Music = {}

local duckUntil = -math.huge
local leaving = false

-- Lowers the music for `seconds` so a big moment reads over it.
function Music.duck(seconds: number)
	duckUntil = math.max(duckUntil, os.clock() + seconds)
end

-- Fades the track out (the party is leaving for a run).
function Music.fadeOut()
	leaving = true
end

-- Brings the track back after fadeOut (the launch didn't go).
function Music.resume()
	leaving = false
end

function Music.start()
	local cue = LobbyCues.music
	local sound = Sfx.need(cue.track):Clone()
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService

	local duckLevel = 1
	RunService.Heartbeat:Connect(function(dt)
		local seconds = if leaving then cue.outSeconds else cue.fadeSeconds
		local k = 1 - math.exp(-dt * 3 / seconds) -- about 95% of the way in `seconds`
		local ducked = os.clock() < duckUntil
		duckLevel += ((if ducked then cue.duck else 1) - duckLevel) * math.min(1, k * 4) -- ducking is quicker than a fade
		local target = if leaving then 0 else cue.volume * duckLevel
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
	end)
end

return Music
