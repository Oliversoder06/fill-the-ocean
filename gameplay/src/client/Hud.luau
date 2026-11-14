-- Fills in the HUD that lives in StarterGui ("Hud", built in Studio) from server attributes:
-- wallet, waiting text, card, and the run panel at the top right (stopwatch from PlaySeconds and
-- RunStartedAt, the map's name, how full the ocean is and its litres, a running boost's countdown).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Boosts = require(ReplicatedStorage.Shared.Boosts)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Ease = require(ReplicatedStorage.Shared.Ease)
local Format = require(ReplicatedStorage.Shared.Format)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local PourFlow = require(ReplicatedStorage.Shared.PourFlow)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["clear-tide"])

local player = Players.LocalPlayer
local Hud = {}

local COIN_BOUNCE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PROGRESS_POP = TweenInfo.new(Ease.POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Studs from a Source or Pour / from where the water will be within which a player scoops or pours
-- (client Action and Guide); the server uses the same (shared/Zones).
Hud.REACH = Zones.REACH

-- Stopwatch text: 4:05, then 1:04:05 past an hour.
function Hud.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h, m = s // 3600, (s // 60) % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

-- 1.2K and money (12,480, then 1.2M): shared/Format, the same words the server's cards use.
Hud.short = Format.short
Hud.money = Format.money

function Hud.find(parent: Instance, path: string): any
	local node = parent
	for name in path:gmatch("[^%.]+") do
		local child = node:FindFirstChild(name)
		assert(child, `Hud is missing {path} (StarterGui.Hud is built in Studio)`)
		node = child
	end
	return node
end

-- Sets a property only when it changes (this runs every frame).
function Hud.set(obj: Instance, prop: string, value: any)
	if (obj :: any)[prop] ~= value then
		(obj :: any)[prop] = value
	end
end

-- The ocean's model (workspace.Ocean), or nil until it has replicated. Non-yielding.
function Hud.ocean(): Model?
	local model = workspace:FindFirstChild("Ocean")
	return if model and model:IsA("Model") then model else nil
end

-- The save's upgrade levels by track id (the team's), from the ReplicatedStorage Level_<track>
-- attributes. A missing one counts as `fallback`; with no fallback the whole table is nil until the
-- server has published them all.
function Hud.levels(fallback: number?): { [string]: number }?
	local levels = {}
	for _, track in Config.tracks do
		local level = ReplicatedStorage:GetAttribute(`Level_{track.id}`)
		if type(level) ~= "number" then
			if fallback == nil then
				return nil
			end
			level = fallback
		end
		levels[track.id] = level
	end
	return levels
end

-- Area ids from a ReplicatedStorage attribute the server publishes as "2,3".
local function areaIds(name: string): { number }
	local ids = {}
	local text = ReplicatedStorage:GetAttribute(name)
	if type(text) == "string" then
		for id in text:gmatch("%d+") do
			table.insert(ids, tonumber(id) :: number)
		end
	end
	return ids
end

-- The open gates (area ids) from the server's GatesOpen attribute ("2,3").
function Hud.gatesOpen(): { number }
	return areaIds("GatesOpen")
end

-- The team's items (common/Items state) from the ReplicatedStorage Owned and ItemLevel_<id> attributes.
function Hud.items(): Items.State
	local owned = {}
	local text = ReplicatedStorage:GetAttribute("Owned")
	if type(text) == "string" then
		for id in text:gmatch("[^,]+") do
			table.insert(owned, id)
		end
	end
	local itemLevels = {}
	for _, item in Config.items do
		local level = ReplicatedStorage:GetAttribute(`ItemLevel_{item.id}`)
		itemLevels[item.id] = if type(level) == "number" then level else 0
	end
	return { owned = owned, itemLevels = itemLevels }
end

-- The team's coins (the server's Wallet attribute).
function Hud.wallet(): number
	local coins = ReplicatedStorage:GetAttribute("Wallet")
	return if type(coins) == "number" then coins else 0
end

