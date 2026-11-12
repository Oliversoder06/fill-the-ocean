-- The intro cutscene. shared/IntroCut is the cut (shots, eyelids, logo, sounds, beats) and
-- shared/IntroClips your body's motion; this plays them while Phase is "intro", on the server's clock
-- from IntroAt, so the whole team sees the same frame. Everything in it is this client's own, in a
-- workspace folder IntroScene: a copy of your avatar walks to a copy of your lounger (turned round to
-- face the sea; the place's one is hidden meanwhile) and lies down on it; the water stands full, then
-- drains to the run's (Zones.setFill); the bacon-hair (ReplicatedStorage.Story: BaconRig, the giant
-- standing in the sea; BaconFat with its Straw over the last Puddle) drinks it far out. The HUD, the
-- chat, every character, the prompts and the touch controls are off meanwhile, and your character
-- waits, anchored, where play starts. Skip (StarterGui.Cutscene.Skip, from IntroCut.skipAfter, or gamepad B) and the
-- cut's end tell the server (Intro remote); the phase leaving "intro" ends it here.
-- Studio: workspace attribute StudioIntroAt (seconds) holds the cut on that frame, for framing shots.
local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Ease = require(ReplicatedStorage.Shared.Ease)
local IntroClips = require(ReplicatedStorage.Shared.IntroClips)
local IntroCut = require(ReplicatedStorage.Shared.IntroCut)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Hud = require(script.Parent.Hud)
local Music = require(script.Parent.Music)
local Staff = require(script.Parent.Staff)

local STEP = "IntroCut"
local CORE_OFF = { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu }
local SOUND_LATE = 0.3 -- seconds late after which a one-shot sound is left out (a late join, a seek)
local MUSIC_DRIFT = 0.15 -- seconds the music may drift from the cut's clock before it is put back
local SOUND_FADE = TweenInfo.new(0.6) -- sounds still playing when the cut ends early
local WALK_FADE = 0.25 -- seconds the walk takes to settle when you stop by the lounger
local EYE_OFFSET = Vector3.new(0, 1.5, 0) -- first person's eye over the root, until it is measured
local SEA = Vector3.new(0, 0, -1)
local REMOVED = { HeldTool = true, HeldGrip = true, WornBackpack = true } -- server/HeldTools' parts
local DRINK_BOB = { degrees = 1.5, hz = 1.6 } -- the sucking head while he drinks
local NOTICE_SECONDS = 0.3
local BURP_TILT = 14 -- degrees his head goes back on the burp
local BURP_HOP = 0.08 -- of his ball's radius, up and down once
local BURP_SECONDS = 0.45
local STRAW_OUT = 0.95 -- of his ball's radius: how far the straw goes out in front before it bends
local STRAW_DROP = 0.1 -- of his ball's radius: how far it dips on the way out
local CHARACTER_WAIT = 5 -- seconds the intro waits for your character to spawn
local CURSOR_SECONDS = 2 -- the mouse cursor shows for this long after the mouse moves (for Skip)

local player = Players.LocalPlayer
local Intro = {}

local AnimPlayer: any, Gait: any, Performance: any
local kit: any = nil -- the place's pieces (Intro.start)
local scene: any = nil -- the intro playing now
local mouseMovedAt = -math.huge

local function v3(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
end

local function asset(parent: Instance, name: string, class: string): any
	local found = parent:WaitForChild(name, 10)
	assert(found and found:IsA(class), `{parent:GetFullName()} is missing {name} (a {class}; built in Studio)`)
	return found
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

-- The ground's height under (x, z), past every character and the scene.
local function groundAt(x: number, z: number, ignore: { Instance }): number
	groundParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, 100, z), Vector3.new(0, -200, 0), groundParams)
	return if hit then hit.Position.Y else 0
end

local function charactersOf(): { Instance }
	local list: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	return list
end

-- Hides a character here (others see nothing of it): parts, decals and its name.
local function hide(character: Instance, undo: { () -> () })
	for _, inst in character:GetDescendants() do
		if inst:IsA("BasePart") or inst:IsA("Decal") then
			inst.LocalTransparencyModifier = 1
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local was = humanoid.DisplayDistanceType
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		table.insert(undo, function()
			humanoid.DisplayDistanceType = was
		end)
	end
	table.insert(undo, function()
		for _, inst in character:GetDescendants() do
			if inst:IsA("BasePart") or inst:IsA("Decal") then
				inst.LocalTransparencyModifier = 0
			end
		end
	end)
