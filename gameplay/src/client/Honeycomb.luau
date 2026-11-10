-- The upgrades honeycomb (StarterGui.Hud.Honeycomb, built in Studio; layout: library
-- ui/screens/shop.md; where each hex sits and its state: shared/Honeycomb). Tab, gamepad Y or the
-- Upgrades button opens and closes it during a run (client/Window pops it in). The main view: the
-- current tool at the centre and a ring of category hexes, each with a red badge counting what can be
-- bought inside and water showing how much of it is owned; a click glides into the category: its hex,
-- a spine and every upgrade as a chain of hexes (copies of Hud.Templates.Hex) joined by bridges
-- (Templates.Bridge), long chains windowed around the next link. Selecting a hex fills the Detail
-- strip, whose Buy button sends Buy(id, bought) (`bought`: what this client saw bought, so a
-- teammate's buy of the same level wins). Everything is the team's, from its wallet at the team's
-- price (Hud.price); the server checks every buy. Items are first bought at their stand (buildings
-- on a plot), so their first hex says where. Detail.AssignButton moves a hired staff to its next
-- post (Staff("assign", itemId, areaId), StaffRules.nextPost). A buy landing fills its hex, then the
-- bridge, and wakes the next hex (numbers in Cues.honeycomb); your own buy also gets coins, a sting
-- and, for a first, a NEW! stamp (client/Purchase). Back (the button, Esc, gamepad B) glides out,
-- then closes.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Ease = require(ReplicatedStorage.Shared.Ease)
local Format = require(ReplicatedStorage.Shared.Format)
local Comb = require(ReplicatedStorage.Shared.Honeycomb)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local StaffRules = require(ReplicatedStorage.Shared.StaffRules)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Hud = require(script.Parent.Hud)
local Purchase = require(script.Parent.Purchase)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local colors, images, motion = Theme.colors, Theme.images, Theme.motion
local short, set, pressable = Hud.short, Hud.set, Hud.pressable
local CUE = Cues.honeycomb

local QUICK = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Upgrades button: squish down while held, spring back past full size on release.
local HOLD_SCALE = 0.82
local HOLD_DOWN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOLD_UP = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BUY_GUARD = 0.4 -- seconds Buy ignores clicks after a buy is sent or lands, so a double click buys once
local PENDING_SECONDS = 2 -- a sent buy that hasn't landed by then was refused; Buy works again
local REFRESH_OPEN = 0.1 -- seconds between state refreshes (after an attribute change) while open
local REFRESH_CLOSED = 0.25 -- only the badges while closed
local DIM = 0.4 -- transparency of a hex that isn't next yet: still readable, clearly not for sale
local SMALL_PRICE = 0.8 -- a future level's price text, of the template's size
local SPACING = 1.14 -- hex centres sit this much further apart than touching, so the bridges show
local BACK_OVERSHOOT = 1.70158 -- TweenService's Back easing
local PRESS_RATE = 25 -- per second: hover and press scales catch up in about 0.08 s
local RIM_SHADE = 0.4 -- a hex's rim: its colour this far toward the outline navy

-- Category display names, in the ring's order (shared/Honeycomb layout.order).
local CATEGORY_NAMES = { tools = "Tools", boosts = "Boosts", gear = "Gear", vehicles = "Vehicles", buildings = "Buildings", staff = "Staff" }
-- Art for each track but the tool (which shows its 3D model) until real upgrade icons are drawn.
local ICONS = { pickup = "pipFull", hold = "unknown", quick = "unknown", walk = "unknown", tip = "coin" }

local Honeycomb = {}

-- Set by Honeycomb.start: open on an id's next link, and the Guide's next click for an id.
local showId: ((string) -> ())? = nil
local guideTarget: ((string) -> GuiObject?)? = nil
local isOpen = false

-- Opens the honeycomb on the next link of track or item `id` (client/Goal).
function Honeycomb.show(id: string)
	assert(showId, "Honeycomb.show before Honeycomb.start")(id)
end

function Honeycomb.isOpen(): boolean
	return isOpen
end

-- What the guide's hand should tap next to buy track or item `id`: the category hex, the link's
-- hex, the Buy button (or Back out of another category); nil while closed.
function Honeycomb.guideTarget(id: string): GuiObject?
	return if guideTarget then guideTarget(id) else nil
end

local layout = Comb.layout(Config)

-- Every link by key, with its chain and category.
type Info = { link: Comb.Link, chain: Comb.Chain, catId: string }
local infos: { [string]: Info } = {}
for _, catId in layout.order do
	for _, chain in layout.categories[catId].chains do
		for _, link in chain.links do
			infos[link.key] = { link = link, chain = chain, catId = catId }
		end
	end
end

local function scoops(n: number): string
	return if n == 1 then "1 scoop" else `{n} scoops`
end

local function percent(bonus: number): string
	return `+{math.floor((bonus - 1) * 100 + 0.5)}%`
end

-- What a track's level changes, from the stats before and after it. Litres per trip include the
-- worn backpack; scoop counts stay the tool's.
local function effectText(id: string, now: Ladder.Stats, after: Ladder.Stats): string
	if id == "tool" then
		local gear = Hud.items()
		local tripNow, tripAfter = Items.withGear(Config, gear, now).capacity, Items.withGear(Config, gear, after).capacity
		return `{short(tripAfter)} L per trip, {scoops(after.sweeps)} to fill (now {short(tripNow)} L)`
	elseif id == "pickup" then
		return `Fill your tool in {scoops(after.sweeps)} (now {scoops(now.sweeps)})`
	elseif id == "hold" then
		return "Hold the button to keep scooping"
	elseif id == "quick" then
		return `{after.actSeconds}s per scoop (now {now.actSeconds}s)`
	elseif id == "walk" then
		return `Walk speed {after.walkSpeed} (now {now.walkSpeed})`
	end
	return `{percent(after.coinBonus)} coins per litre (now {percent(now.coinBonus)})`
end

local function fillNow(): number
	local fill = ReplicatedStorage:GetAttribute("Fill")
	return if type(fill) == "number" then fill else 0
end

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

-- What an item does now and after an upgrade `level` (nil: what it does now, or when bought): a
-- backpack's litres, a gadget's, vehicle's, building's or staff's stats.
local function itemEffect(item, level, owned: boolean): string
	local function nowStat(name: string): number
		if not owned then
			return item[name]
		end
		return if item.kind == "building" then Items.buildingStat(Hud.buildings(), item, name) else Items.stat(Hud.items(), item, name)
	end
	if item.kind == "gadget" or KIND_EFFECTS[item.kind] then
		local effect = KIND_EFFECTS[item.kind] or GADGET_EFFECTS[item.id]
		assert(effect, `Honeycomb has no effect text for {item.id}`)
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

-- Where one of the team's staff works (the server's Staff attribute: an area id, 0 for nowhere), or
-- nil until the server has published it.
local function postOf(id: string): number?
	for _, entry in StaffRules.decode(ReplicatedStorage:GetAttribute("Staff")) do
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

