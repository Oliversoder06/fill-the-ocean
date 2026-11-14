-- The story cutscenes' player (client/Intro, client/Ending: each is a scene, a cut of shared data
-- (shared/IntroCut, shared/EndCut) and its own pieces). A cut plays while the server's Phase is its
-- phase, on the server's clock from its start attribute, so the whole team sees the same frame.
-- Everything in it is this client's own, in a workspace folder (the scene's name): a copy of your
-- avatar, a copy of your lounger turned to face the sea (the place's one hides meanwhile) and the
-- bacon-hair (ReplicatedStorage.Story.BaconRig); the scene adds its own. The HUD, the chat, every
-- character (re-hidden every frame: late spawns, streamed parts and accessories never show), the
-- prompts and the touch controls are off, and your character waits, anchored, where play starts. A
-- cut with a `handover` gives the game its own view back there (the intro); one without ends on
-- black and holds it until the lobby takes over (the ending). Skip (StarterGui.Cutscene.Skip, from
-- the cut's skipAfter, or gamepad B) and the cut's end tell the server (Intro remote); the phase
-- leaving the cut's ends it here. A preview (the admin window) is this client's alone.
-- Studio: the scene's hold attribute (StudioIntroAt, StudioEndingAt) holds the cut on that second.
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
local Arrival = require(script.Parent.Arrival)
local Hud = require(script.Parent.Hud)
local Music = require(script.Parent.Music)
local Sea = require(script.Parent.Sea)
local Staff = require(script.Parent.Staff)

local STEP = "Cutscene"
local CORE_OFF = { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu }
local SOUND_LATE = 0.3 -- seconds late after which a one-shot sound is left out (a late join, a seek)
local MUSIC_DRIFT = 0.15 -- seconds the music may drift from the cut's clock before it is put back
local SOUND_FADE = TweenInfo.new(0.6) -- sounds still playing when the cut is skipped
local LOOK_LAG = 0.25 -- seconds the camera's aim trails a walking body, so it doesn't bob with the steps
local HEAD_FADE = { far = 3, near = 1.2 } -- studs from your copy's head: it fades as the camera goes in
local EYE_UP = 0.1 -- of the head's height: your eyes over its middle, at its front
local ZOOM = 0.5 -- first person's camera distance behind its focus, until it is measured
local PATH_SAMPLES = 40 -- a stroll's curve is measured in this many pieces
local SEA = Vector3.new(0, 0, -1)
local REMOVED = { HeldTool = true, HeldGrip = true, WornBackpack = true } -- server/HeldTools' parts
local CHARACTER_WAIT = 5 -- seconds a cut waits for your character to spawn
local STREAM_WAIT = 10 -- seconds it waits for the beach to stream in here (StreamingEnabled)
local CURSOR_SECONDS = 2 -- the mouse cursor shows for this long after the mouse moves (for Skip)
local HOLD_SECONDS = 15 -- a cut that ends on black holds it this long for the lobby to take over
local COVER_FADE = TweenInfo.new(0.6) -- the black from joining fades into play when no cut comes

local player = Players.LocalPlayer
local Cutscene = {}
Cutscene.SEA = SEA

local AnimPlayer: any
local kit: any = nil -- the place's pieces (Cutscene.start)
local scene: any = nil -- the cut playing now
local mouseMovedAt = -math.huge
local cover = { on = false, tween = nil :: Tween?, order = 0 } -- the black from joining (Cutscene.cover)

local function v3(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
end
Cutscene.v3 = v3

local function asset(parent: Instance, name: string, class: string): any
	local found = parent:WaitForChild(name, 10)
	assert(found and found:IsA(class), `{parent:GetFullName()} is missing {name} (a {class}; built in Studio)`)
	return found
end
Cutscene.asset = asset

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
groundParams.IgnoreWater = true -- the ocean is terrain water

-- The ground's height under (x, z), past every character and the scene.
local function groundAt(x: number, z: number, ignore: { Instance }): number
	groundParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, 100, z), Vector3.new(0, -200, 0), groundParams)
	assert(hit, `[Cutscene] no ground under ({x}, {z}) here: it hasn't streamed in`)
	return hit.Position.Y
end
Cutscene.groundAt = groundAt

-- Keeps a character hidden here (parts, decals and its name), whatever streams or loads into it
-- later (accessories come after it spawns); rays for the ground pass through it.
local function hide(s, character: Model)
	if not s.hidden[character] then
		s.hidden[character] = true
		table.insert(s.ignore, character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local was = humanoid.DisplayDistanceType
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			table.insert(s.undo, function()
				humanoid.DisplayDistanceType = was
			end)
		end
		table.insert(s.undo, function()
			for _, inst in character:GetDescendants() do
				if inst:IsA("BasePart") or inst:IsA("Decal") then
					inst.LocalTransparencyModifier = 0
				end
			end
		end)
	end
	for _, inst in character:GetDescendants() do
		if (inst:IsA("BasePart") or inst:IsA("Decal")) and inst.LocalTransparencyModifier ~= 1 then
			inst.LocalTransparencyModifier = 1
		end
	end
end

-- Only your own copy shows in the cut: every player's character stays hidden here (yours too: the
-- default camera shows it again every frame).
local function hideCharacters(s)
	for _, other in Players:GetPlayers() do
		if other.Character then
			hide(s, other.Character)
		end
	end
end

-- A copy of your avatar for the cut: no scripts, nothing in hand or on the back, anchored at the
-- root, nothing to collide with, no name over it. Its Animator stays: it plays your walk.
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

-- A copy of a Story model, anchored at its PrimaryPart and out of every ray. `animated` keeps its
-- Animator (the bacon-hair's walk); without one nothing resets the joints this turns (the ball's neck).
local function copyStory(template: Model, animated: boolean): Model
	local copy = template:Clone()
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = part == copy.PrimaryPart
			part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
		elseif part:IsA("Humanoid") then
			part.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			part.EvaluateStateMachine = false
		elseif part:IsA("Animator") and not animated then
			part:Destroy()
		end
	end
	return copy
end
Cutscene.copyStory = copyStory

-- A copy of a Story part, anchored and out of every ray.
function Cutscene.copyPart(template: BasePart): BasePart
	local part = template:Clone()
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	return part
end

-- What AnimPlayer leaves to follow the part it hangs on: outfit welds (Staff.outfit) and every
-- accessory (newer avatars hang them on rigid constraints).
local function outfitOf(model: Model): { Instance }
	local list = Staff.outfit(model)
	for _, accessory in model:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
		if handle then
			table.insert(list, handle)
		end
	end
	return list
end

-- A model's Animator (the Humanoid's), to play a Roblox walk on.
local function animatorOf(model: Model): Animator
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid, `{model.Name} has no Humanoid to walk with`)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator :: Animator
end

