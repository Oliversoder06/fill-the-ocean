-- Button and window sounds for the lobby HUD (LobbyCues.ui): client/Session calls hover and press
-- from its button juice, deny from its wobble and window from its show; init's toast calls toast.
-- Calls made before start has its sounds (the first moment after joining) play nothing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyCues = require(ReplicatedStorage.Shared.LobbyCues)
local Sfx = require(script.Parent.Sfx)

local UiSounds = {}

local cue = LobbyCues.ui
local ready = false
local lastHover = -math.huge

function UiSounds.start()
	Sfx.need(cue.click)
	Sfx.need(cue.whoosh)
	Sfx.need(cue.deny)
	ready = true
end

function UiSounds.hover()
	local now = os.clock()
	if not ready or now - lastHover < cue.hoverGap then
		return
	end
	lastHover = now
	Sfx.play(cue.click, { volume = cue.hoverVolume, pitch = cue.hoverPitch })
end

function UiSounds.press()
	if ready then
		Sfx.play(cue.click, { volume = cue.clickVolume })
	end
end

function UiSounds.deny()
	if ready then
		Sfx.play(cue.deny, { volume = cue.denyVolume })
	end
end

function UiSounds.window(open: boolean)
	if ready then
		Sfx.play(cue.whoosh, {
			volume = if open then cue.openVolume else cue.closeVolume,
			pitch = if open then cue.openPitch else cue.closePitch,
		})
	end
end

function UiSounds.toast()
	if ready then
		Sfx.play(cue.click, { volume = cue.toastVolume, pitch = cue.toastPitch })
	end
end

return UiSounds
