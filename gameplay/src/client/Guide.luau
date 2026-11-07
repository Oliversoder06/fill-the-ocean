-- The first-minute guide (StarterGui.Hud.Guide, StarterGui.GuideMarker, Vfx.GuideBeam, all built in
-- Studio): one goal at a time for a new save, until the first purchase. Walk to the well, scoop
-- until full, carry it to the shore, pour, open the shop, buy. Each step comes from live state
-- (where you stand, Carried, Money, the shop), so walking away goes back a step and nothing is
-- saved. The guide says what to do; Action's ActHint says which key. Skip hides it for the session.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Hud = require(script.Parent.Hud)

local player = Players.LocalPlayer
local set = Hud.set

local REACH = Zones.REACH
local BEAM = Cues.guide.beam
local STEPS = 6
local DONE_SECONDS = 3
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BOB_PIXELS, BOB_SPEED = 6, 4 -- marker arrow bob height, and radians per second

local Guide = {}

local function levelsOf(): { [string]: number }?
	local levels = {}
	for _, track in Config.tracks do
		local level = player:GetAttribute(`Level_{track.id}`)
		if type(level) ~= "number" then
			return nil -- not published yet
		end
		levels[track.id] = level
	end
	return levels
end

local function boughtAny(levels: { [string]: number }): boolean
	for _, level in levels do
		if level > 0 then
			return true
		end
	end
	return false
end

local function openAreas(): number
	local fill = ReplicatedStorage:GetAttribute("Fill")
	return Ladder.openAreas(Config, if type(fill) == "number" then fill else 0)
end

-- The cheapest upgrade on sale now: its track and price.
local function cheapest(levels: { [string]: number }): (Config.Track?, number)
	local areas = openAreas()
	local best, bestCost = nil, math.huge
	for _, track in Config.tracks do
		local level, status = Ladder.offer(Config, levels, track.id, areas)
		if status == "buy" and level.cost < bestCost then
			best, bestCost = track, level.cost
		end
	end
	return best, bestCost
end

local function target(ocean: Model, name: string): Attachment
	local found = Zones.part(ocean, name):FindFirstChild("GuideTarget")
	assert(found and found:IsA("Attachment"), `{ocean.Name}.{name} is missing its GuideTarget attachment (built in Studio)`)
	return found
end

local function openText(): string
	local input = UserInputService:GetLastInputType()
	if input == Enum.UserInputType.Touch then
		return "Tap UPGRADES"
	elseif input.Name:sub(1, 7) == "Gamepad" then
		return "Press Y to open UPGRADES"
	end
	return "Open UPGRADES (TAB)"
end