-- The team's state as shared/Honeycomb reads it.
local function readView(): Comb.View
	local snap = Hud.snapshot()
	local levels = Hud.levels(0) :: { [string]: number }
	local items = {}
	for _, item in Config.items do
		local bought = if item.kind == "building" then snap.buildings[item.id] elseif Items.owned(snap.items, item.id) then snap.items.itemLevels[item.id] else nil
		items[item.id] = if bought then bought + 1 else 0
	end
	return {
		levels = levels,
		items = items,
		openAreas = Areas.open(Hud.gatesOpen()),
		wallet = Hud.wallet(),
		-- Only what TAB sells has a price: a track level that changes something (Ladder.helps), an
		-- owned item's upgrade. An item's first link is bought at its stand or built on a plot.
		price = function(link: Comb.Link): number?
			if link.kind == "track" then
				local track = Config.track(link.id :: string) :: Config.Track
				if not Ladder.helps(Config, levels, track.id) then
					return nil
				end
				return Items.price(Config, track.levels[link.level :: number].cost, snap.teamSize)
			end
			local item = Items.get(Config, link.id)
			local level = if (link.level :: number) > 1 then item.levels[(link.level :: number) - 1] else nil
			return if level then Items.price(Config, level.cost, snap.teamSize) else nil
		end,
		reachable = function(id: string): boolean
			return Items.reachable(Config, snap.items, { Items.get(Config, id).area })[1] ~= nil
		end,
	}
end

-- A link's listed price (Config), before the team's scale.
local function listedCost(link: Comb.Link): number
	if link.kind == "track" then
		return (Config.track(link.id :: string) :: Config.Track).levels[link.level :: number].cost
	end
	local item = Items.get(Config, link.id)
	return if link.level == 1 then item.price else item.levels[(link.level :: number) - 1].cost
end

-- An item's first link the team can get now, just not here: at its stand or on a plot.
local function elsewhere(link: Comb.Link, st: Comb.HexState, view: Comb.View): boolean
	return st.state == "locked" and link.kind == "item" and link.level == 1 and view.openAreas[link.areaId] == true and view.reachable(link.id :: string)
end

-- Whether water flows past a hex in `state` into the next one.
local function lit(state: Comb.StateName): boolean
	return state == "owned" or state == "max" or state == "gateOpen"
end

-- The template (a Model or a backpack's Accessory) and image a link shows; nil, nil for none.
local function artOf(link: Comb.Link): (Instance?, string?)
	if link.kind == "gate" then
		return nil, nil
	elseif link.kind == "track" and link.id ~= "tool" then
		return nil, images[ICONS[link.id :: string]]
	end
	local template = if link.kind == "track"
		then ToolModels.find((Config.track("tool") :: Config.Track).levels[link.level :: number].model :: string)
		else ToolModels.itemModel(Items.get(Config, link.id))
	return template, if template then nil else images.unknown -- nil until replicated
end

-- A category hex's art: the current tool, the boosts' pip, else its first item's model.
local function categoryArt(catId: string, stats: Ladder.Stats): (Instance?, string?)
	if catId == "tools" then
		local template = ToolModels.find(stats.toolModel)
		return template, if template then nil else images.unknown
	elseif catId == "boosts" then
		return nil, images.pipFull
	end
	for _, link in layout.categories[catId].chains[1].links do
		if link.kind ~= "gate" then
			return artOf(link)
		end
	end
	return nil, images.unknown
end

-- A hex's (or the detail's) art slot: `template` in its ViewportFrame (copied once per template),
-- else `image` in its Icon, else nothing.
local function showArt(record: { art: Instance? }, view: ViewportFrame, icon: ImageLabel, template: Instance?, image: string?)
	if template and record.art ~= template then
		ToolModels.showIn(view, template :: any)
		record.art = template
	end
	set(view, "Visible", template ~= nil)
	set(icon, "Visible", template == nil and image ~= nil)
	if image then
		set(icon, "Image", image)
	end
end

-- Category hexes take the category's colour (Tool orange, Boosts teal, items deep water).
local function categoryColor(catId: string): Color3
	return if catId == "tools" then colors.toolTag elseif catId == "boosts" then colors.speedTag else colors.deepWater
end

local function scaled(size: UDim2, k: number): UDim2
	return UDim2.new(size.X.Scale * k, size.X.Offset * k, size.Y.Scale * k, size.Y.Offset * k)
end

type Hex = {
	button: ImageButton,
	press: UIScale,
	bottom: ImageLabel,
	water: Frame,
	fill: ImageLabel,
	outline: ImageLabel,
	select: GuiObject,
	view: ViewportFrame,
	icon: ImageLabel,
	name: TextLabel,
	priceRow: GuiObject,
	coin: ImageLabel,
	price: TextLabel,
	lock: GuiObject,
	check: GuiObject,
	badge: GuiObject,
	count: TextLabel,
	waterWidth: UDim,
	checkSize: UDim2,
	badgeSize: UDim2,
	priceSize: number,
	q: number,
	r: number,
	x: number, -- offset from the canvas centre, before zoom
	y: number,
	catId: string?,
	slots: { Hex }?, -- a chain's slot hexes, this one among them
	slot: number?,
	key: string?, -- the link shown now
	art: Instance?,
	hover: boolean,
	down: boolean,
	ease: number, -- hover / press / breathing scale, catching up
	base: number, -- the state's own scale (a small open gate)
	breathe: boolean,
	animKind: string?, -- "enter", "pop" or "wake"
	animAt: number,
	holdUntil: number, -- an animation owns the hex's look until then
	fade: boolean, -- the next paint fades its colours in
	badgeCount: number,
	share: number, -- a category hex's owned share as last painted (-1: never)
}

type Bridge = { frame: Frame, fill: Frame, fillHeight: UDim }

type ViewData = {
	id: string,
	hexes: { Hex },
	bridges: { Bridge },
	byKey: { [string]: Hex },
	into: { [Hex]: Bridge }, -- the bridge leading into each chain slot
	slots: { { Hex } }, -- per chain
	centre: Hex?, -- main: the tool
	ring: { [string]: Hex }, -- main: the category hexes
	catHex: Hex?, -- a category view's own hex
	w: number,
	h: number,
	zoom: number,
	pans: boolean,
}

-- The hex parts a copy of Templates.Hex has (Hud.find: the template must keep these names).
local function hexParts(button: ImageButton)
	return {
		press = Hud.find(button, "Press"),
		bottom = Hud.find(button, "Bottom"),
		water = Hud.find(button, "Water"),
		fill = Hud.find(button, "Water.Fill"),
		outline = Hud.find(button, "Outline"),
		select = Hud.find(button, "Select"),
		view = Hud.find(button, "View"),
		icon = Hud.find(button, "Icon"),
		name = Hud.find(button, "Name"), -- not button.Name: the child's name clashes with the property
		priceRow = Hud.find(button, "PriceRow"),
		coin = Hud.find(button, "PriceRow.Coin"),
		price = Hud.find(button, "PriceRow.Price"),
		lock = Hud.find(button, "Lock"),
		check = Hud.find(button, "Check"),
		badge = Hud.find(button, "Badge"),
		count = Hud.find(button, "Badge.Count"),
	}
