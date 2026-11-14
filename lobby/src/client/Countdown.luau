-- Countdown: the launch's 3-2-1. server/Queue counts a party down before it teleports and sends each
-- member SessionState "countdown" with endsAt (server time). LobbyHud.Countdown (a TextLabel with a
-- UIScale Pop, built in Studio) shows each whole second as it lands, with a tick that climbs and the
-- music ducked under it. At 0: "GO!", a chime, a whoosh, a sparkle on your pad and the music fading out
-- (client/Music). A state that moves on before 0 means it was stopped (someone left): the number
-- shrinks away with a buzz and the music comes back. After 0 the music stays out while the launch runs
-- ("launching", "teleporting") and comes back if the party ends up on the pad again.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LobbyCues = require(ReplicatedStorage.Shared.LobbyCues)
local SessionRules = require(ReplicatedStorage.Common.SessionRules)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Music = require(script.Parent.Music)
local Pads = require(script.Parent.Pads)
local Sfx = require(script.Parent.Sfx)

local CLEANUP_SECONDS = 2
local LAUNCH_KINDS = { launching = true, teleporting = true } -- states of a launch that went

local player = Players.LocalPlayer
local Countdown = {}

function Countdown.start()
	local cue = LobbyCues.countdown
	for _, name in { cue.tick, cue.go, cue.whoosh, cue.cancel } do
		Sfx.need(name)
	end
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("LobbyHud")
	local label = hud:WaitForChild("Countdown", 10)
	assert(label and label:IsA("TextLabel"), "LobbyHud is missing Countdown (a TextLabel, built in Studio)")
	local pop = label:FindFirstChild("Pop")
	assert(pop and pop:IsA("UIScale"), "LobbyHud.Countdown is missing its UIScale Pop (built in Studio)")
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	local sparkle = vfx and vfx:WaitForChild(cue.sparkle, 10)
	assert(sparkle and sparkle:IsA("Attachment"), `ReplicatedStorage.Vfx is missing {cue.sparkle} (an Attachment)`)
	for _, emitter in sparkle:GetChildren() do
		if emitter:IsA("ParticleEmitter") then
			assert(type(emitter:GetAttribute("Burst")) == "number", `Vfx.{cue.sparkle} needs a number attribute Burst on {emitter.Name}`)
		end
	end
	local stateEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SessionState") :: RemoteEvent
	label.Visible = false

	local landing = TweenInfo.new(Theme.motion.openSeconds * 1.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local shrinking = TweenInfo.new(Theme.motion.closeSeconds * 1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local endsAt: number? = nil -- a countdown on screen
	local shown: number? = nil
	local leaving = false -- it reached 0: the music stays out while the launch runs
	local token = 0 -- bumped by every land, so a stale shrink doesn't hide a newer number

	local function land(text: string)
		token += 1
		label.Text = text
		label.Visible = true
		pop.Scale = cue.pop
		TweenService:Create(pop, landing, { Scale = 1 }):Play()
	end

	local function shrink()
		local mine = token
		local tween = TweenService:Create(pop, shrinking, { Scale = 0 })
		tween.Completed:Once(function()
			if token == mine then
				label.Visible = false
			end
		end)
		tween:Play()
	end

	local function sparkleOnPad()
		local pad = Pads.padOf(player)
		local water = pad and pad:FindFirstChild("Water")
		if not (water and water:IsA("BasePart")) then
			return
		end
		local effect = (sparkle :: Attachment):Clone()
		effect.Parent = workspace.Terrain
		effect.WorldPosition = water.Position + Vector3.new(0, 1, 0)
		for _, emitter in effect:GetChildren() do
			if emitter:IsA("ParticleEmitter") then
				emitter:Emit(emitter:GetAttribute("Burst"))
			end
		end
		task.delay(CLEANUP_SECONDS, effect.Destroy, effect)
	end

	stateEvent.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		local kind = state.kind
		if kind == "countdown" and type(state.endsAt) == "number" then
			endsAt, shown = state.endsAt, nil
			return
		end
		if endsAt then
			-- moved on before 0: the countdown was stopped
			endsAt = nil
			shrink()
			Sfx.play(cue.cancel, { volume = cue.cancelVolume })
			Music.resume()
		elseif leaving and not LAUNCH_KINDS[kind] then
			leaving = false -- the launch didn't go: back on the pad, or off it
			Music.resume()
		end
	end)

	RunService.Heartbeat:Connect(function()
		local ends = endsAt
		if not ends then
			return
		end
		local n = LobbyCues.countdownNumber(ends, workspace:GetServerTimeNow())
		if n == shown then
			return
		end
		shown = n
		if n > 0 then
			land(tostring(n))
			Sfx.play(cue.tick, {
				volume = cue.tickVolume,
				pitch = cue.tickPitch + cue.tickPitchStep * math.max(0, SessionRules.COUNTDOWN - n),
			})
			Music.duck(cue.duckSeconds)
			return
		end
		endsAt = nil
		leaving = true
		land("GO!")
		Sfx.play(cue.go, { volume = cue.goVolume })
		Sfx.play(cue.whoosh, { volume = cue.whooshVolume })
		Music.fadeOut()
		sparkleOnPad()
		local mine = token
		task.delay(cue.goSeconds, function()
			if token == mine then
				shrink()
			end
		end)
	end)
end

return Countdown
