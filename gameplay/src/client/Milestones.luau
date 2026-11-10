-- Milestones every 5% of the ocean (shared/Milestones, granted by server/Run; the toast is the
-- server's card). A new Milestone swoops the camera up and out over the ocean and back (not while
-- driving or with the honeycomb open), ducks the music under a fanfare, and a sighting shows the
-- bacon-hair (a copy of ReplicatedStorage.Story.BaconHair, placeholder motion) far out on the
-- horizon. The cove decorations workspace.Map.Revive.M<n> stay hidden here until the Revived
-- attribute names them; one revived while you watch pops in. Numbers in Cues.milestone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Ease = require(ReplicatedStorage.Shared.Ease)
local MilestoneRules = require(ReplicatedStorage.Shared.Milestones)
local Honeycomb = require(script.Parent.Honeycomb)
local CameraFeel = require(script.Parent.CameraFeel)
local Hud = require(script.Parent.Hud)
local Music = require(script.Parent.Music)
local Vehicles = require(script.Parent.Vehicles)

local SWOOP_STEP = "MilestoneSwoop"
local SEA = Vector3.new(0, 0, -1) -- the sea lies toward -Z from the beach (workspace.Ocean)
local SOUND_SECONDS = 3

local Milestones = {}

local function asset(folder: Instance, name: string, class: string): any
	local found = folder:WaitForChild(name, 10)
	assert(found and found:IsA(class), `{folder:GetFullName()} is missing {name} (a {class})`)
	return found
end

local swoop: { start: CFrame, out: CFrame, at: number }? = nil

-- Back to the player's own view, exactly as it was (its untilted aim: CameraFeel adds the tilt). If
-- something else took the camera mid-swoop, it is left to that.
local function endSwoop(restore: boolean)
	local s = swoop :: { start: CFrame, out: CFrame, at: number }
	swoop = nil
	RunService:UnbindFromRenderStep(SWOOP_STEP)
	if restore then
		local camera = workspace.CurrentCamera
		camera.CFrame = s.start
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- From the player's view up and out toward the basin, and back (eased, still at both ends and at the
-- top). Only from the normal first-person camera.
local function startSwoop(basin: BasePart)
	local cue = Cues.milestone
	local camera = workspace.CurrentCamera
	if swoop or Vehicles.driving() or Honeycomb.isOpen() or camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local start = CameraFeel.untilted() or camera.CFrame
	local flat = (basin.Position - start.Position) * Vector3.new(1, 0, 1)
	local dir = if flat.Magnitude > 1 then flat.Unit else SEA
	local over = start.Position + dir * math.min(flat.Magnitude, cue.swoopOut)
	swoop = { start = start, out = CFrame.lookAt(over + Vector3.yAxis * cue.swoopRise, over + dir * cue.swoopLook), at = os.clock() }
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(SWOOP_STEP, Enum.RenderPriority.Camera.Value + 2, function()
		local s = swoop
		if not s then
			return
		end
		local t = (os.clock() - s.at) / cue.swoopSeconds
		if workspace.CurrentCamera.CameraType ~= Enum.CameraType.Scriptable then
			endSwoop(false)
			return
		elseif t >= 1 or Vehicles.driving() or Honeycomb.isOpen() then
			endSwoop(true)
			return
		end
		workspace.CurrentCamera.CFrame = s.start:Lerp(s.out, (1 - math.cos(2 * math.pi * t)) / 2)
	end)
end

local sighting: { model: Model, base: CFrame, height: number, at: number }? = nil

-- A copy of the bacon-hair rises out of the water far out at sea, facing the beach, sways and sinks.
local function sight(template: Model)
	local ocean = Hud.ocean()
	local water = ocean and ocean:FindFirstChild("Water")
	if sighting or not (ocean and water and water:IsA("BasePart")) then
		return
	end
	local cue = Cues.milestone
	local model = template:Clone()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		end
	end
	local box, size = model:GetBoundingBox()
	local feet = model:GetPivot().Position.Y - (box.Position.Y - size.Y / 2) -- pivot height above its lowest point
	local x = workspace.CurrentCamera.CFrame.Position.X
	local at = Vector3.new(x, water.Position.Y + water.Size.Y / 2 + feet, ocean:GetPivot().Position.Z) + SEA * cue.sightingDistance
	local base = CFrame.lookAt(at, at - SEA)
	model:PivotTo(base - Vector3.yAxis * size.Y)
	model.Parent = workspace
	sighting = { model = model, base = base, height = size.Y, at = os.clock() }
end

local function moveSighting()
	local s = sighting
	if not s then
		return
	end
	local cue = Cues.milestone
	local e = os.clock() - s.at
	if e >= cue.sightingSeconds then
		s.model:Destroy()
		sighting = nil
		return
	end
	local shown = math.clamp(math.min(e / cue.sightingRise, (cue.sightingSeconds - e) / cue.sightingSink), 0, 1)
	shown = shown * shown * (3 - 2 * shown)
	local sway = math.rad(cue.sightingRock) * math.sin(e * cue.sightingWaves * 2 * math.pi) * shown
	s.model:PivotTo(s.base * CFrame.new(0, -s.height * (1 - shown), 0) * CFrame.Angles(0, 0, sway))
end

-- How each part, decal and effect of a Revive model looked in the place, so hiding it can be undone.
local looks: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any

