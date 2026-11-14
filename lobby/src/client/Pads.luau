-- Pads: each workspace.Lobby.Pads.PadN shows its State attribute (server/Queue publishes
-- common/SessionRules.padState) in the look LobbyCues.padLook gives it. Its Rim parts, Water, the
-- Water's Ripple texture and PointLight take the theme colour; a pulse breathes the light and the rim;
-- PadBubbles (cloned onto the Water) rise while it invites; the Ripple drifts. Over a countdown (State
-- "counting", LaunchAt in server time) the water rises. Anyone whose root steps onto or off a pad
-- (within LobbyCues.pads.inside of its Zone, as server/Queue's INSIDE) splashes. Pads.padOf(player)
-- is the pad they stand on (client/Countdown's sparkle). Stream-safe: pieces are looked up every
-- frame and skipped while they aren't there.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LobbyCues = require(ReplicatedStorage.Shared.LobbyCues)
local SessionRules = require(ReplicatedStorage.Common.SessionRules)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Sfx = require(script.Parent.Sfx)

local LOW, HIGH = -4, 20 -- pad-space heights that count as on the pad (server/Queue's)
local CLEANUP_SECONDS = 2
local COLOR_SNAP = 0.004 -- summed channel difference under which a fading colour arrives
local TAU = 2 * math.pi
local WHITE = Color3.new(1, 1, 1)
local RIPPLE_WHITE = 0.6 -- how much lighter the ripple's lines are than the water

local Pads = {}

type View = {
	color: Color3,
	light: number,
	rise: number,
	water: BasePart?, -- the Water part this view last saw (a new one streams in at its own place)
	base: CFrame?, -- where that Water rests
}

local views: { [Model]: View } = {}
local standing: { [Player]: Model } = {}
local lastFeet: { [Player]: Vector3 } = {}
local seen: { [Player]: boolean } = {} -- a player's first frame is where they already were, not a step
local rng = Random.new()

function Pads.padOf(player: Player): Model?
	return standing[player]
end

local function close(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < COLOR_SNAP
end

local function feetOf(root: BasePart, humanoid: Humanoid?): Vector3
	local hip = if humanoid then humanoid.HipHeight else 2
	return root.Position - Vector3.new(0, root.Size.Y / 2 + hip, 0)
end

function Pads.start()
	local cue = LobbyCues.pads
	local lobby = workspace:WaitForChild("Lobby", 10)
	local folder = lobby and lobby:WaitForChild("Pads", 10)
	assert(folder, "workspace.Lobby.Pads is missing (built in the lobby place)")
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (built in the lobby place)")
	local splash = vfx:WaitForChild(cue.splash, 10)
	assert(splash and splash:IsA("Attachment"), `ReplicatedStorage.Vfx is missing {cue.splash} (an Attachment)`)
	for _, emitter in splash:GetChildren() do
		if emitter:IsA("ParticleEmitter") then
			assert(type(emitter:GetAttribute("Burst")) == "number", `Vfx.{cue.splash} needs a number attribute Burst on {emitter.Name}`)
		end
	end
	local bubbles = vfx:WaitForChild(cue.bubbles, 10)
	assert(bubbles and bubbles:IsA("Attachment"), `ReplicatedStorage.Vfx is missing {cue.bubbles} (an Attachment)`)
	for state in LobbyCues.padLooks do
		local key = LobbyCues.padLook(state).color
		assert(typeof(Theme.colors[key]) == "Color3", `sunbaked-sea has no colour {key} (LobbyCues.padLooks.{state})`)
	end
	Sfx.need(cue.splashSound)

	local function burst(at: Vector3, scale: number)
		local effect = (splash :: Attachment):Clone()
		effect.Parent = workspace.Terrain
		effect.WorldPosition = at
		for _, emitter in effect:GetChildren() do
			if emitter:IsA("ParticleEmitter") then
				emitter:Emit(math.max(1, math.floor(emitter:GetAttribute("Burst") * scale + 0.5)))
			end
		end
		task.delay(CLEANUP_SECONDS, effect.Destroy, effect)
		Sfx.play(cue.splashSound, {
			volume = cue.splashVolume * scale,
			pitch = rng:NextNumber(cue.splashPitchMin, cue.splashPitchMax),
			at = at,
		})
	end

	local function paintWater(water: BasePart, view: View, look: LobbyCues.PadLook, dip: number, dt: number)
		if water.Color ~= view.color then
			water.Color = view.color
		end
		local ripple = water:FindFirstChild("Ripple")
		if ripple and ripple:IsA("Texture") then
			ripple.OffsetStudsU = (ripple.OffsetStudsU + cue.rippleSpeed * dt) % ripple.StudsPerTileU
			ripple.OffsetStudsV = (ripple.OffsetStudsV + cue.rippleSpeed * 0.6 * dt) % ripple.StudsPerTileV
			local lines = view.color:Lerp(WHITE, RIPPLE_WHITE)
			if ripple.Color3 ~= lines then
				ripple.Color3 = lines
			end
		end
		local light = water:FindFirstChildOfClass("PointLight")
		if light then
			local brightness = cue.light * view.light * (1 - dip)
			if light.Brightness ~= brightness then
				light.Brightness = brightness
			end
			if light.Color ~= view.color then
				light.Color = view.color
			end
		end
		local holder = water:FindFirstChild(cue.bubbles)
		if not holder then
			holder = (bubbles :: Attachment):Clone()
			holder.Parent = water
		end
		for _, emitter in (holder :: Instance):GetChildren() do
			if emitter:IsA("ParticleEmitter") and emitter.Enabled ~= look.bubbles then
				emitter.Enabled = look.bubbles
			end
		end
		if view.water ~= water then
			view.water = water
			view.base = water.CFrame
		end
		local placed = (view.base :: CFrame) + Vector3.new(0, view.rise, 0)
		if water.CFrame ~= placed then
			water.CFrame = placed
		end
	end

	Players.PlayerRemoving:Connect(function(other)
		standing[other], lastFeet[other], seen[other] = nil, nil, nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		local now = workspace:GetServerTimeNow()
		local clock = os.clock()
		local k = 1 - math.exp(-dt * cue.ease)
		local models = folder:GetChildren()
		for _, model in models do
			if not model:IsA("Model") then
				continue
			end
			local state = model:GetAttribute("State")
			state = if type(state) == "string" then state else "open" -- nil until the server's first publish
			local look = LobbyCues.padLook(state)
			local target = Theme.colors[look.color]
			local view = views[model]
			if not view then
				view = { color = target, light = look.light, rise = 0 }
				views[model] = view
			end
			local v = view :: View
			v.color = if close(v.color, target) then target else v.color:Lerp(target, k)
			v.light += (look.light - v.light) * k
			local launchAt = model:GetAttribute("LaunchAt")
			local rise = 0
			if state == "counting" and type(launchAt) == "number" and launchAt > 0 then
				rise = cue.rise * math.clamp(1 - (launchAt - now) / SessionRules.COUNTDOWN, 0, 1)
			elseif state == "launching" then
				rise = cue.rise -- stays up into the launch
			end
			v.rise = if math.abs(rise - v.rise) < 0.001 then rise else v.rise + (rise - v.rise) * k
			local wave = if look.pulseHz > 0 then 0.5 + 0.5 * math.cos(TAU * look.pulseHz * clock) else 1
			local dip = cue.pulseDepth * (1 - wave)
			for _, part in model:GetChildren() do
				if part.Name == "Rim" and part:IsA("BasePart") then
					if part.Color ~= v.color then
						part.Color = v.color
					end
					local transparency = cue.rimTransparency + (1 - cue.rimTransparency) * dip * 0.5
					if part.Transparency ~= transparency then
						part.Transparency = transparency
					end
				end
			end
			local water = model:FindFirstChild("Water")
			if water and water:IsA("BasePart") then
				paintWater(water, v, look, dip, dt)
			end
		end

		-- Who stands on which pad; a change is a step on or off.
		for _, other in Players:GetPlayers() do
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local on: Model? = nil
			if root and root:IsA("BasePart") then
				for _, model in models do
					local zone = model:FindFirstChild("Zone")
					if zone and zone:IsA("BasePart") then
						local at = zone.CFrame:PointToObjectSpace(root.Position)
						if math.abs(at.X) <= cue.inside and math.abs(at.Z) <= cue.inside and at.Y >= LOW and at.Y <= HIGH then
							on = model :: Model
							break
						end
					end
				end
			end
			local was = standing[other]
			if on ~= was then
				standing[other] = on
				if seen[other] then
					local left = lastFeet[other]
					if was and left then
						burst(left, cue.leaveScale)
					end
					if on and root and root:IsA("BasePart") then
						burst(feetOf(root, humanoid), 1)
					end
				end
			end
			if on and root and root:IsA("BasePart") then
				lastFeet[other] = feetOf(root, humanoid)
			end
			seen[other] = true
		end
	end)
end

return Pads