-- Your copy's head and what hangs on it (the face, hair, hats): what fades as the camera goes in.
local function headParts(model: Model, head: BasePart): { Instance }
	local list: { Instance } = { head }
	for _, d in head:GetChildren() do
		if d:IsA("Decal") then
			table.insert(list, d)
		end
	end
	for _, accessory in model:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			for _, a in handle:GetChildren() do
				if a:IsA("Attachment") and head:FindFirstChild(a.Name) then
					table.insert(list, handle)
					for _, d in handle:GetDescendants() do
						if d:IsA("Decal") then
							table.insert(list, d)
						end
					end
					break
				end
			end
		end
	end
	return list
end

-- Your avatar's walk (its Animate script's) and its pace: Roblox's Animate plays it at the walk
-- speed / (IntroClips.walks.player.pace x the body's height scale), so a copy stepped at that pace
-- keeps its feet still on the ground.
local function walkOf(character: Model, humanoid: Humanoid): (string, number)
	local animate = character:FindFirstChild("Animate")
	local walk = animate and animate:FindFirstChild("walk")
	local animation = walk and walk:FindFirstChildOfClass("Animation")
	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local walks = IntroClips.walks
	local id = if animation and animation.AnimationId ~= "" then animation.AnimationId elseif r6 then walks.bacon.id else walks.player.default
	if r6 then
		return id, walks.bacon.pace -- R6's Animate steps the classic walk (the bacon-hair's) at speed / 14.5
	end
	local scale = 1
	if humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.AutomaticScalingEnabled then
		local damping = animate and animate:FindFirstChild("ScaleDampeningPercent")
		scale = if damping and damping:IsA("NumberValue") then 1 + (humanoid.HipHeight - 2) * damping.Value / 2 else humanoid.HipHeight / 2
	end
	return id, IntroClips.walks.player.pace * math.max(scale, 0.25)
end

-- Where the game's first-person camera sits over the root part (its focus) and how far behind that:
-- measured off the camera while it is the game's, else Roblox's own numbers.
local function gameEye(camera: Camera, humanoid: Humanoid, root: BasePart): (Vector3, number)
	local focus = camera.Focus.Position - root.Position
	local zoom = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	local flat = Vector3.new(focus.X, 0, focus.Z)
	if camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid and flat.Magnitude < 0.05 and focus.Y > 0 and focus.Y < 4 and zoom < 1 then
		return Vector3.new(0, focus.Y, 0), zoom
	end
	local height = if humanoid.RigType == Enum.HumanoidRigType.R6 then 1.5 elseif humanoid.AutomaticScalingEnabled then 1.5 + root.Size.Y / 2 - 1 else 2
	return Vector3.new(0, height, 0) + humanoid.CameraOffset, ZOOM
end

