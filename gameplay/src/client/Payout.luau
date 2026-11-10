-- Your payout as coins. When your Earned goes up (your own pours, hose and vehicle; the coins go into
-- the team's Wallet), coins burst out of the water you just poured into,
-- land around you, then fly into the wallet one by one with a rising tick, and the wallet counts up
-- as each one lands (Hud.walletHold). A "+amount" pops up where they burst. Maths in
-- shared/CoinBurst; sounds and templates named in shared/Cues, baked into ReplicatedStorage.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local CoinBurst = require(ReplicatedStorage.Shared.CoinBurst)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Hud = require(script.Parent.Hud)
local Action = require(script.Parent.Action)

local POUR_MEMORY = 2 -- seconds a pour's aim point stays the burst origin
local SCATTER_MIN, SCATTER_MAX = 1.5, 3.5 -- studs from the player where coins land
local MAX_LIFE = 4 -- seconds; a coin still out by then goes straight to the wallet
local SPIN = 9 -- radians per second
local FLY_DEPTH = 3 -- studs in front of the camera where a coin disappears into the wallet
local FLY_ARC = 1.5
local BOUNCE = 0.35 -- share of the fall speed kept on a bounce
local POP_RISE = 3
local POP_SECONDS = 0.9
local SOUND_SECONDS = 2

type Coin = {
	part: BasePart,
	size: Vector3,
	value: number,
	index: number,
	born: number,
	flyAt: number,
	pos: Vector3,
	vel: Vector3,
	ground: number,
	spin: number,
	flyFrom: Vector3?,
}

local player = Players.LocalPlayer
local Payout = {}

local function asset(folder: Instance, name: string, class: string): any
	local found = folder:WaitForChild(name, 10)
	assert(found and found:IsA(class), `{folder.Name} is missing {name} (a {class})`)
	return found
end

function Payout.start()
	local cue = Cues.coins
	local audio = ReplicatedStorage:WaitForChild("Audio", 10)
	assert(audio, "ReplicatedStorage.Audio is missing (the sounds are baked into the place)")
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local coinTemplate = asset(vfx, cue.coin, "BasePart") :: BasePart
	local popTemplate = asset(vfx, cue.pop, "Attachment") :: Attachment
	local popLabel = Hud.find(popTemplate, "Gui.Amount")
	Hud.find(popTemplate, "Gui.Pop")
	local tickSound = asset(audio, cue.tickSound, "Sound") :: Sound
	local burstSound = asset(audio, cue.burstSound, "Sound") :: Sound
	for _, sound in { tickSound, burstSound } do
		assert(sound.SoundGroup, `Audio.{sound.Name} has no SoundGroup`)
	end
	assert(popLabel:IsA("TextLabel"), `Vfx.{cue.pop}.Gui.Amount must be a TextLabel`)

	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local walletCoin = Hud.find(gui, "Wallet.Coin")
	local rng = Random.new()
	local coins: { Coin } = {}

	local function play(template: Sound, volume: number, speed: number)
		local sound = template:Clone()
		sound.Volume = volume
		sound.PlaybackSpeed = speed
		sound.Parent = SoundService
		sound:Play()
		task.delay(SOUND_SECONDS, sound.Destroy, sound)
	end

	-- The world point just in front of the camera that sits over the wallet's coin icon.
	local function walletPoint(camera: Camera): Vector3
		local centre = walletCoin.AbsolutePosition + walletCoin.AbsoluteSize / 2
		local inset = if gui.IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset()
		local ray = camera:ViewportPointToRay(centre.X + inset.X, centre.Y + inset.Y)
		return ray.Origin + ray.Direction * FLY_DEPTH
	end

	local function popUp(at: Vector3, amount: number)
		local pop = popTemplate:Clone()
		pop.Parent = workspace.Terrain
		pop.WorldPosition = at
		local label = (pop :: any).Gui.Amount :: TextLabel
		local scale = (pop :: any).Gui.Pop :: UIScale
		label.Text = `+{Hud.money(amount)}`
		scale.Scale = 0.4
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local rise = TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(pop, rise, { WorldPosition = at + Vector3.new(0, POP_RISE, 0) }):Play()
		local fade = TweenInfo.new(POP_SECONDS * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, POP_SECONDS * 0.6)
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end
		task.delay(POP_SECONDS, pop.Destroy, pop)
	end

	local lastPour: Vector3? = nil
	local lastPourAt = -math.huge
	Action.onStarted(function(action)
		if action.kind == "pour" then
			lastPour, lastPourAt = action.hit, os.clock()
		end
	end)

	local function burst(amount: number)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and root:IsA("BasePart") and humanoid) then
			return -- no one to fly to: the wallet just shows the new total
		end
		local now = os.clock()
		local origin = if lastPour and now - lastPourAt < POUR_MEMORY
			then lastPour
			else root.Position + root.CFrame.LookVector * 6
		local radius = coinTemplate.Size.Y / 2
		local ground = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight + radius
		local n = CoinBurst.count(amount)
		Hud.walletHold += amount
		play(burstSound, cue.burstVolume, rng:NextNumber(0.95, 1.05))
		popUp(origin + Vector3.new(0, 2, 0), amount)
		for i, value in CoinBurst.split(amount, n) do
			local angle = rng:NextNumber(0, 2 * math.pi)
			local distance = rng:NextNumber(SCATTER_MIN, SCATTER_MAX)
			local landAt = Vector3.new(root.Position.X + math.cos(angle) * distance, 0, root.Position.Z + math.sin(angle) * distance)
			local air = CoinBurst.AIR_SECONDS * rng:NextNumber(0.85, 1.15)
			local flat = Vector3.new(landAt.X - origin.X, 0, landAt.Z - origin.Z) / air
			local vy = CoinBurst.launchVertical(ground - origin.Y, air, CoinBurst.GRAVITY)
			local part = coinTemplate:Clone()
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CFrame = CFrame.new(origin)
			part.Parent = workspace
			table.insert(coins, {
				part = part,
				size = part.Size,
				value = value,
				index = i,
				born = now,
				flyAt = CoinBurst.flyAt(i),
				pos = origin,
				vel = flat + Vector3.new(0, vy, 0),
				ground = ground,
				spin = rng:NextNumber(0, 2 * math.pi),
			})
		end
	end

	local function arrive(coin: Coin)
		Hud.walletHold = math.max(0, Hud.walletHold - coin.value)
		play(tickSound, cue.tickVolume, CoinBurst.tickPitch(coin.index))
		coin.part:Destroy()
	end

	local lastEarned = player:GetAttribute("Earned") or 0
	player:GetAttributeChangedSignal("Earned"):Connect(function()
		local earned = player:GetAttribute("Earned") or 0
		local gained = earned - lastEarned
		lastEarned = earned
		if gained > 1e-6 then
			burst(gained)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local now = os.clock()
		for i = #coins, 1, -1 do
			local coin = coins[i]
			local age = now - coin.born
			if age >= coin.flyAt or age >= MAX_LIFE then
				local from = coin.flyFrom or coin.pos
				coin.flyFrom = from
				local k = if age >= MAX_LIFE then 1 else math.clamp((age - coin.flyAt) / CoinBurst.FLY_SECONDS, 0, 1)
				if k >= 1 then
					arrive(coin)
					table.remove(coins, i)
					continue
				end
				local e = k * k -- speeds up toward the wallet, like a magnet
				coin.pos = from:Lerp(walletPoint(camera), e) + Vector3.new(0, math.sin(k * math.pi) * FLY_ARC, 0)
				coin.part.Size = coin.size * (1 - 0.75 * e)
			else
				coin.vel += Vector3.new(0, CoinBurst.GRAVITY * dt, 0)
				coin.pos += coin.vel * dt
				if coin.vel.Y < 0 and coin.pos.Y < coin.ground then
					local up = -coin.vel.Y * BOUNCE
					coin.pos = Vector3.new(coin.pos.X, coin.ground, coin.pos.Z)
					coin.vel = if up < 3 then Vector3.zero else Vector3.new(coin.vel.X * 0.4, up, coin.vel.Z * 0.4)
				end
			end
			coin.spin += SPIN * dt
			coin.part.CFrame = CFrame.new(coin.pos) * CFrame.Angles(0, coin.spin, 0)
		end
	end)
end

return Payout