end

-- A copy of your avatar for the cut: no scripts, nothing in hand or on the back, anchored at the
-- root, nothing to collide with, no name over it.
local function copyAvatar(character: Model): Model
	local was = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = was
	for _, inst in copy:GetDescendants() do
		if inst:IsA("LuaSourceContainer") or inst:IsA("ForceField") or REMOVED[inst.Name] then
			inst:Destroy()
		end
	end
	local root = copy:FindFirstChild("HumanoidRootPart")
	assert(root and root:IsA("BasePart"), "your character has no HumanoidRootPart")
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = part == root
			part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.EvaluateStateMachine = false
	end
	copy.PrimaryPart = root
	return copy
end

-- A copy of a Story model, anchored and out of every ray. No Animator: it would reset the joints this
-- turns (his neck) every frame.
local function copyStory(template: Model): Model
	local copy = template:Clone()
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = part == copy.PrimaryPart
			part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
		elseif part:IsA("Humanoid") then
			part.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			part.EvaluateStateMachine = false
		elseif part:IsA("Animator") then
			part:Destroy()
		end
	end
	return copy
end

-- The place's lounger nearest IntroCut.places.lounger.
local function findLounger(): BasePart
	local map = workspace:WaitForChild("Map", 10)
	local beach = map and map:WaitForChild("Beach", 10)
	assert(beach, "workspace.Map.Beach is missing")
	local at, best, bestDistance = v3(IntroCut.places.lounger), nil, math.huge
	for _, child in beach:GetChildren() do
		if child.Name == "Stage_Pool_Lounger" and child:IsA("BasePart") then
			local d = (child.Position - at).Magnitude
			if d < bestDistance then
				best, bestDistance = child, d
			end
		end
	end
	assert(best and bestDistance < 2, "workspace.Map.Beach has no Stage_Pool_Lounger at IntroCut.places.lounger")
	return best
end

-- A place on the ground: { x, _, z } at the ground's height.
local function onGround(place: { number }, ignore: { Instance }): Vector3
	return Vector3.new(place[1], groundAt(place[1], place[3], ignore), place[3])
end