end

local function setWater(hex: Hex, level: number)
	set(hex.water, "Size", UDim2.new(hex.waterWidth, UDim.new(level, 0)))
	set(hex.water, "Visible", level > 0)
end

local function setBridge(bridge: Bridge, level: number)
	set(bridge.fill, "Size", UDim2.new(UDim.new(level, 0), bridge.fillHeight))
	set(bridge.fill, "Visible", level > 0)
end

-- A hex's body: colour (its rim a darker shade), transparency and outline; `fade` tweens the colours.
local function paintBody(hex: Hex, base: Color3, dim: number, outline: Color3, fade: boolean)
	local rim = base:Lerp(colors.outline, RIM_SHADE)
	if fade then
		TweenService:Create(hex.button, FADE, { ImageColor3 = base, ImageTransparency = dim }):Play()
		TweenService:Create(hex.bottom, FADE, { ImageColor3 = rim, ImageTransparency = dim }):Play()
	else
		set(hex.button, "ImageColor3", base)
		set(hex.button, "ImageTransparency", dim)
		set(hex.bottom, "ImageColor3", rim)
		set(hex.bottom, "ImageTransparency", dim)
	end
	set(hex.outline, "ImageColor3", outline)
	set(hex.outline, "ImageTransparency", dim)
	set(hex.view, "ImageTransparency", dim)
	set(hex.icon, "ImageTransparency", dim)
end

local function paintName(hex: Hex, text: string?, dim: number)
	set(hex.name, "Visible", text ~= nil)
	if text then
		set(hex.name, "Text", text)
		set(hex.name, "TextTransparency", dim)
	end
end

-- The price row: `text` (nil hides it), the coin, its colour, small for a later level.
local function paintPrice(hex: Hex, text: string?, coin: boolean, color: Color3, small: boolean, dim: number)
	set(hex.priceRow, "Visible", text ~= nil)
	if not text then
		return
	end
	set(hex.price, "Text", text)
	set(hex.price, "TextColor3", color)
	set(hex.price, "TextTransparency", dim)
	set(hex.price, "TextSize", if small then math.round(hex.priceSize * SMALL_PRICE) else hex.priceSize)
	set(hex.coin, "Visible", coin)
	set(hex.coin, "ImageTransparency", dim)
end

-- How closed `area`'s gate opens, for its hex: the fill it needs, or its price once on sale.
local function gateText(area): (string, boolean)
	if fillNow() < area.gate.fill then
		return `fill {Format.percent(area.gate.fill)}`, false
	end
	return Hud.money(Hud.price(area.gate.price)), true
end

-- A link hex in its state (shared/Honeycomb.states).
local function paintLink(hex: Hex, link: Comb.Link, st: Comb.HexState, catId: string, view: Comb.View, fade: boolean)
	local state = st.state
	local base, dim, outline = categoryColor(catId), 0, colors.outline
	local water, waterColor, check, lock, art = 0, colors.shallowWater, false, false, true
	local name, priceText, coin, priceColor, small = nil, nil, false, colors.foam, false
	hex.base = 1
	if state == "owned" then
		water, check = 1, true
	elseif state == "max" then
		water, name, outline = 1, "MAX", colors.toolTag
	elseif state == "buy" then
		priceText, coin = Hud.money(st.price :: number), true
	elseif state == "short" then
		base, water, waterColor = colors.locked, st.progress :: number, colors.shallowWater:Lerp(colors.locked, 0.5)
		priceText, coin, priceColor = Hud.money(st.price :: number), true, colors.buyCoral
	elseif state == "future" or elsewhere(link, st, view) then
		dim, small = DIM, true
		priceText, coin = Hud.money(Hud.price(listedCost(link))), true
	elseif link.kind == "gate" then
		local area = Areas.byId(Config, link.areaId)
		base, art, name = colors.locked, false, area.name
		if state == "gateOpen" then
			dim, hex.base = DIM, CUE.gateScale
		else
			lock = true
			priceText, coin = gateText(area)
		end
	else
		base, art, lock = colors.locked, false, true
	end
	paintBody(hex, base, dim, outline, fade)
	set(hex.fill, "ImageColor3", waterColor)
	setWater(hex, water)
	set(hex.check, "Visible", check)
	set(hex.lock, "Visible", lock)
	paintName(hex, name, dim)
	paintPrice(hex, priceText, coin, priceColor, small, dim)
	local template, image = nil, nil
	if art then
		template, image = artOf(link)
	end
	showArt(hex, hex.view, hex.icon, template, image)
	hex.breathe = state == "buy"
end

-- The red ball: pops in when something becomes buyable, shrinks away at 0.
local function paintBadge(hex: Hex, count: number)
	local was = hex.badgeCount
	hex.badgeCount = count
	set(hex.count, "Text", tostring(count))
	local info = TweenInfo.new(CUE.badgeSeconds, Enum.EasingStyle.Back, if count > 0 then Enum.EasingDirection.Out else Enum.EasingDirection.In)
	if was < 0 then
		set(hex.badge, "Visible", count > 0)
	elseif count > 0 and was == 0 then
		hex.badge.Size = UDim2.new()
		hex.badge.Visible = true
		TweenService:Create(hex.badge, info, { Size = hex.badgeSize }):Play()
	elseif count == 0 and was > 0 then
		local shrink = TweenService:Create(hex.badge, info, { Size = UDim2.new() })
		shrink.Completed:Once(function()
			if hex.badgeCount == 0 then
				hex.badge.Visible = false
			end
			hex.badge.Size = hex.badgeSize
		end)
		shrink:Play()
	end
end

-- A category hex: its name, art, badge, and how much of it is owned (water and "3/12").
local function paintCategory(hex: Hex, catId: string, view: Comb.View, count: number, stats: Ladder.Stats)
	local owned, total = Comb.ownedShare(layout, catId, view)
	local share = if total > 0 then owned / total else 0
	paintBody(hex, categoryColor(catId), 0, colors.outline, false)
	set(hex.fill, "ImageColor3", colors.shallowWater)
	if hex.share >= 0 and share > hex.share then -- a buy: the water rises
		hex.water.Visible = true
		TweenService:Create(hex.water, TweenInfo.new(CUE.waterSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(hex.waterWidth, UDim.new(share, 0)) }):Play()
	elseif share ~= hex.share then
		setWater(hex, share)
	end
	hex.share = share
	set(hex.check, "Visible", false)
	set(hex.lock, "Visible", false)
	paintName(hex, CATEGORY_NAMES[catId]:upper(), 0)
	paintPrice(hex, `{owned}/{total}`, false, colors.foam, true, 0)
	showArt(hex, hex.view, hex.icon, categoryArt(catId, stats))
	paintBadge(hex, count)
	hex.breathe = false
