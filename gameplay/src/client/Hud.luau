-- Fills in the HUD that lives in StarterGui ("Hud", built in Studio) from server attributes, and
-- sets this player's scoop/pour prompt hold time and on/off state locally (the server re-checks).
-- Results rows are clones of the hidden RowTemplate.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local Hud = {}

local SUFFIXES = { "K", "M", "B", "T" }
local COIN_BOUNCE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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

local function currentStage(stages: Instance): Model?
	local index = ReplicatedStorage:GetAttribute("Stage")
	local config = type(index) == "number" and Config.stages[index]
	local model = config and stages:FindFirstChild(config.name)
	return if model and model:IsA("Model") then model else nil
end

local find, set = Hud.find, Hud.set

function Hud.start()
	local stagesFolder = workspace:WaitForChild("Stages")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local cardEvent = remotes:WaitForChild("Card") :: RemoteEvent
	local resultsEvent = remotes:WaitForChild("Results") :: RemoteEvent
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")

	local coins = find(gui, "Wallet.Pill.Coins")
	local coinPop = find(gui, "Wallet.Coin.Pop")
	local shownMoney = player:GetAttribute("Money") or 0
	local cardLabel = find(gui, "Card")
	local waiting = find(gui, "Waiting")
	local results = find(gui, "Results")
	local resultsRow = find(gui, "Results.RowTemplate")
	local resultsSub = find(gui, "Results.Sub")
	local footer = find(gui, "Results.Footer")

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
		local playing = phase == "playing"

		-- This player's prompts: hold time from ActSeconds, only with the tool out, scoop only with
		-- room, pour only with water
		local stage = currentStage(stagesFolder)
		local carried = player:GetAttribute("Carried") or 0
		local capacity = player:GetAttribute("Capacity") or 0
		local act = player:GetAttribute("ActSeconds") or Config.start.actSeconds
		local equipped = player:GetAttribute("Equipped") ~= false
		for _, prompt in stagesFolder:GetDescendants() do
			if prompt:IsA("ProximityPrompt") then
				local here = stage ~= nil and prompt:IsDescendantOf(stage)
				local enabled = playing
					and here
					and equipped
					and (if prompt.Name == "ScoopPrompt" then carried < capacity - 1e-6 else carried > 1e-6)
				set(prompt, "HoldDuration", act)
				set(prompt, "Enabled", enabled)
			end
		end

		-- Wallet
		local money = player:GetAttribute("Money") or 0
		set(coins, "Text", Hud.money(money))
		if money > shownMoney + 1e-6 then -- earned: the coin bounces
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

	end)
end

return Hud
