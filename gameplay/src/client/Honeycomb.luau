-- The upgrades honeycomb (StarterGui.Hud.Honeycomb, built in Studio; layout: library
-- ui/screens/shop.md; where each hex sits and its state: shared/Honeycomb). Tab, gamepad Y or the
-- Upgrades button opens and closes it during a run (client/Window pops it in). The main view: the
-- current tool at the centre and a ring of category hexes, each with a red badge counting what can be
-- bought inside and water showing how much of it is owned; a click glides into the category: its hex,
-- a spine of bridges and every upgrade as a chain of hexes joined by bridges (client/HoneycombHex), long chains
-- windowed around the next link. Selecting a hex fills the Detail strip (words: client/HoneycombText),
-- whose Buy button sends Buy(id, bought) (`bought`: what this client saw bought, so a teammate's buy
-- of the same level wins). Everything is the team's, from its wallet at the team's price (Hud.price);
-- the server checks every buy and sets the buyer's LastBuy. Items are first bought at their stand
-- (buildings on a plot), so their first hex says where. Detail.AssignButton moves a hired staff to
-- its next post (Staff("assign", itemId, areaId), StaffRules.nextPost). Your confirmed buy (your
-- LastBuy) moves the selection to the next link at once, so a quick second Buy buys it; a click on
-- a hex still landing is ignored. A landing fills its hex,
-- then the bridge, and wakes the next hex (a windowed chain then slides along); your own buy (your
-- LastBuy) also gets coins, a sting and, for a first, a NEW! stamp (client/Purchase). Back (the
-- button, Backspace, gamepad B) glides out, then closes; Roblox's menu closes it.
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
local Comb = require(ReplicatedStorage.Shared.Honeycomb)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local StaffRules = require(ReplicatedStorage.Shared.StaffRules)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Hud = require(script.Parent.Hud)
local Hex = require(script.Parent.HoneycombHex)
local Text = require(script.Parent.HoneycombText)
local Purchase = require(script.Parent.Purchase)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local colors, images, motion = Theme.colors, Theme.images, Theme.motion
local set, pressable = Hud.set, Hud.pressable
local CUE = Cues.honeycomb