function Guide.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("Hud")
	local panel = Hud.find(gui, "Guide")
	local pop = Hud.find(panel, "Pop") :: UIScale
	local stepText = Hud.find(panel, "Step.Text")
	local text = Hud.find(panel, "Text")
	local skip = Hud.find(panel, "SkipButton")
	local shop = Hud.find(gui, "Shop")
	local admin = Hud.find(gui, "Admin")
	local upgradesRing = Hud.find(gui, "UpgradesButton.GuideRing")
	local buyRing = Hud.find(gui, "Shop.Body.Content.Detail.BuyButton.GuideRing")
	local marker = playerGui:WaitForChild("GuideMarker")
	assert(marker:IsA("BillboardGui"), "StarterGui.GuideMarker must be a BillboardGui")
	local markerLabel = Hud.find(marker, "Label")
	local arrow = Hud.find(marker, "Arrow")
	local arrowRest = arrow.Position
	local vfx = ReplicatedStorage:WaitForChild("Vfx")
	local beamTemplate = vfx:FindFirstChild(BEAM)
	assert(beamTemplate and beamTemplate:IsA("Beam"), `ReplicatedStorage.Vfx is missing {BEAM} (a Beam)`)
	local tiles = {}
	for _, track in Config.tracks do
		local holder = if track.panel == "tool" then "ToolPanel" else "BoostPanel"
		tiles[track.id] = Hud.find(gui, `Shop.Body.Content.{holder}.Tiles.{track.id}.Button.Ring`)
	end

	-- nil until the save's levels are published; then whether this save is new.
	local isNew: boolean? = nil
	local finished = false
	local doneUntil: number? = nil
	local shownStep = 0
	local beam: Beam? = nil

	local function finish(thanks: boolean)
		finished = true
		doneUntil = if thanks then os.clock() + DONE_SECONDS else nil
	end
	skip.Activated:Connect(function()
		finish(false)
	end)

	local function showBeam(to: Attachment?)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local from = root and root:FindFirstChild("RootAttachment")
		if not (to and from and from:IsA("Attachment")) then
			if beam then
				set(beam, "Enabled", false)
			end
			return
		end
		if not beam or beam.Parent ~= root then -- first time, or the character respawned
			if beam then
				beam:Destroy()
			end
			beam = beamTemplate:Clone()
			;(beam :: Beam).Attachment0 = from
			;(beam :: Beam).Parent = root
		end
		local b = beam :: Beam
		set(b, "Attachment1", to)
		set(b, "Enabled", true)
	end

	-- Whether the shop's selected tile (the one whose Ring shows) is on sale and affordable now.
	local function canBuySelected(levels: { [string]: number }, money: number): boolean
		local areas = openAreas()
		for id, ring in tiles do
			if ring.Visible then
				local level, status = Ladder.offer(Config, levels, id, areas)
				return status == "buy" and money + 1e-6 >= level.cost
			end
		end
		return false
	end

	-- The step (1-6), its text and the beam and marker targets, from live state.
	local function current(levels: { [string]: number }, ocean: Model): (number, string, Attachment?, Attachment?, string)
		local well, shore = target(ocean, "Source"), target(ocean, "PourPoint")
		local money = player:GetAttribute("Money") or 0
		local track, cost = cheapest(levels)
		if track and money + 1e-6 >= cost then
			if not shop.Visible then
				return 5, openText(), nil, nil, ""
			end
			if canBuySelected(levels, money) then
				return 6, "Buy it!", nil, nil, ""
			end
			return 6, `Pick {track.name}, then BUY`, nil, nil, ""
		end
		if shop.Visible then
			return 4, `Close the shop and pour more water: {Hud.money(money)} / {Hud.money(cost)} coins`, nil, nil, ""
		end
		if player:GetAttribute("Equipped") == false then
			return 1, "Take out your tool (press 1 or tap the slot)", nil, nil, ""
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return shownStep, text.Text, nil, nil, ""
		end
		local carried = player:GetAttribute("Carried") or 0
		local capacity = player:GetAttribute("Capacity") or 0
		local full = carried >= capacity * (1 - 1e-6)
		local atWell = (root.Position - Zones.part(ocean, "Source").Position).Magnitude <= REACH
		if carried <= 0 and not atWell then
			local again = if money > 0 then `Again! {Hud.money(money)} / {Hud.money(cost)} coins for your first upgrade` else "Walk to the well"
			return 1, again, well, well, "WELL"
		elseif atWell and not full then
			return 2, "Scoop water until your tool is full", nil, well, "WELL"
		end
		local ignore: { Instance } = { workspace.CurrentCamera }
		for _, other in Players:GetPlayers() do
			if other.Character then
				table.insert(ignore, other.Character)
			end
		end
		if Zones.nearFlood(ocean, root.Position, REACH, ignore) then
			return 4, "Pour it in! Every litre pays coins", nil, nil, ""
		end
		return 3, "Carry it to the shore", shore, shore, "POUR HERE"
	end

	RunService.RenderStepped:Connect(function()
		local levels = levelsOf()
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
		local step, message, beamTo, markAt, markText = 0, "", nil, nil, ""
		if active and thanks then
			step, message = STEPS, "Nice! Keep filling the ocean."
		elseif active then
			step, message, beamTo, markAt, markText = current(levels :: { [string]: number }, ocean :: Model)
		end

		set(panel, "Visible", active)
		set(skip, "Visible", active and not thanks)
		set(upgradesRing, "Visible", active and not thanks and step == 5)
		set(buyRing, "Visible", active and not thanks and step == 6 and message == "Buy it!")
		set(marker, "Enabled", markAt ~= nil)
		set(marker, "Adornee", markAt)
		showBeam(beamTo)
		if not active then
			return
		end
		set(text, "Text", message)
		set(stepText, "Text", `{step}/{STEPS}`)
		set(markerLabel, "Text", markText)
		if markAt then
			local bob = math.sin(os.clock() * BOB_SPEED) * BOB_PIXELS
			arrow.Position = arrowRest + UDim2.fromOffset(0, math.round(bob))
		end
		if step ~= shownStep then -- a new goal: the banner bounces
			shownStep = step
			pop.Scale = 1.12
			TweenService:Create(pop, POP, { Scale = 1 }):Play()
		end
	end)
end

return Guide
