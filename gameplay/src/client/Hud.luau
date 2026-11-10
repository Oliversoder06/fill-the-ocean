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
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])

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
-- areas the open gates open (as the
-- server counts them). A track (`levels`): Ladder.offer's level and "buy" / "locked" / "max", or
-- "useless" while the level would change nothing (Ladder.helps; the server doesn't sell it). An
-- item: Items.nextLevel's upgrade and "buy" / "max" / "replaced", or, while unowned, nil and
-- "stand" (buy it at its area's stand) or "locked" (its area is closed). A building: the team's
-- Items.buildingOffer ("buy" / "max" / "unbuilt" / "locked"). `snap`: Hud.snapshot (nil reads it now).
function Hud.offer(levels: { [string]: number }, id: string, money: number, snap: Snapshot?): (any, string?, boolean)
	local s = snap or Hud.snapshot()
	local level, status
	local item = Items.get(Config, id)
	if Config.track(id) then
		level, status = Ladder.offer(Config, levels, id, s.openAreas)
		if status == "buy" and not Ladder.helps(Config, levels, id) then
			status = "useless"
		end
	elseif item and item.kind == "building" then
		level, status = Items.buildingOffer(Config, s.buildings, id, s.openAreas)
	else
		level, status = Items.nextLevel(Config, s.items, id)
		if status == "unowned" then
			status = if (item :: Config.Item).area <= s.openAreas then "stand" else "locked"
		end
	end
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

-- Whether a character at `position` may pour from `reach` studs (Hud.REACH by default; the Water
-- Gun's range): by an open area's Pour, or next to where the water will be, past the camera and
-- every player's character (the same check Action offers the pour with).
function Hud.nearPour(ocean: Model, position: Vector3, reach: number?): boolean
	if Hud.openSpot(ocean, "Pour", position, reach) then
		return true
	end
	local ignore: { Instance } = { workspace.CurrentCamera }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	return Zones.nearFlood(ocean, position, reach or Hud.REACH, ignore)

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

local fillPop: UIScale? = nil -- the fill bar's Progress.Bar.Pop, once Hud.start has found it

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

	local coins = find(gui, "Wallet.Pill.Coins")
	local coinPop = find(gui, "Wallet.Coin.Pop")
	local shownMoney = math.max(0, Hud.wallet() - Hud.walletHold)
	local cardLabel = find(gui, "Card")
	local waiting = find(gui, "Waiting")
	local progress = find(gui, "Progress")
	local timeText = find(progress, "TimeRow.Time")
	local placeText = find(progress, "PlaceRow.Place")
	local boostTag = find(progress, "BoostTag")
	local progressFill = find(progress, "Bar.Fill")
	local progressLabel = find(progress, "Bar.Label")
	local progressPop = find(progress, "Bar.Pop")
	fillPop = progressPop
	local litresLabel = find(progress, "Litres")
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
	RunService.RenderStepped:Connect(function()
		local phase = ReplicatedStorage:GetAttribute("Phase")

		-- Wallet: the team's coins
		local money = math.max(0, Hud.wallet() - Hud.walletHold)
		set(coins, "Text", Hud.money(money))
		if money > shownMoney + 1e-6 then -- earned (each landing coin): the coin bounces
			coinPop.Scale = 1.25
			TweenService:Create(coinPop, COIN_BOUNCE, { Scale = 1 }):Play()
		end
		shownMoney = money

		-- Waiting room: the server's Waiting text is a party count ("2/3") or a message
		local waitText = ReplicatedStorage:GetAttribute("Waiting")
		set(waiting, "Visible", phase == "loading")
		set(waiting, "Text", if type(waitText) ~= "string" or waitText == "" then "Get ready..." elseif waitText:match("^%d+/%d+$") then `Waiting for your friends... {waitText}` else waitText)

		-- Run panel: stopwatch (time played on this save), the map's name, how full the ocean is
		local startedAt = ReplicatedStorage:GetAttribute("RunStartedAt")
		set(progress, "Visible", type(startedAt) == "number")
		if type(startedAt) == "number" then
			-- The server stops counting at the ending, so the clock freezes on the last time played.
			if phase == "playing" or not finalTime then
				local played = ReplicatedStorage:GetAttribute("PlaySeconds")
				finalTime = (if type(played) == "number" then played else 0) + workspace:GetServerTimeNow() - startedAt
			end
			set(timeText, "Text", Hud.clock(finalTime))
			local mapName = ReplicatedStorage:GetAttribute("MapName")
			set(placeText, "Text", if type(mapName) == "string" then mapName else "")
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
			set(litresLabel, "Visible", known)
			if known then
				set(litresLabel, "Text", `{Format.litres(current)} / {Format.litres(goal)} L`)
			end
		end

	end)
end

return Hud
