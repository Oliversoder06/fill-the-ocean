-- Fills in the HUD that lives in StarterGui ("Hud", built in Studio) from server attributes:
-- wallet, waiting text, card, results, and the run panel at the top right (stopwatch from
-- RunStartedAt/RunEndedAt, the stage's name, how full its basin is). Results rows are clones of
-- the hidden RowTemplate.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
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

-- The current stage's model in workspace.Stages, or nil between stages. Non-yielding.
function Hud.currentStage(): Model?
	local stages = workspace:FindFirstChild("Stages")
	local index = ReplicatedStorage:GetAttribute("Stage")
	local config = type(index) == "number" and Config.stages[index]
	local model = stages and config and stages:FindFirstChild(config.name)
	return if model and model:IsA("Model") then model else nil
end
-- Money still flying in as coins (client/Payout): the wallet shows Money minus this, so it counts
-- up coin by coin instead of jumping when the server pays.
Hud.walletHold = 0

local find, set = Hud.find, Hud.set

function Hud.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local cardEvent = remotes:WaitForChild("Card") :: RemoteEvent
	local resultsEvent = remotes:WaitForChild("Results") :: RemoteEvent
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")

	local coins = find(gui, "Wallet.Pill.Coins")
	local coinPop = find(gui, "Wallet.Coin.Pop")
	local shownMoney = math.max(0, (player:GetAttribute("Money") or 0) - Hud.walletHold)
	local cardLabel = find(gui, "Card")
	local waiting = find(gui, "Waiting")
	local results = find(gui, "Results")
	local resultsRow = find(gui, "Results.RowTemplate")
	local resultsSub = find(gui, "Results.Sub")
	local footer = find(gui, "Results.Footer")
	local progress = find(gui, "Progress")
	local timeText = find(progress, "TimeRow.Time")
	local placeText = find(progress, "PlaceRow.Place")
	local stageTag = find(progress, "StageTag")
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

	resultsEvent.OnClientEvent:Connect(function(list)
		for _, child in results:GetChildren() do
			if child.Name == "Row" then
				child:Destroy()
			end
		end
		for i, r in list do
			local row = resultsRow:Clone()
			row.Name = "Row"
			row.LayoutOrder = 10 + i
			row.Visible = true
			row.Rank.Text = tostring(i)
			row.PlayerName.Text = r.name
			row.Share.Text = `{math.floor(r.share * 100 + 0.5)}%`
			row.Reward.Text = if r.saved then `+{r.reward}` else `+{r.reward} (not saved)`
			row.Parent = results
		end
		resultsSub.Text = `Difficulty {ReplicatedStorage:GetAttribute("Difficulty") or 1}`
		results.Visible = true
	end)

	-- Windows (shop, results) free the cursor. First person locks it to the centre every frame, so
	-- this runs right after the camera and overrides that while a window is showing.
	local windows = { find(gui, "Shop"), results }
	RunService:BindToRenderStep("HudCursor", Enum.RenderPriority.Camera.Value + 3, function()
		for _, window in windows do
			if window.Visible then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
				return
			end
		end
	end)

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

		-- Waiting room and results footer
		local waitText = ReplicatedStorage:GetAttribute("Waiting")
		set(waiting, "Visible", phase == "waiting" or phase == "saving")
		set(waiting, "Text", if phase == "saving" then "Saving your Raindrops..." elseif waitText and waitText ~= "" then `Waiting for your friends... {waitText}` else "Get ready...")
		local returnAt = ReplicatedStorage:GetAttribute("ReturnAt")
		if results.Visible and type(returnAt) == "number" then
			set(footer, "Text", `Back to the lobby in {math.max(0, returnAt - os.time())}s`)
		end

		-- Run panel: stopwatch, where you are, how full this stage's basin is
		local startedAt = ReplicatedStorage:GetAttribute("RunStartedAt")
		set(progress, "Visible", type(startedAt) == "number")
		if type(startedAt) == "number" then
			local endedAt = ReplicatedStorage:GetAttribute("RunEndedAt")
			local now = if type(endedAt) == "number" then endedAt else workspace:GetServerTimeNow()
			set(timeText, "Text", Hud.clock(now - startedAt))
			local index = ReplicatedStorage:GetAttribute("Stage")
			local stage = if type(index) == "number" then Config.stages[math.min(index, #Config.stages)] else nil
			if stage then
				set(placeText, "Text", `The {stage.name}`)
				set(stageTag, "Text", `STAGE {math.min(index, #Config.stages)}/{#Config.stages}`)
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