end

-- The main view's centre: the tool in hand.
local function paintCentre(hex: Hex, stats: Ladder.Stats)
	paintBody(hex, colors.toolTag, 0, colors.outline, false)
	setWater(hex, 0)
	set(hex.check, "Visible", false)
	set(hex.lock, "Visible", false)
	paintName(hex, stats.toolName, 0)
	paintPrice(hex, nil, false, colors.foam, false, 0)
	local template = ToolModels.find(stats.toolModel)
	showArt(hex, hex.view, hex.icon, template, if template then nil else images.unknown)
end

-- A spine hex: a quiet connector between the category and its chains.
local function paintSpine(hex: Hex)
	paintBody(hex, colors.deepSea, 0, colors.outline, false)
	setWater(hex, 0)
	for _, part in { hex.check, hex.lock, hex.name, hex.priceRow, hex.view, hex.icon, hex.badge } do
		set(part, "Visible", false)
	end
	hex.button.Active = false
	hex.button.Selectable = false
end

-- The scale an animation adds at `now` (1 when none plays).
local function animScale(hex: Hex, now: number): number
	local kind = hex.animKind
	if not kind then
		return 1
	end
	if kind == "enter" then
		local t = (now - hex.animAt) / CUE.enterSeconds
		if t >= 1 then
			hex.animKind = nil
			return 1
		end
		return CUE.enterFrom + (1 - CUE.enterFrom) * Ease.backOut(t, BACK_OVERSHOOT)
	elseif kind == "pop" then
		local t = (now - hex.animAt) / CUE.popSeconds
		if t >= 1 then
			hex.animKind = nil
			return 1
		end
		return CUE.popFrom + (1 - CUE.popFrom) * Ease.backOut(t, BACK_OVERSHOOT)
	end
	-- wake: up past full size, then settle
	local t = (now - hex.animAt) / CUE.wakeSeconds
	if t >= 1 then
		hex.animKind = nil
		return 1
	elseif t < 0.6 then
		local u = t / 0.6
		return CUE.wakeFrom + (CUE.wakeOvershoot - CUE.wakeFrom) * (1 - (1 - u) * (1 - u))
	end
	local u = (t - 0.6) / 0.4
	return CUE.wakeOvershoot + (1 - CUE.wakeOvershoot) * (1 - (1 - u) * (1 - u))
end

-- The next link after `key` in its chain that isn't a gate, or nil.
local function nextLinkKey(key: string): string?
	local info = infos[key]
	local after = false
	for _, link in info.chain.links do
		if after and link.kind ~= "gate" then
			return link.key
		end
		after = after or link.key == key
	end
	return nil
end

-- The first link of a category that isn't a gate.
local function firstLinkKey(catId: string): string
	for _, link in layout.categories[catId].chains[1].links do
		if link.kind ~= "gate" then
			return link.key
		end
	end
	error(`honeycomb: {catId}'s first chain has only gates`)
end

-- Whether buying `link` gets something new: a track's first level or a new tool model.
local function firstBuy(link: Comb.Link): boolean
	if link.kind ~= "track" then
		return false
	elseif link.level == 1 then
		return true
	end
	local levels = (Config.track(link.id :: string) :: Config.Track).levels
	return link.id == "tool" and levels[link.level :: number].model ~= levels[(link.level :: number) - 1].model
end