-- A walk's way: a curve on the ground from `a` past `b` to `c` (y ignored), measured along its length.
function Cutscene.curve(a: Vector3, b: Vector3, c: Vector3): any
	local lengths = { 0 }
	local last = a
	for i = 1, PATH_SAMPLES do
		local u = i / PATH_SAMPLES
		local p = a * (1 - u) ^ 2 + b * (2 * u * (1 - u)) + c * (u * u)
		table.insert(lengths, lengths[i] + (p - last).Magnitude)
		last = p
	end
	return { a = a, b = b, c = c, lengths = lengths, length = lengths[#lengths] }
end

-- The point `d` studs along a curve and the way ahead there; before its start, back along its first
-- direction.
function Cutscene.along(path: any, d: number): (Vector3, Vector3)
	local a, b, c = path.a, path.b, path.c
	if d < 0 then
		return a + (b - a).Unit * d, (b - a).Unit
	end
	d = math.min(d, path.length)
	local lengths = path.lengths
	local i = 1
	while i < PATH_SAMPLES and lengths[i + 1] < d do
		i += 1
	end
	local span = lengths[i + 1] - lengths[i]
	local u = (i - 1 + (if span > 0 then (d - lengths[i]) / span else 0)) / PATH_SAMPLES
	local p = a * (1 - u) ^ 2 + b * (2 * u * (1 - u)) + c * (u * u)
	local ahead = (b - a) * (2 * (1 - u)) + (c - b) * (2 * u)
	return p, ahead.Unit
end

-- How far along a walk (studs) you are at `t`: IntroCut.walked's share of the way; before it starts,
-- that many seconds back at its steady pace (already walking when the camera finds you).
function Cutscene.walkedAt(t: number, from: number, to: number, length: number): number
	if t < from then
		local span = to - from
		return (t - from) * length / (span - math.min(IntroCut.stopSeconds, span) / 2)
	end
	return IntroCut.walked(t, from, to) * length
end

-- The place's lounger nearest IntroCut.places.lounger, once it has streamed in here.
local function findLounger(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local beach = map and map:FindFirstChild("Beach")
	if not beach then
		return nil
	end
	local at, best, bestDistance = v3(IntroCut.places.lounger), nil, math.huge
	for _, child in beach:GetChildren() do
		if child.Name == "Stage_Pool_Lounger" and child:IsA("BasePart") then
			local d = (child.Position - at).Magnitude
			if d < bestDistance then
				best, bestDistance = child, d
			end
		end
	end
	return if best and bestDistance < 2 then best else nil
end

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }
terrainParams.IgnoreWater = true -- client/Sea's water is there before the sand under it streams in

-- Whether the beach the cut stands on has streamed in here: the sand under its places and the lounger.
local function beachLoaded(def): boolean
	for _, p in def.ground do
		if not workspace:Raycast(Vector3.new(p[1], 100, p[3]), Vector3.new(0, -200, 0), terrainParams) then
			return false
		end
	end
	return findLounger() ~= nil
end

-- A place on the ground: { x, _, z } at the ground's height.
function Cutscene.onGround(place: { number }, ignore: { Instance }): Vector3
	return Vector3.new(place[1], groundAt(place[1], place[3], ignore), place[3])
end

-- Bakes a clip for a body; a pose the body can't reach shows in the output.
function Cutscene.bake(anim: any, clip: any): any
	local baked = anim:bake(clip)
	for _, warning in baked.warnings do
		warn(`[Cutscene] {clip.name}: {warning}`)
	end
	return baked
end

function Cutscene.show(model: Instance, on: boolean, folder: Folder)
	local parent = if on then folder else nil
	if model.Parent ~= parent then
		model.Parent = parent
	end
end

local function fade(list: { Instance }, amount: number)
	for _, inst in list do
		Hud.set(inst, "LocalTransparencyModifier", amount)
	end
end

-- A straw part from `a` to `b` (the template is a cylinder along its X).
function Cutscene.strawBetween(part: BasePart, a: Vector3, b: Vector3)
	part.Size = Vector3.new((b - a).Magnitude, part.Size.Y, part.Size.Z)
	part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
end

-- A camera aim that trails `target` by `lag` seconds.
function Cutscene.follow(s, name: string, target: Vector3, lag: number, dt: number)
	local was = s.aim[name]
	s.aim[name] = if was then was:Lerp(target, 1 - math.exp(-dt / lag)) else target
end

-- The water: "full", "dry", or the run's own. The cut holds this client's open sea (client/Sea);
-- the server's water over the seabed follows the team's cut by itself (server/Run), and a preview
-- leaves that as it is.
function Cutscene.setWater(s, want: "full" | "dry" | "run")
	if s.water == want then
		return
	end
	s.water = want
	Sea.hold(if want == "full" then 1 elseif want == "dry" then 0 else nil)
end

-- Your copy walking `d` studs along `path` on your own walk (stepped by the distance, so its feet
-- never slide), turning over its last `turnStuds` to face `facing`.
function Cutscene.walk(s, path: any, d: number, facing: Vector3?, turnStuds: number)
	if not s.walkTrack then
		s.walkTrack = s.animator:LoadAnimation(s.walkAnimation)
		s.walkTrack.Looped = true
	end
	if not s.walkTrack.IsPlaying then
		s.walkTrack:Play(0, 1, 0)
	end
	local p, ahead = Cutscene.along(path, d)
	local turn = if facing then math.clamp(1 - (path.length - d) / turnStuds, 0, 1) else 0
	local at = Vector3.new(p.X, groundAt(p.X, p.Z, s.ignore) + s.rootHeight, p.Z)
	s.body:PivotTo(CFrame.lookAt(at, at + ahead:Lerp(facing or ahead, turn)))
	if s.walkTrack.Length > 0 then
		s.walkTrack.TimePosition = (d / s.pace) % s.walkTrack.Length
	end
end

-- Builds the scene and takes the screen. Returns nil when your character isn't there. A preview puts
-- your character and your view back where they were at the end.
local function begin(def, at: number, preview: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and root:IsA("BasePart") and humanoid) then
		return nil
	end
	local camera = workspace.CurrentCamera
	local places = IntroCut.places
	local s: any = {
		def = def,
		cut = def.cut,
		at = at,
		preview = preview,
		view = camera.CFrame,
		fov = camera.FieldOfView,
		undo = {} :: { () -> () }, -- put back at the end
		screen = {} :: { () -> () }, -- put back at the handover
		sounds = {} :: { [number]: Sound | false },
		water = "",
		handed = false,
		finished = false,
		aim = {} :: { [string]: Vector3 },
		eyeAt = v3(places.eye),
		kit = kit,
		AnimPlayer = AnimPlayer,
	}
	local undo = s.undo
	local folder = Instance.new("Folder")
	folder.Name = def.name .. "Scene"
	folder.Parent = workspace
	s.folder = folder
	s.ignore = { folder } :: { Instance }
	s.hidden = {} :: { [Model]: boolean }
	hideCharacters(s)
	local ignore = s.ignore

	-- Where play starts, and the game's own view there (the intro's last frame).
	local focus, zoom = gameEye(camera, humanoid, root)
	s.rootHeight = humanoid.HipHeight + root.Size.Y / 2
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg")
		assert(leg and leg:IsA("BasePart"), "your R6 avatar has no Left Leg")
		s.rootHeight += leg.Size.Y -- R6 stands on its legs; its HipHeight is only an offset (Roblox docs)
	end
	s.stand = Cutscene.onGround(places.stand, ignore) + Vector3.new(0, s.rootHeight, 0)
	s.standLook = v3(places.standLook).Unit
	s.standEye = s.stand + focus - s.standLook * zoom

	-- Your copy, standing beside the lounger facing the sea where it lies down (IntroClips.lie). Its
	-- accessories hang on welds or rigid constraints; the animation leaves them to follow.
	s.lieRoot = Cutscene.onGround(places.walkTo, ignore) + Vector3.new(0, s.rootHeight, 0)
	local walkId
	walkId, s.pace = walkOf(character, humanoid)
	s.walkAnimation = Instance.new("Animation")
	s.walkAnimation.AnimationId = walkId
	local body = copyAvatar(character)
	s.body = body
	s.anim = AnimPlayer.new(body, { ignore = outfitOf(body) })
	s.animator = animatorOf(body)
	local head = body:FindFirstChild("Head")
	assert(head and head:IsA("BasePart"), "your avatar has no Head")
	s.head = head
	s.headParts = headParts(body, head)
	s.feet = {} :: { BasePart }
	for _, name in { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" } do
		local foot = body:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			table.insert(s.feet, foot)
		end
	end
	body.Parent = nil

	-- Your character waits where play starts, anchored and hidden, facing the game's first view; so
	-- does everyone else's.
	local stoodAt = character:GetPivot()
	root.Anchored = true
	local facing = Vector3.new(s.standLook.X, 0, s.standLook.Z).Unit
	character:PivotTo(CFrame.lookAt(s.stand, s.stand + facing))
	table.insert(undo, function()
		root.Anchored = false
	end)
	if preview then
		table.insert(undo, function() -- runs before the unanchoring above (undo goes backwards)
			character:PivotTo(stoodAt)
		end)
	end

	-- The lounger, turned round to face the sea; the place's own hides until the end (out of view by
	-- then, so nobody sees it turn back).
	local lounger = findLounger()
	assert(lounger, "workspace.Map.Beach has no Stage_Pool_Lounger at IntroCut.places.lounger")
	local turned = lounger:Clone()
	turned:ClearAllChildren()
	turned.CFrame = lounger.CFrame * CFrame.Angles(0, math.pi, 0)
	turned.Anchored, turned.CanCollide, turned.CanTouch, turned.CanQuery = true, false, false, false
	turned.Parent = folder
	lounger.LocalTransparencyModifier = 1
	table.insert(undo, function()
		lounger.LocalTransparencyModifier = 0
	end)

	-- The bacon-hair on the beach, on his own R6 walk.
	s.walker = copyStory(kit.walker, true)
	s.walkerAnim = AnimPlayer.new(s.walker, { ignore = outfitOf(s.walker) })
	s.walkerAnimator = animatorOf(s.walker)
	local walkerHead = s.walker:FindFirstChild("Head")
	assert(walkerHead and walkerHead:IsA("BasePart"), "Story.BaconRig has no Head")
	s.walkerHead = walkerHead

	def.build(s)

	-- The screen: the HUD, the cursor, the chat and your controls off (back at the handover); the
	-- cut's own on top.
	local screen = s.screen
	local hudGui = player.PlayerGui:FindFirstChild("Hud")
	local cursorGui = player.PlayerGui:FindFirstChild("Cursor")
	for _, gui in { hudGui, cursorGui } do
		if gui and gui:IsA("ScreenGui") then
			local was = gui.Enabled
			gui.Enabled = false
			table.insert(screen, function()
				gui.Enabled = was
			end)
		end
	end
	for _, kind in CORE_OFF do
		local was = StarterGui:GetCoreGuiEnabled(kind)
		StarterGui:SetCoreGuiEnabled(kind, false)
		table.insert(screen, function()
			StarterGui:SetCoreGuiEnabled(kind, was)
		end)
	end
	for _, config in { TextChatService:FindFirstChildOfClass("ChatWindowConfiguration"), TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration") } do
		if config then
			local was = (config :: any).Enabled
			;(config :: any).Enabled = false
			table.insert(screen, function()
				(config :: any).Enabled = was
			end)
		end
	end
	local touch = GuiService.TouchControlsEnabled
	GuiService.TouchControlsEnabled = false
	table.insert(screen, function()
		GuiService.TouchControlsEnabled = touch
	end)
	Music.hush(true)
	table.insert(screen, function()
		Music.hush(false)
	end)
	ProximityPromptService.Enabled = false
	table.insert(undo, function()
		ProximityPromptService.Enabled = true
	end)
	local fov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	table.insert(undo, function()
		camera.FieldOfView = fov
	end)
	local gui = kit.gui
	if cover.tween then
		cover.tween:Cancel()
		cover.tween = nil
	end
	if cover.on then -- the cut takes the screen from the black it opens on
		cover.on = false
		gui.DisplayOrder = cover.order
	end
	gui.Scale.Scale = Hud.uiScale()
	gui.Enabled = true
	kit.skip.Visible = false
	return s
end

-- A camera key's place or subject this frame: the shared ones, else the scene's own.
local function subject(s, name: any): Vector3
	if type(name) == "table" then
		return v3(name)
	elseif name == "player" then
		return s.aim.player
	elseif name == "bacon" then
		return s.aim.bacon
	elseif name == "eye" then
		return s.eyeAt
	elseif name == "stand" then
		return s.standEye
	elseif name == "standLook" then
		return s.standEye + s.standLook * 100
	end
	local own = s.def.subject(s, name)
	assert(own, `{s.def.name} names a camera subject it doesn't know: {name}`)
	return own
end

-- A key's zoom; your eyes where play starts see as the game does.
local function tanHalf(s, key): number
	return math.tan(math.rad(if key.at == "stand" then s.fov else key.fov) / 2)
end

-- The cut's shot on screen at `t` (its first before any starts).
local function shotAt(cut, t: number): any
	local current = cut.shots[1]
	for _, shot in cut.shots do
		if shot.at <= t then
			current = shot
		end
	end
	return current
end

local function camera(s, t: number)
	local cut = s.cut
	local shot = shotAt(cut, t)
	local cf: CFrame, half: number
	if shot.spline then
		-- one smooth move through every key: the place, the way it looks and the zoom
		local weights = IntroCut.spline(shot.keys, t)
		local at = Vector3.zero
		half = 0
		for _, pair in weights do
			local key = shot.keys[pair[1]]
			at += subject(s, key.at) * pair[2]
			half += tanHalf(s, key) * pair[2]
		end
		local ahead = Vector3.zero
		for _, pair in weights do
			ahead += (subject(s, shot.keys[pair[1]].look) - at).Unit * pair[2]
		end
		cf = CFrame.lookAt(at, at + ahead)
	else
		-- eased between the keys' places, turning in yaw and pitch so the horizon stays level
		local a, b, alpha = IntroCut.segment(shot.keys, t)
		local fromA, fromB = subject(s, a.at), subject(s, b.at)
		local dirA, dirB = (subject(s, a.look) - fromA).Unit, (subject(s, b.look) - fromB).Unit
		local yawA = math.atan2(-dirA.X, -dirA.Z)
		local turn = (math.atan2(-dirB.X, -dirB.Z) - yawA + math.pi) % (2 * math.pi) - math.pi -- the short way
		local yaw = yawA + turn * alpha
		local pitch = math.asin(dirA.Y) + (math.asin(dirB.Y) - math.asin(dirA.Y)) * alpha
		local at = fromA:Lerp(fromB, alpha)
		cf = CFrame.lookAt(at, at + Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)))
		local ta, tb = tanHalf(s, a), tanHalf(s, b)
		half = ta + (tb - ta) * alpha -- the zoom eases as it looks, not in degrees
	end
	for _, shake in cut.shakes do
		local u = (t - shake.at) / shake.seconds
		if u > 0 and u < 1 then
			cf *= CFrame.new(Ease.shake(u, shake.cycles, shake.studs), Ease.shake(u, shake.cycles * 0.7, shake.studs * 0.6), 0)
		end
	end
	local cam = workspace.CurrentCamera
	cam.CFrame = cf
	Hud.set(cam, "FieldOfView", math.deg(2 * math.atan(half)))