local QUICK = TweenInfo.new(CUE.quickSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Upgrades button: squish down while held, spring back past full size on release.
local HOLD_DOWN = TweenInfo.new(CUE.holdDownSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOLD_UP = TweenInfo.new(CUE.holdUpSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BUY_GUARD = 0.4 -- seconds Buy ignores clicks after a buy is sent or lands, so a double click buys once
local PENDING_SECONDS = 2 -- a sent buy without its LastBuy by then was refused (or a teammate's won)
local REFRESH_OPEN = 0.1 -- seconds between state refreshes (after an attribute change) while open
local REFRESH_CLOSED = 0.25 -- only the badges while closed
local SPACING = 1.14 -- hex centres sit this much further apart than touching, so the bridges show
local FIT_MARGIN = 28 -- pixels of screen height the window leaves free, so its bottom never clips
local PRESS_RATE = 25 -- per second: hover and press scales catch up in about 0.08 s
local DRAG_SLOP = 8 -- pixels a press on the board may move and still click its hex

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

-- The team's state as shared/Honeycomb reads it. Only what TAB sells has a price (Items.tabOffer):
-- an item's first link is bought at its stand or built on a plot.
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
		price = function(link: Comb.Link): number?
			local id = link.id
			if not id then
				return nil -- a gate
			end
			local level, status = Items.tabOffer(Config, levels, snap.items, snap.buildings, id, snap.openAreas, Ladder.helps(Config, levels, id))
			return if status == "buy" then Items.price(Config, level.cost, snap.teamSize) else nil
		end,
		reachable = function(id: string): boolean
			return Items.reachable(Config, snap.items, { Items.get(Config, id).area })[1] ~= nil
		end,
	}
end

-- Whether water flows past a hex in `state` into the next one.
local function lit(state: Comb.StateName): boolean
	return state == "owned" or state == "max" or state == "gateOpen"
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

local function sameWindow(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for i, index in a do
		if b[i] ~= index then
			return false
		end
	end
	return true
end

-- Attributes a hex's state reads, besides Wallet (shared/Honeycomb.states through readView).
local function readsState(name: string): boolean
	return name == "TeamSize"
		or name == "Owned"
		or name == "GatesOpen"
		or name:sub(1, 6) == "Level_"
		or name:sub(1, 10) == "ItemLevel_"
		or name:sub(1, 14) == "BuildingLevel_"
end

local function noop() end

local function never(): boolean
	return false
end

type ViewData = {
	id: string,
	hexes: { Hex.Hex },
	bridges: { Hex.Bridge },
	byKey: { [string]: Hex.Hex },
	into: { [Hex.Hex]: Hex.Bridge }, -- the bridge leading into each chain slot
	slots: { { Hex.Hex } }, -- per chain
	windows: { [number]: { number } }, -- per chain: the link indices its slots show (Comb.window)
	landing: { [{ Hex.Hex }]: string }, -- chains (by their slots) whose landing plays, the landing link's key: their window holds
	centre: Hex.Hex?, -- main: the tool
	ring: { [string]: Hex.Hex }, -- main: the category hexes
	catHex: Hex.Hex?, -- a category view's own hex
	w: number,
	h: number,
	zoom: number,
	pans: boolean,
}

-- A buy sent (by link key) until its LastBuy lands or PENDING_SECONDS pass.
type Pending = { key: string, id: string, have: number, at: number, cost: number }

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
	local needPulse = Hud.find(needText, "Pulse") :: UIScale
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
	Hex.parts(hexTemplate) -- fail at start, not on the first open
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
	local pending: { [string]: Pending } = {}
	local landed: { [string]: Pending } = {} -- your buys the server confirmed (LastBuy), until their hex lands
	local badgeLow, badgeHigh = -math.huge, math.huge -- wallets that keep the badges (Comb.badges)
	local gamepad = false

	local function inRun(): boolean
		return ReplicatedStorage:GetAttribute("Phase") == "playing"
	end

	-- Only what can change a hex marks a refresh. Fill and Staff only change words, so they count
	-- while open; closed, a wallet change counts only when it crosses a badge's price.
	ReplicatedStorage.AttributeChanged:Connect(function(name: string)
		if readsState(name) or (open and (name == "Fill" or name == "Staff")) then
			dirty = true
		elseif name == "Wallet" then
			local wallet = Hud.wallet()
			dirty = dirty or open or wallet < badgeLow or wallet >= badgeHigh
		end
	end)

	-- Sent buys without their LastBuy after PENDING_SECONDS were refused: their link may land as a
	-- teammate's now.
	local function expirePending(now: number)
		for key, sent in pending do
			if now - sent.at >= PENDING_SECONDS then
				pending[key] = nil
				dirty = true
			end
		end
	end

	-- Your buy landed: the sting, coins into `target` (nil: none) and a NEW! stamp for a first.
	local function playOwn(sent: Pending, view: Comb.View, target: GuiObject?, arrive: () -> (), still: () -> boolean)
		local info = infos[sent.key]
		local pitch = Cues.stingPitch(Comb.ownedCount(info.chain, view))
		Purchase.landed(target, sent.cost, pitch, firstBuy(info.link), arrive, still)
	end

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
		Hex.setTextScale(v.zoom * fitScale)
		clampPan(v)
	end

	-- A panning view keeps `hex` on the board.
	local function panTo(v: ViewData, hex: Hex.Hex?)
		if hex and v.pans then
			panX, panY = -hex.x * v.zoom, -hex.y * v.zoom
			clampPan(v)
		end
	end

	local function refit()
		local size = gui.AbsoluteSize -- the Hud's area inside the top bar and safe insets
		fitScale = math.min(size.X / design.X.Offset, (size.Y - FIT_MARGIN) / design.Y.Offset, 1)
		if open then
			fit.Scale = fitScale
		end
		local v = views[viewId]
		if v then
			fitView(v)
			zoomScale.Scale = v.zoom
			dirty = true -- hex text may cross the smallest readable size
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()

	local function newHex(v: ViewData, q: number, r: number, cx: number, cy: number): Hex.Hex
		local x, y = Comb.toPixel(q, r, spaced)
		local hex = Hex.new(hexTemplate, q, r, x - cx, y - cy, canvas)
		table.insert(v.hexes, hex)
		return hex
	end

	local function newBridge(v: ViewData, a: Comb.Pos, b: Comb.Pos, cx: number, cy: number): Hex.Bridge
		local ax, ay = Comb.toPixel(a.q, a.r, spaced)
		local bx, by = Comb.toPixel(b.q, b.r, spaced)
		local bridge = Hex.newBridge(bridgeTemplate, ax - cx, ay - cy, bx - cx, by - cy, hexTemplate.ZIndex, canvas)
		table.insert(v.bridges, bridge)
		return bridge
	end

	local selectKey: (string?) -> ()
	local showView: (string, string?) -> ()
	local setOpen: (boolean, string?) -> ()
	local dragMoved = false -- the last press on the board dragged: its release clicks nothing

	-- Hover (mouse or gamepad selection) grows a hex and shows its ring; press shrinks it. Clicks
	-- count only while open and not at the end of a drag.
	local function hook(hex: Hex.Hex, onClick: () -> ())
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
			local kind = input.UserInputType
			local pointer = kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
			if kind == Enum.UserInputType.Touch then
				hex.hover = false -- a finger leaves no hover behind
			end
			if open and not (pointer and dragMoved) then
				onClick()
			end
		end)
	end

	local function emptyView(id: string): ViewData
		return { id = id, hexes = {}, bridges = {}, byKey = {}, into = {}, slots = {}, windows = {}, landing = {}, ring = {}, w = 0, h = 0, zoom = 1, pans = false }
	end

	local function buildMain(): ViewData
		local v = emptyView("main")
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
		local v = emptyView(catId)
		local positions: { Comb.Pos } = { cat.hex }
		table.move(cat.spine, 1, #cat.spine, 2, positions)
		for _, chain in cat.chains do
			table.move(chain.slots, 1, #chain.slots, #positions + 1, positions)
		end
		local cx, cy, w, h = Comb.bounds(positions, spaced)
		v.w, v.h = w, h
		for _, bridge in cat.bridges do
			Hex.setBridge(newBridge(v, bridge[1], bridge[2], cx, cy), 1) -- the spine is always full
		end
		local catHex = newHex(v, cat.hex.q, cat.hex.r, cx, cy)
		catHex.catId = catId
		catHex.button.ZIndex = hexTemplate.ZIndex + 1 -- its badge over the chain hexes beside it
		hook(catHex, function()
			showView("main")
		end)
		v.catHex = catHex
		for ci, chain in cat.chains do
			local slots = {}
			v.slots[ci] = slots
			for i, pos in chain.slots do
				local hex = newHex(v, pos.q, pos.r, cx, cy)
				hex.slots, hex.slot = slots, i
				slots[i] = hex
				hook(hex, function()
					if v.landing[slots] ~= hex.key then -- the hex you just bought: the selection moved on
						selectKey(hex.key)
					end
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

	-- A landing on `hex` (Hex.celebrate): its chain's window holds until it ends, and the selection
	-- moves on to the next link if it still sits on the bought one (a teammate's buy; yours moved at
	-- its LastBuy).
	local function celebrate(v: ViewData, hex: Hex.Hex): () -> ()
		local token, key = animToken, hex.key :: string
		local slots = hex.slots :: { Hex.Hex }
		local nextHex = slots[(hex.slot :: number) + 1]
		v.landing[slots] = key
		local function alive(): boolean
			return token == animToken and hex.key == key
		end
		return Hex.celebrate(hex, states[key].state, nextHex, nextHex and v.into[nextHex], alive, function(step: Hex.Step)
			dirty = true
			if step == "filled" and nextHex then
				return -- the bridge and the next hex follow
			end
			if v.landing[slots] == key then -- a quick rebuy's landing in this chain may have taken over
				v.landing[slots] = nil
			end
			if step == "woke" then
				nextRefresh = 0
				if selectedKey == key then
					selectKey(nextLinkKey(key))
				end
			end
		end)
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
			template, image = Hex.artOf(link, true)
		end
		Hex.showArt(detailArt, detailView, detailIcon, template, image)
		set(itemName, "Text", Text.name(link))
		set(levelText, "Text", if link.kind == "gate" then "Gate" elseif Comb.elsewhere(link, st, view) then Text.where(link) else Comb.levelText(link, state))
		set(effect, "Text", Text.effect(link, view))
		local need = Text.reason(link, st, view)
		set(needText, "Visible", need ~= nil)
		if need then
			set(needText, "Text", need)
		end
		local priced = state == "buy" or state == "short"
		set(buyLabel, "Text", if priced then "BUY" else Text.word(link, st, view))
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
			set(assignLabel, "Text", Text.assign(item, postOf(item.id)))
		end
	end

	-- Re-reads the team's state: badges always; while open the shown view, the landings since the
	-- last refresh (yours from LastBuy, teammates' silent) and the detail.
	local function refresh()
		local now = os.clock()
		expirePending(now)
		dirty = false
		local view = readView()
		local badges, low, high = Comb.badges(layout, view)
		badgeLow, badgeHigh = low, high
		set(upgradesBadge, "Visible", badges.total > 0)
		if upgradesCount and upgradesCount:IsA("TextLabel") then
			set(upgradesCount, "Text", tostring(badges.total))
		end
		if not open then
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
			Hex.paintCentre(v.centre :: Hex.Hex, stats, view.levels.tool or 0)
			for id, hex in v.ring do
				Hex.paintCategory(hex, layout, id, view, badges[id], stats)
			end
			local centre = v.centre :: Hex.Hex
			for key, sent in landed do
				landed[key] = nil
				Hex.bounce(buyPress)
				centre.animKind, centre.animAt = "pop", now
				local token = animToken
				playOwn(sent, view, centre.button, noop, function()
					return open and token == animToken
				end)
			end
			paintDetail(view)
			return
		end

		local cat = layout.categories[catId]
		Hex.paintCategory(v.catHex :: Hex.Hex, layout, catId, view, badges[catId], stats)
		-- Links owned now that weren't at the last refresh: one per chain plays its landing. A link
		-- you sent a buy for waits (unpainted) for its LastBuy or the pending's end, so it plays as yours.
		local fresh: { [Comb.Chain]: string | false } = {}
		local waiting: { [string]: boolean } = {}
		local held: { [Comb.Chain]: boolean } = {}
		if lastOwned then
			for key, st in states do
				if lit(st.state) and st.state ~= "gateOpen" and not lastOwned[key] then
					local chain = infos[key].chain
					if pending[key] then
						waiting[key], held[chain] = true, true
					else
						fresh[chain] = if fresh[chain] == nil then key else false
					end
				end
			end
		end
		lastOwned = lastOwned or {}
		for key, st in states do
			(lastOwned :: any)[key] = lit(st.state) and st.state ~= "gateOpen" and not waiting[key]
		end

		-- Windows: a chain whose landing plays (or waits) keeps the links it shows, so the hex you
		-- bought fills where it is; then it slides to its new window.
		table.clear(v.byKey)
		for ci, chain in cat.chains do
			local slots = v.slots[ci]
			local want = Comb.window(chain, Comb.ownedCount(chain, view))
			local shown = v.windows[ci]
			local busy = v.landing[slots] ~= nil or held[chain] == true or type(fresh[chain]) == "string"
			local moves = nil
			if not shown then
				shown = want
			elseif not busy and not sameWindow(shown, want) then
				moves = Comb.moves(shown, want)
				shown = want
			end
			v.windows[ci] = shown
			for i, hex in slots do
				hex.key = chain.links[shown[i]].key
				v.byKey[hex.key :: string] = hex
				local from = if moves then moves[i] else i
				if from ~= i then
					hex.holdUntil, hex.fade = 0, false -- it shows another link now: paint it at once
				end
				if not from then
					hex.animKind, hex.animAt = "enter", now
				elseif from ~= i then
					Hex.slide(hex, slots[from].x, slots[from].y)
				end
			end
		end

		local landings: { Hex.Hex } = {}
		for _, key in fresh do
			local hex = if key then v.byKey[key] else nil
			if hex then
				table.insert(landings, hex)
				local nextHex = (hex.slots :: { Hex.Hex })[(hex.slot :: number) + 1]
				if nextHex then
					nextHex.holdUntil = math.huge -- keeps its old look until it wakes
				end
			end
		end
		-- A hex an animation holds is painted when the hold ends (a fade's end: refresh again then).
		local retryAt = math.huge
		for ci, chain in cat.chains do
			local models = Comb.modelKeys(chain, states)
			for i, hex in v.slots[ci] do
				local key = hex.key :: string
				if waiting[key] then
					continue
				elseif now < hex.holdUntil then
					retryAt = math.min(retryAt, hex.holdUntil)
					continue
				end
				Hex.paintLink(hex, infos[key].link, states[key], catId, view, hex.fade, models[key] == true)
				if hex.fade then
					hex.fade = false
					hex.holdUntil = now + CUE.fadeSeconds
				end
				local before = v.slots[ci][i - 1]
				Hex.setBridge(v.into[hex], if not before or lit(states[before.key :: string].state) then 1 else 0)
			end
		end
		for _, hex in landings do
			local key = hex.key :: string
			local mine = landed[key]
			landed[key] = nil
			local start = celebrate(v, hex)
			if mine then
				Hex.bounce(buyPress)
				local token = animToken
				playOwn(mine, view, hex.button, start, function()
					return open and token == animToken and hex.key == key
				end)
			else
				start()
			end
		end
		-- Your buys that won't land on a hex here (another view, two at once, already shown owned):
		-- the sound only. One still waiting for its level stays.
		for key, sent in landed do
			local st = states[key]
			if not st or lit(st.state) then
				landed[key] = nil
				Hex.bounce(buyPress)
				playOwn(sent, view, nil, noop, never)
			end
		end
		paintDetail(view)
		if retryAt < math.huge then
			dirty, nextRefresh = true, retryAt
		end
	end

	-- The server credited one of your buys (Run's onBuy): it lands as yours.
	player:GetAttributeChangedSignal("LastBuy"):Connect(function()
		local buy = Comb.decodeBuy(player:GetAttribute("LastBuy"))
		local now = os.clock()
		expirePending(now)
		if not buy then
			return
		end
		for key, sent in pending do
			if sent.id == buy.id and sent.have + 1 == buy.level then
				pending[key] = nil
				guardUntil = now + BUY_GUARD
				if selectedKey == key then -- on to the next link now; the landing still plays
					selectedKey = nextLinkKey(key) or key
				end
				if open then
					landed[key] = sent
					dirty, nextRefresh = true, 0
				else -- closed before it landed: the sound only
					playOwn(sent, readView(), nil, noop, never)
				end
			end
		end
	end)

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
		table.clear(v.windows)
		table.clear(v.landing)
		panX, panY = 0, 0
		fitView(v)
		zoomScale.Scale = v.zoom * CUE.glideZoomFrom
		TweenService:Create(zoomScale, TweenInfo.new(CUE.glideSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = v.zoom }):Play()
		local now = os.clock()
		for _, hex in v.hexes do
			hex.animKind, hex.animAt = "enter", now + Comb.enterDelay(hex.q, hex.r, CUE.enterStagger, CUE.enterCap)
			hex.holdUntil, hex.hover, hex.down, hex.fade = 0, false, false, false
			hex.button.Position = UDim2.fromOffset(hex.x, hex.y) -- a slide cut short
		end
		set(backButton, "Visible", id ~= "main")
		set(breadcrumb, "Text", if id == "main" then "UPGRADES" else `UPGRADES › {Text.category(id):upper()}`)
		refresh()
		local selected = if selectedKey then v.byKey[selectedKey] else nil
		panTo(v, selected)
		if gamepad then
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
				-- Esc belongs to Roblox's menu (which closes the window, below), so Back is Backspace / B.
				ContextActionService:BindActionAtPriority("HoneycombBack", function(_, inputState)
					if inputState == Enum.UserInputState.Begin then
						back()
					end
					return Enum.ContextActionResult.Sink
				end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
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
	GuiService.MenuOpened:Connect(function()
		setOpen(false)
	end)

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
		TweenService:Create(upgradesPress, HOLD_DOWN, { Scale = CUE.holdScale }):Play()
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

	local function onInputType(kind: Enum.UserInputType)
		gamepad = kind.Name:sub(1, 7) == "Gamepad"
		set(upgradesKey, "Visible", kind ~= Enum.UserInputType.Touch)
		set(upgradesKeyText, "Text", if gamepad then "Y" else "TAB")
	end
	UserInputService.LastInputTypeChanged:Connect(onInputType)
	onInputType(UserInputService:GetLastInputType())

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
		expirePending(now)
		local v = views[viewId]
		local hex = if v then v.byKey[info.link.key] else nil
		local landing = hex ~= nil and hex.slots ~= nil and v.landing[hex.slots] == info.link.key
		if now < guardUntil or pending[info.link.key] or landing then
			return -- the last buy hasn't landed (or just did): this click must not buy the level after it
		end
		local view = readView()
		local have = Comb.bought(info.link, view)
		local st = Comb.states(layout, info.catId, view)[info.link.key]
		if st.state ~= "buy" then
			Purchase.deny(buyButton)
			if st.state == "short" then
				needPulse.Scale = CUE.needPulse
				TweenService:Create(needPulse, TweenInfo.new(CUE.needSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			return
		end
		buyRemote:FireServer(info.link.id, have) -- what we saw bought: a teammate's buy first wins
		pending[info.link.key] = { key = info.link.key, id = info.link.id :: string, have = have, at = now, cost = st.price :: number }
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
			Hex.bounce(Hud.find(assignButton, "Press"))
			staffRemote:FireServer("assign", item.id, post)
		else
			Purchase.deny(assignButton)
		end
	end)

	-- Drag to pan a view bigger than the board (phones), from anywhere on it, hexes included; a
	-- press that moves more than DRAG_SLOP pixels drags instead of clicking.
	local drag: InputObject? = nil
	local dragFrom, panFrom = Vector3.zero, Vector2.zero
	local function onBoard(position: Vector3): boolean
		local at, size = board.AbsolutePosition, board.AbsoluteSize
		return position.X >= at.X and position.Y >= at.Y and position.X <= at.X + size.X and position.Y <= at.Y + size.Y
	end
	UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if open and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and onBoard(input.Position) then
			drag, dragFrom, panFrom, dragMoved = input, input.Position, Vector2.new(panX, panY), false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not drag or not (input.UserInputType == Enum.UserInputType.MouseMovement or input == drag) then
			return
		end
		local delta = input.Position - dragFrom
		dragMoved = dragMoved or delta.Magnitude > DRAG_SLOP
		local v = views[viewId]
		if not (dragMoved and v and v.pans) then
			return
		end
		local perPixel = boardSize.X / math.max(board.AbsoluteSize.X, 1)
		panX, panY = panFrom.X + delta.X * perPixel, panFrom.Y + delta.Y * perPixel
		clampPan(v)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == drag or input.UserInputType == Enum.UserInputType.MouseButton1 then
			drag = nil
		end
	end)

	local shownWallet = -1
	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		if open and not inRun() then
			setOpen(false)
		end
		set(upgrades, "Visible", inRun() and not root.Visible)
		if next(pending) then
			expirePending(now)
		end
		if dirty and now >= nextRefresh then
			nextRefresh = now + if open then REFRESH_OPEN else REFRESH_CLOSED
			refresh()
		end
		local v = views[viewId]
		if not (root.Visible and v) then
			return
		end
		local wallet = math.max(0, Hud.wallet() - Hud.walletHold)
		if wallet ~= shownWallet then
			shownWallet = wallet
			walletAmount.Text = Hud.money(wallet)
		end
		-- Hex scales: hover / press / breathing (all "buy" hexes in step) times any animation.
		local breathe = 1 + (CUE.breatheScale - 1) * (0.5 - 0.5 * math.cos(now * 2 * math.pi / CUE.breatheSeconds))
		local rate = math.min(1, dt * PRESS_RATE)
		for _, hex in v.hexes do
			local target = if hex.down then motion.pressScale elseif hex.hover then motion.hoverScale elseif hex.breathe then breathe else 1
			hex.ease += (target - hex.ease) * rate
			set(hex.press, "Scale", math.round(hex.base * hex.ease * Hex.animScale(hex, now) * 1000) / 1000)
			set(hex.select, "Visible", hex.hover or (hex.key ~= nil and hex.key == selectedKey))
		end
	end)
end

return Honeycomb