function Honeycomb.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Buy") :: RemoteEvent
	local staffRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Staff") :: RemoteEvent
	local root = Hud.find(gui, "Honeycomb") :: Frame
	local fit = Hud.find(root, "Scale") :: UIScale
	local closeButton = Hud.find(root, "CloseButton")
	local backButton = Hud.find(root, "BackButton")
	local breadcrumb = Hud.find(root, "Breadcrumb")
	local walletAmount = Hud.find(root, "Wallet.Amount")
	local board = Hud.find(root, "Board") :: Frame
	local canvas = Hud.find(board, "Canvas") :: Frame
	local zoomScale = Hud.find(canvas, "Zoom") :: UIScale
	local detail = Hud.find(root, "Detail")
	local detailArt = { art = nil :: Instance? }
	local detailView = Hud.find(detail, "View")
	local detailIcon = Hud.find(detail, "Icon")
	local itemName = Hud.find(detail, "ItemName")
	local levelText = Hud.find(detail, "LevelText")
	local effect = Hud.find(detail, "Effect")
	local needText = Hud.find(detail, "NeedText") :: TextLabel
	local buyButton = Hud.find(detail, "BuyButton")
	local buyPress = Hud.find(buyButton, "Press") :: UIScale
	local buyLabel = Hud.find(buyButton, "Label")
	local buyPriceRow = Hud.find(buyButton, "PriceRow")
	local buyPrice = Hud.find(buyPriceRow, "Price")
	local assignButton = Hud.find(detail, "AssignButton")
	local assignLabel = Hud.find(assignButton, "Label")
	local upgrades = Hud.find(gui, "UpgradesButton")
	local upgradesBadge = Hud.find(upgrades, "Badge")
	local upgradesCount = upgradesBadge:FindFirstChild("Count") -- optional: the total on the ball
	local upgradesPress = Hud.find(upgrades, "Press") :: UIScale
	local upgradesKey = Hud.find(upgrades, "Key")
	local upgradesKeyText = Hud.find(upgradesKey, "Text")
	local hexTemplate = Hud.find(gui, "Templates.Hex") :: ImageButton
	hexParts(hexTemplate) -- fail at start, not on the first open
	local bridgeTemplate = Hud.find(gui, "Templates.Bridge") :: Frame
	Hud.find(bridgeTemplate, "Fill")

	-- The window's own size (offset, its design size) and the board's inside it, to fit views.
	local design = root.Size
	assert(design.X.Scale == 0 and design.Y.Scale == 0, "Hud.Honeycomb needs an offset Size (its design size)")
	assert(board.Parent == root, "Hud.Honeycomb.Board must sit directly in Hud.Honeycomb")
	local boardSize = Vector2.new(
		board.Size.X.Scale * design.X.Offset + board.Size.X.Offset,
		board.Size.Y.Scale * design.Y.Offset + board.Size.Y.Offset
	)
	local hexSize = hexTemplate.Size.X.Offset / 2 -- flat-top: centre to corner
	local hexHeight = hexTemplate.Size.Y.Offset
	assert(hexSize > 0 and hexHeight > 0, "Hud.Templates.Hex needs an offset Size")
	local spaced = hexSize * SPACING
	local canvasBase = canvas.Position
	local needSize = needText.Size

	-- Tab would also toggle Roblox's player list; the game has its own Board, so hide that list.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

	local open = false
	local fitScale = 1
	local window = Window.new(root, fit)
	local views: { [string]: ViewData } = {}
	local viewId = "main"
	local selectedKey: string? = nil
	local pickId: string? = nil -- the id the next refresh selects (Honeycomb.show)
	local states: { [string]: Comb.HexState } = {} -- the shown category's (main: tools')
	local lastOwned: { [string]: boolean }? = nil -- per link key, at the last refresh of this view
	local animToken = 0 -- bumped on view changes and closing: running animations stop
	local dirty = true
	local nextRefresh = 0
	local panX, panY = 0, 0
	local guardUntil = 0
	local pending: { key: string, id: string, have: number, at: number, cost: number }? = nil

	local function inRun(): boolean
		return ReplicatedStorage:GetAttribute("Phase") == "playing"
	end

	ReplicatedStorage.AttributeChanged:Connect(function()
		dirty = true
	end)

	local function applyPan()
		set(canvas, "Position", UDim2.new(canvasBase.X.Scale, canvasBase.X.Offset + panX, canvasBase.Y.Scale, canvasBase.Y.Offset + panY))
	end

	local function clampPan(v: ViewData)
		panX, panY = Comb.clampPan(panX, panY, v.w * v.zoom, v.h * v.zoom, boardSize.X, boardSize.Y)
		applyPan()
	end

	-- Zoom to fit the board, never under CUE.minHexPixels a hex on screen (then the board pans).
	local function fitView(v: ViewData)
		v.zoom, v.pans = Comb.zoom(v.w, v.h, boardSize.X, boardSize.Y, hexHeight * fitScale, CUE.minHexPixels, CUE.maxZoom)
		clampPan(v)
	end

	-- A panning view keeps `hex` on the board.
	local function panTo(v: ViewData, hex: Hex?)
		if hex and v.pans then
			panX, panY = -hex.x * v.zoom, -hex.y * v.zoom
			clampPan(v)
		end
	end

	local function refit()
		local size = gui.AbsoluteSize -- the Hud's area inside the top bar and safe insets
		fitScale = math.min(size.X / design.X.Offset, size.Y / design.Y.Offset, 1)
		if open then
			fit.Scale = fitScale
		end
		local v = views[viewId]
		if v then
			fitView(v)
			zoomScale.Scale = v.zoom
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()

	local function newHex(v: ViewData, q: number, r: number, cx: number, cy: number): Hex
		local button = hexTemplate:Clone()
		local hex = hexParts(button) :: any
		hex.button = button
		hex.waterWidth = hex.water.Size.X
		hex.checkSize = hex.check.Size
		hex.badgeSize = hex.badge.Size
		hex.priceSize = hex.price.TextSize
		local x, y = Comb.toPixel(q, r, spaced)
		hex.q, hex.r, hex.x, hex.y = q, r, x - cx, y - cy
		hex.hover, hex.down, hex.breathe, hex.fade = false, false, false, false
		hex.ease, hex.base, hex.animAt, hex.holdUntil, hex.badgeCount, hex.share = 1, 1, 0, 0, -1, -1
		hex.select.Visible = false
		hex.badge.Visible = false
		button.AutoButtonColor = false -- hover and press scale it instead
		button.Position = UDim2.fromOffset(hex.x, hex.y)
		button.Visible = false
		button.Parent = canvas
		table.insert(v.hexes, hex)
		return hex
	end

	local function newBridge(v: ViewData, a: Comb.Pos, b: Comb.Pos, cx: number, cy: number): Bridge
		local frame = bridgeTemplate:Clone()
		local ax, ay = Comb.toPixel(a.q, a.r, spaced)
		local bx, by = Comb.toPixel(b.q, b.r, spaced)
		frame.Position = UDim2.fromOffset((ax + bx) / 2 - cx, (ay + by) / 2 - cy)
		frame.Rotation = math.deg(math.atan2(by - ay, bx - ax)) -- its Fill grows from a toward b
		frame.ZIndex = hexTemplate.ZIndex - 1 -- under the hexes it joins
		frame.BackgroundColor3 = colors.outline
		frame.Visible = false
		frame.Parent = canvas
		local fill = Hud.find(frame, "Fill") :: Frame
		fill.BackgroundColor3 = colors.shallowWater
		local bridge = { frame = frame, fill = fill, fillHeight = fill.Size.Y }
		table.insert(v.bridges, bridge)
		return bridge
	end

	local selectKey: (string?) -> ()
	local showView: (string, string?) -> ()
	local setOpen: (boolean, string?) -> ()

	-- Hover (mouse or gamepad selection) grows a hex and shows its ring; press shrinks it.
	local function hook(hex: Hex, onClick: () -> ())
		local button = hex.button
		button.MouseEnter:Connect(function()
			hex.hover = true
		end)
		button.MouseLeave:Connect(function()
			hex.hover, hex.down = false, false
		end)
		button.SelectionGained:Connect(function()
			hex.hover = true
		end)
		button.SelectionLost:Connect(function()
			hex.hover = false
		end)
		button.MouseButton1Down:Connect(function()
			hex.down = true
		end)
		button.MouseButton1Up:Connect(function()
			hex.down = false
		end)
		button.Activated:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				hex.hover = false -- a finger leaves no hover behind
			end
			onClick()
		end)
	end

	local function buildMain(): ViewData
		local v: ViewData = { id = "main", hexes = {}, bridges = {}, byKey = {}, into = {}, slots = {}, ring = {}, w = 0, h = 0, zoom = 1, pans = false }
		local positions: { Comb.Pos } = { { q = 0, r = 0 } }
		for _, hex in layout.main.ring do
			table.insert(positions, { q = hex.q, r = hex.r })
		end
		local cx, cy, w, h = Comb.bounds(positions, spaced)
		v.w, v.h = w, h
		local centre = newHex(v, 0, 0, cx, cy)
		hook(centre, function()
			showView("tools")
		end)
		v.centre = centre
		for _, at in layout.main.ring do
			local hex = newHex(v, at.q, at.r, cx, cy)
			hex.catId = at.id
			hook(hex, function()
				showView(at.id)
			end)
			v.ring[at.id] = hex
		end
		return v
	end

	local function buildCategory(catId: string): ViewData
		local cat = layout.categories[catId]
		local v: ViewData = { id = catId, hexes = {}, bridges = {}, byKey = {}, into = {}, slots = {}, ring = {}, w = 0, h = 0, zoom = 1, pans = false }
		local positions: { Comb.Pos } = { cat.hex }
		table.move(cat.spine, 1, #cat.spine, 2, positions)
		for _, chain in cat.chains do
			table.move(chain.slots, 1, #chain.slots, #positions + 1, positions)
		end
		local cx, cy, w, h = Comb.bounds(positions, spaced)
		v.w, v.h = w, h
		for _, bridge in cat.bridges do
			setBridge(newBridge(v, bridge[1], bridge[2], cx, cy), 1) -- the spine is always full
		end
		local catHex = newHex(v, cat.hex.q, cat.hex.r, cx, cy)
		catHex.catId = catId
		v.catHex = catHex
		for _, pos in cat.spine do
			paintSpine(newHex(v, pos.q, pos.r, cx, cy))
		end
		for ci, chain in cat.chains do
			local slots = {}
			v.slots[ci] = slots
			for i, pos in chain.slots do
				local hex = newHex(v, pos.q, pos.r, cx, cy)
				hex.slots, hex.slot = slots, i
				slots[i] = hex
				hook(hex, function()
					selectKey(hex.key)
				end)
				local bridge = chain.bridges[i]
				v.into[hex] = newBridge(v, bridge[1], bridge[2], cx, cy)
			end
		end
		return v
	end

	local function setVisible(v: ViewData, visible: boolean)
		for _, hex in v.hexes do
			hex.button.Visible = visible
		end
		for _, bridge in v.bridges do
			bridge.frame.Visible = visible
		end
	end

	-- The landing's hex animation (shop.md: the hex fills, the bridge fills, the next hex wakes up):
	-- holds the hex and the next one, and returns what starts it (Purchase.landed runs it as the
	-- coins arrive). `own`: the next hex becomes selected.
	local function celebrate(v: ViewData, hex: Hex, own: boolean): () -> ()
		local token, key = animToken, hex.key :: string
		local slots = hex.slots :: { Hex }
		local nextHex = slots[(hex.slot :: number) + 1]
		local bridge = nextHex and v.into[nextHex]
		local final = states[key].state
		hex.holdUntil = math.huge
		setWater(hex, 0)
		set(hex.check, "Visible", false)
		local function alive(): boolean
			return token == animToken and hex.key == key
		end
		local function release()
			hex.holdUntil = 0
			if nextHex then
				nextHex.holdUntil = 0
			end
			dirty = true
		end
		return function()
			if not alive() then
				release()
				return
			end
			hex.water.Visible = true
			local full = UDim2.new(hex.waterWidth, UDim.new(1, 0))
			TweenService:Create(hex.water, TweenInfo.new(CUE.waterSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = full }):Play()
			task.delay(CUE.waterSeconds, function()
				if not alive() then
					release()
					return
				end
				hex.animKind, hex.animAt = "pop", os.clock()
				hex.holdUntil = 0 -- full now: the next paint matches; the check's stamp is Size only
				dirty = true
				if final == "owned" then
					local check = hex.check
					check.Size = UDim2.new()
					check.Visible = true
					local up = TweenService:Create(check, TweenInfo.new(CUE.checkSeconds * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = scaled(hex.checkSize, CUE.checkOvershoot) })
					up.Completed:Once(function()
						TweenService:Create(check, TweenInfo.new(CUE.checkSeconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Size = hex.checkSize }):Play()
					end)
					up:Play()
				end
				if not (nextHex and bridge) then
					return
				end
				setBridge(bridge, 0)
				bridge.fill.Visible = true
				TweenService:Create(bridge.fill, TweenInfo.new(CUE.bridgeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(UDim.new(1, 0), bridge.fillHeight) }):Play()
				task.delay(CUE.bridgeSeconds, function()
					if token ~= animToken then
						release()
						return
					end
					nextHex.fade = true
					nextHex.animKind, nextHex.animAt = "wake", os.clock()
					nextHex.holdUntil = 0
					dirty, nextRefresh = true, 0
					if own or selectedKey == key then
						selectKey(nextLinkKey(key))
					end
				end)
			end)
		end
	end

	-- A button springs when what it sent lands: down, past full size, back.
	local function bounce(scale: UIScale)
		scale.Scale = CUE.bounceLow
		local up = TweenService:Create(scale, TweenInfo.new(CUE.bounceSeconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = CUE.bounceHigh })
		up.Completed:Once(function(playback)
			if playback == Enum.PlaybackState.Completed then
				TweenService:Create(scale, TweenInfo.new(CUE.bounceSeconds * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Scale = 1 }):Play()
			end
		end)
		up:Play()
	end

	-- The detail's words for the selected link: why it can't be bought here (nil when it can).
	local function reasonOf(link: Comb.Link, st: Comb.HexState, view: Comb.View): string?
		local state = st.state
		local area = Areas.byId(Config, link.areaId)
		if state == "short" then
			return `Need {Hud.money(math.ceil((st.price :: number) - view.wallet))} more`
		elseif elsewhere(link, st, view) then
			local item = Items.get(Config, link.id)
			if item.kind == "building" then
				return "Build one on a town plot"
			end
			return `{if item.kind == "staff" then "Hire" else "Buy"} it at the {Format.standName(Config, item.stand, area)}`
		elseif state == "gateClosed" or (state == "locked" and not view.openAreas[link.areaId]) then
			return `Opens with {area.name}: {Format.gateHint(area, fillNow(), Hud.price)}`
		elseif state == "locked" and link.kind == "item" and not view.reachable(link.id :: string) then
			return `Needs the {Items.get(Config, area.needs).name}`
		elseif state == "locked" and link.id == "pickup" then
			return "Your tool already fills in one scoop"
		elseif state == "future" then
			return "Buy the level before it first"
		end
		return nil
	end

	-- The Buy button's word when it can't buy.
	local function wordOf(link: Comb.Link, st: Comb.HexState, view: Comb.View): string
		local state = st.state
		if state == "owned" then
			return "OWNED"
		elseif state == "max" then
			return "MAX"
		elseif state == "gateOpen" then
			return "OPEN"
		elseif elsewhere(link, st, view) then
			return if Items.get(Config, link.id).kind == "building" then "ON A PLOT" else "AT STAND"
		end
		return "LOCKED"
	end

	local function nameOf(link: Comb.Link): string
		if link.kind == "gate" then
			return `{Areas.byId(Config, link.areaId).name} gate`
		elseif link.kind == "track" then
			local track = Config.track(link.id :: string) :: Config.Track
			return Format.levelName(track, link.level :: number, track.levels[link.level :: number])
		end
		return Items.get(Config, link.id).name
	end

	-- One line: what the link's level does (a track: against the level before it).
	local function effectOf(link: Comb.Link, view: Comb.View): string
		if link.kind == "gate" then
			return `Opens {Areas.byId(Config, link.areaId).name} and its upgrades`
		elseif link.kind == "track" then
			local before, after = table.clone(view.levels), table.clone(view.levels)
			before[link.id :: string], after[link.id :: string] = (link.level :: number) - 1, link.level :: number
			return effectText(link.id :: string, Ladder.stats(Config, before), Ladder.stats(Config, after))
		end
		local item = Items.get(Config, link.id)
		local level = if (link.level :: number) > 1 then item.levels[(link.level :: number) - 1] else nil
		return itemEffect(item, level, (view.items[item.id] or 0) > 0)
	end

	local function paintDetail(view: Comb.View)
		local info = if selectedKey then infos[selectedKey] else nil
		local st = if info then states[info.link.key] else nil
		set(detail, "Visible", st ~= nil)
		if not (info and st) then
			return
		end
		local link = info.link
		local state = st.state
		local template, image = nil, images.lock
		if link.kind ~= "gate" then
			template, image = artOf(link)
		end
		showArt(detailArt, detailView, detailIcon, template, image)
		set(itemName, "Text", nameOf(link))
		set(levelText, "Text", if link.kind == "gate" then "Gate" else Comb.levelText(link, state))
		set(effect, "Text", effectOf(link, view))
		local need = reasonOf(link, st, view)
		set(needText, "Visible", need ~= nil)
		if need then
			set(needText, "Text", need)
		end
		local priced = state == "buy" or state == "short"
		set(buyLabel, "Text", if priced then "BUY" else wordOf(link, st, view))
		set(buyPriceRow, "Visible", priced)
		if priced then
			set(buyPrice, "Text", Hud.money(st.price :: number))
			set(buyPrice, "TextColor3", if state == "short" then colors.buyCoral else colors.foam)
		end
		set(buyButton, "ImageColor3", if state == "buy" then colors.buyCoral else colors.locked)
		local item = if link.kind == "item" then Items.get(Config, link.id) else nil
		local hired = item ~= nil and item.kind == "staff" and (view.items[item.id] or 0) > 0
		set(assignButton, "Visible", hired)
		if hired then
			set(assignLabel, "Text", assignText(item, postOf(item.id)))
		end
	end

	-- Re-reads the team's state: badges always; while open the shown view, the landings since the
	-- last refresh and the detail.
	local function refresh()
		local now = os.clock()
		dirty = false
		local view = readView()
		local badges = Comb.badges(layout, view)
		set(upgradesBadge, "Visible", badges.total > 0)
		if upgradesCount and upgradesCount:IsA("TextLabel") then
			set(upgradesCount, "Text", tostring(badges.total))
		end

		-- Your own buy landed (its bought count went up)?
		local own = nil
		if pending then
			local info = infos[pending.key]
			if Comb.bought(info.link, view) > pending.have then
				own = pending
				pending = nil
				guardUntil = now + BUY_GUARD
			elseif now - pending.at >= PENDING_SECONDS then
				pending = nil
			end
		end
		local ownInfo = if own then infos[own.key] else nil
		local ownPitch = if ownInfo then Cues.stingPitch(Comb.ownedCount(ownInfo.chain, view)) else 1
		if not open then
			if own and ownInfo then -- closed before it landed: the sound only
				Purchase.landed(nil, own.cost, ownPitch, firstBuy(ownInfo.link), function() end)
			end
			return
		end

		local v = views[viewId]
		local stats = Ladder.stats(Config, view.levels)
		local catId = if viewId == "main" then "tools" else viewId
		states = Comb.states(layout, catId, view)
		if not selectedKey then
			selectedKey = Comb.pick(layout, catId, states, pickId) or firstLinkKey(catId)
			pickId = nil
		end

		if viewId == "main" then
			paintCentre(v.centre :: Hex, stats)
			for id, hex in v.ring do
				paintCategory(hex, id, view, badges[id], stats)
			end
			if own and ownInfo then
				local centre = v.centre :: Hex
				bounce(buyPress)
				centre.animKind, centre.animAt = "pop", now
				Purchase.landed(centre.button, own.cost, ownPitch, firstBuy(ownInfo.link), function() end)
			end
			paintDetail(view)
			return
		end

		paintCategory(v.catHex :: Hex, catId, view, badges[catId], stats)
		-- Links owned now that weren't at the last refresh: one per chain plays its landing.
		local fresh: { [Comb.Chain]: string | false } = {}
		if lastOwned then
			for key, st in states do
				if lit(st.state) and st.state ~= "gateOpen" and not lastOwned[key] then
					local chain = infos[key].chain
					fresh[chain] = if fresh[chain] == nil then key else false
				end
			end
		end
		lastOwned = lastOwned or {}
		for key, st in states do
			(lastOwned :: any)[key] = lit(st.state) and st.state ~= "gateOpen"
		end

		table.clear(v.byKey)
		for ci, chain in layout.categories[catId].chains do
			local shown = Comb.window(chain, Comb.ownedCount(chain, view))
			for i, hex in v.slots[ci] do
				hex.key = chain.links[shown[i]].key
				v.byKey[hex.key :: string] = hex
			end
		end
		local landings: { Hex } = {}
		for _, key in fresh do
			local hex = if key then v.byKey[key] else nil
			if hex then
				table.insert(landings, hex)
				local nextHex = (hex.slots :: { Hex })[(hex.slot :: number) + 1]
				if nextHex then
					nextHex.holdUntil = math.huge -- keeps its old look until it wakes
				end
			end
		end
		for ci in layout.categories[catId].chains do
			for i, hex in v.slots[ci] do
				if now >= hex.holdUntil then
					local key = hex.key :: string
					paintLink(hex, infos[key].link, states[key], catId, view, hex.fade)
					if hex.fade then
						hex.fade = false
						hex.holdUntil = now + FADE.Time
					end
					local before = v.slots[ci][i - 1]
					setBridge(v.into[hex], if not before or lit(states[before.key :: string].state) then 1 else 0)
				end
			end
		end
		for _, hex in landings do
			local start = celebrate(v, hex, own ~= nil and own.key == hex.key)
			if own and ownInfo and own.key == hex.key then
				bounce(buyPress)
				Purchase.landed(hex.button, own.cost, ownPitch, firstBuy(ownInfo.link), start)
				own = nil
			else
				start()
			end
		end
		if own and ownInfo then -- landed, but its hex isn't shown
			bounce(buyPress)
			Purchase.landed(nil, own.cost, ownPitch, firstBuy(ownInfo.link), function() end)
		end
		paintDetail(view)
	end

	selectKey = function(key: string?)
		if not key then
			return
		end
		selectedKey = key
		local v = views[viewId]
		panTo(v, v.byKey[key])
		refresh()
	end

	-- Shows a view (glides in: the canvas zooms up, hexes pop in ring by ring); `pick`: the id whose
	-- next link to select.
	showView = function(id: string, pick: string?)
		animToken += 1
		local v = views[id]
		if not v then
			v = if id == "main" then buildMain() else buildCategory(id)
			views[id] = v
		end
		for otherId, other in views do
			if otherId ~= id then
				setVisible(other, false)
			end
		end
		setVisible(v, true)
		viewId = id
		selectedKey, pickId, lastOwned = nil, pick, nil
		panX, panY = 0, 0
		fitView(v)
		zoomScale.Scale = v.zoom * CUE.glideZoomFrom
		TweenService:Create(zoomScale, TweenInfo.new(CUE.glideSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = v.zoom }):Play()
		local now = os.clock()
		for _, hex in v.hexes do
			hex.animKind, hex.animAt = "enter", now + Comb.enterDelay(hex.q, hex.r, CUE.enterStagger, CUE.enterCap)
			hex.holdUntil, hex.hover, hex.down, hex.fade = 0, false, false, false
		end
		set(backButton, "Visible", id ~= "main")
		set(breadcrumb, "Text", if id == "main" then "UPGRADES" else `UPGRADES › {CATEGORY_NAMES[id]:upper()}`)
		refresh()
		local selected = if selectedKey then v.byKey[selectedKey] else nil
		panTo(v, selected)
		if UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad" then
			GuiService.SelectedObject = if selected then selected.button elseif v.centre then v.centre.button else nil
		end
	end

	local function back()
		if viewId ~= "main" then
			showView("main")
		else
			setOpen(false)
		end
	end

	setOpen = function(value: boolean, pick: string?)
		if value then
			local was = open
			open, isOpen = true, true
			if not was then
				window.open(fitScale)
				ContextActionService:BindActionAtPriority("HoneycombBack", function(_, inputState)
					if inputState == Enum.UserInputState.Begin then
						back()
					end
					return Enum.ContextActionResult.Sink
				end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
			end
			if pick or not was then
				showView(if pick then Comb.find(layout, pick) or "main" else "main", pick)
			end
		elseif open then
			open, isOpen = false, false
			animToken += 1
			ContextActionService:UnbindAction("HoneycombBack")
			local selected = GuiService.SelectedObject
			if selected and selected:IsDescendantOf(root) then
				GuiService.SelectedObject = nil
			end
			window.close(fitScale)
		end
	end

	showId = function(id: string)
		if inRun() then
			setOpen(true, id)
		end
	end

	guideTarget = function(id: string): GuiObject?
		local catId = Comb.find(layout, id)
		local v = views[viewId]
		if not (open and catId and v) then
			return nil
		elseif viewId == "main" then
			return v.ring[catId].button
		elseif viewId ~= catId then
			return backButton
		end
		local key = Comb.pick(layout, catId, states, id)
		if key and key == selectedKey then
			return buyButton
		end
		local hex = if key then v.byKey[key] else nil
		return if hex then hex.button else nil
	end

	-- The Upgrades button (right edge) shows where the honeycomb is. Holding Tab / Y / the mouse / a
	-- finger squishes it down; letting go springs it back up. Tab and Y open (or close) it as they go
	-- down, so a release that never arrives (focus moving) can't swallow the press; the mouse and a
	-- finger open it on release, like a button. Its key tag tells keyboard and gamepad players which
	-- key does it; its Badge shows while something can be bought now.
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
	ContextActionService:BindAction("ToggleUpgrades", function(_, inputState)
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

	-- Buttons hold a HitPad (a transparent button built in Studio) that keeps the touch target at
	-- least 44 px when the window is scaled down on phones. The pad takes mouse and touch; the button
	-- itself still takes gamepad selection, so both run fn.
	local function onPress(button: GuiButton, fn: () -> ())
		local pad = Hud.find(button, "HitPad") :: GuiButton
		pressable(pad, (button :: any).Press)
		pad.Activated:Connect(fn)
		button.Activated:Connect(fn)
	end
	onPress(closeButton, function()
		setOpen(false)
	end)
	onPress(backButton, back)

	-- Buy: the selected link, if it is next and the wallet pays it (the server checks again).
	onPress(buyButton, function()
		local now = os.clock()
		local info = if selectedKey then infos[selectedKey] else nil
		if not info or info.link.kind == "gate" then
			Purchase.deny(buyButton)
			return
		end
		local view = readView()
		local have = Comb.bought(info.link, view)
		local waiting = pending and pending.id == info.link.id and pending.have == have and now - pending.at < PENDING_SECONDS
		if now < guardUntil or waiting then
			return -- the last buy hasn't landed (or just did): this click must not buy the level after it
		end
		local st = Comb.states(layout, info.catId, view)[info.link.key]
		if st.state ~= "buy" then
			Purchase.deny(buyButton)
			if st.state == "short" then
				needText.Size = scaled(needSize, CUE.needPulse)
				TweenService:Create(needText, TweenInfo.new(CUE.needSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = needSize }):Play()
			end
			return
		end
		buyRemote:FireServer(info.link.id, have) -- what we saw bought: a teammate's buy first wins
		pending = { key = info.link.key, id = info.link.id :: string, have = have, at = now, cost = st.price :: number }
		guardUntil = now + BUY_GUARD
	end)

	-- Assign: the selected staff moves to its next allowed post.
	pressable(assignButton, Hud.find(assignButton, "Press"))
	assignButton.Activated:Connect(function()
		local info = if selectedKey then infos[selectedKey] else nil
		local item = if info and info.link.kind == "item" then Items.get(Config, info.link.id) else nil
		if not (item and item.kind == "staff" and Items.owned(Hud.items(), item.id)) then
			return
		end
		local now = postOf(item.id)
		local post = StaffRules.nextPost(postsOf(item), now)
		if post and post ~= now then
			bounce(Hud.find(assignButton, "Press"))
			staffRemote:FireServer("assign", item.id, post)
		else
			Purchase.deny(assignButton)
		end
	end)

	-- Drag to pan a view bigger than the board (phones).
	local drag: InputObject? = nil
	local dragFrom, panFrom = Vector3.zero, Vector2.zero
	board.InputBegan:Connect(function(input)
		local v = views[viewId]
		local kind = input.UserInputType
		if v and v.pans and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			drag, dragFrom, panFrom = input, input.Position, Vector2.new(panX, panY)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local v = views[viewId]
		if not (drag and v) or not (input.UserInputType == Enum.UserInputType.MouseMovement or input == drag) then
			return
		end
		local perPixel = boardSize.X / math.max(board.AbsoluteSize.X, 1)
		local moved = (input.Position - dragFrom) * perPixel
		panX, panY = panFrom.X + moved.X, panFrom.Y + moved.Y
		clampPan(v)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == drag or input.UserInputType == Enum.UserInputType.MouseButton1 then
			drag = nil
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		if open and not inRun() then
			setOpen(false)
		end
		set(upgrades, "Visible", inRun() and not root.Visible)
		local input = UserInputService:GetLastInputType()
		set(upgradesKey, "Visible", input ~= Enum.UserInputType.Touch)
		set(upgradesKeyText, "Text", if input.Name:sub(1, 7) == "Gamepad" then "Y" else "TAB")
		if dirty and now >= nextRefresh then
			nextRefresh = now + if open then REFRESH_OPEN else REFRESH_CLOSED
			refresh()
		end
		local v = views[viewId]
		if not (root.Visible and v) then
			return
		end
		set(walletAmount, "Text", Hud.money(math.max(0, Hud.wallet() - Hud.walletHold)))
		-- Hex scales: hover / press / breathing (all "buy" hexes in step) times any animation.
		local breathe = 1 + (CUE.breatheScale - 1) * (0.5 - 0.5 * math.cos(now * 2 * math.pi / CUE.breatheSeconds))
		local rate = math.min(1, dt * PRESS_RATE)
		for _, hex in v.hexes do
			local target = if hex.down then motion.pressScale elseif hex.hover then motion.hoverScale elseif hex.breathe then breathe else 1
			hex.ease += (target - hex.ease) * rate
			set(hex.press, "Scale", math.round(hex.base * hex.ease * animScale(hex, now) * 1000) / 1000)
			set(hex.select, "Visible", hex.hover or (hex.key ~= nil and hex.key == selectedKey))
		end
	end)
end

return Honeycomb
