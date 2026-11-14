-- The first-minute guide (StarterGui.Hud.Guide, built in Studio): one goal at a time for a new save,
-- until the first purchase, at the top centre ("Objective 2/6" over the goal). Walk to the well,
-- scoop until full, carry it to the shore, pour, buy your first upgrade. Each step comes from live
-- state (where you stand, Carried, the team's Wallet, the honeycomb), so walking away goes back a step and nothing is
-- saved. The goal (in guide yellow) says what to do, never where to click: a flat yellow lane from
-- inside the player, just below the camera, leads to the place (a clone of ReplicatedStorage.Vfx.GuideLane:
-- a textured Beam whose texture carries the rails and the sliding chevrons, cut cleanly at both
-- ends; shared/GuideTrail), a click hand (a clone of Hud.Templates.ClickHand) taps the button to press, and
-- Action's ActHint says which key. Each new lane goal turns the camera to face it (CameraFeel.face),
-- and while the hand taps a button Hud.GuideDim darkens the screen around it (four frames framing a
-- hole that follows the button). Skip hides it for the session. Once it is done, Guide.pointTo
-- leads the lane anywhere, turns the camera there and outlines the stand, gate or plot there (a
-- clone of Vfx.GuideHighlight).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local GuideTrail = require(ReplicatedStorage.Shared.GuideTrail)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["clear-tide"])
local CameraFeel = require(script.Parent.CameraFeel)
local Honeycomb = require(script.Parent.Honeycomb)
local Hud = require(script.Parent.Hud)
local Telemetry = require(script.Parent.Telemetry)

local player = Players.LocalPlayer
local set = Hud.set

local CUE = Cues.guide
local STEPS = 6
local DONE_SECONDS = 3
local REPORT_GAP = 0.3 -- seconds between guide step reports (the server takes one per 0.25)
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local Guide = {}

-- Where another module wants the lane to lead while the first-minute guide isn't showing, and what
-- to outline there.
local pointed: Vector3? = nil
local pointedModel: Instance? = nil

-- Lead the ground lane to `position` (nil hides it) and outline `model` there (a stand, gate or
-- plot; optional). The first-minute guide's own goals win while it shows.
function Guide.pointTo(position: Vector3?, model: Instance?)
	if position and position ~= pointed then
		CameraFeel.face(position, CUE.faceSeconds)
	end
	pointed, pointedModel = position, if position then model else nil
end

local function boughtAny(levels: { [string]: number }): boolean
	for _, level in levels do
		if level > 0 then
			return true
		end
	end
	return false
end

-- The cheapest upgrade on sale now: its track, the team's price and whether `money` buys it.
local function cheapest(levels: { [string]: number }, money: number): (Config.Track?, number, boolean)
	local best, bestCost, bestAffordable = nil, math.huge, false
	for _, track in Config.tracks do
		local level, status, affordable = Hud.offer(levels, track.id, money)
		local cost = if status == "buy" then Hud.price(level.cost) else math.huge
		if cost < bestCost then
			best, bestCost, bestAffordable = track, cost, affordable
		end
	end
	return best, bestCost, bestAffordable
end

-- The ocean part's GuideTarget, or nil while the part hasn't streamed in.
local function target(ocean: Model, name: string): Attachment?
	local part = ocean:FindFirstChild(name)
	if not part then
		return nil
	end
	local found = part:FindFirstChild("GuideTarget")
	assert(found and found:IsA("Attachment"), `{ocean.Name}.{name} is missing its GuideTarget attachment (built in Studio)`)
	return found
end

