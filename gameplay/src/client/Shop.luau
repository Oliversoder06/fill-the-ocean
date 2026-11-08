-- The shop menu (StarterGui.Hud.Shop, built in Studio in the sunbaked-sea style). Tab, gamepad Y or
-- the on-screen Shop button opens and closes it during a run (client/Window: the frame pops in,
-- then its parts appear layer by layer). One tile per upgrade track (Tool and
-- Boosts panels, from Config.tracks); clicking a tile shows it in the detail panel, whose Buy button
-- sends Buy(trackId). The server checks every buy.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
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

local Shop = {}

-- Art for each track until real upgrade icons are drawn (the tool shows its 3D model instead).
local ICONS = { pickup = "pipFull", hold = "unknown", quick = "unknown", walk = "unknown", tip = "coin" }
local PANEL_NAMES = { tool = "Tool", boosts = "Boosts" }

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

-- What the next level changes, from the stats now and after buying it.
local function effectText(id: string, now: Ladder.Stats, after: Ladder.Stats): string
	if id == "tool" then
		return `{short(after.capacity)} L per trip, {scoops(after.sweeps)} to fill (now {short(now.capacity)} L)`
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

-- Where a locked level opens: "Opens at 22% full" (its area's stand-in fill point).
local function opensText(level): string
	return `Opens at {math.round(Config.ocean.standInOpens[level.area - 1] * 100)}% full`
end

-- The next level's display name: tools have their own, the rest are "<track> <n>".
local function levelName(track, n: number, level): string
	if track.id == "tool" then
		return level.name
	end
	return if #track.levels == 1 then track.name else `{track.name} {n}`
end

local function bounce(scale: UIScale)
	scale.Scale = 1.12
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function Shop.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Buy") :: RemoteEvent
	local shop = Hud.find(gui, "Shop")
	local fit = Hud.find(gui, "Shop.Scale")
	local content = Hud.find(gui, "Shop.Body.Content")
	local detail = Hud.find(content, "Detail")
	local detailArt = Hud.find(detail, "Art")
	local buyButton = Hud.find(detail, "BuyButton")
	local buyText = Hud.find(buyButton, "Row.BuyText")
	local buyCoin = Hud.find(buyButton, "Row.Coin")
	local buyPrice = Hud.find(buyButton, "Row.Price")
	local closeButton = Hud.find(shop, "CloseButton")
	local tiles = {}
	for _, track in Config.tracks do
		local panel = if track.panel == "tool" then "ToolPanel" else "BoostPanel"
		tiles[track.id] = Hud.find(content, `{panel}.Tiles.{track.id}`)
	end
	local selected = "tool"

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
	local function setOpen(value: boolean)
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

	-- The Upgrades button (right edge) shows where the shop is. Holding Tab / Y / the mouse / a
	-- finger squishes it down; letting go springs it back up and opens (or closes) the shop. Its key
	-- tag tells keyboard and gamepad players which key does it.
	local upgrades = Hud.find(gui, "UpgradesButton")
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
		elseif inputState == Enum.UserInputState.End then
			release(true)
		elseif inputState == Enum.UserInputState.Cancel then
			release(false) -- focus lost while held: spring back, don't open
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
	for id, holder in tiles do
		local button = Hud.find(holder, "Button")
		pressable(button, button.Press)
		button.Activated:Connect(function()
			selected = id
		end)
	end
	onPress(buyButton, function()
		local _, _, canBuy = Hud.offer(levelsOf(), selected, player:GetAttribute("Money") or 0)
		if canBuy then
			bounce(buyButton.Press)
		else
			Purchase.deny(buyButton)
		end
		buyRemote:FireServer(selected)
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

	local shownLevels: { [string]: number } = {}
	RunService.RenderStepped:Connect(function()
		if open and not inRun() then
			setOpen(false)
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

		for _, track in Config.tracks do
			local id = track.id
			local holder = tiles[id]
			local button = Hud.find(holder, "Button")
			local have = levels[id]
			local level, status, affordable = Hud.offer(levels, id, money)
			set(button, "ImageColor3", if status == "locked" then colors.locked else panelColor(track))
			set(Hud.find(button, "Ring"), "Visible", id == selected)
			showArt(button, id, now.toolModel, status == "locked")
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
				set(label, "Text", `Lv {now.toolTier}`)
			else
				set(label, "Text", if have > 0 then "OWNED" else "")
			end
			shownLevels[id] = have

			-- Price row: the price (red when you can't afford it), MAX, or the fill that unlocks it
			local priceText = Hud.find(holder, "PriceRow.Price")
			set(Hud.find(holder, "PriceRow.Coin"), "Visible", status == "buy")
			set(priceText, "Text", if status == "buy" then Hud.money(level.cost) elseif status == "max" then "MAX" else opensText(level))
			set(priceText, "TextColor3", if status == "buy" and not affordable then colors.buyCoral else colors.foam)
		end

		-- Detail panel: the selected track's next level
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
			set(Hud.find(detail, "ItemName"), "Text", levelName(track, have + 1, level))
			set(Hud.find(detail, "Effect"), "Text", effectText(selected, now, Ladder.stats(Config, nextLevels)))
		else
			showArt(detailArt, selected, now.toolModel)
			set(Hud.find(detail, "ItemName"), "Text", if selected == "tool" then now.toolName else track.name)
			set(Hud.find(detail, "Effect"), "Text", "All levels bought!")
		end
		set(buyCoin, "Visible", status == "buy")
		set(buyPrice, "Visible", status == "buy")
		set(buyText, "Text", if status == "buy" then "BUY" elseif status == "max" then "MAXED" else opensText(level):upper())
		if status == "buy" then
			set(buyPrice, "Text", Hud.money(level.cost))
		end
		set(buyButton, "ImageColor3", if canBuy then colors.buyCoral else colors.locked)
	end)
end

return Shop
