-- The upgrades honeycomb (StarterGui.Hud.Honeycomb, built in Studio; layout: library
-- ui/screens/shop.md; where each hex sits and its state: shared/Honeycomb). Tab, gamepad Y or the
-- Upgrades button opens and closes it during a run: a full-screen cover (the world blurs through
-- Lighting.HoneycombBlur, the Backdrop darkens, the rest of the HUD hides). One hex per upgrade, a
-- small even gap between hexes, colour-coded (client/HoneycombHex). The main view: the tool at the
-- centre (a click buys its next level) in a ring of categories, each with a red badge counting what
-- can be bought inside; a click glides into a category: its Back hex at the centre, its upgrades
-- around it (Comb.ringSlots). A small card (Tooltip, words: client/HoneycombText) sits by the
-- hovered hex, else the selected one. A mouse click on an affordable hex buys its next level; on
-- touch the first tap selects and the next buys; on a gamepad the D-pad or stick steps between hexes
-- and A presses. A buy sends Buy(id, bought) (`bought`: what this client saw bought, so a teammate's
-- buy of the same level wins); a gate's is Buy("gate:<areaId>", 0). Everything is the team's, from
-- its wallet at the team's price (Hud.price); the server checks every buy and sets the buyer's
-- LastBuy. Items are first bought at their stand (buildings on a plot), so their hex says where. A
-- hired staff's card shows Tooltip.AssignButton, which moves it to its next post (Staff("assign",
-- itemId, areaId), StaffRules.nextPost). A landing plays on the bought hex; your own buy also gets
-- coins, a sting and, for a first, a NEW! stamp (client/Purchase). Back (the Back hex, Backspace,
-- gamepad B) glides out, then closes; Roblox's menu closes it.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
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
local Areas = require(ReplicatedStorage.Common.Areas)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Hud = require(script.Parent.Hud)
local Card = require(script.Parent.HoneycombCard)
local Data = require(script.Parent.HoneycombData)
local Hex = require(script.Parent.HoneycombHex)
local Text = require(script.Parent.HoneycombText)
local Purchase = require(script.Parent.Purchase)
local UpgradesButton = require(script.Parent.HoneycombButton)
local Window = require(script.Parent.Window)

local player = Players.LocalPlayer
local motion = Theme.motion
local set, pressable = Hud.set, Hud.pressable
local CUE = Cues.honeycomb

local BUY_GUARD = 0.4 -- seconds Buy ignores clicks after a buy is sent or lands, so a double click buys once
local PENDING_SECONDS = 2 -- a sent buy without its LastBuy by then was refused (or a teammate's won)
local REFRESH_OPEN = 0.1 -- seconds between state refreshes (after an attribute change) while open
local REFRESH_CLOSED = 0.25 -- only the badges while closed
local PRESS_RATE = 25 -- per second: hover and press scales catch up in about 0.08 s
local STICK = 0.6 -- thumbstick push that steps the selection (let go under it to step again)
local PAD_STEPS = {
	[Enum.KeyCode.DPadUp] = Vector2.new(0, -1),
	[Enum.KeyCode.DPadDown] = Vector2.new(0, 1),
	[Enum.KeyCode.DPadLeft] = Vector2.new(-1, 0),
	[Enum.KeyCode.DPadRight] = Vector2.new(1, 0),
}

local Honeycomb = {}

-- Set by Honeycomb.start: open on an id's hex, and the Guide's next click for an id.
local showId: ((string) -> ())? = nil
local guideTarget: ((string) -> GuiObject?)? = nil
local isOpen = false

-- Opens the honeycomb on the hex of track, item or gate `id`, selected (client/Goal).
function Honeycomb.show(id: string)
	assert(showId, "Honeycomb.show before Honeycomb.start")(id)
end

function Honeycomb.isOpen(): boolean
	return isOpen
end

-- What the guide's hand should tap next to buy `id`: the category hex, then its hex (or Back out of
-- another category); nil while closed.
function Honeycomb.guideTarget(id: string): GuiObject?
	return if guideTarget then guideTarget(id) else nil
end

local layout, infos = Data.layout, Data.infos
local readView, readsState, firstBuy = Data.read, Data.readsState, Data.firstBuy

local function noop() end

local function never(): boolean
	return false
end

-- Whether the next closed gate is on sale now (its hex can be bought: a badge).
local function gateOnSale(): boolean
	local _, onSale = Areas.nextGate(Config, Hud.gatesOpen(), Data.fill())
	return onSale
end