end

-- The screen's overlays: eyelids, blur, black, logo, Skip.
local function overlays(s, t: number)
	local cut = s.cut
	local gui = kit.gui
	local lids = IntroCut.value(cut.lids, t)
	for _, lid in { gui.TopLid, gui.BottomLid } do
		Hud.set(lid, "Visible", lids > 0.001)
		Hud.set(lid, "Size", UDim2.fromScale(1, lids * 0.5))
	end
	local blur = IntroCut.value(cut.blur, t)
	Hud.set(kit.blur, "Enabled", blur > 0.05)
	Hud.set(kit.blur, "Size", blur)
	Hud.set(gui.Black, "BackgroundTransparency", 1 - IntroCut.value(cut.black, t))
	Hud.set(gui.Logo, "ImageTransparency", 1 - IntroCut.value(cut.logoAlpha, t))
	Hud.set(gui.Logo.Pop, "Scale", IntroCut.value(cut.logoScale, t))
	Hud.set(kit.skip, "Visible", t >= cut.skipAfter and t < (cut.handover or cut.length))
end

-- Sounds start on their cue (left out when well past it, but for the music) and stop or fade.
local function sounds(s, t: number)
	local cut = s.cut
	for i, cue in cut.sounds do
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
				Hud.set(sound, "Volume", cue.volume * IntroCut.value(cut.music, t))
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

