-- The honeycomb's hexes (client/Honeycomb): copies of Hud.Templates.Hex, painted by what they are
-- (PAINT: a top-to-bottom gradient on Body, a thin lighter rim, a soft glow) in their upgrade's state
-- (shared/Honeycomb.state): a short name on top, art in the middle, Level ("2/6", "MAX") and the
-- next level's price (or "Owned", "Open") at the bottom. Their animations: popping in, and a landing
-- on the bought hex (its water rises, it pops as a check flashes and its Level ticks up, then it
-- wakes into its next level). Numbers in Cues.honeycomb, colours, images and motion from the
-- clear-tide theme.
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
local Theme = require(ReplicatedStorage.Kit.UI.Themes["clear-tide"])
local Hud = require(script.Parent.Hud)
local Text = require(script.Parent.HoneycombText)

local colors, images, motion = Theme.colors, Theme.images, Theme.motion
local set = Hud.set
local CUE = Cues.honeycomb

local RIM_LIGHT = 0.5 -- a rim is its hex's top colour this far toward white
local DARK = 0.25 -- a flat colour's gradient ends this far toward the shadow
local GLOW_LIT = 0.25 -- hover and gamepad selection: the glow this much less transparent
local WATER_TRANSPARENCY = 0.2

export type Kind = "upgrade" | "owned" | "locked" | "category" | "back" | "empty"
type Paint = { shade: ColorSequence, rim: Color3?, glow: Color3, glowRest: number }

local function look(top: Color3, bottom: Color3, rim: Color3?, glow: Color3, glowRest: number): Paint
	return { shade = ColorSequence.new(top, bottom), rim = rim, glow = glow, glowRest = glowRest }
end

-- Every hex look, from the theme: one colour per job.
local PAINT: { [Kind]: Paint } = {
	upgrade = look(colors.upgradeTop, colors.upgradeBottom, colors.upgradeRim, colors.glow, 0.5),
	owned = look(colors.owned, colors.owned:Lerp(colors.upgradeBottom, DARK), colors.owned:Lerp(colors.text, RIM_LIGHT), colors.owned, 0.35),
	locked = look(colors.locked, colors.locked:Lerp(colors.shadow, DARK), colors.locked:Lerp(colors.text, RIM_LIGHT), colors.glow, 0.5),
	category = look(colors.categoryTop, colors.categoryBottom, colors.categoryTop:Lerp(colors.text, RIM_LIGHT), colors.categoryTop, 0.35),
	back = look(colors.back, colors.back:Lerp(colors.shadow, DARK), colors.back:Lerp(colors.text, RIM_LIGHT), colors.glow, 0.5),
	empty = look(colors.empty, colors.empty:Lerp(colors.shadow, DARK), nil, colors.glow, 0.5),
}
local BACK_OVERSHOOT = 1.70158 -- TweenService's Back easing
-- On-screen text sizes in pixels at the fitted zoom (never hidden).
local TEXT = { name = { 14, 18 }, level = { 12, 14 }, price = { 14, 16 } }

-- Art for the tracks that have an icon (the tool shows its 3D model; the rest none until drawn).
local ICONS = { pickup = "pipFull", tip = "coin" }

-- On-screen pixels per template pixel in the shown view (its zoom).
local textScale = 1

export type Hex = {
	button: ImageButton,
	press: UIScale,
	glow: ImageLabel,
	shade: UIGradient,
	water: Frame,
	fill: ImageLabel,
	outline: ImageLabel,
	select: GuiObject,
	view: ViewportFrame,
	icon: ImageLabel,
	name: TextLabel,
	level: TextLabel,
	priceRow: GuiObject,
	coin: ImageLabel,
	price: TextLabel,
	lock: GuiObject,
	check: GuiObject,
	badge: GuiObject,
	count: TextLabel,
	backArrow: GuiObject,
	areaIcon: GuiObject,
	waterWidth: UDim,
	checkSize: UDim2,
	badgeSize: UDim2,
	designs: { [TextLabel]: number }, -- text sizes at zoom 1
	q: number,
	r: number,
	x: number, -- offset from the canvas centre, before zoom
	y: number,
	key: string?, -- the upgrade id, "cat:<id>" or "back"
	art: Instance?,
	kind: Kind?, -- the look painted
	glowRest: number, -- its glow's transparency while not hovered
	hover: boolean,
	down: boolean,
	ease: number, -- hover / press / breathing scale, catching up
	breathe: boolean,
	animKind: string?, -- "enter", "pop" or "wake"
	animAt: number,
	holdUntil: number, -- a landing owns the hex's look until then
	landing: number, -- bumped by each landing: an older one stops
	badgeCount: number,
}

