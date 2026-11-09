-- The shop menu (StarterGui.Hud.Shop, built in Studio in the sunbaked-sea style). Tab, gamepad Y or
-- the on-screen Shop button opens and closes it during a run (client/Window: the frame pops in,
-- then its parts appear layer by layer). One tile per upgrade track (Tool and
-- Boosts panels, from Config.tracks); clicking a tile shows it in the detail panel, whose Buy button
-- sends Buy(trackId). The server checks every buy.
-- Tabs (Body.Tabs): Tools (the tracks), Gear (one tile per backpack and gadget in GearPanel), Vehicles
-- (one tile per vehicle in VehiclePanel), Buildings (one tile per building in BuildingPanel: the
-- team's levels, server/Buildings), and Staff (one tile per staff in StaffPanel; ComingSoon stands in
-- for a tab without panels). Items are
-- bought once at their area's stand (buildings on a plot); here an owned one shows its level and its
-- Buy button sends Buy(itemId) to level it up, and an unowned one says where to buy it. An owned
-- staff's detail also shows Detail.AssignButton, which sends Staff("assign", itemId, areaId) with the
-- next post it may work (StaffRules.nextPost; the server checks it).
-- Tiles show what you own and every price (dim while locked); the detail panel shows what is next
-- and, when it can't be bought here, where or why in plain words. A tab with something you can buy
-- now shows its Badge (as does the Upgrades button), a tab with nothing on sale is dimmed, and the
-- shop opens on the first tab with something affordable, else Tools.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local StaffRules = require(ReplicatedStorage.Shared.StaffRules)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Hud = require(script.Parent.Hud)
local Purchase = require(script.Parent.Purchase)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local colors, images, motion = Theme.colors, Theme.images, Theme.motion
local short, set, pressable = Hud.short, Hud.set, Hud.pressable

local DESIGN_SIZE = Vector2.new(1000, 660) -- the shop plus room for its decorations
local QUICK = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Upgrades button: squish down while held, spring back past full size on release.
local HOLD_SCALE = 0.82
local HOLD_DOWN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOLD_UP = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BUY_GUARD = 0.4 -- seconds Buy ignores clicks after a buy is sent or lands, so a double click buys once
local PENDING_SECONDS = 2 -- a sent buy that hasn't landed by then was refused; Buy works again
local TAB_REFRESH = 0.25 -- seconds between badge and tab checks while the shop is closed
local DIM = 0.45 -- transparency of a locked tile's price: still readable, clearly not for sale yet

local Shop = {}
local showTile: ((string) -> ())? = nil

-- Art for each track until real upgrade icons are drawn (the tool shows its 3D model instead).
local ICONS = { pickup = "pipFull", hold = "unknown", quick = "unknown", walk = "unknown", tip = "coin" }
local PANEL_NAMES = { tool = "Tool", boosts = "Boosts" }
-- Tabs in order and the Content panels each shows; a tab without panels shows ComingSoon.
local TABS = { "Tools", "Gear", "Vehicles", "Buildings", "Staff" }
local TAB_PANELS = {
	Tools = { "ToolPanel", "BoostPanel" },
	Gear = { "GearPanel" },
	Vehicles = { "VehiclePanel" },
	Buildings = { "BuildingPanel" },
	Staff = { "StaffPanel" },
}
-- the tab panel holding each kind's tiles
local ITEM_PANELS = { backpack = "GearPanel", gadget = "GearPanel", vehicle = "VehiclePanel", building = "BuildingPanel", staff = "StaffPanel" }
-- the detail panel's category line; the rest say "Gear"
local ITEM_CATEGORIES = { vehicle = "Vehicle", building = "Building", staff = "Staff" }

-- Tiles take their panel's tag colour, so the colour says which group an upgrade belongs to.
local function panelColor(track): Color3
	return if track.panel == "tool" then colors.toolTag else colors.speedTag
end

local function scoops(n: number): string
	return if n == 1 then "1 scoop" else `{n} scoops`
end

local function percent(bonus: number): string
	return `+{math.floor((bonus - 1) * 100 + 0.5)}%`