-- What the camera aims at this frame: walking bodies trail by LOOK_LAG (not bobbing with each step);
-- your eyes while your copy shows (kept once it is gone).
local function aims(s, dt: number)
	if s.body.Parent then
		local head = s.head
		local low = head.Position -- your body's middle: between your head and your lowest foot
		for _, foot in s.feet do
			if foot.Position.Y < low.Y then
				low = foot.Position
			end
		end
		Cutscene.follow(s, "player", (head.Position + low) / 2, LOOK_LAG, dt)
		s.eyeAt = (head.CFrame * CFrame.new(0, head.Size.Y * EYE_UP, -head.Size.Z / 2)).Position
	end
	Cutscene.follow(s, "bacon", s.walkerHead.Position, LOOK_LAG, dt)
end

local function restoreScreen(s)
	for i = #s.screen, 1, -1 do
		s.screen[i]()
	end
	table.clear(s.screen)
end

-- The game's own view from here: your eyes where play starts (the camera keeps this exact view as it
-- becomes the game's again), the HUD and the run's water back; the scene adds its own.
local function handover(s)
	s.handed = true
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(s.standEye, s.standEye + s.standLook)
	cam.FieldOfView = s.fov
	cam.CameraType = Enum.CameraType.Custom
	if s.def.handover then
		s.def.handover(s)
	end
	kit.gui.Enabled = false
	kit.blur.Enabled = false
	kit.blur.Size = 0
	Cutscene.setWater(s, "run")
	restoreScreen(s)
