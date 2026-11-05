-- The purchase moment. When a level is bought (its Level_<track> attribute goes up): a cash
-- register sting, coins fly from your money into the tile, and a "BOUGHT!" stamp slams onto it.
-- A buy you can't make shakes the Buy button with a dull thud (Shop calls Purchase.deny). A new
-- tool swings into your hand when the shop closes (client/Viewmodel) with sparkles and a chime;
-- speed upgrades whoosh and kick the field of view when the shop closes. Sounds and effects are
-- named in shared/Cues; the UI templates live in StarterGui.Hud.Templates.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local CoinBurst = require(ReplicatedStorage.Shared.CoinBurst)
local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Ease = require(ReplicatedStorage.Shared.Ease)
local Hud = require(script.Parent.Hud)
local Viewmodel = require(script.Parent.Viewmodel)

local MAX_FLY_COINS = 6
local COIN_SECONDS = 0.35
local COIN_STAGGER = 0.04
local COIN_SPREAD = 14 -- pixels of random start offset
local STAMP_FROM = 2.4 -- the stamp slams down from this size
local STAMP_HOLD = 0.7
local STAMP_FADE = 0.25
local SHAKE_SECONDS = 0.35
local SHAKE_CYCLES = 4
local SHAKE_DEGREES = 7
local FOV_KICK = 8
local SPEED_TRACKS = { walk = true, quick = true }
local SOUND_SECONDS = 3

local player = Players.LocalPlayer
local Purchase = {}

local denyButton: GuiObject? = nil
local denyRest = 0
local denyAt = -math.huge
local playDeny: (() -> ())? = nil

-- Shakes the Buy button: you can't buy this (not enough money, locked or maxed).
function Purchase.deny(button: GuiObject)
	if denyButton ~= button then
		if denyButton then
			denyButton.Rotation = denyRest
		end
		denyButton, denyRest = button, button.Rotation
	end
	denyAt = os.clock()
	if playDeny then
		playDeny()
	end
end

local function asset(folder: Instance, name: string, class: string): any
	local found = folder:WaitForChild(name, 10)
	assert(found and found:IsA(class), `{folder.Name} is missing {name} (a {class})`)
	return found
end

