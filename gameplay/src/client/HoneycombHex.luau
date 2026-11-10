-- The honeycomb's hexes (client/Honeycomb): copies of Hud.Templates.Hex, painted in their state
-- (shared/Honeycomb.states) with a short name on top, art in the middle and a price or state word
-- at the bottom, and their animations: popping in, a landing (the hex fills, then the touching next
-- hex wakes), sliding along a chain's window. Numbers in Cues.honeycomb, colours and images from the
-- sunbaked-sea theme.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Ease = require(ReplicatedStorage.Shared.Ease)
local Format = require(ReplicatedStorage.Shared.Format)
local Comb = require(ReplicatedStorage.Shared.Honeycomb)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Hud = require(script.Parent.Hud)
local Text = require(script.Parent.HoneycombText)

local colors, images = Theme.colors, Theme.images
local set = Hud.set
local CUE = Cues.honeycomb

local FADE = TweenInfo.new(CUE.fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE = TweenInfo.new(CUE.slideSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FUTURE_SHADE = 0.5 -- a hex that isn't next yet: its colour this far toward the outline navy
local SMALL_PRICE = 0.8 -- an item's price at its stand, of the template's size
local BACK_OVERSHOOT = 1.70158 -- TweenService's Back easing
local RIM_SHADE = 0.4 -- a hex's rim: its colour this far toward the outline navy

-- Art for the tracks that have an icon (the tool shows its 3D model; the rest none until drawn).
local ICONS = { pickup = "pipFull", tip = "coin" }

-- On-screen pixels per template pixel in the shown view (its zoom).
local textScale = 1

export type Hex = {
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
	key: string?, -- the link shown now ("centre", "cat:<id>" or "home" for the views' fixed hexes)
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

-- A landing's progress for its caller: the hex is full, the next hex woke, or it stopped (the view
-- changed or the hex shows another link).
export type Step = "filled" | "woke" | "stopped"

local HoneycombHex = {}

-- The hex parts a copy of Templates.Hex has (Hud.find: the template must keep these names).
function HoneycombHex.parts(button: ImageButton)
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

-- A label's text size at view scale 1: TextScaled labels have no real TextSize (it reads 8).
local function designSize(label: TextLabel): number
	if not label.TextScaled then
		return label.TextSize
	end
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	return if limit then limit.MaxTextSize else label.Size.Y.Offset
end

-- A hidden copy of `template` at axial (q, r), `x`, `y` from the canvas centre, in `parent`.
function HoneycombHex.new(template: ImageButton, q: number, r: number, x: number, y: number, parent: Instance): Hex
	local button = template:Clone()
	local hex = HoneycombHex.parts(button) :: any
	hex.button = button
	hex.waterWidth = hex.water.Size.X
	hex.checkSize = hex.check.Size
	hex.badgeSize = hex.badge.Size
	hex.priceSize = designSize(hex.price)
	hex.q, hex.r, hex.x, hex.y = q, r, x, y
	hex.hover, hex.down, hex.breathe, hex.fade = false, false, false, false
	hex.ease, hex.base, hex.animAt, hex.holdUntil, hex.badgeCount, hex.share = 1, 1, 0, 0, -1, -1
	hex.select.Visible = false
	hex.badge.Visible = false
	button.AutoButtonColor = false -- hover and press scale it instead
	button.Position = UDim2.fromOffset(x, y)
	button.Visible = false
	button.Parent = parent
	return hex
end

function HoneycombHex.scaled(size: UDim2, k: number): UDim2
	return UDim2.new(size.X.Scale * k, size.X.Offset * k, size.Y.Scale * k, size.Y.Offset * k)
end

-- The shown view's zoom: hex text under CUE.minTextPixels on screen hides. The caller repaints
-- after a change.
function HoneycombHex.setTextScale(scale: number)
	textScale = scale
end

local function readable(textSize: number): boolean
	return textSize * textScale >= CUE.minTextPixels
end

local function setWater(hex: Hex, level: number)
	set(hex.water, "Size", UDim2.new(hex.waterWidth, UDim.new(level, 0)))
	set(hex.water, "Visible", level > 0)
end

-- The template (a Model or a backpack's Accessory) and image a link shows; nil, nil for none. A
-- link with a 3D model shows nothing unless `model` (few ViewportFrames: Honeycomb.modelKeys).
function HoneycombHex.artOf(link: Comb.Link, model: boolean): (Instance?, string?)
	if link.kind == "gate" then
		return nil, nil
	elseif link.kind == "track" and link.id ~= "tool" then
		local icon = ICONS[link.id :: string]
		return nil, if icon then images[icon] else nil
	elseif not model then
		return nil, nil
	end
	local template = if link.kind == "track"
		then ToolModels.find((Config.track("tool") :: Config.Track).levels[link.level :: number].model :: string)
		else ToolModels.itemModel(Items.get(Config, link.id))
	return template, if template then nil else images.unknown -- nil until replicated
end

-- A category hex's art: the current tool, the boosts' pip, else its first item's model.
local function categoryArt(layout: Comb.Layout, catId: string, stats: Ladder.Stats): (Instance?, string?)
	if catId == "tools" then
		local template = ToolModels.find(stats.toolModel)
		return template, if template then nil else images.unknown
	elseif catId == "boosts" then
		return nil, images.pipFull
	end
	for _, link in layout.categories[catId].chains[1].links do
		if link.kind ~= "gate" then
			return HoneycombHex.artOf(link, true)
		end
	end
	return nil, images.unknown
end

-- A hex's art slot: `template` in its ViewportFrame (copied once per template), else `image` in its
-- Icon, else nothing.
function HoneycombHex.showArt(record: { art: Instance? }, view: ViewportFrame, icon: ImageLabel, template: Instance?, image: string?)
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

-- A hex's body: colour (its rim a darker shade) and outline; `fade` tweens the colours.
local function paintBody(hex: Hex, base: Color3, outline: Color3, fade: boolean)
	local rim = base:Lerp(colors.outline, RIM_SHADE)
	if fade then
		TweenService:Create(hex.button, FADE, { ImageColor3 = base }):Play()
		TweenService:Create(hex.bottom, FADE, { ImageColor3 = rim }):Play()
	else
		set(hex.button, "ImageColor3", base)
		set(hex.bottom, "ImageColor3", rim)
	end
	set(hex.outline, "ImageColor3", outline)
end

local function paintName(hex: Hex, text: string?)
	set(hex.name, "Visible", text ~= nil and readable(designSize(hex.name)))
	if text then
		set(hex.name, "Text", text)
	end
end

-- The price row: `text` (nil hides it), the coin, its colour, small for an item at its stand.
local function paintPrice(hex: Hex, text: string?, coin: boolean, color: Color3, small: boolean)
	local size = if small then math.round(hex.priceSize * SMALL_PRICE) else hex.priceSize
	set(hex.priceRow, "Visible", text ~= nil and readable(size))
	if not text then
		return
	end
	set(hex.price, "Text", text)
	set(hex.price, "TextColor3", color)
	set(hex.price, "TextSize", size)
	set(hex.coin, "Visible", coin)
end

-- A link's listed price (Config), before the team's scale.
local function listedCost(link: Comb.Link): number
	if link.kind == "track" then
		return (Config.track(link.id :: string) :: Config.Track).levels[link.level :: number].cost
	end
	local item = Items.get(Config, link.id)
	return if link.level == 1 then item.price else item.levels[(link.level :: number) - 1].cost
end

-- A link hex in its state (shared/Honeycomb.states); `model`: it may show its 3D model. Every hex
-- has its short name on top; at the bottom the next link's price, an item's price at its stand,
-- "Owned", "MAX" or how a closed gate opens. Later links are a darker shade, without a price.
function HoneycombHex.paintLink(hex: Hex, link: Comb.Link, st: Comb.HexState, catId: string, view: Comb.View, fade: boolean, model: boolean)
	local state = st.state
	local base, outline = categoryColor(catId), colors.outline
	local water, waterColor, check, lock, art, iconColor = 0, colors.shallowWater, false, false, true, colors.foam
	local priceText, coin, priceColor, small = nil, false, colors.foam, false
	hex.base = 1
	if state == "owned" then
		water, check, priceText = 1, true, "Owned"
	elseif state == "max" then
		water, outline, priceText = 1, colors.toolTag, "MAX"
	elseif state == "buy" then
		priceText, coin = Hud.money(st.price :: number), true
	elseif state == "short" then
		base, water, waterColor = colors.locked, st.progress :: number, colors.shallowWater:Lerp(colors.locked, 0.5)
		priceText, coin, priceColor = Hud.money(st.price :: number), true, colors.buyCoral
	elseif Comb.elsewhere(link, st, view) then
		base, small = base:Lerp(colors.outline, FUTURE_SHADE), true
		priceText, coin = Hud.money(Hud.price(listedCost(link))), true
	elseif state == "future" then
		base = base:Lerp(colors.outline, FUTURE_SHADE)
	elseif state == "gateOpen" then
		-- passed: a small lock in water blue (the theme has no open-lock image yet)
		base, art, hex.base, iconColor = colors.locked, false, CUE.gateScale, colors.shallowWater
	elseif link.kind == "gate" then
		base, art, lock = colors.locked, false, true
		priceText, coin = Text.gate(Areas.byId(Config, link.areaId))
	else
		base, art, lock = colors.locked, false, true
	end
	paintBody(hex, base, outline, fade)
	set(hex.fill, "ImageColor3", waterColor)
	setWater(hex, water)
	set(hex.check, "Visible", check)
	set(hex.lock, "Visible", lock)
	paintName(hex, Text.short(link))
	paintPrice(hex, priceText, coin, priceColor, small)
	local template, image = nil, if state == "gateOpen" then images.lock else nil
	if art then
		template, image = HoneycombHex.artOf(link, model)
	end
	HoneycombHex.showArt(hex, hex.view, hex.icon, template, image)
	set(hex.icon, "ImageColor3", iconColor)
	hex.breathe = state == "buy"
end

-- The red ball: pops in when something becomes buyable, shrinks away at 0.
local function paintBadge(hex: Hex, count: number)
	local was = hex.badgeCount
	hex.badgeCount = count
	set(hex.count, "Text", tostring(count))
	set(hex.count, "Visible", readable(designSize(hex.count)))
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
function HoneycombHex.paintCategory(hex: Hex, layout: Comb.Layout, catId: string, view: Comb.View, count: number, stats: Ladder.Stats)
	local owned, total = Comb.ownedShare(layout, catId, view)
	local share = if total > 0 then owned / total else 0
	paintBody(hex, categoryColor(catId), colors.outline, false)
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
	paintName(hex, Text.category(catId):upper())
	paintPrice(hex, `{owned}/{total}`, false, colors.foam, true)
	HoneycombHex.showArt(hex, hex.view, hex.icon, categoryArt(layout, catId, stats))
	paintBadge(hex, count)
	hex.breathe = false
end

-- The main view's centre: the tool in hand and its level (the tool chain's level, as its hexes
-- and the card count; none for the starting tool).
function HoneycombHex.paintCentre(hex: Hex, stats: Ladder.Stats, level: number)
	paintBody(hex, colors.toolTag, colors.outline, false)
	setWater(hex, 0)
	set(hex.check, "Visible", false)
	set(hex.lock, "Visible", false)
	paintName(hex, Format.toolName(stats.toolName))
	paintPrice(hex, if level > 0 then `Lv {level}` else nil, false, colors.foam, true)
	local template = ToolModels.find(stats.toolModel)
	HoneycombHex.showArt(hex, hex.view, hex.icon, template, if template then nil else images.unknown)
end

-- The scale an animation adds at `now` (1 when none plays).
function HoneycombHex.animScale(hex: Hex, now: number): number
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

-- A landing (shop.md: the hex fills, the touching next hex wakes): holds the hex and `nextHex`, and
-- returns what starts it (Purchase.landed runs it as the coins arrive). `final`: the hex's state
-- once landed. `alive()` false stops it and lets both go; `update` hears each step, and the caller
-- repaints after it.
function HoneycombHex.celebrate(hex: Hex, final: Comb.StateName, nextHex: Hex?, alive: () -> boolean, update: (Step) -> ()): () -> ()
	hex.holdUntil = math.huge
	setWater(hex, 0)
	set(hex.check, "Visible", false)
	local function stop()
		hex.holdUntil = 0
		if nextHex then
			nextHex.holdUntil = 0
		end
		update("stopped")
	end
	return function()
		if not alive() then
			stop()
			return
		end
		hex.water.Visible = true
		local full = UDim2.new(hex.waterWidth, UDim.new(1, 0))
		TweenService:Create(hex.water, TweenInfo.new(CUE.waterSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = full }):Play()
		task.delay(CUE.waterSeconds, function()
			if not alive() then
				stop()
				return
			end
			hex.animKind, hex.animAt = "pop", os.clock()
			hex.holdUntil = 0 -- full now: the next paint matches; the check's stamp is Size only
			if final == "owned" then
				local check = hex.check
				check.Size = UDim2.new()
				check.Visible = true
				local up = TweenService:Create(check, TweenInfo.new(CUE.checkSeconds * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = HoneycombHex.scaled(hex.checkSize, CUE.checkOvershoot) })
				up.Completed:Once(function()
					TweenService:Create(check, TweenInfo.new(CUE.checkSeconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Size = hex.checkSize }):Play()
				end)
				up:Play()
			end
			update("filled")
			if not nextHex then
				return
			end
			task.delay(CUE.bridgeSeconds, function()
				if not alive() then
					stop()
					return
				end
				nextHex.fade = true
				nextHex.animKind, nextHex.animAt = "wake", os.clock()
				nextHex.holdUntil = 0
				update("woke")
			end)
		end)
	end
end

-- A chain's window moved: the hex glides from (fromX, fromY), the slot its link sat in, to its own.
function HoneycombHex.slide(hex: Hex, fromX: number, fromY: number)
	hex.button.Position = UDim2.fromOffset(fromX, fromY)
	TweenService:Create(hex.button, SLIDE, { Position = UDim2.fromOffset(hex.x, hex.y) }):Play()
end

-- A button springs when what it sent lands: down, past full size, back.
function HoneycombHex.bounce(scale: UIScale)
	scale.Scale = CUE.bounceLow
	local up = TweenService:Create(scale, TweenInfo.new(CUE.bounceSeconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = CUE.bounceHigh })
	up.Completed:Once(function(playback)
		if playback == Enum.PlaybackState.Completed then
			TweenService:Create(scale, TweenInfo.new(CUE.bounceSeconds * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Scale = 1 }):Play()
		end
	end)
	up:Play()
end

return HoneycombHex
