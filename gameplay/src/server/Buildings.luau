-- The team's buildings (3e, D2; Config.items kind "building", shared/BuildingRules) on the cove's
-- plots. server/Run starts it with hooks, hands it the save (Buildings.load) and passes it the TAB
-- buys of building ids (Buildings.buy).
-- Building: a plot's Prompt opens client/Buildings' picker; the client sends Build(plot number, item
-- id) and the server checks it (plot empty, area open, the team's price, near the plot, rate limit),
-- takes the coins from the team's wallet and clones ReplicatedStorage.Buildings.<model> onto the plot. save.plots
-- keeps which building stands on which plot; save.buildings the upgrades bought per building id: a
-- level counts on every plot with that building (one TAB tile per kind, levelled by anyone).
-- Output: while playing with someone present (D4), every building pours its rate (litres a second)
-- into the ocean; its coins (BuildingRules.payPerLitre) go into the team's wallet in batches
-- (server/Payroll).
-- Clogs: after BuildingRules.clogDelay seconds of play a building clogs and makes half until someone
-- holds E on its Unclog prompt.
-- Published: ReplicatedStorage BuildingLevel_<id> (upgrades bought; nil until the team builds one),
-- each placed building's Clogged (the server also switches its Clog emitter and Unclog prompt), and
-- each aqueduct's Flowing while a plot on its side (BuildingRules.side) has a building and the run
-- plays (the server shows its Water part; client/Buildings scrolls its textures).
-- 3f's Plumber: Buildings.setPlumber(scale, keepClear) and Buildings.unclog(plot).
-- Place contract (Studio): workspace.Map.Plots.Plot1..PlotN, each a Model with a part Base (the
-- building stands centred on its top face) holding a ProximityPrompt "Prompt"; Town.Aqueduct_ShopSide
-- and Town.Aqueduct_StaffSide, each holding a part Water; ReplicatedStorage.Buildings.<model> per
-- building (pivot at its bottom centre, a ProximityPrompt "Unclog" in a part, a ParticleEmitter "Clog").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BuildingRules = require(ReplicatedStorage.Shared.BuildingRules)
local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Common.Items)
local RunSave = require(ReplicatedStorage.Common.RunSave)
local Payroll = require(script.Parent.Payroll)
local Telemetry = require(script.Parent.Telemetry)

local TICK = 1 -- seconds between output ticks
local MAX_BUILDS_PER_SECOND = 2
local MAX_UNCLOGS_PER_SECOND = 2
local SIDES = { "ShopSide", "StaffSide" }

export type Hooks = {
	states: { [Player]: any }, -- server/Run's player states (rate limits)
	playing: () -> boolean,
	openIds: () -> { number }, -- the open area ids (Areas.openIds)
	openAreas: () -> number, -- areas open so far (Ladder.openAreas)
	inReach: (Player, ProximityPrompt) -> boolean,
	allow: (any, string, number) -> boolean, -- server/Run's per-player rate limit (state, key, max a second)
	price: (number) -> number, -- a listed price for the team (Items.price)
	spend: (number, Player, string, string) -> (), -- takes coins from the team's wallet (buyer, analytics reason, sku)
	fill: (number) -> number, -- pours litres into the ocean; returns the litres it took
	card: (string) -> (), -- a card for everyone
	tell: (Player, string) -> (), -- a card for one player
	save: (string) -> (), -- save the run soon (the reason, for warnings)
}

type Plot = { model: Model, base: BasePart, prompt: ProximityPrompt, side: string }
type Placed = { item: any, model: Model, prompt: ProximityPrompt, emitter: ParticleEmitter, clogged: boolean, clogIn: number }

local Buildings = {}

local hooks: Hooks
local save: RunSave.Save? = nil -- the run's save once loaded (the same table server/Run writes)
local plots: { Plot } = {}
local placed: { [number]: Placed } = {}
local aqueducts: { [string]: { model: Instance, water: BasePart, transparency: number, flowing: boolean? } } = {}
local templates: Folder
local rng = Random.new()
local plumber = { scale = 1, keepClear = false }

local function child(parent: Instance, name: string, class: string): any
	local found = parent:FindFirstChild(name)
	assert(found and found:IsA(class), `{parent:GetFullName()} is missing {name} (a {class})`)
	return found
end

