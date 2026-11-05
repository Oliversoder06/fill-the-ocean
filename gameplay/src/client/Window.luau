-- Opens and closes a window the same way everywhere, matched to the GUI reference clip: the frame
-- pops in from small, then each descendant with a number attribute "Reveal" pops in through its
-- one UIScale child, layer by layer (timing in shared/Reveal). Decorations (Reveal 4 and up) also
-- swing into place and land together with the last item. Closing is one quick shrink.
-- Don't put Reveal on a child of a UIListLayout/UIGridLayout: its scale moves its siblings; mark
-- what is inside it instead. The window's root UIScale (`fit`) also fits it to the screen.
-- Opening and closing play a whoosh (Cues.window).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Cues = require(ReplicatedStorage.Shared.Cues)
local Reveal = require(ReplicatedStorage.Shared.Reveal)

local SOUND_SECONDS = 2

export type Window = {
	open: (fitScale: number) -> (),
	close: (fitScale: number) -> (),
}

local Window = {}

local whoosh: Sound? = nil

local function playWhoosh(volume: number, pitch: number)
	if not whoosh then
		local audio = ReplicatedStorage:FindFirstChild("Audio")
		local found = audio and audio:FindFirstChild(Cues.window.whoosh)
		assert(found and found:IsA("Sound"), `ReplicatedStorage.Audio is missing {Cues.window.whoosh} (a Sound)`)
		whoosh = found
	end
	local sound = (whoosh :: Sound):Clone()
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.Parent = SoundService
	sound:Play()
	task.delay(SOUND_SECONDS, sound.Destroy, sound)
end

function Window.new(root: GuiObject, fit: UIScale): Window
	local parts: { UIScale } = {}
	local orders: { number } = {}
	local spins: { [number]: { gui: GuiObject, rest: number, turn: number } } = {}
	local decorCount = 0
	for _, d in root:GetDescendants() do
		local order = d:GetAttribute("Reveal")
		if order ~= nil then
			assert(type(order) == "number", `{d:GetFullName()}: the Reveal attribute must be a number`)
			local scales = {}
			for _, child in d:GetChildren() do
				if child:IsA("UIScale") then
					table.insert(scales, child)
				end
			end
			assert(#scales == 1, `{d:GetFullName()} has a Reveal attribute, so it needs exactly one UIScale (has {#scales})`)
			local parent = d.Parent
			assert(
				not (parent and (parent:FindFirstChildOfClass("UIListLayout") or parent:FindFirstChildOfClass("UIGridLayout"))),
				`{d:GetFullName()} is in a layout; its Reveal scale would move its siblings`
			)
			table.insert(parts, scales[1])
			table.insert(orders, order)
			if math.floor(order) >= Reveal.DECOR_LAYER and d:IsA("GuiObject") then
				decorCount += 1
				spins[#parts] = { gui = d, rest = d.Rotation, turn = Reveal.spin(decorCount) }
			end
		end
	end
	local delays, durations = Reveal.plan(orders)
	local frameIn = TweenInfo.new(Reveal.FRAME_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local frameOut = TweenInfo.new(Reveal.CLOSE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local playing: { Tween } = {}
	local token = 0

	local function play(tween: Tween)
		tween:Play()
		table.insert(playing, tween)
	end

	local function stop()
		for _, tween in playing do
			tween:Cancel()
		end
		table.clear(playing)
	end

	local window = {}

	function window.open(fitScale: number)
		token += 1
		stop()
		root.Visible = true
		playWhoosh(Cues.window.openVolume, Cues.window.openPitch)
		fit.Scale = fitScale * Reveal.FRAME_FROM
		play(TweenService:Create(fit, frameIn, { Scale = fitScale }))
		for i, scale in parts do
			scale.Scale = 0
			local info = TweenInfo.new(durations[i], Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delays[i])
			play(TweenService:Create(scale, info, { Scale = 1 }))
			local spin = spins[i]
			if spin then -- decorations also swing into place
				spin.gui.Rotation = spin.rest + spin.turn
				play(TweenService:Create(spin.gui, info, { Rotation = spin.rest }))
			end
		end
	end

	function window.close(fitScale: number)
		token += 1
		stop()
		local mine = token
		playWhoosh(Cues.window.closeVolume, Cues.window.closePitch)
		for _, scale in parts do
			scale.Scale = 1
		end
		for _, spin in spins do
			spin.gui.Rotation = spin.rest
		end
		play(TweenService:Create(fit, frameOut, { Scale = fitScale * Reveal.CLOSE_FROM }))
		task.delay(Reveal.CLOSE_SECONDS, function()
			if token == mine then
				root.Visible = false
			end
		end)
	end

	return window
end

return Window
