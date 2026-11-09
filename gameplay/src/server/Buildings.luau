-- The team's buildings (3e, D2; Config.items kind "building", shared/BuildingRules) on the cove's
-- plots. server/Run starts it with hooks, hands it the save (Buildings.load) and passes it the TAB
-- buys of building ids (Buildings.buy).
-- Building: a plot's Prompt opens client/Buildings' picker; the client sends Build(plot number, item
-- id) and the server checks it (plot empty, area open, price, near the plot, rate limit), takes the
-- coins from the buyer and clones ReplicatedStorage.Buildings.<model> onto the plot. save.plots
-- keeps which building stands on which plot; save.buildings the upgrades bought per building id: a
-- level counts on every plot with that building (one TAB tile per kind, levelled by anyone).
-- Output: while playing with someone present (D4), every building pours its rate (litres a second)
-- into the ocean; its coins (BuildingRules.payPerLitre) are split evenly between the players
-- present, paid every PAY_SECONDS so the coin burst (client/Payout) doesn't fire every second.
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

local TICK = 1 -- seconds between output ticks
local PAY_SECONDS = 10 -- seconds between paydays
local MAX_BUILDS_PER_SECOND = 2
local MAX_UNCLOGS_PER_SECOND = 2
local MONEY_EPSILON = 1e-6 -- pours add fractional coins; 149999.9999999 must still buy a 150,000 level
local SIDES = { "ShopSide", "StaffSide" }

export type Hooks = {
	states: { [Player]: any }, -- server/Run's player states (money)
	playing: () -> boolean,
	openIds: () -> { number }, -- the open area ids (Areas.openIds)
	openAreas: () -> number, -- areas open so far (Ladder.openAreas)
	inReach: (Player, ProximityPrompt) -> boolean,
	allow: (any, string, number) -> boolean, -- server/Run's per-player rate limit (state, key, max a second)
	publish: (Player) -> (), -- publish a player's money
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

-- The run's save is in: its buildings stand on their plots again. A plot or building the place or
-- Config no longer has is left in the save (a later fix brings it back) and warned about.
function Buildings.load(runSave: RunSave.Save)
	save = runSave
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
	local ok, reason = BuildingRules.canBuild(save.plots, #plots, index, item, hooks.openAreas(), state.money)
	if not ok then
		if reason == "money" then
			hooks.tell(player, "Not enough coins")
		end
		return
	end
	local plotIndex = index :: number
	if not hooks.inReach(player, plots[plotIndex].prompt) then
		return
	end
	state.money = math.max(0, state.money - item.price)
	save.plots[tostring(plotIndex)] = item.id
	if save.buildings[item.id] == nil then
		save.buildings[item.id] = 0
	end
	place(plotIndex, item)
	publishLevels()
	hooks.publish(player)
	hooks.card(`{player.DisplayName} built a {item.name}!`)
	hooks.save(`{player.Name} built {item.id} on plot {plotIndex}`)
end

-- TAB's Buy(id) for a building id: the buyer pays the next level of that building for the whole
-- team (Items.buildingOffer). True when `id` is a building (handled here, bought or not).
function Buildings.buy(player: Player, state, id: string): boolean
	local item = Items.get(Config, id)
	if not item or item.kind ~= "building" then
		return false
	end
	if not save then
		return true
	end
	local level, status = Items.buildingOffer(Config, save.buildings, id, hooks.openAreas())
	if status ~= "buy" or state.money + MONEY_EPSILON < level.cost then
		return true
	end
	state.money = math.max(0, state.money - level.cost)
	save.buildings[id] += 1
	publishLevels()
	hooks.publish(player)
	hooks.card(`{player.DisplayName} levelled up the {item.name}: Lv {save.buildings[id] + 1}!`)
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

local owed = 0 -- coins made since the last payday

-- Splits what the buildings made between the players present.
local function payday()
	local present = {}
	for player in hooks.states do
		table.insert(present, player)
	end
	if owed <= 0 or #present == 0 then
		return
	end
	local share = owed / #present
	owed = 0
	for _, player in present do
		hooks.states[player].money += share
		hooks.publish(player)
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
		owed += hooks.fill(litres) * BuildingRules.payPerLitre(Config, hooks.openIds())
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

	local sinceTick, sincePay = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		sinceTick += dt
		sincePay += dt
		if sinceTick >= TICK then
			tick(sinceTick)
			sinceTick = 0
		end
		if sincePay >= PAY_SECONDS then
			payday()
			sincePay = 0
		end
	end)
end

return Buildings