-- A building's model in ReplicatedStorage.Buildings, checked against the contract above.
local function template(item): Model
	local model = child(templates, item.model, "Model")
	local prompt = model:FindFirstChild("Unclog", true)
	assert(prompt and prompt:IsA("ProximityPrompt") and prompt.Parent and prompt.Parent:IsA("BasePart"), `{model:GetFullName()} needs a ProximityPrompt "Unclog" in a part`)
	local emitter = model:FindFirstChild("Clog", true)
	assert(emitter and emitter:IsA("ParticleEmitter"), `{model:GetFullName()} needs a ParticleEmitter "Clog"`)
	return model
end

-- Upgrades bought per building id ("BuildingLevel_pump"), nil until the team builds one (client/Hud).
local function publishLevels()
	for _, item in Config.items do
		if item.kind == "building" then
			ReplicatedStorage:SetAttribute(`BuildingLevel_{item.id}`, if save then save.buildings[item.id] else nil)
		end
	end
end

local function setClogged(building: Placed, clogged: boolean)
	building.clogged = clogged
	building.model:SetAttribute("Clogged", clogged)
	building.prompt.Enabled = clogged
	building.emitter.Enabled = clogged
	if not clogged then
		building.clogIn = BuildingRules.clogDelay(Config, rng:NextNumber())
	end
end

-- Clears plot `index`'s clog; true when it was clogged. The Unclog prompt, and 3f's Plumber.
function Buildings.unclog(index: number): boolean
	local building = placed[index]
	if not building or not building.clogged then
		return false
	end
	setClogged(building, false)
	return true
end

-- 3f's Plumber: `scale` multiplies every building's output (1.1 = +10 %), and `keepClear` stops clogs
-- (and clears the ones there are).
function Buildings.setPlumber(scale: number, keepClear: boolean)
	plumber.scale, plumber.keepClear = scale, keepClear
	if keepClear then
		for index in placed do
			Buildings.unclog(index)
		end
	end
end

local function onUnclog(player: Player, index: number)
	local state = hooks.states[player]
	local building = placed[index]
	if not state or not building or not hooks.playing() or not hooks.allow(state, "unclog", MAX_UNCLOGS_PER_SECOND) then
		return
	end
	if hooks.inReach(player, building.prompt) and Buildings.unclog(index) then
		hooks.tell(player, `The {building.item.name} runs again!`)
	end
end

-- Puts `item`'s model on plot `index` and closes the plot's prompt.
local function place(index: number, item)
	local plot = plots[index]
	local model = template(item):Clone()
	model.Name = "Building"
	model:PivotTo(plot.base.CFrame * CFrame.new(0, plot.base.Size.Y / 2, 0))
	local prompt = model:FindFirstChild("Unclog", true) :: ProximityPrompt
	local building = { item = item, model = model, prompt = prompt, emitter = model:FindFirstChild("Clog", true) :: ParticleEmitter, clogged = false, clogIn = 0 }
	setClogged(building, false)
	model.Parent = plot.model
	prompt.Triggered:Connect(function(player)
		onUnclog(player, index)
	end)
	placed[index] = building
	plot.prompt.Enabled = false
end

-- The run's save is in: its buildings stand on their plots again, and nothing else does (an admin
-- reset loads a blank save over a played one). A plot or building the place or Config no longer has
-- is left in the save (a later fix brings it back) and warned about.
function Buildings.load(runSave: RunSave.Save)
	save = runSave
	for index, building in placed do
		building.model:Destroy()
		plots[index].prompt.Enabled = true
	end
	table.clear(placed)
	for key, id in runSave.plots do
		local index = tonumber(key) :: number
		local item = Items.get(Config, id)
		if not plots[index] or not item or item.kind ~= "building" then
			warn(`[Buildings] the save has {id} on plot {key}, but there is no such plot or building; not placed`)
			continue
		end
		if runSave.buildings[id] == nil then
			runSave.buildings[id] = 0
		end
		place(index, item)
	end
	publishLevels()
end

