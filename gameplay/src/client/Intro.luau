-- The intro cutscene. shared/IntroCut is the cut (shots, eyelids, logo, sounds, beats) and
-- shared/IntroClips the bodies' motion; this plays them while Phase is "intro", on the server's clock
-- from IntroAt, so the whole team sees the same frame. Everything in it is this client's own, in a
-- workspace folder IntroScene: a copy of your avatar walks up the beach on its own walk animation
-- (stepped by the distance walked, so its feet never slide) to a copy of your lounger (turned round
-- to face the sea; the place's one is hidden meanwhile), stretches, sits down on it and lies back
-- (IntroClips.lie). The bacon-hair (ReplicatedStorage.Story.BaconRig) strolls onto the beach in
-- front of you, sits down and plays in the sand (Story.SandPile). One camera take (a spline) runs
-- from the music's drop into your eyes as they close. The water stands full, then drains
-- (Zones.setFill); the ball (Story.BaconFat, its Straw down to the Puddle) drinks it far out, burps,
-- rolls for the beach and its slope throws him past you over the island (IntroCut.flight). You get
-- up into the game's own first-person view: from IntroCut.handover the
-- camera is the game's (the same view, no cut), the HUD is back and your tool swings up into your
-- hand (Viewmodel.swingIn); play starts at IntroCut.length. The HUD, the chat, every character,
-- the prompts and the touch controls are off until then, and your character waits, anchored, where
-- play starts. Skip (StarterGui.Cutscene.Skip, from IntroCut.skipAfter, or gamepad B) and the cut's
-- end tell the server (Intro remote); the phase leaving "intro" ends it here.
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
local Viewmodel = require(script.Parent.Viewmodel)

local STEP = "IntroCut"
local CORE_OFF = { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu }
local SOUND_LATE = 0.3 -- seconds late after which a one-shot sound is left out (a late join, a seek)
local MUSIC_DRIFT = 0.15 -- seconds the music may drift from the cut's clock before it is put back
local SOUND_FADE = TweenInfo.new(0.6) -- sounds still playing when the cut is skipped
local LIE_BLEND = 0.35 -- seconds your walk takes to settle into the lie-down's first pose
local TURN_BLEND = 0.2 -- seconds the lie-down's stand hands over to its lie (IntroClips.lie)
local SIT_BLEND = 0.25 -- seconds his walk takes to settle into sitting down
local TURN_STUDS = 1.5 -- over your last steps you turn to face the sea, as the lie-down starts
local LOOK_LAG = 0.25 -- seconds the camera's aim trails a walking body, so it doesn't bob with the steps
local FAT_LAG = 0.06 -- seconds it trails the ball: your head chasing him as he flies past
local HEAD_FADE = { far = 3, near = 1.2 } -- studs from your copy's head: it fades as the camera goes in
local EYE_UP = 0.1 -- of the head's height: your eyes over its middle, at its front
local BACON_LOW = 2 -- studs under him that "baconLow" aims (your eyes getting heavy)
local PILE_GROW = 3.2 -- seconds his sand pile takes to grow
local ZOOM = 0.5 -- first person's camera distance behind its focus, until it is measured
local PATH_SAMPLES = 40 -- a stroll's curve is measured in this many pieces
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
local STREAM_WAIT = 10 -- seconds it waits for the beach to stream in here (StreamingEnabled)
local CURSOR_SECONDS = 2 -- the mouse cursor shows for this long after the mouse moves (for Skip)

local player = Players.LocalPlayer
local Intro = {}

local AnimPlayer: any
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
	assert(hit, `[Intro] no ground under ({x}, {z}) here: it hasn't streamed in`)
	return hit.Position.Y
end

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
local function curve(a: Vector3, b: Vector3, c: Vector3): any
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
local function along(path: any, d: number): (Vector3, Vector3)
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
local function walkedAt(t: number, from: number, to: number, length: number): number
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
local GROUND_PLACES = { "walkFrom", "walkTo", "stand", "baconFrom", "baconBend", "baconTo" }

-- Whether the beach the cut stands on has streamed in here: the sand under its places and the lounger.
local function beachLoaded(): boolean
	for _, name in GROUND_PLACES do
		local p = IntroCut.places[name]
		if not workspace:Raycast(Vector3.new(p[1], 100, p[3]), Vector3.new(0, -200, 0), terrainParams) then
			return false
		end
	end
	return findLounger() ~= nil
end

-- A place on the ground: { x, _, z } at the ground's height.
local function onGround(place: { number }, ignore: { Instance }): Vector3
	return Vector3.new(place[1], groundAt(place[1], place[3], ignore), place[3])
end

-- Bakes a clip for a body; a pose the body can't reach shows in the output.
local function bake(anim: any, clip: any): any
	local baked = anim:bake(clip)
	for _, warning in baked.warnings do
		warn(`[Intro] {clip.name}: {warning}`)
	end
	return baked
end

-- Builds the scene and takes the screen. Returns nil when your character isn't there. A preview puts
-- your character and your view back where they were at the end.
local function begin(at: number, preview: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and root:IsA("BasePart") and humanoid) then
		return nil
	end
	local camera = workspace.CurrentCamera
	local places = IntroCut.places
	local s: any = {
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
	}
	local undo = s.undo
	local folder = Instance.new("Folder")
	folder.Name = "IntroScene"
	folder.Parent = workspace
	s.folder = folder
	s.ignore = { folder } :: { Instance }
	s.hidden = {} :: { [Model]: boolean }
	hideCharacters(s)
	local ignore = s.ignore

	-- Where play starts, and the game's own view there (the cut's last frame).
	local focus, zoom = gameEye(camera, humanoid, root)
	s.rootHeight = humanoid.HipHeight + root.Size.Y / 2
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg")
		assert(leg and leg:IsA("BasePart"), "your R6 avatar has no Left Leg")
		s.rootHeight += leg.Size.Y -- R6 stands on its legs; its HipHeight is only an offset (Roblox docs)
	end
	s.stand = onGround(places.stand, ignore) + Vector3.new(0, s.rootHeight, 0)
	s.standLook = v3(places.standLook).Unit
	s.standEye = s.stand + focus - s.standLook * zoom

	-- Your copy: your walk up the beach (a straight curve), then the lie-down where it stops. Its
	-- accessories hang on welds or rigid constraints; the animation leaves them to follow.
	local walkFrom, walkTo = v3(places.walkFrom), v3(places.walkTo)
	s.walkPath = curve(walkFrom, (walkFrom + walkTo) / 2, walkTo)
	s.lieRoot = onGround(places.walkTo, ignore) + Vector3.new(0, s.rootHeight, 0)
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

	-- The bacon-hair on the beach: his stroll, where he sits and the sand he plays with.
	s.walker = copyStory(kit.walker, true)
	s.walkerAnim = AnimPlayer.new(s.walker, { ignore = outfitOf(s.walker) })
	s.walkerAnimator = animatorOf(s.walker)
	local walkerHead = s.walker:FindFirstChild("Head")
	assert(walkerHead and walkerHead:IsA("BasePart"), "Story.BaconRig has no Head")
	s.walkerHead = walkerHead
	s.baconPath = curve(v3(places.baconFrom), v3(places.baconBend), v3(places.baconTo))
	local sitAt, sitAhead = along(s.baconPath, s.baconPath.length)
	sitAt = Vector3.new(sitAt.X, groundAt(sitAt.X, sitAt.Z, ignore), sitAt.Z)
	s.baconSeat = CFrame.lookAt(sitAt, sitAt + sitAhead)
	local pileAt = s.baconSeat * v3(places.sandPile)
	s.pileAt = Vector3.new(pileAt.X, groundAt(pileAt.X, pileAt.Z, ignore), pileAt.Z)
	s.pile = kit.pile:Clone()
	s.pile.Anchored, s.pile.CanCollide, s.pile.CanTouch, s.pile.CanQuery = true, false, false, false
	s.pileSize = kit.pile.Size.X

	-- The ball far out on the seabed with his straw, once the water is gone.
	local fatAt = v3(places.fat)
	s.fatAt = CFrame.lookAt(fatAt, fatAt - SEA) * CFrame.Angles(0, math.rad(places.baconTurn), 0) -- toward the beach, turned
	s.fat = copyStory(kit.fat, false)
	s.fat:PivotTo(s.fatAt)
	s.belly = asset(s.fat, "Belly", "BasePart")
	s.fatRadius = s.belly.Size.Y / 2
	-- his roll for the beach and his flight off it; the model from his middle
	s.flight = IntroCut.flight(s.fatRadius, workspace.Gravity)
	s.rollAxis = Vector3.new(s.flight.hx, 0, s.flight.hz):Cross(Vector3.yAxis)
	s.fromMiddle = CFrame.new(fatAt + Vector3.new(0, s.fatRadius, 0)):Inverse() * s.fatAt
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
	s.puddleAt = v3(places.puddle)
	-- where his head turns when he notices you: your eyes on the lounger, in his own axes
	local toEye = s.fatAt:VectorToObjectSpace((v3(places.eye) - s.mouth.WorldPosition).Unit)
	s.lookYaw = math.deg(math.atan2(-toEye.X, -toEye.Z))
	s.lookPitch = math.deg(math.asin(toEye.Y))

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
	gui.Scale.Scale = Hud.uiScale()
	gui.Enabled = true
	kit.skip.Visible = false

	-- Bakes take a few frames each; the slump is needed first, the lie-down from IntroCut.beats.lie.
	task.spawn(function()
		s.slumpBaked = bake(s.anim, IntroClips.slump)
		task.wait()
		local rootAt = { s.lieRoot.X, s.lieRoot.Y, s.lieRoot.Z }
		local seat = IntroClips.seat(places.cushion, places.recline, rootAt)
		local stand, lie = IntroClips.lie(s.anim.anatomy, seat, IntroClips.watch(places.baconFrom, places.baconTo, rootAt))
		s.standBaked = bake(s.anim, stand)
		task.wait()
		s.lieBaked = bake(s.anim, lie)
		task.wait()
		s.sitBaked = bake(s.walkerAnim, IntroClips.sandSit)
		task.wait()
		s.playBaked = bake(s.walkerAnim, IntroClips.sandPlay)
	end)
	return s
