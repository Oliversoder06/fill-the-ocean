-- The upgrades honeycomb (StarterGui.Hud.Honeycomb, built in Studio; layout: library
-- ui/screens/shop.md; where each hex sits and its state: shared/Honeycomb). Tab, gamepad Y or the
-- Upgrades button opens and closes it during a run: a full-screen cover (the world blurs through
-- Lighting.HoneycombBlur, the Backdrop darkens, the rest of the HUD hides) with one cluster of
-- touching hexes in the middle. The main view: the current tool at the centre and a ring of category
-- hexes, each with a red badge counting what can be bought inside and water showing how much of it
-- is owned; a click glides into the category: its hex and every upgrade as a chain of touching hexes
-- (client/HoneycombHex), long chains windowed around the next link. A small card (Tooltip, words:
-- client/HoneycombText) sits by the hovered hex, else the selected one. A mouse click on the next
-- affordable hex buys it; on touch the first tap selects and the next buys; on a gamepad the D-pad
-- or stick steps between hexes and A buys. A buy sends Buy(id, bought) (`bought`: what this client
-- saw bought, so a teammate's buy of the same level wins). Everything is the team's, from its wallet
-- at the team's price (Hud.price); the server checks every buy and sets the buyer's LastBuy. Items
-- are first bought at their stand (buildings on a plot), so their first hex says where. A hired
-- staff's card shows Tooltip.AssignButton, which moves it to its next post (Staff("assign", itemId,
-- areaId), StaffRules.nextPost); clicking its hex pins the card. Your confirmed buy (your LastBuy)
-- moves the selection to the next link at once; a click on a hex still landing is ignored. A
-- landing fills its hex and wakes the next one (a windowed chain then slides along); your own buy
-- also gets coins, a sting and, for a first, a NEW! stamp (client/Purchase). Back (the button,
-- Backspace, gamepad B) glides out, then closes; Roblox's menu closes it.
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
local DRAG_SLOP = 8 -- pixels a press on the board may move and still click its hex
local STICK = 0.6 -- thumbstick push that steps the selection (let go under it to step again)
local PAD_STEPS = {
	[Enum.KeyCode.DPadUp] = Vector2.new(0, -1),
	[Enum.KeyCode.DPadDown] = Vector2.new(0, 1),
	[Enum.KeyCode.DPadLeft] = Vector2.new(-1, 0),
	[Enum.KeyCode.DPadRight] = Vector2.new(1, 0),
}

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

-- What the guide's hand should tap next to buy track or item `id`: the category hex, then the
-- link's hex (or Back out of another category); nil while closed.
function Honeycomb.guideTarget(id: string): GuiObject?
	return if guideTarget then guideTarget(id) else nil
end

local layout, infos = Data.layout, Data.infos
local readView, readsState, nextLinkKey, firstLinkKey, firstBuy = Data.read, Data.readsState, Data.nextLinkKey, Data.firstLinkKey, Data.firstBuy

-- Whether water flows past a hex in `state` into the next one.
local function lit(state: Comb.StateName): boolean
	return state == "owned" or state == "max" or state == "gateOpen"
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

local function noop() end

local function never(): boolean
	return false
end

type ViewData = {
	id: string,
	hexes: { Hex.Hex },
	byKey: { [string]: Hex.Hex }, -- by link key, and the fixed hexes' "centre", "cat:<id>", "home"
	slots: { { Hex.Hex } }, -- per chain
	windows: { [number]: { number } }, -- per chain: the link indices its slots show (Comb.window)
	landing: { [{ Hex.Hex }]: string }, -- chains (by their slots) whose landing plays, the landing link's key: their window holds
	centre: Hex.Hex?, -- main: the tool
	ring: { [string]: Hex.Hex }, -- main: the category hexes
	catHex: Hex.Hex?, -- a category view's own hex
	w: number,
	h: number,
	zoom: number,
	pans: boolean, -- too big for the board at the smallest hex (phones): drag to pan
}

type Input = Card.Input