-- The lane only shows and never blocks: no collisions, rays, touches or shadows.
local function quiet(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
		instance.CastShadow = false
	end
end

function Guide.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local panel = Hud.find(gui, "Guide")
	local pop = Hud.find(panel, "Pop") :: UIScale
	local objective = Hud.find(panel, "Objective")
	local text = Hud.find(panel, "Text")
	objective.TextColor3 = Theme.colors.guide
	text.TextColor3 = Theme.colors.guide
	local skip = Hud.find(panel, "SkipButton")
	local admin = Hud.find(gui, "Admin")
	local toolSlot = Hud.find(gui, "Hotbar.Slot")
	local upgrades = Hud.find(gui, "UpgradesButton")
	local upgradesRing = Hud.find(upgrades, "GuideRing")
	local closeButton = Hud.find(gui, "Honeycomb.CloseButton")
	local handTemplate = Hud.find(gui, "Templates.ClickHand")
	assert(handTemplate:IsA("GuiObject"), "StarterGui.Hud.Templates.ClickHand must be an ImageLabel or TextLabel")
	local hand = handTemplate:Clone() :: GuiObject
	hand.Visible = false
	hand.Parent = gui
	local dim = Hud.find(gui, "GuideDim") :: GuiObject
	Hud.bleed(dim) -- its sides reach past the top bar and a phone's notch; the hole is measured from it
	local dimSides = {}
	for _, name in { "Top", "Bottom", "Left", "Right" } do
		local side = Hud.find(dim, name) :: GuiObject
		side.BackgroundColor3 = Theme.colors.shadow
		dimSides[name] = side
	end
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local laneTemplate = vfx:WaitForChild(CUE.lane, 10)
	assert(laneTemplate and laneTemplate:IsA("BasePart"), `ReplicatedStorage.Vfx is missing {CUE.lane} (a Part holding Start, End and a Beam)`)
	local highlightTemplate = vfx:WaitForChild(CUE.highlight, 10)
	assert(highlightTemplate and highlightTemplate:IsA("Highlight"), `ReplicatedStorage.Vfx is missing {CUE.highlight} (a Highlight)`)
	local highlight = highlightTemplate:Clone()

	-- The lane sits in the camera while it shows, unparented while it doesn't.
	local lane = laneTemplate:Clone()
	quiet(lane)
	local laneStart = lane:FindFirstChild("Start")
	local laneEnd = lane:FindFirstChild("End")
	assert(laneStart and laneStart:IsA("Attachment") and laneEnd and laneEnd:IsA("Attachment"), `Vfx.{CUE.lane} needs Attachments Start and End`)

	-- nil until the save's levels are published; then whether this save is new.
	local isNew: boolean? = nil
	local finished = false
	local doneUntil: number? = nil
	local shownStep = 0
	local facedStep = 0 -- the last step whose lane goal the camera turned to
	local dimShown = 0 -- 0 clear .. 1 fully dimmed
	local holeFrom: Vector2?, holeTo: Vector2? = nil, nil -- the dim's clear rectangle, in Hud offsets
	local reportedStep = 0 -- the step the server's analytics last heard (its Stage "Guide:<n>"; 0: hidden)
	local reportedAt = -math.huge

	local function finish(thanks: boolean)
		finished = true
		doneUntil = if thanks then os.clock() + DONE_SECONDS else nil
	end
	Hud.pressable(skip, Hud.find(skip, "Press"))
	skip.Activated:Connect(function()
		Telemetry.report("guideSkip")
		finish(false)
	end)

	-- Whether `object` and every frame above it in the Hud show.
	local function onScreen(object: GuiObject): boolean
		local node: Instance? = object
		while node and node ~= gui do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		return node == gui
	end

	-- The step (1-6), its goal, where the chevrons lead and the button the hand taps, from live state.
	local function current(levels: { [string]: number }, ocean: Model): (number, string, Vector3?, GuiObject?)
		local well, shore = target(ocean, "Source"), target(ocean, "PourPoint")
		local source = ocean:FindFirstChild("Source")
		local money = Hud.wallet()
		local track, cost, affordable = cheapest(levels, money)
		if track and affordable then
			if not Honeycomb.isOpen() then
				return 5, "Buy your first upgrade", nil, upgrades
			end
			-- the category hex, then the upgrade's hex (a click on it buys)
			return 6, `Buy {track.name}`, nil, Honeycomb.guideTarget(track.id)
		end
		if Honeycomb.isOpen() then
			return 4, `Pour more water: {Hud.money(money)} / {Hud.money(cost)} coins`, nil, closeButton
		end
		if player:GetAttribute("Equipped") == false then
			return 1, "Take out your tool", nil, toolSlot
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart") and source and source:IsA("BasePart") and well and shore) then
			return shownStep, text.Text, nil, nil -- no body yet, or the cove not streamed in
		end
		local carried = player:GetAttribute("Carried") or 0
		local capacity = player:GetAttribute("Capacity") or 0
		local full = carried >= capacity * (1 - 1e-6)
		local atWell = (root.Position - source.Position).Magnitude <= Hud.REACH
		if carried <= 0 and not atWell then
			local again = if money > 0 then `Again! {Hud.money(money)} / {Hud.money(cost)} coins for your first upgrade` else "Walk to the well"
			return 1, again, well.WorldPosition, nil
		elseif atWell and not full then
			return 2, "Scoop water until your tool is full", nil, nil
		end
		if Hud.nearPour(ocean, root.Position) then
			return 4, "Pour it in! Every litre pays coins", nil, nil
		end
		return 3, "Carry it to the shore", shore.WorldPosition, nil
	end

	-- Lays the lane from the player toward `goal` (nil hides it): flat, belowCamera studs under the
	-- camera, whatever the ground does.
	local function placeTrail(goal: Vector3?)
		local camera = workspace.CurrentCamera
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local from = if root and root:IsA("BasePart") then root.Position else nil
		local flat = if goal and from then Vector3.new(goal.X - from.X, 0, goal.Z - from.Z) else Vector3.zero
		local distance = flat.Magnitude
		local laneFrom, laneTo = nil, nil
		if goal and from then
			laneFrom, laneTo = GuideTrail.lane(CUE, distance)
		end
		local along = if laneFrom then flat / distance else Vector3.zero
		local origin = if from then Vector3.new(from.X, camera.CFrame.Position.Y - CUE.belowCamera, from.Z) else Vector3.zero

		-- A Beam's width runs along its attachments' Y axis: Y across the lane keeps it flat.
		if laneFrom and laneTo then
			local across = along:Cross(Vector3.yAxis)
			set(laneStart, "WorldCFrame", CFrame.fromMatrix(origin + along * laneFrom, Vector3.yAxis, across))
			set(laneEnd, "WorldCFrame", CFrame.fromMatrix(origin + along * laneTo, Vector3.yAxis, across))
		end
		set(lane, "Parent", if laneFrom then camera else nil)
	end

	-- The hand taps the middle of `button` while it shows (nil hides the hand).
	local function pointHand(button: GuiObject?)
		local shown = button ~= nil and onScreen(button)
		set(hand, "Visible", shown)
		if not shown then
			return
		end
		local at = ((button :: GuiObject).AbsolutePosition + (button :: GuiObject).AbsoluteSize / 2) / Hud.uiScale()
		local tap = math.abs(math.sin(os.clock() * math.pi * CUE.handSpeed)) * CUE.handBob
		set(hand, "Position", UDim2.fromOffset(math.round(at.X), math.round(at.Y + tap)))
	end

	-- Darkens everything but `button` (nil fades the dim out). The hole starts wide and closes in,
	-- then glides from button to button.
	local function dimAround(button: GuiObject?, dt: number)
		local shown = button ~= nil and onScreen(button)
		local follow = 1 - math.exp(-CUE.dimEase * dt)
		dimShown += ((if shown then 1 else 0) - dimShown) * follow
		local scale = Hud.uiScale()
		if shown then
			local b = button :: GuiObject
			local pad = Vector2.one * CUE.dimPad
			local from = (b.AbsolutePosition - dim.AbsolutePosition) / scale - pad
			local to = from + b.AbsoluteSize / scale + pad * 2
			if not (holeFrom and holeTo) then
				holeFrom, holeTo = from - Vector2.one * CUE.dimOpen, to + Vector2.one * CUE.dimOpen
			end
			holeFrom = (holeFrom :: Vector2):Lerp(from, follow)
			holeTo = (holeTo :: Vector2):Lerp(to, follow)
		end
		if dimShown < 0.01 and not shown then
			dimShown, holeFrom, holeTo = 0, nil, nil
			set(dim, "Visible", false)
			return
		end
		if not (holeFrom and holeTo) then
			return
		end
		set(dim, "Visible", true)
		local size = dim.AbsoluteSize / scale
		local x0, y0 = math.round(math.clamp(holeFrom.X, 0, size.X)), math.round(math.clamp(holeFrom.Y, 0, size.Y))
		local x1, y1 = math.round(math.clamp(holeTo.X, x0, size.X)), math.round(math.clamp(holeTo.Y, y0, size.Y))
		local w, h = math.round(size.X), math.round(size.Y)
		local place = {
			Top = { 0, 0, w, y0 },
			Bottom = { 0, y1, w, math.max(h - y1, 0) },
			Left = { 0, y0, x0, y1 - y0 },
			Right = { x1, y0, math.max(w - x1, 0), y1 - y0 },
		}
		local transparency = 1 - CUE.dimDarkness * dimShown
		for name, side in dimSides do
			local p = place[name]
			set(side, "Position", UDim2.fromOffset(p[1], p[2]))
			set(side, "Size", UDim2.fromOffset(p[3], p[4]))
			set(side, "BackgroundTransparency", transparency)
		end
	end

	RunService.RenderStepped:Connect(function(dt: number)
		local levels = Hud.levels()
		if levels and isNew == nil then
			isNew = not boughtAny(levels)
		end
		if levels and isNew and not finished and boughtAny(levels) then
			finish(true)
		end

		local thanks = doneUntil ~= nil and os.clock() < doneUntil
		local ocean = Hud.ocean()
		local active = isNew == true
			and (not finished or thanks)
			and levels ~= nil
			and ocean ~= nil
			and ReplicatedStorage:GetAttribute("Phase") == "playing"
			and not admin.Visible
			and not Hud.cutscene
		local step, message, goal, click = 0, "", nil, nil
		if active and thanks then
			step, message = STEPS, "Nice! Keep filling the ocean."
		elseif active then
			step, message, goal, click = current(levels :: { [string]: number }, ocean :: Model)
		end

		set(panel, "Visible", active and not Honeycomb.isOpen()) -- hidden under the honeycomb's cover; the hand still shows
		set(skip, "Visible", active and not thanks)
		set(upgradesRing, "Visible", click == upgrades)
		placeTrail(if active then goal elseif Hud.cutscene then nil else pointed)
		local outline = if not active and not Hud.cutscene and pointedModel and pointedModel:IsDescendantOf(workspace) then pointedModel else nil
		set(highlight, "Adornee", outline)
		set(highlight, "Parent", if outline then workspace.CurrentCamera else nil)
		pointHand(click)
		dimAround(click, dt)
		-- A step that leads somewhere new turns the camera there once (not again as the player
		-- flickers in and out of reach of the same goal).
		if goal and step ~= facedStep then
			facedStep = step
			CameraFeel.face(goal, CUE.faceSeconds)
		end
		-- The step showing goes to analytics on change, at most one per CLIENT gap (a step flickering
		-- at a reach edge settles first).
		local report = if active and not thanks then step else 0
		local now = os.clock()
		if report ~= reportedStep and now - reportedAt >= REPORT_GAP then
			reportedStep, reportedAt = report, now
			Telemetry.report("guide", report)
		end
		if not active then
			return
		end
		set(text, "Text", message)
		if step ~= shownStep then -- a new goal: the objective bounces
			shownStep = step
			objective.Text = `Objective {step}/{STEPS}`
			pop.Scale = 1.12
			TweenService:Create(pop, POP, { Scale = 1 }):Play()
		end
	end)
end

return Guide
