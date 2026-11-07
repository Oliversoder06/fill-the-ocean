-- Fills in the HUD that lives in StarterGui ("Hud", built in Studio) from server attributes:
-- wallet, waiting text, card, and the run panel at the top right (stopwatch from PlaySeconds and
-- RunStartedAt, the map's name, how full the ocean is, a running boost's countdown).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Boosts = require(ReplicatedStorage.Shared.Boosts)
local Ease = require(ReplicatedStorage.Shared.Ease)

local player = Players.LocalPlayer
local Hud = {}

local SUFFIXES = { "K", "M", "B", "T" }
local COIN_BOUNCE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PROGRESS_POP = TweenInfo.new(Ease.POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Stopwatch text: 4:05, then 1:04:05 past an hour.
function Hud.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h, m = s // 3600, (s // 60) % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

function Hud.short(n: number): string
	if n < 10 then
		return string.format("%.1f", n)
	elseif n < 1000 then
		return tostring(math.floor(n))
	end
	local i = 0
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	return string.format("%.1f%s", n, SUFFIXES[i])
end

-- Money: whole coins with thousands separators below 100K, then the short form (1.2M).
function Hud.money(n: number): string
	n = math.floor(n)
	if n >= 100000 then
		return Hud.short(n)
	end
	local text = tostring(n)
	local count
	repeat
		text, count = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return text
end

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
-- Money still flying in as coins (client/Payout): the wallet shows Money minus this, so it counts
-- up coin by coin instead of jumping when the server pays.
Hud.walletHold = 0

local find, set = Hud.find, Hud.set

function Hud.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local cardEvent = remotes:WaitForChild("Card") :: RemoteEvent
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")

	local coins = find(gui, "Wallet.Pill.Coins")
	local coinPop = find(gui, "Wallet.Coin.Pop")
	local shownMoney = math.max(0, (player:GetAttribute("Money") or 0) - Hud.walletHold)
	local cardLabel = find(gui, "Card")
	local waiting = find(gui, "Waiting")
	local progress = find(gui, "Progress")
	local timeText = find(progress, "TimeRow.Time")
	local placeText = find(progress, "PlaceRow.Place")
	local boostTag = find(progress, "BoostTag")
	local progressFill = find(progress, "Bar.Fill")
	local progressLabel = find(progress, "Bar.Label")
	local progressPop = find(progress, "Bar.Pop")
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

	-- Windows (shop, admin) free the cursor. First person locks it to the centre every frame, so
	-- this runs right after the camera and overrides that while a window is showing. In play the
	-- mouse icon is hidden and the place's cursor image (StarterGui.Cursor) marks where you aim.
	local windows = { find(gui, "Shop"), find(gui, "Admin") }
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
		set(UserInputService, "MouseIconEnabled", windowOpen)
		set(crosshair, "Visible", not windowOpen)
	end)

	local finalTime: number? = nil -- time played as last shown while playing
	RunService.RenderStepped:Connect(function()
		local phase = ReplicatedStorage:GetAttribute("Phase")

		-- Wallet
		local money = math.max(0, (player:GetAttribute("Money") or 0) - Hud.walletHold)
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
				if target > fillTo then
					progressPop.Scale = 1.06
					TweenService:Create(progressPop, PROGRESS_POP, { Scale = 1 }):Play()
				end
				fillFrom, fillTo, fillChangedAt = shownFill, target, clock
			end
			shownFill = math.clamp(Ease.pop(fillFrom, fillTo, clock - fillChangedAt), 0, 1)
			set(progressFill, "Size", UDim2.fromScale(shownFill, 1))
			set(progressFill, "Visible", shownFill > 0)
			set(progressLabel, "Text", string.format("%.1f%% filled", math.floor(target * 1000) / 10))
		end

	end)
end

return Hud
