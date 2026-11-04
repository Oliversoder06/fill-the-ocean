-- Fills in the HUD that lives in StarterGui ("Hud", built in Studio) from server attributes, and
-- sets this player's scoop/pour prompt hold time and on/off state locally (the server re-checks).
-- Rows for the board and results are clones of the hidden RowTemplate in each list.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local Hud = {}

local SUFFIXES = { "K", "M", "B", "T" }
local COLOR_AFFORD = Color3.fromRGB(70, 200, 110)
local COLOR_CANT = Color3.fromRGB(90, 100, 120)
local STAGE_TITLES = { Pool = "The Pool", Lake = "Camp Lake", Ocean = "The Ocean" }

local function short(n: number): string
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

local function find(parent: Instance, path: string): any
	local node = parent
	for name in path:gmatch("[^%.]+") do
		local child = node:FindFirstChild(name)
		assert(child, `Hud is missing {path} (StarterGui.Hud is built in Studio)`)
		node = child
	end
	return node
end

-- Sets a property only when it changes (this runs every frame).
local function set(obj: Instance, prop: string, value: any)
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

function Hud.start()
	local stagesFolder = workspace:WaitForChild("Stages")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local buy = remotes:WaitForChild("Buy") :: RemoteEvent
	local cardEvent = remotes:WaitForChild("Card") :: RemoteEvent
	local resultsEvent = remotes:WaitForChild("Results") :: RemoteEvent
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")

	local stageName = find(gui, "Top.StageName")
	local difficulty = find(gui, "Top.DifficultyChip.Difficulty")
	local fillBar = find(gui, "Top.FillBar.Fill")
	local amount = find(gui, "Top.FillBar.Amount")
	local coins = find(gui, "Wallet.Coins")
	local carry = find(gui, "Wallet.Carry")
	local carryBar = find(gui, "Wallet.CarryBar.Fill")
	local shop = find(gui, "Shop")
	local itemName = find(gui, "Shop.ItemName")
	local buyButton = find(gui, "Shop.BuyButton")
	local board = find(gui, "Board")
	local boardRow = find(gui, "Board.RowTemplate")
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

	buyButton.Activated:Connect(function()
		buy:FireServer()
	end)

	local boardRows: { [Player]: Instance } = {}
	local boardTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		local phase = ReplicatedStorage:GetAttribute("Phase")
		local playing = phase == "playing"
		local inRun = playing or phase == "card"

		-- This player's prompts: hold time from ActSeconds, scoop only with room, pour only with water
		local stage = currentStage(stagesFolder)
		local carried = player:GetAttribute("Carried") or 0
		local capacity = player:GetAttribute("Capacity") or 0
		local act = player:GetAttribute("ActSeconds") or Config.start.actSeconds
		for _, prompt in stagesFolder:GetDescendants() do
			if prompt:IsA("ProximityPrompt") then
				local here = stage ~= nil and prompt:IsDescendantOf(stage)
				local enabled = playing
					and here
					and (if prompt.Name == "ScoopPrompt" then carried < capacity - 1e-6 else carried > 1e-6)
				set(prompt, "HoldDuration", act)
				set(prompt, "Enabled", enabled)
			end
		end

		-- Top bar
		local index = ReplicatedStorage:GetAttribute("Stage") or 0
		local config = Config.stages[index]
		set(stageName, "Text", if config then STAGE_TITLES[config.name] or config.name elseif index > #Config.stages then "Ocean filled!" else "Get ready...")
		set(difficulty, "Text", `Difficulty {ReplicatedStorage:GetAttribute("Difficulty") or 1}`)
		local fill = math.clamp(ReplicatedStorage:GetAttribute("Fill") or 0, 0, 1)
		set(fillBar, "Size", UDim2.new(fill, 0, 1, 0))
		set(amount, "Text", `{short(ReplicatedStorage:GetAttribute("Current") or 0)} / {short(ReplicatedStorage:GetAttribute("Target") or 0)} L`)

		-- Wallet
		local money = player:GetAttribute("Money") or 0
		set(coins, "Text", `{short(money)} coins`)
		set(carry, "Text", `{player:GetAttribute("ToolName") or "Spoon"}   {short(carried)} / {short(capacity)} L`)
		set(carryBar, "Size", UDim2.new(if capacity > 0 then math.clamp(carried / capacity, 0, 1) else 0, 0, 1, 0))

		-- Shop: only during the run, and only while something is left to buy
		local cost = player:GetAttribute("NextItemCost") or -1
		set(shop, "Visible", inRun)
		if cost < 0 then
			set(itemName, "Text", "Everything bought!")
			set(buyButton, "Text", "Maxed")
			set(buyButton, "BackgroundColor3", COLOR_CANT)
		else
			set(itemName, "Text", player:GetAttribute("NextItemName") or "")
			set(buyButton, "Text", `Buy   {short(cost)}`)
			set(buyButton, "BackgroundColor3", if money + 1e-6 >= cost then COLOR_AFFORD else COLOR_CANT)
		end

		-- Waiting room and results footer
		local waitText = ReplicatedStorage:GetAttribute("Waiting")
		set(waiting, "Visible", phase == "waiting" or phase == "saving")
		set(waiting, "Text", if phase == "saving" then "Saving your Raindrops..." elseif waitText and waitText ~= "" then `Waiting for your friends... {waitText}` else "Get ready...")
		local returnAt = ReplicatedStorage:GetAttribute("ReturnAt")
		if results.Visible and type(returnAt) == "number" then
			set(footer, "Text", `Back to the lobby in {math.max(0, returnAt - os.time())}s`)
		end

		-- Board, a few times a second
		boardTimer += dt
		if boardTimer >= 0.25 then
			boardTimer = 0
			local players = Players:GetPlayers()
			table.sort(players, function(a, b)
				return (a:GetAttribute("Share") or 0) > (b:GetAttribute("Share") or 0)
			end)
			local seen = {}
			for rank, p in players do
				seen[p] = true
				local row = boardRows[p]
				if not row then
					row = boardRow:Clone()
					row.Name = "Row"
					row.Visible = true
					row.Parent = board
					boardRows[p] = row
				end
				set(row, "LayoutOrder", rank)
				set(row.PlayerName, "Text", p.DisplayName)
				set(row.Share, "Text", `{math.floor((p:GetAttribute("Share") or 0) * 100 + 0.5)}%`)
			end
			for p, row in boardRows do
				if not seen[p] then
					row:Destroy()
					boardRows[p] = nil
				end
			end
		end
	end)
end

return Hud
