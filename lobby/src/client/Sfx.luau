-- One-shot sounds from ReplicatedStorage.Audio (built in the lobby place). A module asks for its
-- sounds once when it starts (Sfx.need waits for them to replicate and checks them), so playing never
-- yields. Volumes multiply the template's own Volume (it evens out a matched set); each copy plays
-- through the template's SoundGroup, 2D, or 3D from a point in the world.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local WAIT_SECONDS = 10
local TAIL_SECONDS = 0.5 -- past a sound's end before its copy goes
local BACKSTOP_SECONDS = 10 -- a copy whose length isn't known yet goes after this

local Sfx = {}

export type Options = {
	volume: number,
	pitch: number?,
	at: Vector3?, -- 3D from here; nil plays it 2D
	rollOffMin: number?,
	rollOffMax: number?,
}

local templates: { [string]: Sound } = {}

function Sfx.need(name: string): Sound
	local cached = templates[name]
	if cached then
		return cached
	end
	local audio = ReplicatedStorage:WaitForChild("Audio", WAIT_SECONDS)
	assert(audio, "ReplicatedStorage.Audio is missing (the sounds are built into the lobby place)")
	local sound = audio:WaitForChild(name, WAIT_SECONDS)
	assert(sound and sound:IsA("Sound"), `ReplicatedStorage.Audio is missing {name} (a Sound)`)
	assert(sound.SoundGroup, `Audio.{name} has no SoundGroup`)
	templates[name] = sound
	return sound
end

function Sfx.play(name: string, options: Options): Sound
	local template = templates[name]
	assert(template, `Sfx.play("{name}") before Sfx.need("{name}")`)
	local sound = template:Clone()
	sound.Volume = options.volume * template.Volume
	sound.PlaybackSpeed = options.pitch or 1
	local spot: Attachment? = nil
	if options.at then
		local attachment = Instance.new("Attachment")
		attachment.Name = `Sfx_{name}`
		attachment.Parent = workspace.Terrain
		attachment.WorldPosition = options.at
		spot = attachment
		if options.rollOffMin then
			sound.RollOffMinDistance = options.rollOffMin
		end
		if options.rollOffMax then
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMaxDistance = options.rollOffMax
		end
		sound.Parent = attachment
	else
		sound.Parent = SoundService
	end
	sound:Play()
	local function remove()
		sound:Destroy()
		if spot then
			spot:Destroy()
		end
	end
	sound.Ended:Once(remove)
	-- in case it never plays (an asset that failed to load): the template's length once known
	local speed = math.max(sound.PlaybackSpeed, 0.1)
	task.delay(if template.TimeLength > 0 then template.TimeLength / speed + TAIL_SECONDS else BACKSTOP_SECONDS, remove)
	return sound
end

return Sfx
