-- Ambience: one looping bed (surf and gulls; LobbyCues.ambience) that fades in once started. The
-- sound is in ReplicatedStorage.Audio; it plays through its SoundGroup.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local LobbyCues = require(ReplicatedStorage.Shared.LobbyCues)
local Sfx = require(script.Parent.Sfx)

local Ambience = {}

function Ambience.start()
	local cue = LobbyCues.ambience
	local bed = Sfx.need(cue.bed):Clone()
	bed.Looped = true
	bed.Volume = 0
	bed.Parent = SoundService
	bed:Play()

	local fading: RBXScriptConnection? = nil
	fading = RunService.Heartbeat:Connect(function(dt)
		local k = 1 - math.exp(-dt * 3 / cue.fadeSeconds) -- about 95% of the way in fadeSeconds
		local v = bed.Volume + (cue.volume - bed.Volume) * k
		if math.abs(cue.volume - v) < 0.002 then
			v = cue.volume -- arrived: nothing left to ease
			if fading then
				fading:Disconnect()
			end
		end
		bed.Volume = v
	end)
end

return Ambience