type ViewData = {
	id: string,
	hexes: { Hex.Hex }, -- every hex; the gamepad steps between them
	byKey: { [string]: Hex.Hex }, -- by upgrade id, "cat:<id>" and "back"
	upgrades: { Hex.Hex }, -- the hexes that sell something
	ring: { [string]: Hex.Hex }, -- main: the category hexes
	back: Hex.Hex?, -- a category's Back hex
	w: number,
	h: number,
	zoom: number,
}

type Input = Card.Input

-- A buy sent for upgrade `id` (Buy(buyId, have)) with `owned` of its levels owned, until its
-- LastBuy lands or PENDING_SECONDS pass.
type Pending = { id: string, buyId: string, have: number, owned: number, at: number, cost: number }

function Honeycomb.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Buy") :: RemoteEvent
	local staffRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Staff") :: RemoteEvent
	local root = Hud.find(gui, "Honeycomb") :: Frame
	local backdrop = Hud.find(root, "Backdrop") :: Frame
	local closeButton = Hud.find(root, "CloseButton")
	local closeLabel = Hud.find(closeButton, "Label") :: TextLabel
	local title = Hud.find(root, "Title") :: TextLabel
	local walletAmount = Hud.find(root, "Wallet.Amount")
	local board = Hud.find(root, "Board") :: Frame
	local canvas = Hud.find(board, "Canvas") :: Frame
	local zoomScale = Hud.find(canvas, "Zoom") :: UIScale
	local card = Card.new(root)
	local blur = Lighting:FindFirstChild("HoneycombBlur") :: BlurEffect
	assert(blur and blur:IsA("BlurEffect"), "Lighting is missing HoneycombBlur (a BlurEffect, built in Studio)")
	local upgrades = Hud.find(gui, "UpgradesButton")
	local upgradesBadge = Hud.find(upgrades, "Badge")
	local upgradesCount = upgradesBadge:FindFirstChild("Count") -- optional: the total on the ball
	local hexTemplate = Hud.find(gui, "Templates.Hex") :: ImageButton
	Hex.parts(hexTemplate) -- fail at start, not on the first open
	Hud.find(root, "BackButton").Visible = false -- the Back hex took its place

	-- Flat-top: centre to corner; hexes sit Comb.SPACING of that apart, a small gap between them.
	local hexSize = hexTemplate.Size.X.Offset / 2
	local hexHeight = hexTemplate.Size.Y.Offset
	assert(hexSize > 0 and hexHeight > 0, "Hud.Templates.Hex needs an offset Size")
	local shade = backdrop.BackgroundTransparency -- Studio's value: how dark the cover gets
	backdrop.BackgroundTransparency = 1
	blur.Size = 0
	local cover = TweenInfo.new(CUE.coverSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local uncover = TweenInfo.new(CUE.uncoverSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	-- Tab would also toggle Roblox's player list; the game has its own Board, so hide that list.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

	local open = false
	local window = Window.new(root, nil) -- full screen: no frame pop
	local views: { [string]: ViewData } = {}
	local viewId = "main"
	local selectedKey: string? = nil
	local pickId: string? = nil -- the id the next refresh selects (Honeycomb.show)
	local states: { [string]: Comb.HexState } = {} -- the shown view's
	local lastOwned: { [string]: number } = {} -- levels owned per upgrade at the last refresh of this view
	local animToken = 0 -- bumped on view changes and closing: running landings stop
	local dirty = true
	local nextRefresh = 0
	local guardUntil = 0
	local pending: { [string]: Pending } = {}
	local landed: { [string]: Pending } = {} -- your buys the server confirmed (LastBuy), until their hex lands
	local badgeLow, badgeHigh = -math.huge, math.huge -- wallets that keep the badges (Comb.badges)
	local onSale = false -- gateOnSale at the last refresh
	local input: Input = "mouse"
	local cardKey: string? = nil -- the upgrade the card shows
	local overCard = false -- the mouse is on the card

	local function inRun(): boolean
		return ReplicatedStorage:GetAttribute("Phase") == "playing"
	end

	-- Only what can change a hex marks a refresh. Staff only changes words, so it counts while open;
	-- closed, a wallet change counts only when it crosses a badge's price, the fill only when it puts
	-- a gate on sale.
	ReplicatedStorage.AttributeChanged:Connect(function(name: string)
		if readsState(name) or (open and name == "Staff") then
			dirty = true
		elseif name == "Fill" then
			dirty = dirty or open or gateOnSale() ~= onSale
		elseif name == "Wallet" then
			local wallet = Hud.wallet()
			dirty = dirty or open or wallet < badgeLow or wallet >= badgeHigh
		end
	end)

	-- Sent buys without their LastBuy after PENDING_SECONDS were refused: their hex may land as a
	-- teammate's now.
	local function expirePending(now: number)
		for id, sent in pending do
			if now - sent.at >= PENDING_SECONDS then
				pending[id] = nil
				dirty = true
			end
		end
	end

	-- Your buy landed: the sting (higher per level), coins into `target` (nil: none) and a NEW! stamp
	-- for a first.
	local function playOwn(sent: Pending, target: GuiObject?, arrive: () -> (), still: () -> boolean)
		local bought = infos[sent.id].upgrade.links[sent.owned + 1]
		Purchase.landed(target, sent.cost, Cues.stingPitch(sent.owned + 1), firstBuy(bought), arrive, still)
	end

	-- Zoom to fill the board, never under CUE.minHexPixels a hex on screen.
	local function fitView(v: ViewData)
		local size = board.AbsoluteSize
		v.zoom = (Comb.zoom(v.w, v.h, size.X, size.Y, hexHeight, CUE.minHexPixels, CUE.maxZoom))
		Hex.setTextScale(v.zoom)
	end

	board:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local v = views[viewId]
		if v then
			fitView(v)
			zoomScale.Scale = v.zoom
			dirty = true -- hex text keeps its on-screen size
		end
	end)

	local selectKey: (string?) -> ()
	local showView: (string, string?) -> ()
	local setOpen: (boolean, string?) -> ()
	local clickUpgrade: (Hex.Hex, Input) -> ()
	local actions: { [Hex.Hex]: (Input) -> () } = {} -- what a click on each hex does (gamepad A too)

	-- Hover grows a hex; press shrinks it. Clicks count only while open.
	local function hook(hex: Hex.Hex, onClick: (Input) -> ())
		local button = hex.button
		actions[hex] = onClick
		button.MouseEnter:Connect(function()
			hex.hover = true
		end)
		button.MouseLeave:Connect(function()
			hex.hover, hex.down = false, false
		end)
		button.MouseButton1Down:Connect(function()
			hex.down = true
		end)
		button.MouseButton1Up:Connect(function()
			hex.down = false
		end)
		button.Activated:Connect(function(inputObject: InputObject)
			local kind = inputObject.UserInputType
			if kind == Enum.UserInputType.Touch then
				hex.hover = false -- a finger leaves no hover behind
			end
			if open then
				onClick(if kind == Enum.UserInputType.Touch then "touch" elseif kind == Enum.UserInputType.MouseButton1 then "mouse" else "gamepad")
			end
		end)
	end

	-- A view around (0, 0) and `cells`, centred on the canvas; with where its centre sits.
	local function newView(id: string, cells: { Comb.Pos }): (ViewData, number, number)
		local positions: { Comb.Pos } = { { q = 0, r = 0 } }
		for _, pos in cells do
			table.insert(positions, { q = pos.q, r = pos.r })
		end
		local cx, cy, w, h = Comb.bounds(positions, hexSize, Comb.SPACING)
		return { id = id, hexes = {}, byKey = {}, upgrades = {}, ring = {}, w = w, h = h, zoom = 1 }, cx, cy
	end

	local function newHex(v: ViewData, pos: Comb.Pos, cx: number, cy: number, key: string, onClick: (Input) -> ()): Hex.Hex
		local x, y = Comb.toPixel(pos.q, pos.r, hexSize * Comb.SPACING)
		local hex = Hex.new(hexTemplate, pos.q, pos.r, x - cx, y - cy, canvas)
		hex.key = key
		table.insert(v.hexes, hex)
		v.byKey[key] = hex
		hook(hex, onClick)
		return hex
	end

	local function addUpgrade(v: ViewData, upgrade: Comb.Upgrade, pos: Comb.Pos, cx: number, cy: number)
		local hex
		hex = newHex(v, pos, cx, cy, upgrade.id, function(kind: Input)
			clickUpgrade(hex, kind)
		end)
		table.insert(v.upgrades, hex)
	end

	local function buildMain(): ViewData
		local v, cx, cy = newView("main", layout.ring)
		addUpgrade(v, layout.tool, { q = 0, r = 0 }, cx, cy)
		for _, at in layout.ring do
			local hex = newHex(v, at, cx, cy, `cat:{at.id}`, function()
				showView(at.id)
			end)
			hex.button.ZIndex = hexTemplate.ZIndex + 1 -- its badge over the tool hex
			v.ring[at.id] = hex
		end
		return v
	end

	local function buildCategory(catId: string): ViewData
		local cat = layout.categories[catId]
		local v, cx, cy = newView(catId, cat.slots)
		v.back = newHex(v, { q = 0, r = 0 }, cx, cy, "back", function()
			showView("main")
		end)
		for i, upgrade in cat.upgrades do
			addUpgrade(v, upgrade, cat.slots[i], cx, cy)
		end
		return v
	end

	local function setVisible(v: ViewData, visible: boolean)
		for _, hex in v.hexes do
			hex.button.Visible = visible
		end
	end

	-- The card shows upgrade `cardKey`'s next level (none for categories and Back).
	local function paintCard(view: Comb.View)
		local info = if cardKey then infos[cardKey] else nil
		local st = if cardKey then states[cardKey] else nil
		Card.paint(card, if info and st then Comb.link(info.upgrade, st.owned) else nil, st, view, input)
	end

	-- A level landed on `hex` (Hex.celebrate): as yours when you bought it (Purchase.landed starts
	-- it as the coins arrive), else silent.
	local function land(hex: Hex.Hex)
		local id = hex.key :: string
		local upgrade = infos[id].upgrade
		local token = animToken
		local function alive(): boolean
			return open and token == animToken
		end
		local start = Hex.celebrate(hex, function()
			local view = readView()
			Hex.paintUpgrade(hex, upgrade, Comb.state(upgrade, view), view, Ladder.stats(Config, view.levels))
		end, alive, function()
			dirty, nextRefresh = true, 0
		end)
		local mine = landed[id]
		landed[id] = nil
		if mine then
			playOwn(mine, hex.button, start, alive)
		else
			start()
		end
	end

	-- Re-reads the team's state: badges always; while open the shown view, the landings since the
	-- last refresh (yours from LastBuy, teammates' silent) and the card.
	local function refresh()
		local now = os.clock()
		expirePending(now)
		dirty = false
		local view = readView()
		local badges, low, high = Comb.badges(layout, view)
		badgeLow, badgeHigh, onSale = low, high, gateOnSale()
		set(upgradesBadge, "Visible", badges.total > 0)
		if upgradesCount and upgradesCount:IsA("TextLabel") then
			set(upgradesCount, "Text", tostring(badges.total))
		end
		if not open then
			return
		end

		local v = views[viewId]
		local stats = Ladder.stats(Config, view.levels)
		states = Comb.states(layout, viewId, view)
		if not selectedKey and viewId ~= "main" then
			selectedKey = Comb.pick(layout, viewId, states, pickId) or layout.categories[viewId].upgrades[1].id
			pickId = nil
		end
		if v.back then
			Hex.paintBack(v.back)
		end
		for id, hex in v.ring do
			Hex.paintCategory(hex, layout, id, view, badges[id])
		end
		for _, hex in v.upgrades do
			local id = hex.key :: string
			local st = states[id]
			local was = lastOwned[id]
			if was and st.owned > was and pending[id] then
				continue -- your buy: it lands as yours at its LastBuy (or as a teammate's once refused)
			end
			lastOwned[id] = st.owned
			if was and st.owned > was then
				land(hex)
			end
			if now >= hex.holdUntil then
				Hex.paintUpgrade(hex, infos[id].upgrade, st, view, stats)
			end
		end
		-- Your buys that won't land on a hex here (another view, or already shown): the sound only.
		-- One still waiting for its level stays.
		for id, sent in landed do
			local st = states[id]
			if not st or st.owned > sent.owned then
				landed[id] = nil
				playOwn(sent, nil, noop, never)
			end
		end
		paintCard(view)
	end

	-- The server credited one of your buys (Run's onBuy): it lands as yours.
	player:GetAttributeChangedSignal("LastBuy"):Connect(function()
		local buy = Comb.decodeBuy(player:GetAttribute("LastBuy"))
		local now = os.clock()
		expirePending(now)
		if not buy then
			return
		end
		for id, sent in pending do
			if sent.buyId == buy.id and sent.have + 1 == buy.level then
				pending[id] = nil
				guardUntil = now + BUY_GUARD
				if open then
					landed[id] = sent
					dirty, nextRefresh = true, 0
				else -- closed before it landed: the sound only
					playOwn(sent, nil, noop, never)
				end
			end
		end
	end)

	selectKey = function(key: string?)
		if key then
			selectedKey = key
			refresh()
		end
	end

	-- Assign: the card's hired staff moves to its next allowed post.
	local function assign()
		local info = if cardKey then infos[cardKey] else nil
		local st = if cardKey then states[cardKey] else nil
		if info and st then
			Card.assign(card, Comb.link(info.upgrade, st.owned), readView(), staffRemote)
		end
	end

	-- A press on an upgrade's hex that means it: buys its next level if the wallet pays it (the
	-- server checks again); a gamepad's A on a hired staff posts it; else the hex shakes and the
	-- card's hint pulses.
	local function activate(hex: Hex.Hex, kind: Input)
		local now = os.clock()
		local id = hex.key :: string
		local upgrade = infos[id].upgrade
		expirePending(now)
		if now < guardUntil or pending[id] then
			return -- the last buy hasn't landed (or just did): this click must not buy the level after it
		end
		local view = readView()
		local st = Comb.state(upgrade, view)
		local link = Comb.link(upgrade, st.owned)
		if st.state == "buy" then
			local have = Comb.bought(link, view)
			buyRemote:FireServer(link.id, have) -- what we saw bought: a teammate's buy first wins
			pending[id] = { id = id, buyId = link.id, have = have, owned = st.owned, at = now, cost = st.price :: number }
			guardUntil = now + BUY_GUARD
		elseif kind == "gamepad" and Card.hiredStaff(link, view) then
			assign()
		elseif st.state ~= "max" then
			Purchase.deny(hex.button)
			Card.pulse(card)
		end
	end

	-- A mouse click acts at once; a tap or A selects first (the card shows) and acts on the selected hex.
	clickUpgrade = function(hex: Hex.Hex, kind: Input)
		local again = selectedKey == hex.key
		selectKey(hex.key)
		if kind == "mouse" or again then
			activate(hex, kind)
		end
	end

	-- Gamepad: the selection steps toward unit direction (dx, dy) (Comb.step).
	local function step(dx: number, dy: number)
		local v = views[viewId]
		local from = (if selectedKey then v.byKey[selectedKey] else nil) or v.hexes[1]
		local to = Comb.step(v.hexes, table.find(v.hexes, from) :: number, dx, dy)
		if to then
			selectKey(v.hexes[to].key)
		end
	end

	-- Shows a view (glides in: the canvas zooms up, hexes pop in ring by ring); `pick`: the id whose
	-- hex to select.
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
		selectedKey = if id == "main" and (pick or input == "gamepad") then layout.tool.id else nil
		pickId, cardKey = pick, nil
		table.clear(lastOwned)
		fitView(v)
		zoomScale.Scale = v.zoom * CUE.glideZoomFrom
		TweenService:Create(zoomScale, TweenInfo.new(CUE.glideSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = v.zoom }):Play()
		local now = os.clock()
		for _, hex in v.hexes do
			hex.animKind, hex.animAt = "enter", now + Comb.enterDelay(hex.q, hex.r, CUE.enterStagger, CUE.enterCap)
			hex.holdUntil, hex.hover, hex.down = 0, false, false
		end
		set(title, "Text", if id == "main" then "UPGRADES" else `UPGRADES › {Text.category(id):upper()}`)
		refresh()
	end

	local function back()
		if viewId ~= "main" then
			showView("main")
		else
			setOpen(false)
		end
	end

	-- Gamepad while open: the D-pad and left stick step the selection, A presses the selected hex.
	local stickHeld = false
	local function onPad(_, inputState: Enum.UserInputState, inputObject: InputObject)
		local code = inputObject.KeyCode
		if code == Enum.KeyCode.Thumbstick1 then
			local push = Vector2.new(inputObject.Position.X, -inputObject.Position.Y)
			if push.Magnitude > STICK and not stickHeld then
				step(push.Unit.X, push.Unit.Y)
			end
			stickHeld = push.Magnitude > STICK
		elseif inputState == Enum.UserInputState.Begin then
			local v = views[viewId]
			local hex = if selectedKey then v.byKey[selectedKey] else nil
			if code == Enum.KeyCode.ButtonA then
				if hex then
					actions[hex]("gamepad")
				else
					selectKey(v.hexes[1].key)
				end
			else
				local dir = PAD_STEPS[code]
				step(dir.X, dir.Y)
			end
		end
		return Enum.ContextActionResult.Sink
	end

	setOpen = function(value: boolean, pick: string?)
		if value then
			local was = open
			open, isOpen = true, true
			if not was then
				window.open(1)
				TweenService:Create(backdrop, cover, { BackgroundTransparency = shade }):Play()
				TweenService:Create(blur, cover, { Size = CUE.blur }):Play()
				-- Esc belongs to Roblox's menu (which closes the window, below), so Back is Backspace / B.
				ContextActionService:BindActionAtPriority("HoneycombBack", function(_, inputState)
					if inputState == Enum.UserInputState.Begin then
						back()
					end
					return Enum.ContextActionResult.Sink
				end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
				ContextActionService:BindActionAtPriority("HoneycombPad", onPad, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.Thumbstick1, Enum.KeyCode.ButtonA)
			end
			if pick or not was then
				showView(if pick then Comb.find(layout, pick) or "main" else "main", pick)
			end
		elseif open then
			open, isOpen = false, false
			animToken += 1
			cardKey = nil
			ContextActionService:UnbindAction("HoneycombBack")
			ContextActionService:UnbindAction("HoneycombPad")
			TweenService:Create(backdrop, uncover, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(blur, uncover, { Size = 0 }):Play()
			window.close(1)
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
		local where, upgrade = Comb.find(layout, id)
		local v = views[viewId]
		if not (open and where and upgrade and v) then
			return nil
		elseif where == viewId then
			return v.byKey[upgrade.id].button
		elseif viewId == "main" then
			return v.ring[where].button
		end
		return (v.back :: Hex.Hex).button
	end

	UpgradesButton.start(upgrades, function()
		setOpen(not open and inRun())
	end)

	local function onInputType(kind: Enum.UserInputType)
		if kind.Name:sub(1, 7) == "Gamepad" then
			input = "gamepad"
		elseif kind == Enum.UserInputType.Touch then
			input = "touch"
		elseif kind == Enum.UserInputType.Keyboard or kind.Name:sub(1, 5) == "Mouse" then
			input = "mouse"
		end
		set(closeLabel, "Text", if input == "touch" then "Close" elseif input == "gamepad" then "Close [Y]" else "Close [Tab]")
		dirty = true -- the card's hint names the input
	end
	UserInputService.LastInputTypeChanged:Connect(onInputType)
	onInputType(UserInputService:GetLastInputType())

	-- The close button holds a HitPad (a transparent button built in Studio) that keeps the touch
	-- target at least 44 px on phones. The pad takes mouse and touch; the button itself still takes
	-- gamepad selection, so both close.
	local closePad = Hud.find(closeButton, "HitPad") :: GuiButton
	pressable(closePad, (closeButton :: any).Press)
	for _, button in { closePad, closeButton :: GuiButton } do
		button.Activated:Connect(function()
			setOpen(false)
		end)
	end
	card.assign.Activated:Connect(assign)
	card.frame.MouseEnter:Connect(function()
		overCard = true
	end)
	card.frame.MouseLeave:Connect(function()
		overCard = false
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
		-- Hex scales: hover / press / gamepad selection / breathing (all "buy" hexes in step) times
		-- any animation.
		local breathe = 1 + (CUE.breatheScale - 1) * (0.5 - 0.5 * math.cos(now * 2 * math.pi / CUE.breatheSeconds))
		local rate = math.min(1, dt * PRESS_RATE)
		local hoverHex: Hex.Hex? = nil
		for _, hex in v.hexes do
			local selected = hex.key == selectedKey
			local target = if hex.down then motion.pressScale elseif hex.hover or (selected and input == "gamepad") then motion.hoverScale elseif hex.breathe then breathe else 1
			hex.ease += (target - hex.ease) * rate
			set(hex.press, "Scale", math.round(hex.ease * Hex.animScale(hex, now) * 1000) / 1000)
			set(hex.select, "Visible", hex.hover or selected)
			if hex.hover then
				hoverHex = hex
			end
		end
		-- The card follows the hovered upgrade (mouse), else the selected one; it stays while the
		-- mouse is on its Assign button.
		local key = if hoverHex and input == "mouse" and infos[hoverHex.key :: string] then hoverHex.key else selectedKey
		if key and not infos[key] then
			key = nil -- a category or Back: no card
		end
		if overCard and card.assign.Visible then
			key = cardKey
		end
		if key ~= cardKey then
			cardKey = key
			paintCard(readView())
		end
		local shown = if cardKey then v.byKey[cardKey] else nil
		if shown and card.frame.Visible then
			Card.place(card, root, shown.button, hexHeight * zoomScale.Scale / 2)
		end
	end)
end

return Honeycomb
