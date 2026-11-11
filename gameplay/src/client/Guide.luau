-- The first-minute guide (StarterGui.Hud.Guide, built in Studio): one goal at a time for a new save,
-- until the first purchase, at the top centre ("Objective 2/6" over the goal). Walk to the well,
-- scoop until full, carry it to the shore, pour, buy your first upgrade. Each step comes from live
-- state (where you stand, Carried, the team's Wallet, the honeycomb), so walking away goes back a step and nothing is
-- saved. The goal (in guide yellow) says what to do, never where to click: a flat yellow lane just
-- below the camera leads to the place (shared/GuideTrail: clones of ReplicatedStorage.Vfx.GuideChevron
-- every few studs sliding forward, between two clones of Vfx.GuideRail along
-- its edges), a click hand (a clone of Hud.Templates.ClickHand) taps the button to press, and
-- Action's ActHint says which key. Skip hides it for the session. Once it is done, Guide.pointTo
-- leads the lane anywhere and outlines the stand, gate or plot there (a clone of Vfx.GuideHighlight).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local GuideTrail = require(ReplicatedStorage.Shared.GuideTrail)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["clear-tide"])
local Honeycomb = require(script.Parent.Honeycomb)
local Hud = require(script.Parent.Hud)

local player = Players.LocalPlayer
local set = Hud.set

local CUE = Cues.guide
local STEPS = 6
local DONE_SECONDS = 3
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_STEP = 0.05 -- the end fades move in steps, so most frames write nothing

local Guide = {}

-- Where another module wants the lane to lead while the first-minute guide isn't showing, and what
-- to outline there.
local pointed: Vector3? = nil
local pointedModel: Instance? = nil

-- Lead the ground lane to `position` (nil hides it) and outline `model` there (a stand, gate or
-- plot; optional). The first-minute guide's own goals win while it shows.
function Guide.pointTo(position: Vector3?, model: Instance?)
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
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local chevronTemplate = vfx:WaitForChild(CUE.chevron, 10)
	assert(chevronTemplate and (chevronTemplate:IsA("Model") or chevronTemplate:IsA("BasePart")), `ReplicatedStorage.Vfx is missing {CUE.chevron} (a Model or BasePart)`)

	local railTemplate = vfx:WaitForChild(CUE.rail, 10)
	assert(railTemplate and railTemplate:IsA("BasePart"), `ReplicatedStorage.Vfx is missing {CUE.rail} (a thin BasePart)`)
	local highlightTemplate = vfx:WaitForChild(CUE.highlight, 10)
	assert(highlightTemplate and highlightTemplate:IsA("Highlight"), `ReplicatedStorage.Vfx is missing {CUE.highlight} (a Highlight)`)
	local highlight = highlightTemplate:Clone()

	-- The lane's pools: each piece sits in the camera while it shows, unparented while it doesn't.
	-- Each chevron's images (Decals, ImageLabels) fade in and out at the lane's ends from their
	-- template transparency.
	local most = GuideTrail.most(CUE)
	local chevrons: { PVInstance } = {}
	local glows: { [number]: { { image: Instance, prop: string, rest: number } } } = {}
	for i = 1, most do
		local chevron = chevronTemplate:Clone() :: PVInstance
		quiet(chevron)
		local images = {}
		for _, d in chevron:GetDescendants() do
			quiet(d)
			if d:IsA("Decal") then
				table.insert(images, { image = d, prop = "Transparency", rest = d.Transparency })
			elseif d:IsA("ImageLabel") then
				table.insert(images, { image = d, prop = "ImageTransparency", rest = d.ImageTransparency })
			end
		end
		assert(#images > 0, `ReplicatedStorage.Vfx.{CUE.chevron} needs a Decal or ImageLabel (the chevron image)`)
		chevrons[i], glows[i] = chevron, images
	end
	-- Rails: one straight piece along each edge.
	local railWidth, railHeight = railTemplate.Size.X, railTemplate.Size.Y
	local rails: { BasePart } = {}
	for i = 1, 2 do
		local rail = railTemplate:Clone()
		quiet(rail)
		rails[i] = rail
	end

	-- nil until the save's levels are published; then whether this save is new.
	local isNew: boolean? = nil
	local finished = false
	local doneUntil: number? = nil
	local shownStep = 0

	local function finish(thanks: boolean)
		finished = true
		doneUntil = if thanks then os.clock() + DONE_SECONDS else nil
	end
	Hud.pressable(skip, Hud.find(skip, "Press"))
	skip.Activated:Connect(function()
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
		local ahead = if laneFrom then GuideTrail.chevrons(CUE, distance, os.clock()) else {}
		local along = if laneFrom then flat / distance else Vector3.zero
		local origin = if from then Vector3.new(from.X, camera.CFrame.Position.Y - CUE.belowCamera, from.Z) else Vector3.zero

		for i, chevron in chevrons do
			local at = ahead[i]
			if at then
				local point = origin + along * at
				chevron:PivotTo(CFrame.lookAt(point, point + along))
				local hidden = 1 - GuideTrail.fade(CUE, at, laneFrom :: number, laneTo :: number)
				hidden = math.round(hidden / FADE_STEP) * FADE_STEP
				for _, glow in glows[i] do
					set(glow.image, glow.prop, glow.rest + (1 - glow.rest) * hidden)
				end
			end
			set(chevron, "Parent", if at then camera else nil)
		end

		-- The rails: one straight piece along each edge, the whole lane long.
		local right = along:Cross(Vector3.yAxis)
		for i, rail in rails do
			if laneFrom and laneTo then
				local side = right * CUE.laneHalfWidth * (if i == 1 then -1 else 1) - Vector3.yAxis * (railHeight / 2)
				local a = origin + along * laneFrom + side
				local b = origin + along * laneTo + side
				set(rail, "Size", Vector3.new(railWidth, railHeight, (b - a).Magnitude))
				set(rail, "CFrame", CFrame.lookAt((a + b) / 2, b))
			end
			set(rail, "Parent", if laneFrom then camera else nil)
		end
	end

	-- The hand taps the middle of `button` while it shows (nil hides the hand).
	local function pointHand(button: GuiObject?)
		local shown = button ~= nil and onScreen(button)
		set(hand, "Visible", shown)
		if not shown then
			return
		end
		local at = (button :: GuiObject).AbsolutePosition + (button :: GuiObject).AbsoluteSize / 2
		local tap = math.abs(math.sin(os.clock() * math.pi * CUE.handSpeed)) * CUE.handBob
		set(hand, "Position", UDim2.fromOffset(math.round(at.X), math.round(at.Y + tap)))
	end

	RunService.RenderStepped:Connect(function()
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
		local step, message, goal, click = 0, "", nil, nil
		if active and thanks then
			step, message = STEPS, "Nice! Keep filling the ocean."
		elseif active then
			step, message, goal, click = current(levels :: { [string]: number }, ocean :: Model)
		end

		set(panel, "Visible", active and not Honeycomb.isOpen()) -- hidden under the honeycomb's cover; the hand still shows
		set(skip, "Visible", active and not thanks)
		set(upgradesRing, "Visible", click == upgrades)
		placeTrail(if active then goal else pointed)
		local outline = if not active and pointedModel and pointedModel:IsDescendantOf(workspace) then pointedModel else nil
		set(highlight, "Adornee", outline)
		set(highlight, "Parent", if outline then workspace.CurrentCamera else nil)
		pointHand(click)
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