local function show(inst: Instance, shown: boolean)
	if inst:IsA("BasePart") then
		local look = looks[inst]
		if not look then
			look = { transparency = inst.Transparency, canCollide = inst.CanCollide, canQuery = inst.CanQuery, canTouch = inst.CanTouch }
			looks[inst] = look
		end
		inst.Transparency = if shown then look.transparency else 1
		inst.CanCollide = shown and look.canCollide
		inst.CanQuery = shown and look.canQuery
		inst.CanTouch = shown and look.canTouch
	elseif inst:IsA("Decal") then -- Textures too
		local transparency = looks[inst] or inst.Transparency
		looks[inst] = transparency
		inst.Transparency = if shown then transparency else 1
	elseif inst:IsA("ParticleEmitter") or inst:IsA("Light") or inst:IsA("Beam") then
		local effect = inst :: any
		local enabled = looks[inst]
		if enabled == nil then
			enabled = effect.Enabled
			looks[inst] = enabled
		end
		effect.Enabled = shown and enabled
	end
end

-- Hides the decorations not revived yet and shows the rest, also as they stream in.
local function watchRevive(revive: Instance, popIn: (Model) -> ())
	local revived: { [number]: boolean } = {}
	local function numberOf(inst: Instance): number?
		local node = inst
		while node.Parent and node.Parent ~= revive do
			node = node.Parent
		end
		return if node.Parent == revive then tonumber(node.Name:match("^M(%d+)$")) else nil
	end
	local function read(): { [number]: boolean }
		local text = ReplicatedStorage:GetAttribute("Revived")
		local set = {}
		for n in (if type(text) == "string" then text else ""):gmatch("%d+") do
			set[tonumber(n) :: number] = true
		end
		return set
	end
	local function apply()
		for _, inst in revive:GetDescendants() do
			local n = numberOf(inst)
			if n then
				show(inst, revived[n] == true)
			end
		end
	end
	revived = read() -- what is already back shows without a pop
	apply()
	ReplicatedStorage:GetAttributeChangedSignal("Revived"):Connect(function()
		local before = revived
		revived = read()
		apply()
		for n in revived do
			local model = revive:FindFirstChild(`M{n}`)
			if not before[n] and model and model:IsA("Model") then
				popIn(model)
			end
		end
	end)
	revive.DescendantAdded:Connect(function(inst)
		local n = numberOf(inst)
		if n then
			show(inst, revived[n] == true)
		end
	end)
end

function Milestones.start()
	local cue = Cues.milestone
	local audio = ReplicatedStorage:WaitForChild("Audio", 10)
	assert(audio, "ReplicatedStorage.Audio is missing (the sounds are baked into the place)")
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local fanfare = asset(audio, cue.sound, "Sound") :: Sound
	local sparkle = asset(vfx, Cues.purchase.sparkle, "Attachment") :: Attachment

	local function play()
		local sound = fanfare:Clone()
		sound.Volume = cue.soundVolume
		sound.Parent = SoundService
		sound:Play()
		task.delay(SOUND_SECONDS, sound.Destroy, sound)
	end

	local popping: { [Model]: boolean } = {}
	local function popIn(model: Model)
		local part = model:FindFirstChildWhichIsA("BasePart", true)
		if popping[model] or not part then
			return
		end
		popping[model] = true
		play()
		local effect = sparkle:Clone()
		effect.Parent = part
		effect.WorldPosition = model:GetPivot().Position
		for _, emitter in effect:GetChildren() do
			if emitter:IsA("ParticleEmitter") then
				emitter:Emit(emitter:GetAttribute("Burst"))
			end
		end
		task.delay(SOUND_SECONDS, effect.Destroy, effect)
		local full, at = model:GetScale(), os.clock()
		local connection
		connection = RunService.Heartbeat:Connect(function()
			local t = (os.clock() - at) / cue.reviveSeconds
			if t >= 1 then
				connection:Disconnect()
				model:ScaleTo(full)
				popping[model] = nil
				return
			end
			model:ScaleTo(full * (cue.reviveFrom + (1 - cue.reviveFrom) * Ease.backOut(t, cue.reviveOvershoot)))
		end)
	end

	-- Owner pieces built in Studio: each waits in its own thread, so a missing one fails loudly here
	-- without stopping the rest.
	local bacon: Model? = nil
	task.spawn(function()
		local story = ReplicatedStorage:WaitForChild("Story", 30)
		assert(story, "ReplicatedStorage.Story is missing (Studio): the milestones' bacon-hair sightings")
		bacon = asset(story, "BaconHair", "Model")
	end)
	task.spawn(function()
		local map = workspace:WaitForChild("Map", 30)
		local revive = map and map:WaitForChild("Revive", 30)
		assert(revive, "workspace.Map.Revive is missing (Studio): the milestones' cove decorations")
		watchRevive(revive, popIn)
	end)

	RunService.Heartbeat:Connect(moveSighting)

	local _, lastAt = MilestoneRules.decode(ReplicatedStorage:GetAttribute("Milestone"))
	ReplicatedStorage:GetAttributeChangedSignal("Milestone"):Connect(function()
		local index, at = MilestoneRules.decode(ReplicatedStorage:GetAttribute("Milestone"))
		if not (index and at) or (lastAt and at <= lastAt) then
			return
		end
		lastAt = at
		if workspace:GetServerTimeNow() - at > cue.freshSeconds then
			return
		end
		Music.duck(cue.duckSeconds)
		play()
		local ocean = Hud.ocean()
		local basin = ocean and ocean:FindFirstChild("Basin")
		if basin and basin:IsA("BasePart") then
			startSwoop(basin)
		end
		if MilestoneRules.reward(Config, index).sighting then
			if bacon then
				sight(bacon)
			else
				warn("[Milestones] no ReplicatedStorage.Story.BaconHair (Studio): the sighting is skipped")
			end
		end
	end)
end

return Milestones