end

-- What the next level changes, from the stats now and after buying it. Litres per trip include the
-- worn backpack; scoop counts stay the tool's.
local function effectText(id: string, now: Ladder.Stats, after: Ladder.Stats): string
	if id == "tool" then
		local gear = Hud.items()
		local tripNow, tripAfter = Items.withGear(Config, gear, now).capacity, Items.withGear(Config, gear, after).capacity
		return `{short(tripAfter)} L per trip, {scoops(after.sweeps)} to fill (now {short(tripNow)} L)`
	elseif id == "pickup" then
		return `Fill your tool in {scoops(after.sweeps)} (now {scoops(now.sweeps)})`
	elseif id == "hold" then
		return "One-time buy"
	elseif id == "quick" then
		return `{after.actSeconds}s per scoop (now {now.actSeconds}s)`
	elseif id == "walk" then
		return `Walk speed {after.walkSpeed} (now {now.walkSpeed})`
	end
	return `{percent(after.coinBonus)} coins per litre (now {percent(now.coinBonus)})`
end

local function levelsOf(): { [string]: number }
	return Hud.levels(0) :: { [string]: number }
end

local function fillNow(): number
	local fill = ReplicatedStorage:GetAttribute("Fill")
	return if type(fill) == "number" then fill else 0
end

-- Why something of area `areaId` is locked: "Behind the Hot Springs gate (fill the ocean to 22%)".
local function behindGate(areaId: number): string
	local area = Areas.byId(Config, areaId)
	return `Behind the {area.name} gate ({Format.gateHint(area, fillNow())})`
end

-- The tab showing an item's tile.
local function tabOf(item): string
	for name, panels in TAB_PANELS do
		if table.find(panels, ITEM_PANELS[item.kind]) then
			return name
		end
	end
	error(`Shop has no tab for {item.kind} items`)
end

-- Upgrades bought on an item, or nil while it isn't owned: the player's own, or the team's for a
-- building (Hud.buildings).
local function boughtLevel(item, itemState: Items.State): number?
	if item.kind == "building" then
		return Hud.buildings()[item.id]
	end
	return if Items.owned(itemState, item.id) then itemState.itemLevels[item.id] else nil
end

-- Per tab: the first tile `money` buys in TAB now (nil for none) and whether anything there is on
-- sale here, at a stand or on a plot (else the tab is dimmed).
local function tabStates(levels: { [string]: number }, money: number): { [string]: { afford: string?, any: boolean } }
	local states = {}
	for _, name in TABS do
		states[name] = { afford = nil, any = false }
	end
	local function check(name: string, id: string)
		local _, status, affordable = Hud.offer(levels, id, money)
		local s = states[name]
		s.any = s.any or status == "buy" or status == "stand" or status == "unbuilt"
		if affordable and not s.afford then
			s.afford = id
		end
	end
	for _, track in Config.tracks do
		check("Tools", track.id)
	end
	for _, item in Config.items do
		check(tabOf(item), item.id)
	end
	return states
end

-- Levels bought of track or item `id` as the server has published them (-1 while an item isn't
-- owned), to tell when a buy has landed.
local function boughtCount(id: string): number
	if Config.track(id) then
		return levelsOf()[id]
	end
	return boughtLevel(Items.get(Config, id), Hud.items()) or -1
end

-- What an unowned or maxed item's detail says (Hud.offer's item statuses): where to get it and its
-- price, or why not yet. Staff are hired at the Lifeguard Tower in the cove once the area they open
-- with is open, so a locked one says which gate.
local function itemNote(item, status: string?): string
	local area = Areas.byId(Config, item.area)
	local place = Format.standName(Config, item.stand, area)
	local verb = if item.kind == "staff" then "Hire" else "Buy"
	if status == "max" then
		return "MAX"
	elseif status == "replaced" then
		local worn = Items.backpack(Config, Hud.items())
		return `Replaced by the {if worn then worn.name else "next one"}`
	elseif status == "unbuilt" then
		return `Build one on a town plot · {Hud.money(item.price)}`
	elseif status == "stand" then
		return `{verb} at the {place} · {Hud.money(item.price)}`
	elseif item.stand then
		return `{verb} at the {place} once {area.name} opens ({Format.gateHint(area, fillNow())})`
	end
	return behindGate(item.area)
