-- The first-minute guide (StarterGui.Hud.Guide, built in Studio): one goal at a time for a new save,
-- until the first purchase, at the top centre ("Objective 2/6" over the goal). Walk to the well,
-- scoop until full, carry it to the shore, pour, buy your first upgrade. Each step comes from live
-- state (where you stand, Carried, the team's Wallet, the shop), so walking away goes back a step and nothing is
-- saved. The goal says what to do, never where to click: yellow chevrons on the ground (clones of
-- ReplicatedStorage.Vfx.GuideChevron, placed by shared/GuideTrail) lead to the place, a click hand
-- (a clone of Hud.Templates.ClickHand) taps the button to press, and Action's ActHint says which
-- key. Skip hides it for the session. Once it is done, Guide.pointTo leads the chevrons anywhere.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local GuideTrail = require(ReplicatedStorage.Shared.GuideTrail)
local Hud = require(script.Parent.Hud)

local player = Players.LocalPlayer
local set = Hud.set

local CUE = Cues.guide
local STEPS = 6
local DONE_SECONDS = 3
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local RAY_UP, RAY_DOWN = 8, 40 -- studs above the trail line a chevron's ground ray starts, and its length
local LIFT = 0.05 -- studs a chevron floats over the ground, so it never flickers into it
local RAY_EVERY = 0.1 -- seconds between a chevron's ground rays; between them it slides along the last ground hit
local RAY_DRIFT = 2 -- studs a chevron may slide from its last ray before it casts again (it also loops back)
local FILTER_EVERY = 0.5 -- seconds between rebuilds of what the ground rays skip (bodies and vehicles come and go)

local Guide = {}

-- Where another module wants the chevrons to lead while the first-minute guide isn't showing.
local pointed: Vector3? = nil

-- Lead the ground chevrons to `position` (nil hides them). The first-minute guide's own goals win
-- while it shows.
function Guide.pointTo(position: Vector3?)
	pointed = position
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

-- Chevrons only show and never block: no collisions, rays, touches or shadows.
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
	local skip = Hud.find(panel, "SkipButton")
	local shop = Hud.find(gui, "Shop")
	local admin = Hud.find(gui, "Admin")
	local toolSlot = Hud.find(gui, "Hotbar.Slot")
	local upgrades = Hud.find(gui, "UpgradesButton")
	local upgradesRing = Hud.find(upgrades, "GuideRing")
	local closeButton = Hud.find(shop, "CloseButton")
	local toolsTab = Hud.find(shop, "Body.Tabs.Tools")
	local buyButton = Hud.find(shop, "Body.Content.Detail.BuyButton")
	local buyRing = Hud.find(buyButton, "GuideRing")
	local handTemplate = Hud.find(gui, "Templates.ClickHand")
	assert(handTemplate:IsA("GuiObject"), "StarterGui.Hud.Templates.ClickHand must be an ImageLabel or TextLabel")
	local hand = handTemplate:Clone() :: GuiObject
	hand.Visible = false
	hand.Parent = gui
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local chevronTemplate = vfx:WaitForChild(CUE.chevron, 10)
	assert(chevronTemplate and (chevronTemplate:IsA("Model") or chevronTemplate:IsA("BasePart")), `ReplicatedStorage.Vfx is missing {CUE.chevron} (a Model or BasePart)`)
	local tiles = {}
	for _, track in Config.tracks do
		local holder = if track.panel == "tool" then "ToolPanel" else "BoostPanel"
		local button = Hud.find(gui, `Shop.Body.Content.{holder}.Tiles.{track.id}.Button`)
		tiles[track.id] = { button = button, ring = Hud.find(button, "Ring") }
	end

	-- The trail's pool: each chevron sits in the camera while it shows, unparented while it doesn't.
	local chevrons: { PVInstance } = {}
	local placed: { [number]: CFrame } = {}
	for i = 1, GuideTrail.COUNT do
		local chevron = chevronTemplate:Clone() :: PVInstance
		quiet(chevron)
		for _, d in chevron:GetDescendants() do
			quiet(d)
		end
		chevrons[i] = chevron
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true -- the ground, not invisible zones (as shared/Zones.ground)
	local filterAt = -math.huge
	-- Each chevron's last ground ray: the point it was cast over, when, and the ground it hit (nil: none).
	local castFrom: { [number]: Vector3? } = {}
	local castAt: { [number]: number } = {}
	local hitAt: { [number]: Vector3? } = {}
	local hitUp: { [number]: Vector3? } = {}

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

	-- Whether the shop's selected tile (the one whose Ring shows) is on sale and affordable now.
	local function canBuySelected(levels: { [string]: number }, money: number): boolean
		for id, tile in tiles do
			if tile.ring.Visible then
				local _, _, canBuy = Hud.offer(levels, id, money)
				return canBuy
			end
		end
		return false
	end

	-- The step (1-6), its goal, where the chevrons lead and the button the hand taps, from live state.
	local function current(levels: { [string]: number }, ocean: Model): (number, string, Vector3?, GuiObject?)
		local well, shore = target(ocean, "Source"), target(ocean, "PourPoint")
		local source = ocean:FindFirstChild("Source")
		local money = Hud.wallet()
		local track, cost, affordable = cheapest(levels, money)
		if track and affordable then
			if not shop.Visible then
				return 5, "Buy your first upgrade", nil, upgrades
			end
			if canBuySelected(levels, money) then
				return 6, "Buy it!", nil, buyButton
			end
			local tile = tiles[track.id].button
			return 6, `Buy {track.name}`, nil, if onScreen(tile) then tile else toolsTab
		end
		if shop.Visible then
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

	-- Chevron `i`'s ground spot `ahead` studs along the flat line `along` from `from` toward `goal`,
	-- turned to point at the goal; nil over a gap or a wall.
	local function groundAt(i: number, now: number, from: Vector3, goal: Vector3, along: Vector3, ahead: number, distance: number): CFrame?
		local point = from + along * ahead + Vector3.yAxis * ((goal.Y - from.Y) * ahead / distance)
		local castPoint = castFrom[i]
		if not castPoint or now - castAt[i] >= RAY_EVERY or (point - castPoint).Magnitude > RAY_DRIFT then
			local hit = workspace:Raycast(point + Vector3.yAxis * RAY_UP, Vector3.yAxis * -RAY_DOWN, rayParams)
			castPoint = point
			castFrom[i], castAt[i] = point, now
			hitAt[i], hitUp[i] = if hit then hit.Position else nil, if hit then hit.Normal else nil
		end
		local ground, up = hitAt[i], hitUp[i]
		if not (ground and up) then
			return nil
		end
		local look = along - up * along:Dot(up)
		if look.Magnitude < 1e-3 then
			return nil
		end
		local moved = point - (castPoint :: Vector3)
		local at = ground + (moved - up * moved:Dot(up)) + up * LIFT
		return CFrame.lookAt(at, at + look.Unit, up)
	end

	-- Lays the chevrons from the player toward `goal` (nil hides them).
	local function placeTrail(goal: Vector3?)
		local camera = workspace.CurrentCamera
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local from = if root and root:IsA("BasePart") then root.Position else nil
		local flat = if goal and from then Vector3.new(goal.X - from.X, 0, goal.Z - from.Z) else Vector3.zero
		local distance = flat.Magnitude
		local seconds = os.clock()
		if distance > GuideTrail.HIDE_NEAR and seconds - filterAt >= FILTER_EVERY then
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
		for i, chevron in chevrons do
			local ahead = GuideTrail.ahead(i, seconds)
			local at = if GuideTrail.shows(ahead, distance) then groundAt(i, seconds, from :: Vector3, goal :: Vector3, flat / distance, ahead, distance) else nil
			if at and at ~= placed[i] then
				placed[i] = at
				chevron:PivotTo(at)
			end
			set(chevron, "Parent", if at then camera else nil)
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

		set(panel, "Visible", active)
		set(skip, "Visible", active and not thanks)
		set(upgradesRing, "Visible", click == upgrades)
		set(buyRing, "Visible", click == buyButton)
		placeTrail(if active then goal else pointed)
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