-- Builds the scene and takes the screen. Returns nil when your character isn't there. A preview puts
-- your character back where it was at the end.
local function begin(at: number, preview: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and root:IsA("BasePart") and humanoid) then
		return nil
	end
	local camera = workspace.CurrentCamera
	local s: any = {
		at = at,
		preview = preview,
		view = camera.CFrame,
		undo = {} :: { () -> () },
		sounds = {} :: { [number]: Sound },
		water = "",
		finished = false,
	}
	local undo = s.undo
	local folder = Instance.new("Folder")
	folder.Name = "IntroScene"
	folder.Parent = workspace
	s.folder = folder
	local ignore = charactersOf()
	table.insert(ignore, folder)

	-- Your eyes in first person, over the root, for the cut's last move.
	local eye = camera.CFrame.Position - root.Position
	s.eyeOffset = if camera.CameraType == Enum.CameraType.Custom and eye.Magnitude < 4 then Vector3.new(0, eye.Y, 0) else EYE_OFFSET
	s.rootHeight = humanoid.HipHeight + root.Size.Y / 2
	s.stand = onGround(IntroCut.places.stand, ignore) + Vector3.new(0, s.rootHeight, 0)
	s.walkFrom = onGround(IntroCut.places.walkFrom, ignore)
	s.walkTo = onGround(IntroCut.places.walkTo, ignore)

	-- Your copy, its walk and its time on the lounger. Accessories hang on welds or (newer avatars)
	-- rigid constraints; the animation leaves them all to follow the part they hang on.
	local body = copyAvatar(character)
	s.body = body
	local outfit = Staff.outfit(body)
	for _, accessory in body:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
		if handle then
			table.insert(outfit, handle)
		end
	end
	s.anim = AnimPlayer.new(body, { ignore = outfit })
	s.bodyRoot = body.PrimaryPart
	body.Parent = nil

	-- Your character waits where play starts, anchored and hidden; so does everyone else's.
	local stoodAt = character:GetPivot()
	root.Anchored = true
	character:PivotTo(CFrame.lookAt(s.stand, s.stand + SEA))
	table.insert(undo, function()
		root.Anchored = false
	end)
	if preview then
		table.insert(undo, function() -- runs before the unanchoring above (undo goes backwards)
			character:PivotTo(stoodAt)
		end)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			hide(other.Character, undo)
		end
	end
	local joined = Players.PlayerAdded:Connect(function(other)
		local spawned = other.CharacterAdded:Connect(function(c)
			if scene == s then
				hide(c, undo)
			end
		end)
		table.insert(undo, function()
			spawned:Disconnect()
		end)
	end)
	table.insert(undo, function()
		joined:Disconnect()
	end)

	-- The lounger, turned round to face the sea; the place's own hides meanwhile.
	local lounger = findLounger()
	local turned = lounger:Clone()
	turned:ClearAllChildren()
	turned.CFrame = lounger.CFrame * CFrame.Angles(0, math.pi, 0)
	turned.Anchored, turned.CanCollide, turned.CanTouch, turned.CanQuery = true, false, false, false
	turned.Parent = folder
	lounger.LocalTransparencyModifier = 1
	table.insert(undo, function()
		lounger.LocalTransparencyModifier = 0
	end)

	-- The bacon-hair: standing in the sea, then sitting round on the seabed with his straw.
	local baconAt = v3(IntroCut.places.bacon)
	local facing = CFrame.lookAt(baconAt, baconAt - SEA) -- toward the beach
	s.giant = copyStory(kit.giant)
	s.giantAt = facing
	s.giant:PivotTo(facing)
	s.fat = copyStory(kit.fat)
	s.fatAt = facing * CFrame.Angles(0, math.rad(IntroCut.places.baconTurn), 0)
	s.fat:PivotTo(s.fatAt)
	local belly = asset(s.fat, "Belly", "BasePart")
	s.fatRadius = belly.Size.Y / 2
	s.neck = s.fat:FindFirstChild("Neck", true)
	assert(s.neck and s.neck:IsA("Motor6D"), "Story.BaconFat needs a Motor6D Neck (his head turns)")
	s.mouth = s.fat:FindFirstChild("Mouth", true)
	assert(s.mouth and s.mouth:IsA("Attachment"), "Story.BaconFat needs an Attachment Mouth (where the straw goes)")
	s.straw = kit.straw:Clone() -- a bendy straw: out of his mouth, then down to the puddle
	s.strawDown = kit.straw:Clone()
	s.puddle = kit.puddle:Clone()
	for _, part in { s.straw, s.strawDown, s.puddle } do
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	end
	s.puddleAt = v3(IntroCut.places.puddle)
	-- where his head turns when he notices you: your eyes on the lounger, in his own axes
	local toEye = s.fatAt:VectorToObjectSpace((v3(IntroCut.places.eye) - s.mouth.WorldPosition).Unit)
	s.lookYaw = math.deg(math.atan2(-toEye.X, -toEye.Z))
	s.lookPitch = math.deg(math.asin(toEye.Y))

	-- The screen: the HUD, the cursor, the chat and your controls off; the cut's own on top.
	local hudGui = player.PlayerGui:FindFirstChild("Hud")
	local cursorGui = player.PlayerGui:FindFirstChild("Cursor")
	for _, gui in { hudGui, cursorGui } do
		if gui and gui:IsA("ScreenGui") then
			local was = gui.Enabled
			gui.Enabled = false
			table.insert(undo, function()
				gui.Enabled = was
			end)
		end
	end
	for _, kind in CORE_OFF do
		local was = StarterGui:GetCoreGuiEnabled(kind)
		StarterGui:SetCoreGuiEnabled(kind, false)
		table.insert(undo, function()
			StarterGui:SetCoreGuiEnabled(kind, was)
		end)
	end
	for _, config in { TextChatService:FindFirstChildOfClass("ChatWindowConfiguration"), TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration") } do
		if config then
			local was = (config :: any).Enabled
			;(config :: any).Enabled = false
			table.insert(undo, function()
				(config :: any).Enabled = was
			end)
		end
	end
	local touch = GuiService.TouchControlsEnabled
	GuiService.TouchControlsEnabled = false
	ProximityPromptService.Enabled = false
	table.insert(undo, function()
		GuiService.TouchControlsEnabled = touch
		ProximityPromptService.Enabled = true
	end)
	Music.hush(true)
	table.insert(undo, function()
		Music.hush(false)
	end)
	local fov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	table.insert(undo, function()
		camera.FieldOfView = fov
	end)
	local gui = kit.gui
	gui.Scale.Scale = Hud.uiScale()
	gui.Enabled = true
	kit.skip.Visible = false

	-- Bakes take a few frames each; the walk is needed from IntroCut.beats.walk.
	task.spawn(function()
		local a = s.anim.anatomy
		s.walkBaked = Gait.cycle(a, IntroClips.gaits.walk)
		task.wait()
		s.lieBaked = Performance.bake(a, IntroClips.clips.lie)
	end)
	return s
end

-- Where the camera key's `at` and `look` are this frame.
local function placeOf(s, at: any): Vector3
	if at == "stand" then
		return s.stand + s.eyeOffset
	end
	return v3(at)
end

local function lookOf(s, look: any, from: Vector3): Vector3
	if look == "player" then
		local head = s.body:FindFirstChild("Head")
		return if head and head:IsA("BasePart") then head.Position else s.bodyRoot.Position
	elseif look == "bacon" then
		local belly = s.fat:FindFirstChild("Belly") :: BasePart
		return belly.Position + Vector3.new(0, s.fatRadius * 0.35, 0)
	elseif look == "sea" then
		return from + SEA * 100
	end
	return v3(look)
end

local function keyFrame(s, key): (CFrame, number)
	local at = placeOf(s, key.at)
	return CFrame.lookAt(at, lookOf(s, key.look, at)), key.fov
end

local function camera(s, t: number)
	local shot = IntroCut.shot(t) or IntroCut.shots[1]
	local a, b, alpha = IntroCut.segment(shot.keys, t)
	local cfA, fovA = keyFrame(s, a)
	local cfB, fovB = keyFrame(s, b)
	local cf = cfA:Lerp(cfB, alpha)
	-- the zoom eases as it looks, not in degrees
	local ta, tb = math.tan(math.rad(fovA) / 2), math.tan(math.rad(fovB) / 2)
	local fov = math.deg(2 * math.atan(ta + (tb - ta) * alpha))
	for _, shake in IntroCut.shakes do
		local u = (t - shake.at) / shake.seconds
		if u > 0 and u < 1 then
			cf *= CFrame.new(Ease.shake(u, shake.cycles, shake.studs), Ease.shake(u, shake.cycles * 0.7, shake.studs * 0.6), 0)
		end
	end
	local cam = workspace.CurrentCamera
	cam.CFrame = cf
	Hud.set(cam, "FieldOfView", fov)
end

-- The screen's overlays: eyelids, blur, black, logo, Skip.
local function overlays(t: number)
	local gui = kit.gui
	local lids = IntroCut.value(IntroCut.lids, t)
	for _, lid in { gui.TopLid, gui.BottomLid } do
		Hud.set(lid, "Visible", lids > 0.001)
		Hud.set(lid, "Size", UDim2.fromScale(1, lids * 0.5))
	end
	local blur = IntroCut.value(IntroCut.blur, t)
	Hud.set(kit.blur, "Enabled", blur > 0.05)
	Hud.set(kit.blur, "Size", blur)
	Hud.set(gui.Black, "BackgroundTransparency", 1 - IntroCut.value(IntroCut.black, t))
	Hud.set(gui.Logo, "ImageTransparency", 1 - IntroCut.value(IntroCut.logoAlpha, t))
	Hud.set(gui.Logo.Pop, "Scale", IntroCut.value(IntroCut.logoScale, t))
	Hud.set(kit.skip, "Visible", t >= IntroCut.skipAfter)
end

-- Sounds start on their cue (left out when well past it, but for the music) and stop or fade.
local function sounds(s, t: number)
	for i, cue in IntroCut.sounds do
		local sound = s.sounds[i]
		if sound == nil and t >= cue.t then
			if cue.music or t - cue.t <= SOUND_LATE then
				sound = kit.sounds[cue.sound]:Clone()
				sound.Volume = cue.volume
				sound.Parent = SoundService
				sound.TimePosition = math.max(0, t - cue.t)
				sound:Play()
				s.sounds[i] = sound
			else
				s.sounds[i] = false
			end
		end
		if sound then
			if cue.music then
				Hud.set(sound, "Volume", cue.volume * IntroCut.value(IntroCut.music, t))
				if math.abs(sound.TimePosition - (t - cue.t)) > MUSIC_DRIFT and sound.IsLoaded then
					sound.TimePosition = t - cue.t
				end
			elseif cue.stop and t >= cue.stop and sound.IsPlaying then
				sound:Stop()
			elseif cue.fade then
				local left = cue.t + sound.TimeLength - t
				Hud.set(sound, "Volume", cue.volume * math.clamp(left / cue.fade, 0, 1))
			end
		end
	end
end

-- The water: full until the swap, then drunk dry; the run's own once the cut is over.
local function setWater(s, want: "full" | "dry" | "run")
	if s.water == want then
		return
	end
	s.water = want
	local ocean = Hud.ocean()
	if ocean then
		local fill = ReplicatedStorage:GetAttribute("Fill")
		Zones.setFill(ocean, if want == "full" then 1 elseif want == "dry" then 0 elseif type(fill) == "number" then fill else 0)
	end
end

local function show(model: Instance, on: boolean, folder: Folder)
	local parent = if on then folder else nil
	if model.Parent ~= parent then
		model.Parent = parent
	end
end

-- Your copy: up the beach, then on the lounger (shown from the walk until your own eyes take over).
local function body(s, t: number)
	local b = IntroCut.beats
	show(s.body, t >= b.walk and t < b.pov, s.folder)
	if t < b.walk or t >= b.pov then
		return
	end
	if t < b.lie then
		local along = IntroCut.walked(t)
		local at = s.walkFrom:Lerp(s.walkTo, along) + Vector3.new(0, s.rootHeight, 0)
		local dir = (s.walkTo - s.walkFrom) * Vector3.new(1, 0, 1)
		s.body:PivotTo(CFrame.lookAt(at, at + dir.Unit))
		if s.walkBaked and not s.walkHandle then
			s.walkHandle = s.anim:play(s.walkBaked, { loop = true, fadeIn = 0, fadeOut = WALK_FADE })
			s.walkHandle:setSpeed(0)
		end
		if s.walkHandle then
			s.walkHandle:seek(t - b.walkFrom)
			if along >= 1 and not s.walkHandle.stopping then
				s.walkHandle:stop(WALK_FADE)
			end
		end
	else
		if s.walkHandle then
			s.walkHandle:stop(0)
			s.walkHandle = nil
		end
		local places = IntroCut.places
		s.body:PivotTo(CFrame.new(v3(places.hips)) * CFrame.Angles(math.rad(places.recline), 0, 0))
		if s.lieBaked and not s.lieHandle then
			s.lieHandle = s.anim:play(s.lieBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
			s.lieHandle:setSpeed(0)
		end
		if s.lieHandle then
			s.lieHandle:seek(math.min(t - b.lie, s.lieBaked.length - 1e-3))
		end
	end
end

-- A straw part from `a` to `b` (the template is a cylinder along its X).
local function strawBetween(part: BasePart, a: Vector3, b: Vector3)
	part.Size = Vector3.new((b - a).Magnitude, part.Size.Y, part.Size.Z)
	part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
end

-- The bacon-hair: the giant sways in the full sea until the swap; then the ball drinks the puddle
-- (head down, sucking), looks round at you, burps and rolls off.
local function bacon(s, t: number)
	local b = IntroCut.beats
	local swapped = t >= b.swap
	local drinking = swapped and t < b.drunk + 0.2
	show(s.giant, t >= b.lie and not swapped, s.folder) -- out there only once you spot him
	show(s.fat, swapped, s.folder)
	show(s.straw, drinking, s.folder)
	show(s.strawDown, drinking, s.folder)
	show(s.puddle, swapped and t < b.drunk, s.folder)
	if not swapped then
		local sway = IntroCut.giantSway
		s.giant:PivotTo(s.giantAt * CFrame.Angles(0, 0, math.rad(sway.degrees) * math.sin(2 * math.pi * t / sway.seconds)))
		return
	end
	-- head: down at the straw (sucking), round to look at you on noticing, back for the burp
	local sipping = -20 + DRINK_BOB.degrees * math.sin(2 * math.pi * DRINK_BOB.hz * t)
	local noticed = IntroCut.eased("out", math.clamp((t - b.notice) / NOTICE_SECONDS, 0, 1))
	local pitch = sipping + (s.lookPitch - sipping) * noticed
	local yaw = s.lookYaw * noticed
	local hop = 0
	if t >= b.burp and t < b.burp + BURP_SECONDS * 2 then
		local u = (t - b.burp) / BURP_SECONDS
		pitch += BURP_TILT * math.sin(math.pi * math.clamp(u / 2, 0, 1))
		hop = BURP_HOP * s.fatRadius * math.sin(math.pi * math.clamp(u, 0, 1))
	end
	s.neck.Transform = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
	-- the roll: along the seabed, turning by the distance over his radius
	local from, to = v3(IntroCut.places.bacon), v3(IntroCut.places.rollTo)
	local path = to - from
	local gone = IntroCut.rolled(t)
	local axis = path.Unit:Cross(Vector3.yAxis)
	local centre = from + path * gone + Vector3.new(0, s.fatRadius + hop, 0)
	local turn = CFrame.fromAxisAngle(axis, -path.Magnitude * gone / s.fatRadius)
	s.fat:PivotTo(CFrame.new(centre) * turn * (CFrame.new(from + Vector3.new(0, s.fatRadius, 0)):Inverse() * s.fatAt))
	if drinking then
		local left = IntroCut.puddleLeft(t)
		local size = 2 * IntroCut.places.puddleRadius * math.max(left, 0.02)
		s.puddle.Size = Vector3.new(s.puddle.Size.X, size, size)
		s.puddle.CFrame = CFrame.new(s.puddleAt) * CFrame.Angles(0, 0, math.pi / 2)
		-- out of the mouth and forward past the ball, then bent down into the puddle
		local mouth = s.mouth.WorldPosition
		local bend = mouth + s.fatAt.LookVector * s.fatRadius * STRAW_OUT - Vector3.new(0, s.fatRadius * STRAW_DROP, 0)
		strawBetween(s.straw, mouth, bend)
		strawBetween(s.strawDown, bend, s.puddleAt)
	end
end

local function finish(s, tellServer: boolean)
	if s.finished then
		return
	end
	s.finished = true
	scene = nil
	Hud.cutscene = false
	RunService:UnbindFromRenderStep(STEP)
	if tellServer then
		kit.remote:FireServer("done")
	end
	for _, sound in s.sounds do
		if sound then
			TweenService:Create(sound, SOUND_FADE, { Volume = 0 }):Play()
			task.delay(SOUND_FADE.Time, sound.Destroy, sound)
		end
	end
	setWater(s, "run")
	s.anim:destroy()
	s.folder:Destroy()
	for i = #s.undo, 1, -1 do
		s.undo[i]()
	end
	local gui = kit.gui
	gui.Enabled = false
	kit.blur.Enabled = false
	kit.blur.Size = 0
	-- back to your own eyes: looking out to sea where play starts, or where a preview began
	local cam = workspace.CurrentCamera
	local eye = s.stand + s.eyeOffset
	cam.CFrame = if s.preview then s.view else CFrame.lookAt(eye, eye + SEA)
	cam.CameraType = Enum.CameraType.Custom
end

local function frame(s)
	local hold = if RunService:IsStudio() then workspace:GetAttribute("StudioIntroAt") else nil
	local t = if type(hold) == "number" then hold else workspace:GetServerTimeNow() - s.at
	if t >= IntroCut.length then
		finish(s, not s.preview)
		return
	end
	camera(s, t)
	overlays(t)
	sounds(s, t)
	setWater(s, if t < IntroCut.beats.swap then "full" else "dry")
	body(s, t)
	bacon(s, t)
	-- your own character stays hidden (the default camera shows it again every frame), and the
	-- cursor is free for Skip
	local character = player.Character
	if character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and part.LocalTransparencyModifier ~= 1 then
				part.LocalTransparencyModifier = 1
			end
		end
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	Hud.set(UserInputService, "MouseIconEnabled", kit.skip.Visible and os.clock() - mouseMovedAt < CURSOR_SECONDS)
end

-- Plays the cut from `at` (server time of its first frame) once your character is there. A preview
-- is this client's alone: the server is never told.
local function run(at: number, preview: boolean)
	local deadline = os.clock() + CHARACTER_WAIT
	while not (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) and os.clock() < deadline do
		task.wait(0.1)
	end
	if scene or not (preview or ReplicatedStorage:GetAttribute("Phase") == "intro") then
		return
	end
	local s = begin(at, preview)
	if not s then
		warn("[Intro] no character to play the intro with; skipped here")
		if not preview then
			kit.remote:FireServer("done")
		end
		return
	end
	scene = s
	Hud.cutscene = true
	-- after the camera, the HUD's cursor and everything else that moves the camera
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 4, function()
		if scene == s then
			frame(s)
		end
	end)
end

-- The team's intro (Phase "intro").
local function play()
	if scene then
		return
	end
	local at = ReplicatedStorage:GetAttribute("IntroAt")
	if type(at) ~= "number" then
		return -- comes with the IntroAt change
	elseif workspace:GetServerTimeNow() - at >= IntroCut.length then
		kit.remote:FireServer("done") -- joined after it ended: nothing to wait for here
		return
	end
	run(at, false)
end

-- An admin's preview (client/Admin): the whole cut from now, on this client only, while the run goes
-- on. Returns why it can't start, or nil.
function Intro.preview(): string?
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if scene then
		return "The intro is already playing."
	elseif humanoid and humanoid.SeatPart then
		return "Get out of the seat first."
	end
	task.spawn(run, workspace:GetServerTimeNow(), true)
	return nil
end

local function skip()
	local s = scene
	if s and kit.skip.Visible then
		if not s.preview then
			kit.remote:FireServer("skip")
		end
		finish(s, false)
	end
end

function Intro.start()
	local animation = ReplicatedStorage:WaitForChild("Animation", 10)
	assert(animation, "ReplicatedStorage.Animation is missing (the animation runtime, Rojo project)")
	AnimPlayer = require(animation:WaitForChild("Roblox"):WaitForChild("AnimPlayer")) :: any
	Gait = require(animation:WaitForChild("Gait")) :: any
	Performance = require(animation:WaitForChild("Performance")) :: any

	local story = asset(ReplicatedStorage, "Story", "Folder")
	local audio = asset(ReplicatedStorage, "Audio", "Folder")
	local gui = asset(player:WaitForChild("PlayerGui"), "Cutscene", "ScreenGui")
	local giant = asset(story, "BaconRig", "Model")
	local fat = asset(story, "BaconFat", "Model")
	assert(giant.PrimaryPart and fat.PrimaryPart, "Story.BaconRig and Story.BaconFat need a PrimaryPart (their pivot is at their feet)")
	kit = {
		gui = gui,
		skip = Hud.find(gui, "Skip"),
		blur = asset(Lighting, "IntroBlur", "BlurEffect"),
		giant = giant,
		fat = fat,
		straw = asset(story, "Straw", "BasePart"),
		puddle = asset(story, "Puddle", "BasePart"),
		remote = asset(ReplicatedStorage:WaitForChild("Remotes"), "Intro", "RemoteEvent"),
		sounds = {},
	}
	for _, name in { "TopLid", "BottomLid", "Black", "Logo", "Logo.Pop", "Scale" } do
		Hud.find(gui, name)
	end
	local preload: { Instance } = { gui.Logo }
	for _, cue in IntroCut.sounds do
		local sound = asset(audio, cue.sound, "Sound")
		assert(sound.SoundGroup, `Audio.{cue.sound} has no SoundGroup`)
		kit.sounds[cue.sound] = sound
		table.insert(preload, sound)
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(preload, function(id, status)
			if status == Enum.AssetFetchStatus.Failure then
				warn(`[Intro] couldn't load {id}`)
			end
		end)
	end)
	local press = Hud.find(gui, "Skip.Press")
	Hud.pressable(kit.skip, press)
	kit.skip.Activated:Connect(skip)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonB then
			skip()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			mouseMovedAt = os.clock()
		end
	end)

	local function onPhase()
		local phase = ReplicatedStorage:GetAttribute("Phase")
		if phase == "intro" then
			if scene and scene.preview then
				finish(scene, false) -- the team's own comes first
			end
			task.spawn(play)
		elseif scene then
			finish(scene, false)
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	ReplicatedStorage:GetAttributeChangedSignal("IntroAt"):Connect(onPhase)
	onPhase()
end

return Intro