-- Build(plot, item id) from client/Buildings' picker.
local function onBuild(player: Player, index: unknown, id: unknown)
	local state = hooks.states[player]
	if not state or not save or not hooks.playing() or not hooks.allow(state, "build", MAX_BUILDS_PER_SECOND) then
		return
	end
	local item = Items.get(Config, id)
	local ok, reason = BuildingRules.canBuild(save.plots, #plots, index, item, hooks.openAreas(), save.team.wallet, hooks.price)
	if not ok then
		if reason == "money" then
			hooks.tell(player, "Not enough coins")
			if item then
				Telemetry.blocked(player, "CantAfford", item.id)
			end
		elseif reason == "taken" then
			hooks.tell(player, "A teammate already built on this plot")
		end
		return
	end
	local plotIndex = index :: number
	if not hooks.inReach(player, plots[plotIndex].prompt) then
		return
	end
	hooks.spend(hooks.price(item.price), player, "Build", item.id)
	save.plots[tostring(plotIndex)] = item.id
	if save.buildings[item.id] == nil then
		save.buildings[item.id] = 0
	end
	place(plotIndex, item)
	publishLevels()
	Telemetry.buildingBuilt(player, item.id)
	hooks.card(`{player.DisplayName} built a {item.name} for the team!`)
	hooks.save(`{player.Name} built {item.id} on plot {plotIndex}`)
end

-- TAB's Buy(id) for building `id` (server/Run checks it is one and that nobody bought this level
-- first): the team's wallet pays the next level of that building for the whole team
-- (Items.buildingOffer). A level needs one standing on a plot: a saved one the place lost
-- (Buildings.load) makes nothing. True when it bought the level.
function Buildings.buy(player: Player, id: string): boolean
	local item = Items.get(Config, id)
	if not save or not item then
		return false
	end
	local level, status = Items.buildingOffer(Config, save.buildings, id, hooks.openAreas())
	local cost = if status == "buy" then hooks.price(level.cost) else 0
	if status ~= "buy" or not Items.affords(save.team.wallet, cost) then
		return false
	end
	local standing = false
	for _, building in placed do
		standing = standing or building.item.id == id
	end
	if not standing then
		hooks.tell(player, `Build a {item.name} on a plot first`)
		Telemetry.blocked(player, "NotBuilt", id)
		return false
	end
	hooks.spend(cost, player, "BuildingLevel", id)
	save.buildings[id] += 1
	publishLevels()
	hooks.card(`{player.DisplayName} levelled up the team's {item.name}: Lv {save.buildings[id] + 1}!`)
	hooks.save(`{player.Name} levelled {id}`)
	return true
end

-- An aqueduct's water shows while a plot on its side has a building and the run plays.
local function updateAqueducts()
	local playing = hooks.playing()
	for side, aqueduct in aqueducts do
		local flowing = false
		for index in placed do
			flowing = flowing or (playing and plots[index].side == side)
		end
		if aqueduct.flowing ~= flowing then
			aqueduct.flowing = flowing
			aqueduct.model:SetAttribute("Flowing", flowing)
			aqueduct.water.Transparency = if flowing then aqueduct.transparency else 1
		end
	end
end

-- One output tick of `dt` seconds: every building pours, clocks tick toward clogs.
local function tick(dt: number)
	updateAqueducts()
	if not save or not hooks.playing() or next(hooks.states) == nil then
		return -- D4: nothing fills while nobody plays
	end
	local litres = 0
	for _, building in placed do
		local rate = Items.buildingStat(save.buildings, building.item, "rate")
		litres += BuildingRules.litres(Config, rate, dt, building.clogged, plumber.scale)
		if not building.clogged and not plumber.keepClear then
			building.clogIn -= dt
			if building.clogIn <= 0 then
				setClogged(building, true)
			end
		end
	end
	if litres > 0 then
		Payroll.owe(hooks.fill(litres) * BuildingRules.payPerLitre(Config, hooks.openIds()), "Buildings")
	end
end

function Buildings.start(runHooks: Hooks, buildRemote: RemoteEvent)
	hooks = runHooks
	templates = child(ReplicatedStorage, "Buildings", "Folder")
	for _, item in Config.items do
		if item.kind == "building" then
			template(item)
		end
	end
	local scenery = child(workspace, "Map", "Instance")
	local folder = child(scenery, "Plots", "Instance")
	for index = 1, math.huge do
		local model = folder:FindFirstChild(`Plot{index}`)
		if not model then
			break
		end
		assert(model:IsA("Model"), `{model:GetFullName()} must be a Model`)
		local base = child(model, "Base", "BasePart")
		local prompt = child(base, "Prompt", "ProximityPrompt")
		plots[index] = { model = model, base = base, prompt = prompt, side = BuildingRules.side(base.Position.X) }
	end
	assert(#plots > 0, `{folder:GetFullName()} has no Plot1`)
	local town = child(scenery, "Town", "Instance")
	for _, side in SIDES do
		local model = child(town, `Aqueduct_{side}`, "Instance")
		local water = child(model, "Water", "BasePart")
		aqueducts[side] = { model = model, water = water, transparency = water.Transparency, flowing = nil }
	end
	updateAqueducts()
	buildRemote.OnServerEvent:Connect(onBuild)

	local sinceTick = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceTick += dt
		if sinceTick >= TICK then
			tick(sinceTick)
			sinceTick = 0
		end
	end)
end

return Buildings