end

-- A camera key's place or subject this frame.
local function subject(s, name: any): Vector3
	if type(name) == "table" then
		return v3(name)
	elseif name == "player" then
		return s.aim.player
	elseif name == "bacon" then
		return s.aim.bacon
	elseif name == "baconLow" then
		return s.aim.bacon - Vector3.new(0, BACON_LOW, 0)
	elseif name == "eye" then
		return s.eyeAt
	elseif name == "fat" then
		return s.aim.fat
	elseif name == "stand" then
		return s.standEye
	elseif name == "standLook" then
		return s.standEye + s.standLook * 100
	end
	error(`IntroCut names a camera subject the intro doesn't know: {name}`)
end

-- A key's zoom; your eyes where play starts see as the game does.
local function tanHalf(s, key): number
	return math.tan(math.rad(if key.at == "stand" then s.fov else key.fov) / 2)
end

local function camera(s, t: number)
	local shot = IntroCut.shot(t) or IntroCut.shots[1]
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
	for _, shake in IntroCut.shakes do
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
	Hud.set(kit.skip, "Visible", t >= IntroCut.skipAfter and t < IntroCut.handover)
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

-- The water: full until the swap, then drunk dry; the run's own from the handover.
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

local function fade(list: { Instance }, amount: number)
	for _, inst in list do
		Hud.set(inst, "LocalTransparencyModifier", amount)
	end