local HoneycombHex = {}

-- The hex parts a copy of Templates.Hex has (Hud.find: the template must keep these names).
function HoneycombHex.parts(button: ImageButton)
	return {
		press = Hud.find(button, "Press"),
		glow = Hud.find(button, "Glow"),
		shade = Hud.find(button, "Body.Shade"),
		water = Hud.find(button, "Water"),
		fill = Hud.find(button, "Water.Fill"),
		outline = Hud.find(button, "Outline"),
		select = Hud.find(button, "Select"),
		view = Hud.find(button, "View"),
		icon = Hud.find(button, "Icon"),
		name = Hud.find(button, "Name"), -- not button.Name: the child's name clashes with the property
		level = Hud.find(button, "Level"),
		priceRow = Hud.find(button, "PriceRow"),
		coin = Hud.find(button, "PriceRow.Coin"),
		price = Hud.find(button, "PriceRow.Price"),
		lock = Hud.find(button, "Lock"),
		check = Hud.find(button, "Check"),
		badge = Hud.find(button, "Badge"),
		count = Hud.find(button, "Badge.Count"),
		backArrow = Hud.find(button, "BackArrow"),
		areaIcon = Hud.find(button, "AreaIcon"),
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
	hex.designs = {}
	for _, label in { hex.name, hex.level, hex.price } do
		hex.designs[label] = designSize(label)
	end
	hex.q, hex.r, hex.x, hex.y = q, r, x, y
	hex.hover, hex.down, hex.breathe = false, false, false
	hex.ease, hex.animAt, hex.holdUntil, hex.landing, hex.badgeCount, hex.glowRest = 1, 0, 0, 0, -1, 1
	hex.select.Visible = false
	hex.badge.Visible = false
	hex.fill.ImageColor3 = colors.owned
	hex.fill.ImageTransparency = WATER_TRANSPARENCY
	button.AutoButtonColor = false -- hover and press scale it instead
	button.Position = UDim2.fromOffset(x, y)
	button.Visible = false
	button.Parent = parent
	return hex
end

function HoneycombHex.scaled(size: UDim2, k: number): UDim2
	return UDim2.new(size.X.Scale * k, size.X.Offset * k, size.Y.Scale * k, size.Y.Offset * k)
end

-- The shown view's zoom: hex text keeps to its TEXT sizes on screen. The caller repaints after.
function HoneycombHex.setTextScale(scale: number)
	textScale = scale
end

-- `label` shows `text` (nil hides it) at an on-screen size within `range`: a TextScaled label with a
-- UITextSizeConstraint shrinks to fit within it, any other label takes its design size clamped.
local function paintText(hex: Hex, label: TextLabel, text: string?, range: { number })
	set(label, "Visible", text ~= nil)
	if not text then
		return
	end
	set(label, "Text", text)
	local low, high = range[1] / textScale, range[2] / textScale
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if label.TextScaled and limit then
		set(limit, "MinTextSize", math.clamp(math.floor(low), 1, 100))
		set(limit, "MaxTextSize", math.clamp(math.ceil(high), 1, 100))
	else
		set(label, "TextScaled", false)
		set(label, "TextSize", math.round(math.clamp(hex.designs[label], low, high)))
	end
end

-- The price row: `text` (nil hides it), the coin, its colour.
local function paintPrice(hex: Hex, text: string?, coin: boolean, color: Color3)
	set(hex.priceRow, "Visible", text ~= nil)
	paintText(hex, hex.price, text, TEXT.price)
	if text then
		set(hex.price, "TextColor3", color)
		set(hex.coin, "Visible", coin)
	end
end

local function setWater(hex: Hex, level: number)
	set(hex.water, "Size", UDim2.new(hex.waterWidth, UDim.new(level, 0)))
	set(hex.water, "Visible", level > 0)
end

-- Hover and gamepad selection light a hex's glow.
function HoneycombHex.lit(hex: Hex, on: boolean)
	set(hex.glow, "ImageTransparency", if on then math.max(0, hex.glowRest - GLOW_LIT) else hex.glowRest)
end

-- A hex's body: its look (gradient, rim, glow; written when it changes), its water level and which
-- marks show (the check, the lock, Back's arrow, the area flag).
local function paintBody(hex: Hex, kind: Kind, water: number, check: boolean, lock: boolean, arrow: boolean, area: boolean)
	if hex.kind ~= kind then
		hex.kind = kind
		local style = PAINT[kind]
		hex.shade.Color = style.shade
		hex.outline.Visible = style.rim ~= nil
		if style.rim then
			hex.outline.ImageColor3 = style.rim
		end
		hex.glow.ImageColor3 = style.glow
		hex.glowRest = style.glowRest
		HoneycombHex.lit(hex, false)
	end
	setWater(hex, water)
	set(hex.check, "Visible", check)
	set(hex.lock, "Visible", lock)
	set(hex.backArrow, "Visible", arrow)
	set(hex.areaIcon, "Visible", area)
end

-- The template (a Model or a backpack's Accessory) and image a level shows; nil, nil for none (a
-- gate shows AreaIcon; the tool its model in hand, see paintUpgrade).
function HoneycombHex.artOf(link: Comb.Link): (Instance?, string?)
	if link.kind == "gate" then
		return nil, nil
	elseif link.kind == "track" then
		local icon = ICONS[link.id]
		return nil, if icon then images[icon] else nil
	end
	local template = ToolModels.itemModel(Items.get(Config, link.id))
	return template, if template then nil else images.unknown -- nil until replicated
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

-- The tool in hand's model.
local function toolArt(stats: Ladder.Stats): (Instance?, string?)
	local template = ToolModels.find(stats.toolModel)
	return template, if template then nil else images.unknown
end

-- An upgrade hex's Level: owned of all levels ("2/6"), "MAX" when done; none for a gate.
function HoneycombHex.levelText(upgrade: Comb.Upgrade, st: Comb.HexState): string?
	if upgrade.kind == "gate" then
		return nil
	end
	return if st.state == "max" then "MAX" else `{st.owned}/{st.total}`
end

-- A link's listed price (Config), before the team's scale.
local function listedCost(link: Comb.Link): number
	local item = Items.get(Config, link.id)
	return if link.level == 1 then item.price else item.levels[link.level - 1].cost
end

-- An upgrade's hex in state `st`: upgrade blue (cyan once owned, slate while locked); its name,
-- art, Level and at the bottom the next level's price (short and a rising fill while short), the
-- stand price, what a closed gate waits for, "Owned" or "Open"; a check once maxed.
function HoneycombHex.paintUpgrade(hex: Hex, upgrade: Comb.Upgrade, st: Comb.HexState, view: Comb.View, stats: Ladder.Stats)
	local state = st.state
	local link = Comb.link(upgrade, st.owned)
	local gate = upgrade.kind == "gate"
	local kind: Kind, water, art = "upgrade", 0, true
	local priceText, coin, priceColor = nil, false, colors.text
	if state == "max" then
		kind, priceText = "owned", if gate then "Open" else "Owned"
	elseif state == "buy" then
		priceText, coin = Hud.money(st.price :: number), true
	elseif state == "short" then
		water, priceText, coin, priceColor = st.progress :: number, Hud.money(st.price :: number), true, colors.short
	elseif Comb.elsewhere(link, st, view) then
		priceText, coin = Hud.money(Hud.price(listedCost(link))), true
	else
		kind, art = "locked", false
		priceText = if gate then Text.gateWait(Areas.byId(Config, link.areaId)) else nil
	end
	paintBody(hex, kind, water, state == "max", not art, false, gate and art)
	local tool = upgrade.id == "tool"
	paintText(hex, hex.name, if tool then Format.toolName(stats.toolName) else Text.short(link), TEXT.name)
	paintText(hex, hex.level, HoneycombHex.levelText(upgrade, st), TEXT.level)
	paintPrice(hex, priceText, coin, priceColor)
	local template, image = nil, nil
	if art and tool then
		template, image = toolArt(stats)
	elseif art then
		template, image = HoneycombHex.artOf(link)
	end
	HoneycombHex.showArt(hex, hex.view, hex.icon, template, image)
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

-- A category hex: warm, its name, art, "3/12" levels owned, "Open" and its badge.
function HoneycombHex.paintCategory(hex: Hex, layout: Comb.Layout, catId: string, view: Comb.View, count: number)
	local owned, total = Comb.ownedShare(layout, catId, view)
	paintBody(hex, "category", 0, false, false, false, catId == "areas")
	paintText(hex, hex.name, Text.category(catId):upper(), TEXT.name)
	paintText(hex, hex.level, `{owned}/{total}`, TEXT.level)
	paintPrice(hex, "Open", false, colors.text)
	local template, image = nil, nil
	if catId == "boosts" then
		image = images.pipFull
	elseif catId ~= "areas" then
		template, image = HoneycombHex.artOf(layout.categories[catId].upgrades[1].links[1])
	end
	HoneycombHex.showArt(hex, hex.view, hex.icon, template, image)
	paintBadge(hex, count)
	hex.breathe = false
end

-- A category's centre: Back, with its arrow.
function HoneycombHex.paintBack(hex: Hex)
	paintBody(hex, "back", 0, false, false, true, false)
	paintText(hex, hex.name, "Back", TEXT.name)
	paintText(hex, hex.level, nil, TEXT.level)
	paintPrice(hex, nil, false, colors.text)
	HoneycombHex.showArt(hex, hex.view, hex.icon, nil, nil)
	hex.breathe = false
end

-- A dark empty hex that completes the honeycomb's shape: nothing on it.
function HoneycombHex.paintEmpty(hex: Hex)
	paintBody(hex, "empty", 0, false, false, false, false)
	paintText(hex, hex.name, nil, TEXT.name)
	paintText(hex, hex.level, nil, TEXT.level)
	paintPrice(hex, nil, false, colors.text)
	HoneycombHex.showArt(hex, hex.view, hex.icon, nil, nil)
	hex.breathe = false
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
		return motion.buyPop + (1 - motion.buyPop) * Ease.backOut(t, BACK_OVERSHOOT)
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

-- A landing on a bought hex: holds its look, and returns what starts it (Purchase.landed runs it as
-- the coins arrive). The water rises; the hex pops as `paint()` shows its new level and a check
-- flashes; bridgeSeconds after the check it wakes into its next level and `done()` runs (the caller
-- repaints). `alive()` false stops it early (then `done()` too); a newer landing on the hex takes over.
function HoneycombHex.celebrate(hex: Hex, paint: () -> (), alive: () -> boolean, done: () -> ()): () -> ()
	hex.landing += 1
	local mine = hex.landing
	hex.holdUntil = math.huge
	local function live(): boolean
		if hex.landing ~= mine then
			return false -- a newer landing owns the hex
		elseif not alive() then
			hex.holdUntil = 0
			done()
			return false
		end
		return true
	end
	return function()
		if not live() then
			return
		end
		hex.water.Visible = true
		local full = UDim2.new(hex.waterWidth, UDim.new(1, 0))
		TweenService:Create(hex.water, TweenInfo.new(CUE.waterSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = full }):Play()
		task.delay(CUE.waterSeconds, function()
			if not live() then
				return
			end
			hex.animKind, hex.animAt = "pop", os.clock()
			paint()
			setWater(hex, 1)
			local check = hex.check
			check.Size = UDim2.new()
			check.Visible = true
			local up = TweenService:Create(check, TweenInfo.new(CUE.checkSeconds * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = HoneycombHex.scaled(hex.checkSize, CUE.checkOvershoot) })
			up.Completed:Once(function()
				TweenService:Create(check, TweenInfo.new(CUE.checkSeconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Size = hex.checkSize }):Play()
			end)
			up:Play()
			task.delay(CUE.checkSeconds + CUE.bridgeSeconds, function()
				if not live() then
					return
				end
				hex.animKind, hex.animAt = "wake", os.clock()
				hex.holdUntil = 0
				done()
			end)
		end)
	end
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