end

-- Ends the cut: `played` when it ran to its end (its last sounds play out; skipped, they fade). A
-- team's cut without a handover holds black for the lobby to take over (HOLD_SECONDS at most).
local function finish(s, tellServer: boolean, played: boolean)
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
	for i, sound in s.sounds do
		if not sound then
			continue
		end
		if played and not s.cut.sounds[i].music and sound.IsPlaying then
			sound.Ended:Once(function()
				sound:Destroy()
			end)
		else
			TweenService:Create(sound, SOUND_FADE, { Volume = 0 }):Play()
			task.delay(SOUND_FADE.Time, sound.Destroy, sound)
		end
	end
	local holding = s.cut.handover == nil and not s.preview
	if holding then
		kit.gui.Black.BackgroundTransparency = 0
		kit.skip.Visible = false
		task.delay(HOLD_SECONDS, function()
			if scene == nil then
				handover(s)
			end
		end)
	elseif not s.handed then
		handover(s)
	end
	s.def.finish(s)
	s.anim:destroy()
	s.walkerAnim:destroy()
	s.folder:Destroy()
	s.body:Destroy()
	s.walker:Destroy()
	for i = #s.undo, 1, -1 do
		s.undo[i]()
	end
	if s.preview then -- back to where the preview began
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = s.view
		cam.CameraType = Enum.CameraType.Custom
	end