function Purchase.start()
	local cue = Cues.purchase
	local audio = ReplicatedStorage:WaitForChild("Audio", 10)
	assert(audio, "ReplicatedStorage.Audio is missing (the sounds are baked into the place)")
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local sounds = {}
	for _, name in { cue.sting, cue.deny, cue.unlock, cue.whoosh, Cues.coins.tickSound } do
		local sound = asset(audio, name, "Sound") :: Sound
		assert(sound.SoundGroup, `Audio.{name} has no SoundGroup`)
		sounds[name] = sound
	end
	local sparkle = asset(vfx, cue.sparkle, "Attachment") :: Attachment
	for _, emitter in sparkle:GetChildren() do
		if emitter:IsA("ParticleEmitter") then
			assert(type(emitter:GetAttribute("Burst")) == "number", `Vfx.{cue.sparkle} needs a number attribute Burst on {emitter.Name}`)
		end
	end

	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local shop = Hud.find(gui, "Shop") :: GuiObject
	local content = Hud.find(shop, "Body.Content")
	local moneyCoin = Hud.find(content, "Detail.MoneyRow.Coin") :: GuiObject
	local flyCoin = Hud.find(gui, "Templates.FlyCoin") :: GuiObject
	local stampTemplate = Hud.find(gui, "Templates.BoughtStamp") :: TextLabel
	Hud.find(stampTemplate, "Pop")
	local buttons: { [string]: GuiObject } = {}
	for _, track in Config.tracks do
		local panel = if track.panel == "tool" then "ToolPanel" else "BoostPanel"
		buttons[track.id] = Hud.find(content, `{panel}.Tiles.{track.id}.Button`)
	end

	local function play(name: string, volume: number, speed: number)
		local sound = sounds[name]:Clone()
		sound.Volume = volume
		sound.PlaybackSpeed = speed
		sound.Parent = SoundService
		sound:Play()
		task.delay(SOUND_SECONDS, sound.Destroy, sound)
	end

	playDeny = function()
		play(cue.deny, cue.denyVolume, 1)
	end

	local function centre(object: GuiObject): Vector2
		return object.AbsolutePosition + object.AbsoluteSize / 2
	end

	local function stamp(button: GuiObject)
		local label = stampTemplate:Clone()
		local pop = (label :: any).Pop :: UIScale
		label.Visible = true
		pop.Scale = STAMP_FROM
		label.Parent = button
		TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local fade = TweenInfo.new(STAMP_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, STAMP_HOLD)
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end
		task.delay(STAMP_HOLD + STAMP_FADE, label.Destroy, label)
	end

	-- Coins leave your money and land in the tile; the stamp slams when the last one lands.
	local function payInto(button: GuiObject, cost: number)
		local from, to = centre(moneyCoin), centre(button)
		local n = math.min(MAX_FLY_COINS, CoinBurst.count(cost))
		local rng = Random.new()
		for i = 1, n do
			local coin = flyCoin:Clone()
			local start = from + Vector2.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * COIN_SPREAD
			coin.Position = UDim2.fromOffset(start.X, start.Y)
			coin.Visible = true
			coin.Parent = gui
			local info = TweenInfo.new(COIN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, (i - 1) * COIN_STAGGER)
			local tween = TweenService:Create(coin, info, { Position = UDim2.fromOffset(to.X, to.Y) })
			tween.Completed:Once(function()
				coin:Destroy()
				play(Cues.coins.tickSound, Cues.coins.tickVolume, CoinBurst.tickPitch(i))
				if i == n then
					stamp(button)
				end
			end)
			tween:Play()
		end
	end

	local speedPending = false
	local kickBase: number? = nil
	local function speedUp()
		play(cue.whoosh, cue.whooshVolume, 1)
		local camera = workspace.CurrentCamera
		local base = kickBase or camera.FieldOfView
		kickBase = base
		local out = TweenService:Create(camera, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base + FOV_KICK })
		out.Completed:Once(function()
			local back = TweenService:Create(camera, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base })
			back.Completed:Once(function()
				kickBase = nil
			end)
			back:Play()
		end)
		out:Play()
	end

	local function bought(id: string, level: number)
		local track = Config.track(id)
		local cost = track and track.levels[level] and track.levels[level].cost or 0
		play(cue.sting, cue.stingVolume, 1)
		if shop.Visible then
			payInto(buttons[id], cost)
		end
		if SPEED_TRACKS[id] then
			speedPending = true
		end
	end

	for _, track in Config.tracks do
		local attribute = `Level_{track.id}`
		local last = player:GetAttribute(attribute) or 0
		player:GetAttributeChangedSignal(attribute):Connect(function()
			local level = player:GetAttribute(attribute) or 0
			if level > last then
				bought(track.id, level)
			end
			last = level
		end)
	end

	Viewmodel.onReveal(function(model)
		play(cue.unlock, cue.unlockVolume, 1)
		local effect = sparkle:Clone()
		effect.Parent = model:FindFirstChildWhichIsA("BasePart", true) or workspace.Terrain -- follows the tool
		effect.WorldPosition = model:GetPivot().Position
		for _, emitter in effect:GetChildren() do
			if emitter:IsA("ParticleEmitter") then
				emitter:Emit(emitter:GetAttribute("Burst"))
			end
		end
		task.delay(SOUND_SECONDS, effect.Destroy, effect)
	end)

	RunService.RenderStepped:Connect(function()
		if denyButton then
			local t = (os.clock() - denyAt) / SHAKE_SECONDS
			Hud.set(denyButton, "Rotation", denyRest + Ease.shake(t, SHAKE_CYCLES, SHAKE_DEGREES))
		end
		if speedPending and not shop.Visible then
			speedPending = false
			speedUp()
		end
	end)
end

return Purchase