end

-- The Buy button's word when it can't buy (the full reason is in the detail's effect text).
local BUTTON_WORDS = { max = "MAXED", stand = "AT STAND", unbuilt = "ON A PLOT", replaced = "REPLACED", locked = "LOCKED", useless = "NOT YET" }

-- A stat in the effect texts: whole numbers under 1000 as they are (6), the rest short (1.6, 3.0K).
local function amount(n: number): string
	return if n == math.floor(n) and n < 1000 then tostring(n) else short(n)
end

-- Effect texts read stats as `stat(name, unit, format)`: the value and its unit ("6 L/s per plot"),
-- and " (now 3)" when the text shows the next level (`was` reads the current one) and it changes.
type Stat = (name: string, unit: string?, format: ((number) -> string)?) -> string
local function statText(read: (string) -> number, was: ((string) -> number)?): Stat
	return function(name, unit, format)
		local show = format or amount
		local value = read(name)
		local before = if was then was(name) else value
		local text = `{show(value)}{unit or ""}`
		return if before ~= value then `{text} (now {show(before)})` else text
	end
end

-- What each gadget does at some level (Config.ItemLevel stats).
local GADGET_EFFECTS = {
	waterGun = function(stat: Stat)
		return `Pours from {stat("range", " studs away")}`
	end,
	gardenHose = function(stat: Stat)
		return `{stat("rate", " L/s")}, reach {stat("reach", " studs")}`
	end,
	heatGloves = function(stat: Stat)
		return `Hot pools {stat("hotFill", "x faster")}`
	end,
	icePick = function(stat: Stat)
		return stat("hits", " hits per block")
	end,
	jetpackTank = function(stat: Stat)
		return `{stat("flightSeconds", "s flight")}, holds {stat("capacity", " L")}`
	end,
	cloudNet = function(stat: Stat)
		return `Catches clouds from {stat("range", " studs")}`
	end,
}

-- What a vehicle does at some level (as GADGET_EFFECTS).
local function vehicleEffect(stat: Stat): string
	return `{stat("tank", " L tank")}, {stat("fillRate", " L/s fill")}`
end

-- What a building does at some level (every building: its litres a second).
local function buildingEffect(stat: Stat): string
	return stat("rate", " L/s per plot")
end

-- What a staff does at some level, by its job (Config.items `job`); how many are hired only once
-- one is.
local function staffEffect(stat: Stat, item, owned: boolean): string
	local who = if owned then `{stat("hires", " hired")}, ` else ""
	if item.job == "area" then
		return `{who}{stat("carry", " L")} every {stat("tripSeconds", "s")} per {item.name}`
	elseif item.job == "truck" then
		return `{who}a tank every {stat("tripSeconds", "s")} per {item.name}`
	end
	return `{who}no clogs, {stat("boost", " output", percent)}`
end

local KIND_EFFECTS = { vehicle = vehicleEffect, building = buildingEffect, staff = staffEffect }

-- What an item does now and after its next upgrade: a backpack's litres, a gadget's, vehicle's,
-- building's or staff's stats.
local function itemEffect(item, level, owned: boolean): string
	local function nowStat(name: string): number
		if not owned then
			return item[name]
		end
		return if item.kind == "building" then Items.buildingStat(Hud.buildings(), item, name) else Items.stat(Hud.items(), item, name)
	end
	if item.kind == "gadget" or KIND_EFFECTS[item.kind] then
		local effect = KIND_EFFECTS[item.kind] or GADGET_EFFECTS[item.id]
		assert(effect, `Shop has no effect text for {item.id}`)
		if level then
			return effect(statText(function(name: string): number
				return level[name]
			end, nowStat), item, owned)
		end
		return effect(statText(nowStat), item, owned)
	end
	local now = nowStat("capacity")
	if level then
		return `Holds {short(level.capacity)} L on your back (now {short(now)} L)`
	end
	return `Holds {short(now)} L on your back`
end


-- The display name of a track's level `n`: tools have their own, the rest are "<track> <n>".
function Shop.levelName(track, n: number, level): string
	if track.id == "tool" then
		return level.name
	end
	return if #track.levels == 1 then track.name else `{track.name} {n}`
end

-- Opens the shop on the tile of track or item `id` (client/Goal).
function Shop.show(id: string)
	assert(showTile, "Shop.show before Shop.start")(id)
end

local function bounce(scale: UIScale)
	scale.Scale = 1.12
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Where an owned staff works (the server's Staff attribute: an area id, 0 for nowhere), or nil until
-- the server has published it.
local function postOf(id: string): number?
	for _, entry in StaffRules.decode(player:GetAttribute("Staff")) do
		if entry.id == id then
			return entry.post
		end
	end
	return nil
end

-- The posts staff `item` may work now, as the server checks them (StaffRules.targets).
local function postsOf(item): { number }
	local items = Hud.items()
	return StaffRules.targets(Config, item, items.owned, Items.reachable(Config, items, Areas.openIds(Hud.gatesOpen())))
end

-- The Assign button's text for staff `item` working at `post`.
local function assignText(item, post: number?): string
	if item.job == "plots" then
		return "FIXES THE TEAM'S BUILDINGS"
	elseif not post or post == 0 then
		return if item.job == "truck" then "BUY A VEHICLE FIRST" else "..."
	elseif item.job == "truck" then
		local truck = StaffRules.truck(Config, post)
		if truck then
			return `DRIVES THE {truck.name:upper()}`
		end
	end
	return `WORKS AT {Areas.byId(Config, post).name:upper()}`
end

function Shop.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Buy") :: RemoteEvent
	local staffRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Staff") :: RemoteEvent
	local shop = Hud.find(gui, "Shop")
	local fit = Hud.find(gui, "Shop.Scale")
	local content = Hud.find(gui, "Shop.Body.Content")
	local detail = Hud.find(content, "Detail")
	local detailArt = Hud.find(detail, "Art")
	local buyButton = Hud.find(detail, "BuyButton")
	local buyText = Hud.find(buyButton, "Row.BuyText")
	local buyCoin = Hud.find(buyButton, "Row.Coin")
	local buyPrice = Hud.find(buyButton, "Row.Price")
	local assignButton = Hud.find(detail, "AssignButton")
	local assignLabel = Hud.find(assignButton, "Label")
	local closeButton = Hud.find(shop, "CloseButton")
	local tiles = {}
	for _, track in Config.tracks do
		local panel = if track.panel == "tool" then "ToolPanel" else "BoostPanel"
		tiles[track.id] = Hud.find(content, `{panel}.Tiles.{track.id}`)
	end
	local itemTiles = {}
	for _, item in Config.items do
		local panel = ITEM_PANELS[item.kind]
		assert(panel, `Shop has no panel for {item.kind} items yet`)
		itemTiles[item.id] = Hud.find(content, `{panel}.Tiles.{item.id}`)
	end
	local tabButtons = {}
	local tabBadges = {}
	for _, name in TABS do
		tabButtons[name] = Hud.find(gui, `Shop.Body.Tabs.{name}`)
		tabBadges[name] = Hud.find(tabButtons[name], "Badge")
		for _, panel in TAB_PANELS[name] or {} do
			Hud.find(content, panel) -- fail at start, not on the first tab switch
		end
	end
	local comingSoon = Hud.find(content, "ComingSoon")
	local selected = "tool"
	local tab = "Tools"

	-- Tab would also toggle Roblox's player list; the game has its own Board, so hide that list.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

	local open = false
	local fitScale = 1
	local function refit()
		local view = gui.AbsoluteSize -- the Hud's area inside the top bar and safe insets, not the viewport
		fitScale = math.min(view.X / DESIGN_SIZE.X, view.Y / DESIGN_SIZE.Y, 1)
		if open then
			fit.Scale = fitScale
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()

	local window = Window.new(shop, fit)
	-- Opening shows the first tab with something you can buy now (on that tile), else Tools; `pick` (a
	-- track or item id) opens on its tile instead.
	local function setOpen(value: boolean, pick: string?)
		if value and pick then
			tab, selected = if Config.track(pick) then "Tools" else tabOf(Items.get(Config, pick)), pick
		elseif value and not open then
			local states = tabStates(levelsOf(), player:GetAttribute("Money") or 0)
			tab, selected = "Tools", "tool"
			for _, name in TABS do
				if states[name].afford then
					tab, selected = name, states[name].afford :: string
					break
				end
			end
		end
		if value == open then
			return
		end
		open = value
		if value then
			window.open(fitScale)
		else
			window.close(fitScale)
		end
	end

	local function inRun(): boolean
		local phase = ReplicatedStorage:GetAttribute("Phase")
		return phase == "playing"
	end
	showTile = function(id: string)
		if inRun() then
			setOpen(true, id)
		end
	end

	-- The Upgrades button (right edge) shows where the shop is. Holding Tab / Y / the mouse / a
	-- finger squishes it down; letting go springs it back up. Tab and Y open (or close) the shop as
	-- they go down, so a release that never arrives (focus moving) can't swallow the press; the mouse
	-- and a finger open it on release, like a button. Its key tag tells keyboard and gamepad players
	-- which key does it; its Badge shows while something in the shop can be bought now.
	local upgrades = Hud.find(gui, "UpgradesButton")
	local upgradesBadge = Hud.find(upgrades, "Badge")
	local upgradesPress = Hud.find(upgrades, "Press") :: UIScale
	local upgradesKey = Hud.find(upgrades, "Key")
	local upgradesKeyText = Hud.find(upgradesKey, "Text")
	local held = false
	local hovered = false
	local function hold()
		held = true
		TweenService:Create(upgradesPress, HOLD_DOWN, { Scale = HOLD_SCALE }):Play()
	end
	local function release(toggle: boolean)
		if not held then
			return
		end
		held = false
		TweenService:Create(upgradesPress, HOLD_UP, { Scale = if hovered then motion.hoverScale else 1 }):Play()
		if toggle then
			setOpen(not open and inRun())
		end
	end
	ContextActionService:BindAction("ToggleShop", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			hold()
			setOpen(not open and inRun())
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			release(false)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Tab, Enum.KeyCode.ButtonY)
	upgrades.MouseEnter:Connect(function()
		hovered = true
		if not held then
			TweenService:Create(upgradesPress, QUICK, { Scale = motion.hoverScale }):Play()
		end
	end)
	upgrades.MouseLeave:Connect(function()
		hovered = false
		if held then
			release(false) -- dragged off the button: cancel, like a normal button
		else
			TweenService:Create(upgradesPress, QUICK, { Scale = 1 }):Play()
		end
	end)
	upgrades.MouseButton1Down:Connect(hold) -- touch fires these too
	upgrades.MouseButton1Up:Connect(function()
		release(true)
	end)

	-- Buy and Close each hold a HitPad (a transparent button built in Studio) that keeps the touch
	-- target at least 44 px when the shop is scaled down on phones. The pad takes mouse and touch;
	-- the button itself still takes gamepad selection, so both run fn.
	local function onPress(button: GuiButton, fn: () -> ())
		local pad = Hud.find(button, "HitPad") :: GuiButton
		pressable(pad, (button :: any).Press)
		pad.Activated:Connect(fn)
		button.Activated:Connect(fn)
	end
	onPress(closeButton, function()
		setOpen(false)
	end)
	for _, list in { tiles, itemTiles } do
		for id, holder in list do
			local button = Hud.find(holder, "Button")
			pressable(button, button.Press)
			button.Activated:Connect(function()
				selected = id
			end)
		end
	end
	-- A tab shows its panels and selects its first tile.
	local firstTile = { Tools = "tool" }
	for _, item in Config.items do
		local name = tabOf(item)
		firstTile[name] = firstTile[name] or item.id
	end
	for name, button in tabButtons do
		pressable(button, button.Press)
		button.Activated:Connect(function()
			tab = name
			selected = firstTile[name] or selected
		end)
	end
	local guardUntil = 0
	local pending: { id: string, have: number, at: number }? = nil
	onPress(buyButton, function()
		local now = os.clock()
		local have = boughtCount(selected)
		local waiting = pending and pending.id == selected and pending.have == have and now - pending.at < PENDING_SECONDS
		if now < guardUntil or waiting then
			return -- the last buy hasn't landed (or just did): this click must not buy the level after it
		end
		local _, _, canBuy = Hud.offer(levelsOf(), selected, player:GetAttribute("Money") or 0)
		if not canBuy then
			Purchase.deny(buyButton)
			return
		end
		bounce(buyButton.Press)
		buyRemote:FireServer(selected)
		pending = { id = selected, have = have, at = now }
		guardUntil = now + BUY_GUARD
	end)
	-- Assign: the selected staff moves to its next allowed post.
	pressable(assignButton, assignButton.Press)
	assignButton.Activated:Connect(function()
		local item = Items.get(Config, selected)
		if not (item and item.kind == "staff" and Items.owned(Hud.items(), item.id)) then
			return
		end
		local now = postOf(item.id)
		local post = StaffRules.nextPost(postsOf(item), now)
		if post and post ~= now then
			bounce(assignButton.Press)
			staffRemote:FireServer("assign", item.id, post)
		else
			Purchase.deny(assignButton)
		end
	end)

	-- Shows the tool model (tool track) or the track's icon (a lock while locked) in an art slot.
	local shownModels: { [Instance]: string } = {}
	local function showArt(holder: Instance, id: string, model: string, locked: boolean?)
		local icon, view = Hud.find(holder, "Icon"), Hud.find(holder, "View")
		set(icon, "Visible", id ~= "tool")
		set(view, "Visible", id == "tool")
		if id ~= "tool" then
			set(icon, "Image", if locked then images.lock else images[ICONS[id]])
		elseif shownModels[view] ~= model then
			local template = ToolModels.find(model)
			if template then -- nil until replicated; try again next frame
				ToolModels.showIn(view, template)
				shownModels[view] = model
			end
		end
	end

	-- A tile's price row: `cost` (red when you can't pay it, dim while `grey`) or `word` (MAX, Replaced).
	local function priceRow(holder: Instance, cost: number?, word: string, grey: boolean, money: number)
		local coin, price = Hud.find(holder, "PriceRow.Coin"), Hud.find(holder, "PriceRow.Price")
		set(coin, "Visible", cost ~= nil)
		set(coin, "ImageTransparency", if grey then DIM else 0)
		set(price, "Text", if cost then Hud.money(cost) else word)
		set(price, "TextTransparency", if grey then DIM else 0)
		set(price, "TextColor3", if cost and not grey and not Items.affords(money, cost) then colors.buyCoral else colors.foam)
	end

	local shownLevels: { [string]: number } = {}
	local tabInfo = tabStates(levelsOf(), 0)
	local tabsAt = 0
	local shownSelected, shownHave = selected, boughtCount(selected)
	RunService.RenderStepped:Connect(function()
		if open and not inRun() then
			setOpen(false)
		end
		local clock = os.clock()
		if clock >= tabsAt then -- badges show while the shop is closed too
			tabsAt = clock + TAB_REFRESH
			tabInfo = tabStates(levelsOf(), player:GetAttribute("Money") or 0)
			local any = false
			for name, badge in tabBadges do
				set(badge, "Visible", tabInfo[name].afford ~= nil)
				any = any or tabInfo[name].afford ~= nil
			end
			set(upgradesBadge, "Visible", any)
		end
		set(upgrades, "Visible", inRun() and not shop.Visible)
		local input = UserInputService:GetLastInputType()
		local touch = input == Enum.UserInputType.Touch
		set(upgradesKey, "Visible", not touch)
		set(upgradesKeyText, "Text", if input.Name:sub(1, 7) == "Gamepad" then "Y" else "TAB")
		if not shop.Visible then
			return
		end
		local money = player:GetAttribute("Money") or 0
		local levels = levelsOf()
		local now = Ladder.stats(Config, levels)

		-- A buy landing (the selected tile's bought count goes up) holds Buy back for a moment too.
		local boughtNow = boughtCount(selected)
		if selected == shownSelected and boughtNow ~= shownHave then
			guardUntil = clock + BUY_GUARD
		end
		shownSelected, shownHave = selected, boughtNow

		-- Tabs: the open one is shallow blue, the rest sand, dimmed with nothing on sale; ComingSoon
		-- stands in for missing panels.
		for name, button in tabButtons do
			set(button, "ImageColor3", if name == tab then colors.shallowWater elseif tabInfo[name].any then colors.drySand else colors.locked)
			for _, panel in TAB_PANELS[name] or {} do
				set(Hud.find(content, panel), "Visible", name == tab)
			end
		end
		set(comingSoon, "Visible", TAB_PANELS[tab] == nil)
		set(detail, "Visible", TAB_PANELS[tab] ~= nil)

		-- Item tiles: the level you own, and the next upgrade's price or the item's own
		local itemState = Hud.items()
		for _, item in Config.items do
			local holder = itemTiles[item.id]
			local button = Hud.find(holder, "Button")
			local bought = boughtLevel(item, itemState)
			local level, status = Hud.offer(levels, item.id, money)
			local grey = status == "locked" or status == "replaced"
			set(button, "ImageColor3", if grey then colors.locked else colors.shallowWater)
			set(Hud.find(button, "Ring"), "Visible", item.id == selected)
			set(Hud.find(button, "Icon"), "Visible", true)
			set(Hud.find(button, "View"), "Visible", false)
			set(Hud.find(button, "Icon"), "Image", if status == "locked" then images.lock else images.unknown)
			set(Hud.find(button, "ItemName"), "Text", item.name)
			set(Hud.find(button, "Pips"), "Visible", false)
			set(Hud.find(button, "Level"), "Visible", true)
			set(Hud.find(button, "Level"), "Text", if bought then `Lv {bought + 1}` else "")
			local cost = if status == "buy" then level.cost elseif bought == nil and status ~= "replaced" then item.price else nil
			priceRow(holder, cost, if status == "max" then "MAX" else "Replaced", grey, money)
		end

		for _, track in Config.tracks do
			local id = track.id
			local holder = tiles[id]
			local button = Hud.find(holder, "Button")
			local have = levels[id]
			local level, status = Hud.offer(levels, id, money)
			local grey = status == "locked" or status == "useless"
			set(button, "ImageColor3", if grey then colors.locked else panelColor(track))
			set(Hud.find(button, "Ring"), "Visible", id == selected)
			showArt(button, id, now.toolModel, grey)
			set(Hud.find(button, "ItemName"), "Text", if id == "tool" then now.toolName else track.name)

			-- Level pips (short tracks) or a level label (the long tool ladder, the one-time Hold)
			local pips = Hud.find(button, "Pips")
			local label = Hud.find(button, "Level")
			local usePips = id ~= "tool" and #track.levels > 1
			set(pips, "Visible", usePips)
			set(label, "Visible", not usePips)
			if usePips then
				for _, pip in pips:GetChildren() do
					if pip:IsA("ImageLabel") then
						set(pip, "Visible", pip.LayoutOrder <= #track.levels)
						set(pip, "Image", if pip.LayoutOrder <= have then images.pipFull else images.pipEmpty)
					end
				end
				if shownLevels[id] and have > shownLevels[id] then
					local pip = pips:FindFirstChild(`Pip{have}`)
					if pip then
						bounce(pip.Pop)
					end
				end
			elseif id == "tool" then
				set(label, "Text", "OWNED") -- the tool you hold; the detail shows the next one
			else
				set(label, "Text", if have > 0 then "OWNED" else "")
			end
			shownLevels[id] = have

			-- Price row: the next level's price (red when you can't afford it, dim while locked), or MAX
			priceRow(holder, if level then level.cost else nil, "MAX", grey, money)
		end

		-- Detail panel: the selected item's next upgrade
		local selectedItem = Items.get(Config, selected)
		if selectedItem then
			local level, status, canLevel = Hud.offer(levels, selected, money)
			local bought = boughtLevel(selectedItem, itemState)
			set(Hud.find(detail, "Category"), "Text", ITEM_CATEGORIES[selectedItem.kind] or "Gear")
			set(detailArt, "ImageColor3", if status == "locked" or status == "replaced" then colors.locked else colors.shallowWater)
			set(Hud.find(detailArt, "Icon"), "Visible", true)
			set(Hud.find(detailArt, "View"), "Visible", false)
			set(Hud.find(detailArt, "Icon"), "Image", if status == "locked" then images.lock else images.unknown)
			set(Hud.find(detail, "About"), "Text", selectedItem.about)
			set(Hud.find(detail, "MoneyRow.Money"), "Text", Hud.money(money))
			local name = selectedItem.name
			set(Hud.find(detail, "ItemName"), "Text", if bought and level then `Next: {name} Lv {bought + 2}` elseif bought then `{name} Lv {bought + 1}` else name)
			local effect = itemEffect(selectedItem, level, bought ~= nil)
			-- the button only fits a word, so the full "where to get it" sentence leads the effect
			local note = status ~= "buy" and status ~= "max"
			set(Hud.find(detail, "Effect"), "Text", if note then `{itemNote(selectedItem, status)}\n{effect}` else effect)
			set(buyCoin, "Visible", status == "buy")
			set(buyPrice, "Visible", status == "buy")
			-- the button fits a short word beside the price (a longer one overflows at 150.0K)
			set(buyText, "Text", if status == "buy" then "BUY" else BUTTON_WORDS[status :: string] or "LOCKED")
			if status == "buy" then
				set(buyPrice, "Text", Hud.money(level.cost))
			end
			set(buyButton, "ImageColor3", if canLevel then colors.buyCoral else colors.locked)
			local hired = selectedItem.kind == "staff" and bought ~= nil
			set(assignButton, "Visible", hired)
			if hired then
				set(assignLabel, "Text", assignText(selectedItem, postOf(selectedItem.id)))
			end
			return
		end

		-- Detail panel: the selected track's next level
		set(assignButton, "Visible", false)
		local track = Config.track(selected) :: Config.Track
		local have = levels[selected]
		local level, status, canBuy = Hud.offer(levels, selected, money)
		set(Hud.find(detail, "Category"), "Text", PANEL_NAMES[track.panel])
		set(detailArt, "ImageColor3", if status == "locked" then colors.locked else panelColor(track))
		set(Hud.find(detail, "About"), "Text", track.about)
		set(Hud.find(detail, "MoneyRow.Money"), "Text", Hud.money(money))
		if level then
			local nextLevels = table.clone(levels)
			nextLevels[selected] = have + 1
			showArt(detailArt, selected, if selected == "tool" then level.model else now.toolModel)
			local name = Shop.levelName(track, have + 1, level)
			set(Hud.find(detail, "ItemName"), "Text", if selected == "tool" or have > 0 then `Next: {name}` else name)
			local effect = effectText(selected, now, Ladder.stats(Config, nextLevels))
			if status == "locked" then
				effect = `{behindGate(level.area)}\n{effect}`
			elseif status == "useless" then
				effect = `Your {now.toolName} already fills in one scoop: this helps once a tool takes more`
			end
			set(Hud.find(detail, "Effect"), "Text", effect)
		else
			showArt(detailArt, selected, now.toolModel)
			set(Hud.find(detail, "ItemName"), "Text", if selected == "tool" then now.toolName else track.name)
			set(Hud.find(detail, "Effect"), "Text", "All levels bought!")
		end
		set(buyCoin, "Visible", status == "buy")
		set(buyPrice, "Visible", status == "buy")
		set(buyText, "Text", if status == "buy" then "BUY" else BUTTON_WORDS[status :: string] or "LOCKED")
		if status == "buy" then
			set(buyPrice, "Text", Hud.money(level.cost))
		end
		set(buyButton, "ImageColor3", if canBuy then colors.buyCoral else colors.locked)
	end)
end

return Shop