end

local function frame(s, dt: number)
	local cut = s.cut
	local hold = if RunService:IsStudio() then workspace:GetAttribute(s.def.hold) else nil
	local t = if type(hold) == "number" then hold else workspace:GetServerTimeNow() - s.at
	if t >= cut.length then
		finish(s, not s.preview, true)
		return
	end
	sounds(s, t)
	if cut.handover and t >= cut.handover then
		if not s.handed then
			handover(s)
		end
		return
	end
	s.def.frame(s, t, dt)
	aims(s, dt)
	camera(s, t)
	overlays(s, t)
	if s.body.Parent then
		local near = (workspace.CurrentCamera.CFrame.Position - s.head.Position).Magnitude
		fade(s.headParts, math.clamp((HEAD_FADE.far - near) / (HEAD_FADE.far - HEAD_FADE.near), 0, 1))
	end
	-- only your own copy shows, and the cursor is free for Skip
	hideCharacters(s)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	Hud.set(UserInputService, "MouseIconEnabled", kit.skip.Visible and os.clock() - mouseMovedAt < CURSOR_SECONDS)
end

-- Plays a cut from `at` (server time of its first frame) once your character and the beach under
-- the scene are there. A preview is this client's alone: the server is never told.
local function run(def, at: number, preview: boolean)
	local deadline = os.clock() + CHARACTER_WAIT
	while not (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) and os.clock() < deadline do
		task.wait(0.1)
	end
	deadline = os.clock() + STREAM_WAIT
	while not beachLoaded(def) and os.clock() < deadline do
		task.wait(0.1)
	end
	if scene or not (preview or ReplicatedStorage:GetAttribute("Phase") == def.phase) then
		return
	end
	local s = if beachLoaded(def) then begin(def, at, preview) else nil
	if not s then
		warn(`[Cutscene] no character, or the beach hasn't streamed in here; the {def.name} is skipped here`)
		if not preview then
			kit.remote:FireServer("done")
		end
		return
	end
	scene = s
	Hud.cutscene = true
	-- after the camera, the HUD's cursor and everything else that moves the camera. A frame that
	-- fails ends the cut (reported once, with its stack) rather than failing every frame with the
	-- screen taken
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 4, function(dt: number)
		if scene ~= s then
			return
		end
		local ok, err = xpcall(frame, debug.traceback, s, dt)
		if not ok then
			task.spawn(error, `[Cutscene] the {def.name} failed and was ended: {err}`, 0)
			finish(s, not s.preview, false)
		end
	end)
end

-- The team's cut (its Phase).
local function play(def)
	if scene then
		return
	end
	local at = ReplicatedStorage:GetAttribute(def.at)
	if type(at) ~= "number" then
		return -- comes with the start attribute's change
	elseif workspace:GetServerTimeNow() - at >= def.cut.length then
		kit.remote:FireServer("done") -- joined after it ended: nothing to wait for here
		return
	end
	run(def, at, false)
end

-- An admin's preview (client/Admin): the whole cut from now, on this client only, while the run goes
-- on. Returns why it can't start, or nil.
function Cutscene.preview(def): string?
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if scene then
		return "A cutscene is already playing."
	elseif humanoid and humanoid.SeatPart then
		return "Get out of the seat first."
	end
	task.spawn(run, def, workspace:GetServerTimeNow(), true)
	return nil
end

local function skip()
	local s = scene
	if s and kit.skip.Visible then
		if not s.preview then
			kit.remote:FireServer("skip")
		end
		finish(s, false, false)
	end
end

-- The black and the eyelids must reach every physical edge (under the top bar, the notch and rounded
-- corners too): a fullscreen gui that Roblox neither insets, clips nor stretches.
local function fullscreen(gui: ScreenGui)
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
end