-- A buy sent (by link key) until its LastBuy lands or PENDING_SECONDS pass.
type Pending = { key: string, id: string, have: number, at: number, cost: number }

function Honeycomb.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Buy") :: RemoteEvent
	local staffRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Staff") :: RemoteEvent
	local root = Hud.find(gui, "Honeycomb") :: Frame
	local backdrop = Hud.find(root, "Backdrop") :: Frame
	local closeButton = Hud.find(root, "CloseButton")
	local closeLabel = Hud.find(closeButton, "Label") :: TextLabel
	local backButton = Hud.find(root, "BackButton")
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

	-- Flat-top: centre to corner, so hexes this far apart (Comb.toPixel) touch; the outline image
	-- draws the thin dark line between them.
	local hexSize = hexTemplate.Size.X.Offset / 2
	local hexHeight = hexTemplate.Size.Y.Offset
	assert(hexSize > 0 and hexHeight > 0, "Hud.Templates.Hex needs an offset Size")
	local canvasBase = canvas.Position
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
	local input: Input = "mouse"
	local cardKey: string? = nil -- the link the card shows
	local overCard = false -- the mouse is on the card

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
		local size = board.AbsoluteSize
		panX, panY = Comb.clampPan(panX, panY, v.w * v.zoom, v.h * v.zoom, size.X, size.Y)
		applyPan()
	end

	-- Zoom to fill the board, never under CUE.minHexPixels a hex on screen (then the board pans).
	local function fitView(v: ViewData)
		local size = board.AbsoluteSize
		v.zoom, v.pans = Comb.zoom(v.w, v.h, size.X, size.Y, hexHeight, CUE.minHexPixels, CUE.maxZoom)
		Hex.setTextScale(v.zoom)
		clampPan(v)
	end

	-- A panning view keeps `hex` on the board.
	local function panTo(v: ViewData, hex: Hex.Hex?)
		if hex and v.pans then
			panX, panY = -hex.x * v.zoom, -hex.y * v.zoom
			clampPan(v)
		end
	end

	board:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local v = views[viewId]
		if v then
			fitView(v)
			zoomScale.Scale = v.zoom
			dirty = true -- hex text may cross the smallest readable size
		end
	end)

	local function newHex(v: ViewData, q: number, r: number, cx: number, cy: number, key: string?): Hex.Hex
		local x, y = Comb.toPixel(q, r, hexSize)
		local hex = Hex.new(hexTemplate, q, r, x - cx, y - cy, canvas)
		hex.key = key
		table.insert(v.hexes, hex)
		return hex
	end

	local selectKey: (string?) -> ()
	local showView: (string, string?) -> ()
	local setOpen: (boolean, string?) -> ()
	local dragMoved = false -- the last press on the board dragged: its release clicks nothing
	local actions: { [Hex.Hex]: (Input) -> () } = {} -- what a click on each hex does (gamepad A too)

	-- Hover grows a hex; press shrinks it. Clicks count only while open and not at the end of a drag.
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
			if open and not dragMoved then
				onClick(if kind == Enum.UserInputType.Touch then "touch" elseif kind == Enum.UserInputType.MouseButton1 then "mouse" else "gamepad")
			end
		end)
	end

	local function emptyView(id: string): ViewData
		return { id = id, hexes = {}, byKey = {}, slots = {}, windows = {}, landing = {}, ring = {}, w = 0, h = 0, zoom = 1, pans = false }
	end

	local function buildMain(): ViewData
		local v = emptyView("main")
		local positions: { Comb.Pos } = { { q = 0, r = 0 } }
		for _, hex in layout.main.ring do
			table.insert(positions, { q = hex.q, r = hex.r })
		end
		local cx, cy, w, h = Comb.bounds(positions, hexSize)
		v.w, v.h = w, h
		local centre = newHex(v, 0, 0, cx, cy, "centre")
		hook(centre, function()
			showView("tools")
		end)
		v.centre = centre
		v.byKey.centre = centre
		for _, at in layout.main.ring do
			local hex = newHex(v, at.q, at.r, cx, cy, `cat:{at.id}`)
			hex.catId = at.id
			hook(hex, function()
				showView(at.id)
			end)
			v.ring[at.id] = hex
			v.byKey[`cat:{at.id}`] = hex
		end
		return v
	end

	local clickLink: (Hex.Hex, Input) -> ()

	local function buildCategory(catId: string): ViewData
		local cat = layout.categories[catId]
		local v = emptyView(catId)
		local positions: { Comb.Pos } = { cat.hex }
		for _, chain in cat.chains do
			table.move(chain.slots, 1, #chain.slots, #positions + 1, positions)
		end
		local cx, cy, w, h = Comb.bounds(positions, hexSize)
		v.w, v.h = w, h
		local catHex = newHex(v, cat.hex.q, cat.hex.r, cx, cy, "home")
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
				hook(hex, function(kind: Input)
					clickLink(hex, kind)
				end)
			end
		end
		return v
	end

	local function setVisible(v: ViewData, visible: boolean)
		for _, hex in v.hexes do
			hex.button.Visible = visible
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
		return Hex.celebrate(hex, states[key].state, nextHex, alive, function(step: Hex.Step)
			dirty = true
			if step == "filled" and nextHex then
				return -- the next hex wakes after
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

	-- The card shows link `cardKey` (none for the views' own hexes).
	local function paintCard(view: Comb.View)
		local info = if cardKey then infos[cardKey] else nil
		Card.paint(card, if info then info.link else nil, if info then states[info.link.key] else nil, view, input)
	end

	-- Re-reads the team's state: badges always; while open the shown view, the landings since the
	-- last refresh (yours from LastBuy, teammates' silent) and the card.
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
		if not selectedKey and viewId ~= "main" then
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
				centre.animKind, centre.animAt = "pop", now
				local token = animToken
				playOwn(sent, view, centre.button, noop, function()
					return open and token == animToken
				end)
			end
			paintCard(view)
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
		v.byKey.home = v.catHex
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
			for _, hex in v.slots[ci] do
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
			end
		end
		for _, hex in landings do
			local key = hex.key :: string
			local mine = landed[key]
			landed[key] = nil
			local start = celebrate(v, hex)
			if mine then
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
				playOwn(sent, view, nil, noop, never)
			end
		end
		paintCard(view)
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

	-- Assign: the card's hired staff moves to its next allowed post.
	local function assign()
		local info = if cardKey then infos[cardKey] else nil
		if info then
			Card.assign(card, info.link, readView(), staffRemote)
		end
	end

	-- A press on a link's hex that means it: buys it if it is next and the wallet pays it (the
	-- server checks again); a gamepad's A on a hired staff posts it; else the hex shakes and the
	-- card's hint pulses.
	local function activate(hex: Hex.Hex, kind: Input)
		local now = os.clock()
		local key = hex.key :: string
		local info = infos[key]
		expirePending(now)
		if now < guardUntil or pending[key] then
			return -- the last buy hasn't landed (or just did): this click must not buy the level after it
		end
		local view = readView()
		local st = Comb.states(layout, info.catId, view)[key]
		if st.state == "buy" then
			local have = Comb.bought(info.link, view)
			buyRemote:FireServer(info.link.id, have) -- what we saw bought: a teammate's buy first wins
			pending[key] = { key = key, id = info.link.id :: string, have = have, at = now, cost = st.price :: number }
			guardUntil = now + BUY_GUARD
		elseif kind == "gamepad" and Card.hiredStaff(info.link, view) then
			assign()
		elseif st.state ~= "owned" and st.state ~= "max" and st.state ~= "gateOpen" then
			Purchase.deny(hex.button)
			Card.pulse(card)
		end
	end

	-- A mouse click acts at once; a tap or A selects first (the card shows) and acts on the selected hex.
	clickLink = function(hex: Hex.Hex, kind: Input)
		local key = hex.key :: string
		if views[viewId].landing[hex.slots :: { Hex.Hex }] == key then
			return -- the hex you just bought: the selection moved on
		end
		local again = selectedKey == key
		selectKey(key)
		if kind == "mouse" or again then
			activate(hex, kind)
		end
	end

	-- Gamepad: the selection steps toward unit direction (dx, dy) (Comb.step).
	local function step(dx: number, dy: number)
		local v = views[viewId]
		local from = (if selectedKey then v.byKey[selectedKey] else nil) or v.centre or v.catHex :: Hex.Hex
		local to = Comb.step(v.hexes, table.find(v.hexes, from) :: number, dx, dy)
		if to then
			selectKey(v.hexes[to].key)
		end
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
		selectedKey = if input == "gamepad" and id == "main" then "centre" else nil
		pickId, lastOwned, cardKey = pick, nil, nil
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
		set(title, "Text", if id == "main" then "UPGRADES" else `UPGRADES › {Text.category(id):upper()}`)
		refresh()
		panTo(v, if selectedKey then v.byKey[selectedKey] else nil)
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
					selectKey(if viewId == "main" then "centre" else "home")
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
		local hex = if key then v.byKey[key] else nil
		return if hex then hex.button else nil
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

	-- Buttons hold a HitPad (a transparent button built in Studio) that keeps the touch target at
	-- least 44 px on phones. The pad takes mouse and touch; the button itself still takes gamepad
	-- selection, so both run fn.
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
	card.assign.Activated:Connect(assign)
	card.frame.MouseEnter:Connect(function()
		overCard = true
	end)
	card.frame.MouseLeave:Connect(function()
		overCard = false
	end)

	-- Drag to pan a view bigger than the board (phones), from anywhere on it, hexes included; a
	-- press that moves more than DRAG_SLOP pixels drags instead of clicking.
	local drag: InputObject? = nil
	local dragFrom, panFrom = Vector3.zero, Vector2.zero
	local function onBoard(position: Vector3): boolean
		local at, size = board.AbsolutePosition, board.AbsoluteSize
		return position.X >= at.X and position.Y >= at.Y and position.X <= at.X + size.X and position.Y <= at.Y + size.Y
	end
	UserInputService.InputBegan:Connect(function(inputObject)
		local kind = inputObject.UserInputType
		if open and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and onBoard(inputObject.Position) then
			drag, dragFrom, panFrom, dragMoved = inputObject, inputObject.Position, Vector2.new(panX, panY), false
		end
	end)
	UserInputService.InputChanged:Connect(function(inputObject)
		if not drag or not (inputObject.UserInputType == Enum.UserInputType.MouseMovement or inputObject == drag) then
			return
		end
		local delta = inputObject.Position - dragFrom
		dragMoved = dragMoved or delta.Magnitude > DRAG_SLOP
		local v = views[viewId]
		if not (dragMoved and v and v.pans) then
			return
		end
		panX, panY = panFrom.X + delta.X, panFrom.Y + delta.Y
		clampPan(v)
	end)
	UserInputService.InputEnded:Connect(function(inputObject)
		if inputObject == drag or inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
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
		-- Hex scales: hover / press / gamepad selection / breathing (all "buy" hexes in step) times
		-- any animation.
		local breathe = 1 + (CUE.breatheScale - 1) * (0.5 - 0.5 * math.cos(now * 2 * math.pi / CUE.breatheSeconds))
		local rate = math.min(1, dt * PRESS_RATE)
		local hoverHex: Hex.Hex? = nil
		for _, hex in v.hexes do
			local selected = hex.key ~= nil and hex.key == selectedKey
			local target = if hex.down then motion.pressScale elseif hex.hover or (selected and input == "gamepad") then motion.hoverScale elseif hex.breathe then breathe else 1
			hex.ease += (target - hex.ease) * rate
			set(hex.press, "Scale", math.round(hex.base * hex.ease * Hex.animScale(hex, now) * 1000) / 1000)
			set(hex.select, "Visible", hex.hover or selected)
			if hex.hover then
				hoverHex = hex
			end
		end
		-- The card follows the hovered link (mouse), else the selected one; it stays while the mouse
		-- is on its Assign button.
		local key = if hoverHex and input == "mouse" and hoverHex.key and infos[hoverHex.key] then hoverHex.key else selectedKey
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
