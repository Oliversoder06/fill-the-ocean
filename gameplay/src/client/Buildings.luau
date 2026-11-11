-- The team's buildings on the client (server/Buildings). Holding E on an empty plot's Prompt
-- (workspace.Map.Plots.PlotN.Base.Prompt) opens the build picker (StarterGui.Hud.BuildPicker, built
-- in Studio; opens through client/Window) with one option per building, cloned from
-- Hud.Templates.BuildOption: its name, litres a second and price, or the area that opens it.
-- Clicking one sends Build(plot, itemId); the server checks everything. Walking away, the plot
-- being built on, or the run leaving "playing" closes it.
-- Also scrolls the textures of an aqueduct's Water while its Flowing attribute is set.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local BuildingRules = require(ReplicatedStorage.Shared.BuildingRules)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local Areas = require(ReplicatedStorage.Common.Areas)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["clear-tide"])
local Channels = require(script.Parent.Channels)
local Hud = require(script.Parent.Hud)
local Purchase = require(script.Parent.Purchase)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local colors = Theme.colors
local set = Hud.set

local DESIGN_SIZE = Vector2.new(620, 440) -- the picker plus room for its decorations
local REACH_SLACK = 4 -- studs past the prompt's reach before the picker closes
local FLOW_SPEED = 8 -- studs a second the aqueduct water's textures scroll
local FIND_SECONDS = 1 -- seconds between looks for an aqueduct not found yet (or streamed out)
local SIDES = { "ShopSide", "StaffSide" }

local Buildings = {}

local flows: { [string]: { aqueduct: Instance, textures: { Texture } } } = {}
local nextFind = 0

-- The plot number of a plot's prompt (Plots.PlotN.Base.Prompt), or nil for any other prompt.
local function plotOf(prompt: ProximityPrompt): number?
	local base = prompt.Parent
	local plot = base and base.Parent
	local plots = plot and plot.Parent
	if prompt.Name ~= "Prompt" or not base or base.Name ~= "Base" or not plots or plots.Name ~= "Plots" then
		return nil
	end
	local index = (plot :: Instance).Name:match("^Plot(%d+)$")
	return if index then tonumber(index) else nil
end

-- Finds the aqueducts and their water textures once each (again only after one streams out).
local function findFlows()
	local scenery = workspace:FindFirstChild("Map")
	local town = scenery and scenery:FindFirstChild("Town")
	for _, side in SIDES do
		local flow = flows[side]
		if flow and flow.aqueduct:IsDescendantOf(workspace) then
			continue
		end
		flows[side] = nil
		local aqueduct = town and town:FindFirstChild(`Aqueduct_{side}`)
		local water = aqueduct and aqueduct:FindFirstChild("Water")
		if water then
			flows[side] = { aqueduct = aqueduct :: Instance, textures = Channels.textures(water) }
		end
	end
end

-- Scrolls the water textures of the flowing aqueducts (none while streamed out).
local function scrollAqueducts(dt: number)
	local now = os.clock()
	if now >= nextFind then
		nextFind = now + FIND_SECONDS
		findFlows()
	end
	for _, flow in flows do
		if flow.aqueduct:GetAttribute("Flowing") == true then
			Channels.scroll(flow.textures, FLOW_SPEED, dt)
		end
	end
end

function Buildings.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local buildRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Build") :: RemoteEvent
	local root = Hud.find(gui, "BuildPicker")
	local fit = Hud.find(root, "Scale") :: UIScale
	local title = Hud.find(root, "Title")
	local list = Hud.find(root, "List")
	local template = Hud.find(gui, "Templates.BuildOption") :: GuiButton
	local window = Window.new(root, fit)

	local open = false
	local plot: number? = nil
	local plotPrompt: ProximityPrompt? = nil
	local fitScale = 1
	local function refit()
		local view = gui.AbsoluteSize / Hud.uiScale()
		fitScale = math.min(view.X / DESIGN_SIZE.X, view.Y / DESIGN_SIZE.Y, 1)
		if open then
			fit.Scale = fitScale
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()

	local function setOpen(value: boolean)
		if value == open then
			return
		end
		open = value
		if value then
			refit() -- the HUD's scale may have changed since
			window.open(fitScale)
		else
			window.close(fitScale)
		end
	end

	-- Whether a building is on sale (its area is open) and the team can build it now, by the server's check.
	local function offer(item, openAreas: number): (boolean, boolean)
		local ok, reason = BuildingRules.buildable(item, openAreas, Hud.wallet(), Hud.price)
		return reason ~= "locked", ok
	end

	local options: { [any]: { button: GuiButton, price: TextLabel, coin: GuiObject } } = {}
	local order = 0
	for _, item in Config.items do
		if item.kind == "building" then
			order += 1
			local option = template:Clone()
			option.Name = item.id
			option.LayoutOrder = order
			option.Visible = true
			set(Hud.find(option, "ItemName"), "Text", item.name)
			set(Hud.find(option, "Rate"), "Text", `{Hud.short(item.rate)} L/s`)
			Hud.pressable(option, Hud.find(option, "Press"))
			option.Activated:Connect(function()
				local _, buildable = offer(item, Ladder.openAreas(Config, Hud.gatesOpen()))
				if not (buildable and plot) then
					Purchase.deny(option)
					return
				end
				buildRemote:FireServer(plot, item.id)
				setOpen(false)
			end)
			option.Parent = list
			options[item] = { button = option, price = Hud.find(option, "PriceRow.Price"), coin = Hud.find(option, "PriceRow.Coin") }
		end
	end

	Hud.find(root, "CloseButton").Activated:Connect(function()
		setOpen(false)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local index = plotOf(prompt)
		if index and ReplicatedStorage:GetAttribute("Phase") == "playing" then
			plot, plotPrompt = index, prompt
			set(title, "Text", `Build on Plot {index}`)
			setOpen(true)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		scrollAqueducts(dt)
		if not open then
			return
		end
		local base = plotPrompt and plotPrompt.Parent
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local away = not (base and base:IsA("BasePart") and rootPart and rootPart:IsA("BasePart"))
			or (rootPart.Position - base.Position).Magnitude > (plotPrompt :: ProximityPrompt).MaxActivationDistance + REACH_SLACK
		if away or not (plotPrompt :: ProximityPrompt).Enabled or ReplicatedStorage:GetAttribute("Phase") ~= "playing" then
			setOpen(false)
			return
		end
		local openAreas = Ladder.openAreas(Config, Hud.gatesOpen())
		for item, option in options do
			local onSale, buildable = offer(item, openAreas)
			set(option.button, "ImageColor3", if onSale then colors.upgradeTop else colors.locked)
			set(option.coin, "Visible", onSale)
			set(option.price, "Text", if onSale then Hud.money(Hud.price(item.price)) else `Opens with {Areas.byId(Config, item.area).name}`)
			set(option.price, "TextColor3", if onSale and not buildable then colors.short else colors.text)
		end
	end)
end

return Buildings