-- From joining, the screen is black (the Cutscene gui's Black) until a cut takes it (the intro opens
-- on black) or the run goes on without one, when it fades into play: the world never shows for a
-- moment before the intro. While the run loads it sits under the HUD, so its waiting text shows. The
-- teleport screen you arrived behind (client/Arrival) sits over it: told when the black is up, and
-- when play starts it opens onto play itself, so the black goes at once instead of fading.
local function coverScreen(gui: ScreenGui)
	if scene then
		return
	end
	local phase = ReplicatedStorage:GetAttribute("Phase")
	local black = Hud.find(gui, "Black") :: Frame
	if phase == nil or phase == "loading" or phase == "intro" then
		if cover.tween then
			cover.tween:Cancel()
			cover.tween = nil
		end
		if not cover.on then
			cover.on = true
			cover.order = gui.DisplayOrder
			for _, name in { "TopLid", "BottomLid", "Skip" } do
				(Hud.find(gui, name) :: GuiObject).Visible = false
			end
			(Hud.find(gui, "Logo") :: ImageLabel).ImageTransparency = 1
			gui.Enabled = true
		end
		black.BackgroundTransparency = 0
		gui.DisplayOrder = if phase == "loading" then -1 else cover.order
		Arrival.underBlack(phase)
	elseif cover.on then
		cover.on = false
		gui.DisplayOrder = cover.order
		if Arrival.covering() then
			black.BackgroundTransparency = 1
			gui.Enabled = false
			return
		end
		local tween = TweenService:Create(black, COVER_FADE, { BackgroundTransparency = 1 })
		cover.tween = tween
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and cover.tween == tween then
				cover.tween = nil
				gui.Enabled = false
			end
		end)
		tween:Play()
	end
end

-- Puts up the black from joining; called first thing by the client, before anything else loads.
function Cutscene.cover()
	task.spawn(function()
		local gui = asset(player:WaitForChild("PlayerGui"), "Cutscene", "ScreenGui")
		fullscreen(gui)
		coverScreen(gui)
		ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(function()
			coverScreen(gui)
		end)
	end)
end

-- Loads the place's pieces and plays each scene's cut while the server's Phase is its phase.
function Cutscene.start(defs: { any })
	local animation = ReplicatedStorage:WaitForChild("Animation", 10)
	assert(animation, "ReplicatedStorage.Animation is missing (the animation runtime, Rojo project)")
	AnimPlayer = require(animation:WaitForChild("Roblox"):WaitForChild("AnimPlayer")) :: any

	local story = asset(ReplicatedStorage, "Story", "Folder")
	local audio = asset(ReplicatedStorage, "Audio", "Folder")
	local gui = asset(player:WaitForChild("PlayerGui"), "Cutscene", "ScreenGui")
	local baconRig = asset(story, "BaconRig", "Model")
	assert(baconRig.PrimaryPart, "Story.BaconRig needs a PrimaryPart (its pivot is at its feet)")
	local baconWalk = Instance.new("Animation")
	baconWalk.AnimationId = IntroClips.walks.bacon.id
	kit = {
		gui = gui,
		skip = Hud.find(gui, "Skip"),
		blur = asset(Lighting, "IntroBlur", "BlurEffect"),
		story = story,
		walker = baconRig,
		baconWalk = baconWalk,
		remote = asset(ReplicatedStorage:WaitForChild("Remotes"), "Intro", "RemoteEvent"),
		sounds = {},
	}
	for _, name in { "TopLid", "BottomLid", "Black", "Logo", "Logo.Pop", "Scale" } do
		Hud.find(gui, name)
	end
	-- Skip, the one thing to tap, is kept inside the device's safe area.
	fullscreen(gui)
	local skipAt = kit.skip.Position
	local cutsceneScale = Hud.find(gui, "Scale") :: UIScale
	local function keepSkipSafe()
		local full = GuiService:GetInsetArea(Enum.ScreenInsets.None)
		local safe = GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
		local inset = (full.Max - safe.Max) / cutsceneScale.Scale -- Skip hangs from the bottom right
		kit.skip.Position = skipAt - UDim2.fromOffset(inset.X, inset.Y)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(keepSkipSafe)
	keepSkipSafe()
	local preload: { Instance } = { gui.Logo, baconWalk }
	for _, def in defs do
		def.load(kit)
		for _, cue in def.cut.sounds do
			if not kit.sounds[cue.sound] then
				local sound = asset(audio, cue.sound, "Sound")
				assert(sound.SoundGroup, `Audio.{cue.sound} has no SoundGroup`)
				kit.sounds[cue.sound] = sound
				table.insert(preload, sound)
			end
		end
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(preload, function(id, status)
			if status == Enum.AssetFetchStatus.Failure then
				warn(`[Cutscene] couldn't load {id}`)
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
		for _, def in defs do
			if phase == def.phase then
				if scene and (scene.preview or scene.def ~= def) then
					finish(scene, false, false) -- the team's own comes first
				end
				task.spawn(play, def)
				return
			end
		end
		if scene and not scene.preview then
			finish(scene, false, false)
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	for _, def in defs do
		ReplicatedStorage:GetAttributeChangedSignal(def.at):Connect(onPhase)
	end
	onPhase()
end

return Cutscene
