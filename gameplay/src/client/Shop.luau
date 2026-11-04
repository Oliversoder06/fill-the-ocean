-- The shop menu (StarterGui.Hud.Shop, built in Studio in the sunbaked-sea style). Tab, gamepad Y or
-- the on-screen Shop button opens and closes it during a run. Shows the next item to buy, the
-- three after it, and the player's gear. Buying still fires the one Buy remote; the server checks it.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Hud = require(script.Parent.Hud)

local player = Players.LocalPlayer
local colors, images, motion = Theme.colors, Theme.images, Theme.motion
local short, set = Hud.short, Hud.set

local DESIGN_SIZE = Vector2.new(1000, 660) -- the shop plus room for its decorations
local POP = TweenInfo.new(motion.openSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHRINK = TweenInfo.new(motion.closeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local QUICK = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Shop = {}

local function effectText(item, capacity: number, walkSpeed: number, act: number): string
	if item.kind == "tool" then
		return `{short(item.capacity)} L per trip (now {short(capacity)} L)`
	elseif item.kind == "walk" then
		return `Walk speed {short(item.walkSpeed)} (now {short(walkSpeed)})`
	end
	return `Scoop and pour in {item.actSeconds}s (now {act}s)`
end

local function boughtPerStage(): { number }
	local bought = {}
	for s = 1, #Config.stages do
		bought[s] = player:GetAttribute(`Bought{s}`) or 0
	end
	return bought
end

-- Grows on hover, shrinks while pressed (motion values from the style).
local function pressable(button: GuiButton, scale: UIScale)
	local hovered = false
	local function to(value: number)
		TweenService:Create(scale, QUICK, { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		hovered = true
		to(motion.hoverScale)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		to(motion.pressScale)
	end)
	button.MouseButton1Up:Connect(function()
		to(if hovered then motion.hoverScale else 1)
	end)
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
	local nextPanel = Hud.find(gui, "Shop.Body.Content.Next")
	local itemName = Hud.find(nextPanel, "ItemName")
	local itemIcon = Hud.find(nextPanel, "Tile.ItemIcon")
	local effect = Hud.find(nextPanel, "Effect")
	local buyButton = Hud.find(nextPanel, "BuyButton")
	local buyText = Hud.find(buyButton, "Row.BuyText")
	local buyCoin = Hud.find(buyButton, "Row.Coin")
	local buyPrice = Hud.find(buyButton, "Row.Price")
	local moneyLabel = Hud.find(nextPanel, "MoneyRow.Money")
	local slots = Hud.find(gui, "Shop.Body.Content.Upcoming.Slots")
	local gear = Hud.find(gui, "Shop.Body.Content.Gear")
	local toolValue = Hud.find(gear, "ToolRow.Value")
	local closeButton = Hud.find(shop, "CloseButton")

	-- Tab would also toggle Roblox's player list; the game has its own Board, so hide that list.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

	local open = false
	local fitScale = 1
	local function refit()
		local view = workspace.CurrentCamera.ViewportSize
		fitScale = math.min(view.X / DESIGN_SIZE.X, view.Y / DESIGN_SIZE.Y, 1)
		if open then
			fit.Scale = fitScale
		end
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	refit()

	local closeToken = 0
	local function setOpen(value: boolean)
		if value == open then
			return
		end
		open = value
		closeToken += 1
		if value then
			shop.Visible = true
			fit.Scale = fitScale * 0.85
			TweenService:Create(fit, POP, { Scale = fitScale }):Play()
		else
			local token = closeToken
			TweenService:Create(fit, SHRINK, { Scale = fitScale * 0.85 }):Play()
			task.delay(motion.closeSeconds, function()
				if token == closeToken then
					shop.Visible = false
				end
			end)
		end
	end

	local function inRun(): boolean
		local phase = ReplicatedStorage:GetAttribute("Phase")
		return phase == "playing" or phase == "card"
	end

	ContextActionService:BindAction("ToggleShop", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			setOpen(not open and inRun())
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.Tab, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle("ToggleShop", "Shop")

	pressable(buyButton, buyButton.Press)
	pressable(closeButton, closeButton.Press)
	closeButton.Activated:Connect(function()
		setOpen(false)
	end)
	buyButton.Activated:Connect(function()
		local cost = player:GetAttribute("NextItemCost") or -1
		if cost >= 0 and (player:GetAttribute("Money") or 0) + 1e-6 >= cost then
			bounce(buyButton.Press)
		end
		buyRemote:FireServer()
	end)

	local shownBought = { walk = -1, hands = -1 }
	local function renderPips(row: Instance, kind: string, bought: { number })
		local have, total = Ladder.kindProgress(Config, bought, kind)
		local pips = Hud.find(row, "Pips")
		for _, pip in pips:GetChildren() do
			if pip:IsA("ImageLabel") then
				local n = pip.LayoutOrder
				set(pip, "Visible", n <= total)
				set(pip, "Image", if n <= have then images.pipFull else images.pipEmpty)
			end
		end
		if shownBought[kind] >= 0 and have > shownBought[kind] then
			local pip = pips:FindFirstChild(`Pip{have}`)
			if pip then
				bounce(pip.Pop)
			end
		end
		shownBought[kind] = have
	end

	RunService.RenderStepped:Connect(function()
		if open and not inRun() then
			setOpen(false)
		end
		if not shop.Visible then
			return
		end
		local money = player:GetAttribute("Money") or 0
		local capacity = player:GetAttribute("Capacity") or Config.start.capacity
		local walkSpeed = player:GetAttribute("WalkSpeed") or Config.start.walkSpeed
		local act = player:GetAttribute("ActSeconds") or Config.start.actSeconds
		local stage = ReplicatedStorage:GetAttribute("Stage") or 0
		local bought = boughtPerStage()
		local list = Ladder.upcoming(Config, stage, bought, 4)

		-- Next up
		local nextItem = list[1] and list[1].item
		set(moneyLabel, "Text", Hud.money(money))
		set(itemIcon, "Image", images.unknown) -- upgrade icons are not drawn yet
		if nextItem then
			local canBuy = money + 1e-6 >= nextItem.cost
			set(itemName, "Text", nextItem.name)
			set(effect, "Text", effectText(nextItem, capacity, walkSpeed, act))
			set(buyText, "Text", "BUY")
			set(buyPrice, "Text", Hud.money(nextItem.cost))
			set(buyCoin, "Visible", true)
			set(buyPrice, "Visible", true)
			set(buyButton, "ImageColor3", if canBuy then colors.buyCoral else colors.locked)
		else
			set(itemName, "Text", "Everything bought!")
			set(effect, "Text", "")
			set(buyText, "Text", "MAXED")
			set(buyCoin, "Visible", false)
			set(buyPrice, "Visible", false)
			set(buyButton, "ImageColor3", colors.locked)
		end

		-- Coming up: tools with a new model stay a surprise until they are next
		local model = player:GetAttribute("ToolModel") or Config.start.toolModel
		for i = 1, 3 do
			local slot = Hud.find(slots, `Slot{i}`)
			local entry = list[i + 1]
			set(slot, "Visible", entry ~= nil)
			if entry then
				local item = entry.item
				local secret = item.kind == "tool" and item.model ~= model
				set(slot.ItemName, "Text", if secret then "???" else item.name)
				set(slot.Tile.Icon, "Image", if secret then images.unknown else images.lock)
				set(slot.PriceRow.Price, "Text", Hud.money(item.cost))
			end
		end

		-- Your gear
		set(toolValue, "Text", `{player:GetAttribute("ToolName") or Config.start.toolName} · {short(capacity)} L`)
		renderPips(Hud.find(gear, "WalkRow"), "walk", bought)
		renderPips(Hud.find(gear, "HandsRow"), "hands", bought)
	end)
end

return Shop