-- The save's team size (the server's TeamSize attribute; 1 until it is published).
function Hud.teamSize(): number
	local size = ReplicatedStorage:GetAttribute("TeamSize")
	return if type(size) == "number" then size else 1
end

-- What a listed price (Config) costs this team (Items.price): every price shown goes through it.
function Hud.price(cost: number): number
	return Items.price(Config, cost, Hud.teamSize())
end

-- The team's buildings (save.buildings: upgrades bought per building id, only the ones built) from
-- the server's BuildingLevel_<id> attributes (server/Buildings).
function Hud.buildings(): { [string]: number }
	local levels = {}
	for _, item in Config.items do
		local level = if item.kind == "building" then ReplicatedStorage:GetAttribute(`BuildingLevel_{item.id}`) else nil
		if type(level) == "number" then
			levels[item.id] = level
		end
	end
	return levels
end

-- The attributes offers read (items, buildings, the areas the open gates open, the team's size), read
-- once per refresh and passed to every Hud.offer / Stands.offer of it.
export type Snapshot = { items: Items.State, buildings: { [string]: number }, openAreas: number, teamSize: number }

function Hud.snapshot(): Snapshot
	return { items = Hud.items(), buildings = Hud.buildings(), openAreas = Ladder.openAreas(Config, Hud.gatesOpen()), teamSize = Hud.teamSize() }
end

-- What TAB offers next and whether `money` buys it now at the team's price (Hud.price), with the
-- areas the open gates open (as the server counts them): Items.tabOffer's level and status (a track:
-- "buy" / "locked" / "max" / "useless"; an item: "buy" / "max" / "replaced" / "stand" / "locked";
-- a building: "buy" / "max" / "unbuilt" / "locked"). `snap`: Hud.snapshot (nil reads it now).
function Hud.offer(levels: { [string]: number }, id: string, money: number, snap: Snapshot?): (any, string?, boolean)
	local s = snap or Hud.snapshot()
	local level, status = Items.tabOffer(Config, levels, s.items, s.buildings, id, s.openAreas, Ladder.helps(Config, levels, id))
	return level, status, status == "buy" and Items.affords(money, Items.price(Config, level.cost, s.teamSize))
end

-- The open area the local player reaches (Items.reachable: Cloud Catcher needs the Jetpack Tank)
-- whose `name` part (Source, Pour or Tap) is within `reach` studs (Hud.REACH by default) of
-- `position`, and that part (Zones.openSpot, as the server checks it).
function Hud.openSpot(ocean: Model, name: string, position: Vector3, reach: number?)
	local reached = Areas.open(Items.reachable(Config, Hud.items(), Areas.openIds(Hud.gatesOpen())))
	return Zones.openSpot(ocean, Config, reached, name, position, reach or Hud.REACH)
end

-- Where the local player at `position` scoops (Zones.scoopSpot, as the server checks it): the open
-- area, the part (its Source, or a DeepPool behind a broken rock from the RocksBroken attribute) and
-- whether it is a deep pool. With the Cloud Net the drifting cloud is in reach from the net's range.
function Hud.scoopSpot(ocean: Model, position: Vector3)
	local items = Hud.items()
	local reached = Areas.open(Items.reachable(Config, items, Areas.openIds(Hud.gatesOpen())))
	local net = Items.gadgetStat(Config, items, "cloudNet", "range")
	return Zones.scoopSpot(ocean, Config, reached, areaIds("RocksBroken"), position, Hud.REACH, net)
end

-- What may stand on the ground a pour lands on: the camera and every player's character.
local function pourIgnore(): { Instance }
	local ignore: { Instance } = { workspace.CurrentCamera }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	return ignore
end