end

-- Your copy, from the drop until your eyes shut: up the beach on your own walk, a tired slump over
-- it, turning to the sea over the last steps; then the lie-down (IntroClips.lie: the stand, then the
-- lie), blended in from the walk's last step.
local function body(s, t: number)
	local b = IntroCut.beats
	local on = t >= b.drop and t < b.swap
	show(s.body, on, s.folder)
	if not on then
		return
	end
	if not s.walkTrack then
		s.walkTrack = s.animator:LoadAnimation(s.walkAnimation)
		s.walkTrack.Looped = true
	end
	if s.slumpBaked and not s.slump then
		s.slump = s.anim:play(s.slumpBaked, { loop = true, layer = "add", fadeIn = 0, fadeOut = 0 })
	end
	local lying = math.clamp((t - b.lie) / LIE_BLEND, 0, 1)
	if s.slump then
		s.slump:setWeight(1 - lying)
	end
	if t < b.lie then
		if s.standing then -- (back before the lie-down: Studio's StudioIntroAt)
			s.standing:setWeight(0)
			s.lying:setWeight(0)
		end
		if not s.walkTrack.IsPlaying then
			s.walkTrack:Play(0, 1, 0)
		end
		local d = walkedAt(t, b.walkFrom, b.walkTo, s.walkPath.length)
		local p, ahead = along(s.walkPath, d)
		local turn = math.clamp(1 - (s.walkPath.length - d) / TURN_STUDS, 0, 1)
		local at = Vector3.new(p.X, groundAt(p.X, p.Z, s.ignore) + s.rootHeight, p.Z)
		s.body:PivotTo(CFrame.lookAt(at, at + ahead:Lerp(SEA, turn)))
		if s.walkTrack.Length > 0 then
			s.walkTrack.TimePosition = (d / s.pace) % s.walkTrack.Length
		end
	else
		s.body:PivotTo(CFrame.new(s.lieRoot)) -- facing the sea, as IntroClips.lie starts
		if s.walkTrack.IsPlaying then
			s.walkTrack:Stop(LIE_BLEND)
		end
		-- the stand is the older handle, so it is written last: over the lie, fading out at the turn
		if s.standBaked and s.lieBaked and not s.standing then
			s.standing = s.anim:play(s.standBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
			s.standing:setSpeed(0)
			s.lying = s.anim:play(s.lieBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
			s.lying:setSpeed(0)
		end
		if s.standing then
			local into = t - b.lie
			local turned = into - IntroClips.turnSeconds
			s.lying:setWeight(if turned >= 0 then lying else 0)
			s.standing:setWeight(lying * (1 - math.clamp(turned / TURN_BLEND, 0, 1)))
			s.standing:seek(math.clamp(into, 0, s.standBaked.length - 1e-3))
			s.lying:seek(math.clamp(turned, 0, s.lieBaked.length - 1e-3))
		end
	end
end

-- The bacon-hair on the beach, from his stroll in until your eyes shut: walking on his own R6 walk
-- along his curve, slowing to a stop; then he sits down in the sand and plays in it, the pile growing.
local function walker(s, t: number)
	local b = IntroCut.beats
	local on = t >= b.baconFrom and t < b.swap
	show(s.walker, on, s.folder)
	show(s.pile, on and t >= b.baconPlay, s.folder)
	if t < b.baconSit then
		local d = walkedAt(t, b.baconFrom, b.baconTo, s.baconPath.length)
		local p, ahead = along(s.baconPath, d)
		local at = Vector3.new(p.X, groundAt(p.X, p.Z, s.ignore), p.Z)
		s.walker:PivotTo(CFrame.lookAt(at, at + ahead))
		if not on then
			return -- placed all the same: the camera aims ahead of him
		end
		if not s.walkerTrack then
			s.walkerTrack = s.walkerAnimator:LoadAnimation(kit.baconWalk)
			s.walkerTrack.Looped = true
		end
		if not s.walkerTrack.IsPlaying then
			s.walkerTrack:Play(0, 1, 0)
		end
		if s.walkerTrack.Length > 0 then
			s.walkerTrack.TimePosition = (d / IntroClips.walks.bacon.pace) % s.walkerTrack.Length
		end
		-- (back before he sat: Studio's StudioIntroAt)
		if s.sit then
			s.sit:setWeight(0)
		end
		if s.play then
			s.play:setWeight(0)
		end
		return
	end
	s.walker:PivotTo(s.baconSeat)
	if not on then
		return
	end
	if s.walkerTrack and s.walkerTrack.IsPlaying then
		s.walkerTrack:Stop(SIT_BLEND)
	end
	if s.sitBaked and not s.sit then
		s.sit = s.walkerAnim:play(s.sitBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
		s.sit:setSpeed(0)
	end
	if s.playBaked and not s.play then
		s.play = s.walkerAnim:play(s.playBaked, { loop = true, fadeIn = 0, fadeOut = 0 })
		s.play:setSpeed(0)
	end
	-- one at a time: the sit ends on the play's first pose (a stopped clip would put the joints back
	-- for a frame, so the other one just weighs nothing)
	local playing = t >= b.baconPlay
	if s.sit then
		s.sit:setWeight(if playing then 0 else math.clamp((t - b.baconSit) / SIT_BLEND, 0, 1))
		s.sit:seek(math.min(t - b.baconSit, s.sitBaked.length - 1e-3))
	end
	if s.play then
		s.play:setWeight(if playing then 1 else 0)
		s.play:seek(math.max(t - b.baconPlay, 0) % s.playBaked.length)
	end
	if playing then
		local grown = IntroCut.eased("out", math.clamp((t - b.baconPlay) / PILE_GROW, 0, 1))
		local size = s.pileSize * (0.45 + 0.55 * grown)
		local rise = size * (0.12 + 0.1 * grown) -- a ball sunk into the sand: only its top shows
		Hud.set(s.pile, "Size", Vector3.one * size)
		Hud.set(s.pile, "CFrame", CFrame.new(s.pileAt + Vector3.new(0, rise - size / 2, 0)))
	end
end

-- A straw part from `a` to `b` (the template is a cylinder along its X).
local function strawBetween(part: BasePart, a: Vector3, b: Vector3)
	part.Size = Vector3.new((b - a).Magnitude, part.Size.Y, part.Size.Z)
	part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
end

-- The ball, from the swap: drinks the puddle (head down, sucking), looks round at you, burps, rolls
-- for the beach and flies off it (IntroCut.flight).
local function fat(s, t: number)
	local b = IntroCut.beats
	local swapped = t >= b.swap
	local drinking = swapped and t < b.drunk + 0.2
	show(s.fat, swapped, s.folder)
	show(s.straw, drinking, s.folder)
	show(s.strawDown, drinking, s.folder)
	show(s.puddle, swapped and t < b.drunk, s.folder)
	if not swapped then
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
	-- rolling for the beach, then flying: turned about the run's axis by how far he has rolled
	local x, y, z, turned = IntroCut.ballAt(s.flight, t)
	local turn = CFrame.fromAxisAngle(s.rollAxis, -turned)
	s.fat:PivotTo(CFrame.new(x, y + hop, z) * turn * s.fromMiddle)
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

-- What the camera aims at this frame: walking bodies trail by LOOK_LAG (not bobbing with each step),
-- the ball by FAT_LAG; your eyes on the lounger (kept once your copy is gone).
local function aims(s, t: number, dt: number)
	local function follow(name: string, target: Vector3, lag: number)
		local was = s.aim[name]
		s.aim[name] = if was then was:Lerp(target, 1 - math.exp(-dt / lag)) else target
	end
	if t < IntroCut.beats.swap then
		local head = s.head
		local low = head.Position -- your body's middle: between your head and your lowest foot
		for _, foot in s.feet do
			if foot.Position.Y < low.Y then
				low = foot.Position
			end
		end
		follow("player", (head.Position + low) / 2, LOOK_LAG)
		s.eyeAt = (head.CFrame * CFrame.new(0, head.Size.Y * EYE_UP, -head.Size.Z / 2)).Position
	end
	follow("bacon", s.walkerHead.Position, LOOK_LAG)
	follow("fat", s.belly.Position, FAT_LAG)
end

-- The game's own view from here: your eyes where play starts (the camera keeps this exact view as it
-- becomes the game's again), the tool swinging up into your hand, the HUD and the run's water back.
local function handover(s)
	s.handed = true
	show(s.fat, false, s.folder) -- long gone over the island
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(s.standEye, s.standEye + s.standLook)
	cam.FieldOfView = s.fov
	cam.CameraType = Enum.CameraType.Custom
	Viewmodel.swingIn()
	kit.gui.Enabled = false
	kit.blur.Enabled = false
	kit.blur.Size = 0
	setWater(s, "run")
	for i = #s.screen, 1, -1 do
		s.screen[i]()
	end
	table.clear(s.screen)
end

-- Ends the cut: `played` when it ran to its end (its last sounds play out; skipped, they fade).
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
		if played and not IntroCut.sounds[i].music and sound.IsPlaying then
			sound.Ended:Once(function()
				sound:Destroy()
			end)
		else
			TweenService:Create(sound, SOUND_FADE, { Volume = 0 }):Play()
			task.delay(SOUND_FADE.Time, sound.Destroy, sound)
		end
	end
	if not s.handed then
		handover(s)
	end
	s.anim:destroy()
	s.walkerAnim:destroy()
	s.folder:Destroy()
	s.body:Destroy()
	s.walker:Destroy()
	s.fat:Destroy()
	for _, part in { s.pile, s.straw, s.strawDown, s.puddle } do
		part:Destroy()
	end
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
	local hold = if RunService:IsStudio() then workspace:GetAttribute("StudioIntroAt") else nil
	local t = if type(hold) == "number" then hold else workspace:GetServerTimeNow() - s.at
	if t >= IntroCut.length then
		finish(s, not s.preview, true)
		return
	end
	sounds(s, t)
	if t >= IntroCut.handover then
		if not s.handed then
			handover(s)
		end
		return
	end
	setWater(s, if t < IntroCut.beats.swap then "full" else "dry")
	body(s, t)
	walker(s, t)
	fat(s, t)
	aims(s, t, dt)
	camera(s, t)
	overlays(t)
	if t < IntroCut.beats.swap then
		local near = (workspace.CurrentCamera.CFrame.Position - s.head.Position).Magnitude
		fade(s.headParts, math.clamp((HEAD_FADE.far - near) / (HEAD_FADE.far - HEAD_FADE.near), 0, 1))
	end
	-- only your own copy shows, and the cursor is free for Skip
	hideCharacters(s)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	Hud.set(UserInputService, "MouseIconEnabled", kit.skip.Visible and os.clock() - mouseMovedAt < CURSOR_SECONDS)
end

-- Plays the cut from `at` (server time of its first frame) once your character and the beach under
-- the scene are there. A preview is this client's alone: the server is never told.
local function run(at: number, preview: boolean)
	local deadline = os.clock() + CHARACTER_WAIT
	while not (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) and os.clock() < deadline do
		task.wait(0.1)
	end
	deadline = os.clock() + STREAM_WAIT
	while not beachLoaded() and os.clock() < deadline do
		task.wait(0.1)
	end
	if scene or not (preview or ReplicatedStorage:GetAttribute("Phase") == "intro") then
		return
	end
	local s = if beachLoaded() then begin(at, preview) else nil
	if not s then
		warn("[Intro] no character, or the beach hasn't streamed in here; the intro is skipped here")
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
			task.spawn(error, `[Intro] the cutscene failed and was ended: {err}`, 0)
			finish(s, not s.preview, false)
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
		finish(s, false, false)
	end
end

function Intro.start()
	local animation = ReplicatedStorage:WaitForChild("Animation", 10)
	assert(animation, "ReplicatedStorage.Animation is missing (the animation runtime, Rojo project)")
	AnimPlayer = require(animation:WaitForChild("Roblox"):WaitForChild("AnimPlayer")) :: any

	local story = asset(ReplicatedStorage, "Story", "Folder")
	local audio = asset(ReplicatedStorage, "Audio", "Folder")
	local gui = asset(player:WaitForChild("PlayerGui"), "Cutscene", "ScreenGui")
	local baconRig = asset(story, "BaconRig", "Model")
	local baconFat = asset(story, "BaconFat", "Model")
	assert(baconRig.PrimaryPart and baconFat.PrimaryPart, "Story.BaconRig and Story.BaconFat need a PrimaryPart (their pivot is at their feet)")
	local baconWalk = Instance.new("Animation")
	baconWalk.AnimationId = IntroClips.walks.bacon.id
	kit = {
		gui = gui,
		skip = Hud.find(gui, "Skip"),
		blur = asset(Lighting, "IntroBlur", "BlurEffect"),
		walker = baconRig,
		baconWalk = baconWalk,
		fat = baconFat,
		pile = asset(story, "SandPile", "BasePart"),
		straw = asset(story, "Straw", "BasePart"),
		puddle = asset(story, "Puddle", "BasePart"),
		remote = asset(ReplicatedStorage:WaitForChild("Remotes"), "Intro", "RemoteEvent"),
		sounds = {},
	}
	for _, name in { "TopLid", "BottomLid", "Black", "Logo", "Logo.Pop", "Scale" } do
		Hud.find(gui, name)
	end
	local preload: { Instance } = { gui.Logo, baconWalk }
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
				finish(scene, false, false) -- the team's own comes first
			end
			task.spawn(play)
		elseif scene then
			finish(scene, false, false)
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(onPhase)
	ReplicatedStorage:GetAttributeChangedSignal("IntroAt"):Connect(onPhase)
	onPhase()
end

return Intro
