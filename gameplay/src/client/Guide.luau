-- The first-minute guide (StarterGui.Hud.Guide, built in Studio): one goal at a time for a new save,
-- until the first purchase, at the top centre ("Objective 2/6" over the goal). Walk to the well,
-- scoop until full, carry it to the shore, pour, buy your first upgrade. Each step comes from live
-- state (where you stand, Carried, the team's Wallet, the honeycomb), so walking away goes back a step and nothing is
-- saved. The goal (in guide yellow) says what to do, never where to click: a glowing yellow lane on
-- the ground leads to the place (shared/GuideTrail: clones of ReplicatedStorage.Vfx.GuideChevron
-- every few studs with a gentle brightness wave, between two steady clones of Vfx.GuideRail along
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
local RAY_UP, RAY_DOWN = 8, 40 -- studs above the lane's line a ground ray starts, and its length
local LIFT = 0.05 -- studs the lane floats over the ground, so it never flickers into it
local RAY_EVERY = 0.1 -- seconds between a stop's ground rays; between them it slides along the last ground hit
local RAY_DRIFT = 2 -- studs a stop may slide from its last ray before it casts again
local FILTER_EVERY = 0.5 -- seconds between rebuilds of what the ground rays skip (bodies and vehicles come and go)
local PULSE_STEP = 0.05 -- the fade moves in steps, so most frames write nothing

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
	-- Each chevron's images (Decals, ImageLabels) fade with the pulse from their template transparency.
	local most = GuideTrail.most(CUE)
	local chevrons: { PVInstance } = {}
	local placed: { [number]: CFrame } = {}
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
		assert(#images > 0, `ReplicatedStorage.Vfx.{CUE.chevron} needs a Decal or ImageLabel (the chevron image) for its pulse`)
		chevrons[i], glows[i] = chevron, images
	end
	-- Rails: one segment between each pair of neighbouring stops, on both sides.
	local railWidth, railHeight = railTemplate.Size.X, railTemplate.Size.Y
	local rails: { BasePart } = {}
	for i = 1, 2 * (most + 1) do
		local rail = railTemplate:Clone()
		quiet(rail)
		rails[i] = rail
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true -- the ground, not invisible zones (as shared/Zones.ground)
	local filterAt = -math.huge
	-- Each stop's last ground ray: the point it was cast over, when, and the ground it hit (nil: none);
	-- and this frame's ground under it.
	local castFrom: { [number]: Vector3? } = {}
	local castAt: { [number]: number } = {}
	local hitAt: { [number]: Vector3? } = {}
	local hitUp: { [number]: Vector3? } = {}
	local groundOf: { [number]: Vector3? } = {}
	local upOf: { [number]: Vector3? } = {}

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

	-- Stop `s`'s ground under `point` and the ground's up; nil over a gap.
	local function groundAt(s: number, now: number, point: Vector3): (Vector3?, Vector3?)
		local castPoint = castFrom[s]
		if not castPoint or now - castAt[s] >= RAY_EVERY or (point - castPoint).Magnitude > RAY_DRIFT then
			local hit = workspace:Raycast(point + Vector3.yAxis * RAY_UP, Vector3.yAxis * -RAY_DOWN, rayParams)
			castPoint = point
			castFrom[s], castAt[s] = point, now
			hitAt[s], hitUp[s] = if hit then hit.Position else nil, if hit then hit.Normal else nil
		end
		local ground, up = hitAt[s], hitUp[s]
		if not (ground and up) then
			return nil, nil
		end
		local moved = point - (castPoint :: Vector3)
		return ground + (moved - up * moved:Dot(up)) + up * LIFT, up
	end

	-- Lays the lane from the player toward `goal` (nil hides it).
	local function placeTrail(goal: Vector3?)
		local camera = workspace.CurrentCamera
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local from = if root and root:IsA("BasePart") then root.Position else nil
		local flat = if goal and from then Vector3.new(goal.X - from.X, 0, goal.Z - from.Z) else Vector3.zero
		local distance = flat.Magnitude
		local seconds = os.clock()
		local stops = if goal and from then GuideTrail.stops(CUE, distance) else {}
		if #stops > 0 and seconds - filterAt >= FILTER_EVERY then
			filterAt = seconds
			local ignore: { Instance } = { camera }
			for _, other in Players:GetPlayers() do
				if other.Character then
					table.insert(ignore, other.Character)
				end
				local vehicle = workspace:FindFirstChild(`Vehicle_{other.UserId}`)
				if vehicle then
					table.insert(ignore, vehicle)
				end
			end
			local staff = workspace:FindFirstChild("StaffBodies")
			if staff then
				table.insert(ignore, staff)
			end
			rayParams.FilterDescendantsInstances = ignore
		end
		local along = if #stops > 0 then flat / distance else Vector3.zero
		local points: { GuideTrail.Point | false } = {}
		for s, ahead in stops do
			local point = (from :: Vector3) + along * ahead + Vector3.yAxis * (((goal :: Vector3).Y - (from :: Vector3).Y) * ahead / distance)
			local ground, up = groundAt(s, seconds, point)
			groundOf[s], upOf[s] = ground, up
			points[s] = if ground then { X = ground.X, Y = ground.Y, Z = ground.Z } else false
		end

		-- Chevron i sits on stop i + 1 (the first and last stops are the lane's ends), tip toward the goal.
		for i, chevron in chevrons do
			local s = i + 1
			local ground, up = nil, nil
			if s < #stops then
				ground, up = groundOf[s], upOf[s]
			end
			local at: CFrame? = nil
			if ground and up then
				local look = along - up * along:Dot(up)
				if look.Magnitude > 1e-3 then
					at = CFrame.lookAt(ground, ground + look.Unit, up)
				end
			end
			if at and at ~= placed[i] then
				placed[i] = at
				chevron:PivotTo(at)
			end
			if at then
				local fade = math.round(CUE.pulseDim * (1 - GuideTrail.pulse(CUE, stops[s], seconds)) / PULSE_STEP) * PULSE_STEP
				for _, glow in glows[i] do
					set(glow.image, glow.prop, glow.rest + (1 - glow.rest) * fade)
				end
			end
			set(chevron, "Parent", if at then camera else nil)
		end

		-- The rails: steady, resting on the ground along both edges.
		local right = along:Cross(Vector3.yAxis)
		local left, rightSide = GuideTrail.rails(points, { X = right.X, Y = right.Y, Z = right.Z }, CUE.laneHalfWidth)
		local lift = Vector3.yAxis * (railHeight / 2)
		local used = 0
		for _, side in { left, rightSide } do
			for _, segment in side do
				used += 1
				local rail = rails[used]
				local a = Vector3.new(segment.from.X, segment.from.Y, segment.from.Z) + lift
				local b = Vector3.new(segment.to.X, segment.to.Y, segment.to.Z) + lift
				set(rail, "Size", Vector3.new(railWidth, railHeight, (b - a).Magnitude))
				set(rail, "CFrame", CFrame.lookAt((a + b) / 2, b))
				set(rail, "Parent", camera)
			end
		end
		for i = used + 1, #rails do
			set(rails[i], "Parent", nil)
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