-- Whether a character at `position` may pour from `reach` studs (Hud.REACH by default; the Water
-- Gun's range): by an open area's Pour, or next to where the water will be, past the camera and
-- every player's character (the same check Action offers the pour with).
function Hud.nearPour(ocean: Model, position: Vector3, reach: number?): boolean
	if Hud.openSpot(ocean, "Pour", position, reach) then
		return true
	end
	return Zones.nearFlood(ocean, position, reach or Hud.REACH, pourIgnore())
end

-- Where a pour from `position` lands when the look doesn't reach the water: the ground within
-- `reach` that will flood, most in the direction `toward` (Zones.floodPoint).
function Hud.floodPoint(ocean: Model, position: Vector3, reach: number?, toward: Vector3): Vector3?
	return Zones.floodPoint(ocean, position, reach or Hud.REACH, pourIgnore(), toward)
end

-- Grows on hover, shrinks while pressed (motion values from the style).
function Hud.pressable(button: GuiButton, scale: UIScale)
	local hovered = false
	local function to(value: number)
		TweenService:Create(scale, PRESS, { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		hovered = true
		to(Theme.motion.hoverScale)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		to(Theme.motion.pressScale)
	end)
	button.MouseButton1Up:Connect(function()
		to(if hovered then Theme.motion.hoverScale else 1)
	end)
end
-- Money still flying in as coins (client/Payout): the wallet shows Wallet minus this, so it counts
-- up coin by coin instead of jumping when the server pays.
Hud.walletHold = 0

-- The waiting room's words (the HUD's Waiting line, client/Arrival's screen): the server's Waiting
-- text is a party count ("2/3") or a message.
function Hud.waitingText(): string
	local waitText = ReplicatedStorage:GetAttribute("Waiting")
	return if type(waitText) ~= "string" or waitText == "" then "Get ready..." elseif waitText:match("^%d+/%d+$") then `Waiting for your friends... {waitText}` else waitText
end

-- client/Intro is on screen (the team's intro or an admin's preview, which plays while the run does):
-- acting, the honeycomb, staff bodies, stand signs and the guide's lane stand down meanwhile.
Hud.cutscene = false

local fillPop: UIScale? = nil -- the fill bar's Progress.Bar.Pop, once Hud.start has found it

-- The HUD is laid out for screens DESIGN_HEIGHT tall: a smaller one (a phone) shrinks all of it
-- (Hud.Scale, a UIScale on the ScreenGui), a touch-only tablet grows it a little.
local DESIGN_HEIGHT = 600
local MIN_SCALE = 0.55
local TOUCH_MAX_SCALE = 1.25
local SMALL_SCALE = 0.75 -- below this the HUD drops its small print (litres, areas open)
local hudScale: UIScale? = nil

-- The HUD's scale: code that turns screen pixels (AbsolutePosition, input) into offsets divides by it.
function Hud.uiScale(): number
	return if hudScale then hudScale.Scale else 1
end

-- Offset pixels a full-screen cover overhangs its ScreenGui by: more than any top bar, notch or
-- rounded corner at any HUD scale (MIN_SCALE shrinks the gui's units, so it's generous).
Hud.BLEED = 4000

-- Makes a full-screen cover in a safe-area ScreenGui (the Hud) reach every physical edge: the
-- gui's default insets stop "full size" under the top bar and short of a phone's notch, and its
-- ClipToDeviceSafeArea cuts any overhang off, so turn the clipping off and overhang by BLEED.
function Hud.bleed(cover: GuiObject)
	local screen = cover:FindFirstAncestorWhichIsA("ScreenGui")
	assert(screen, `{cover:GetFullName()} is not in a ScreenGui`)
	screen.ClipToDeviceSafeArea = false
	cover.AnchorPoint = Vector2.zero
	cover.Position = UDim2.fromOffset(-Hud.BLEED, -Hud.BLEED)
	cover.Size = UDim2.new(1, Hud.BLEED * 2, 1, Hud.BLEED * 2)
end

-- Paints a keycap (a `Key` frame, the dark lip, over its `Text` label, the white face; built in
-- Studio, sized by AutomaticSize) from the theme, so a key to press reads as a key.
function Hud.paintKey(key: Instance)
	local face = Hud.find(key, "Text") :: TextLabel
	local outline = key:FindFirstChildOfClass("UIStroke")
	assert(key:IsA("GuiObject") and outline, `{key:GetFullName()} must be a keycap Frame with a UIStroke`)
	key.BackgroundColor3 = Theme.colors.shadow
	outline.Color = Theme.colors.shadow
	face.BackgroundColor3 = Theme.colors.text
	face.TextColor3 = Theme.colors.shadow
	face.FontFace = Theme.fonts.title
end

-- What the player plays with, for words and key tags: the last input, but always touch on a
-- touch-only device (a phone reports no Touch until its first tap).
function Hud.input(): "touch" | "gamepad" | "mouse"
	local last = UserInputService:GetLastInputType()
	if last.Name:sub(1, 7) == "Gamepad" then
		return "gamepad"
	elseif last == Enum.UserInputType.Touch or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		return "touch"
	end
	return "mouse"
end

-- Pours on their way down a channel (client/Channels): their landing pulses the bar, so the Fill rise
-- doesn't pop it too.
Hud.wavesInFlight = 0

-- Pulses the fill bar as poured water reaches the ocean (client/Channels); bigger pours pulse more.
function Hud.pulseFill(litres: number)
	if fillPop then
		fillPop.Scale = PourFlow.pulse(Cues.channel, litres)
		TweenService:Create(fillPop, PROGRESS_POP, { Scale = 1 }):Play()
	end
end

local find, set = Hud.find, Hud.set

function Hud.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local cardEvent = remotes:WaitForChild("Card") :: RemoteEvent
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")

	local scale = find(gui, "Scale") :: UIScale
	hudScale = scale
	local function fitScreen()
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local fitted = workspace.CurrentCamera.ViewportSize.Y / DESIGN_HEIGHT
		set(scale, "Scale", math.round(math.clamp(fitted, MIN_SCALE, if touchOnly then TOUCH_MAX_SCALE else 1) * 100) / 100)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScreen)
	fitScreen()
	local walletFrame = find(gui, "Wallet")
	local coins = find(walletFrame, "Pill.Coins")
	local coinPop = find(walletFrame, "Coin.Pop")
	local shownMoney = math.max(0, Hud.wallet() - Hud.walletHold)
	local cardLabel = find(gui, "Card")
	local waiting = find(gui, "Waiting")
	local progress = find(gui, "Progress")
	local timeText = find(progress, "Time")
	local areaText = find(progress, "Area")
	local areaSub = find(progress, "AreaSub")
	local boostTag = find(progress, "BoostTag")
	local progressFill = find(progress, "Bar.Fill")
	local progressLabel = find(progress, "Bar.Label")
	local progressPop = find(progress, "Bar.Pop")
	fillPop = progressPop
	local litresLabel = find(progress, "Bar.Litres")
	local shownFill, fillFrom, fillTo, fillChangedAt = 0, 0, 0, -math.huge

	local cardToken = 0
	cardEvent.OnClientEvent:Connect(function(text: string, seconds: number)
		cardToken += 1
		local token = cardToken
		cardLabel.Text = text
		cardLabel.Visible = true
		task.delay(seconds, function()
			if token == cardToken then
				cardLabel.Visible = false
			end
		end)
	end)

	-- Windows (honeycomb, admin, build picker) free the cursor. First person locks it to the centre every frame, so
	-- this runs right after the camera and overrides that while a window is showing. In play the
	-- mouse icon is hidden and the place's cursor image (StarterGui.Cursor) marks where you aim.
	local windows = { find(gui, "Honeycomb"), find(gui, "Admin"), find(gui, "BuildPicker") }
	local honeycomb = windows[1]
	local crosshair = find(player:WaitForChild("PlayerGui"):WaitForChild("Cursor"), "Cursor")
	RunService:BindToRenderStep("HudCursor", Enum.RenderPriority.Camera.Value + 3, function()
		local windowOpen = false
		for _, window in windows do
			if window.Visible then
				windowOpen = true
				break
			end
		end
		if windowOpen then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		-- Driving is third person (client/CameraFeel): the camera frees the mouse and nothing is aimed.
		local cursorFree = windowOpen or player.CameraMode ~= Enum.CameraMode.LockFirstPerson
		set(UserInputService, "MouseIconEnabled", cursorFree)
		set(crosshair, "Visible", not cursorFree)
	end)

	local finalTime: number? = nil -- time played as last shown while playing
	local shownGates: any = false -- the GatesOpen the area subtitle shows (false: none yet)
	RunService.RenderStepped:Connect(function()
		local phase = ReplicatedStorage:GetAttribute("Phase")

		-- Wallet: the team's coins (hidden under the honeycomb, which shows its own)
		set(walletFrame, "Visible", not honeycomb.Visible)
		local money = math.max(0, Hud.wallet() - Hud.walletHold)
		set(coins, "Text", Hud.money(money))
		if money > shownMoney + 1e-6 then -- earned (each landing coin): the coin bounces
			coinPop.Scale = 1.25
			TweenService:Create(coinPop, COIN_BOUNCE, { Scale = 1 }):Play()
		end
		shownMoney = money

		-- Waiting room (the server's Waiting text, Hud.waitingText)
		set(waiting, "Visible", phase == "loading")
		set(waiting, "Text", Hud.waitingText())

		-- Run panel: the map's name and how many areas are open, how full the ocean is (inside the
		-- bar), stopwatch (time played on this save) (hidden under the honeycomb's full-screen cover)
		local startedAt = ReplicatedStorage:GetAttribute("RunStartedAt")
		set(progress, "Visible", type(startedAt) == "number" and not honeycomb.Visible)
		if type(startedAt) == "number" then
			-- The server stops counting at the ending, so the clock freezes on the last time played.
			if phase == "playing" or not finalTime then
				local played = ReplicatedStorage:GetAttribute("PlaySeconds")
				finalTime = (if type(played) == "number" then played else 0) + workspace:GetServerTimeNow() - startedAt
			end
			set(timeText, "Text", Hud.clock(finalTime))
			local mapName = ReplicatedStorage:GetAttribute("MapName")
			set(areaText, "Text", if type(mapName) == "string" then mapName else "")
			local gates = ReplicatedStorage:GetAttribute("GatesOpen")
			if gates ~= shownGates then
				shownGates = gates
				areaSub.Text = `AREAS {Ladder.openAreas(Config, Hud.gatesOpen())}/{#Config.areas} OPEN`
			end
			set(areaSub, "Visible", Hud.uiScale() >= SMALL_SCALE)
			-- A running fill-milestone boost shows its countdown in the boost tag.
			local boost = ReplicatedStorage:GetAttribute("Boost")
			local endsAt = ReplicatedStorage:GetAttribute("BoostEndsAt")
			local kind = if type(boost) == "string" and boost ~= "" then Boosts.kind(Config, boost) else nil
			set(boostTag, "Visible", kind ~= nil and type(endsAt) == "number")
			if kind and type(endsAt) == "number" then
				set(boostTag, "Text", `{kind.tag} {math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))}s`)
			end
			local fill = ReplicatedStorage:GetAttribute("Fill")
			local target = if type(fill) == "number" then math.clamp(fill, 0, 1) else 0
			local clock = os.clock()
			if target ~= fillTo then
				if target > fillTo and Hud.wavesInFlight == 0 then
					progressPop.Scale = 1.06
					TweenService:Create(progressPop, PROGRESS_POP, { Scale = 1 }):Play()
				end
				fillFrom, fillTo, fillChangedAt = shownFill, target, clock
			end
			shownFill = math.clamp(Ease.pop(fillFrom, fillTo, clock - fillChangedAt), 0, 1)
			set(progressFill, "Size", UDim2.fromScale(shownFill, 1))
			set(progressFill, "Visible", shownFill > 0)
			set(progressLabel, "Text", `{Format.fill(target)} filled`)
			local current, goal = ReplicatedStorage:GetAttribute("Current"), ReplicatedStorage:GetAttribute("Target")
			local known = type(current) == "number" and type(goal) == "number"
			set(litresLabel, "Visible", known and Hud.uiScale() >= SMALL_SCALE)
			if known then
				set(litresLabel, "Text", `{Format.litres(current)} / {Format.litres(goal)} L`)
			end
		end

	end)
end

return Hud
