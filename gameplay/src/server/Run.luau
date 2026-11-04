-- The run: pool -> lake -> ocean. Owns money, carried water, purchases and the water level.
-- Clients trigger the scoop/pour hold prompts (baked into the stages) and send Buy(); state goes
-- out as attributes. Each player's prompt hold time is set on their client from ActSeconds; the
-- server checks distance when the hold starts and the hold length when it triggers.
-- Session: in a reserved server the lobby's ticket gives the difficulty and the party; in Studio
-- or a normal server, workspace attribute StudioDifficulty (default 1) and no party wait.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local Water = require(ReplicatedStorage.Shared.Water)
local Rewards = require(ReplicatedStorage.Shared.Rewards)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Difficulty = require(ReplicatedStorage.Common.Difficulty)
local Places = require(ReplicatedStorage.Common.Places)
local PlayerData = require(ReplicatedStorage.Common.PlayerData)
local Retry = require(ReplicatedStorage.Common.Retry)
local RunTicket = require(ReplicatedStorage.Common.RunTicket)
local Map = require(script.Parent.Map)

local START_DELAY = 5 -- no party (Studio): start this long after the first player spawns
local PARTY_WAIT = 20 -- party: start when everyone is in, or this long after the first arrival
local CARD_SECONDS = 3
local RETURN_SECONDS = 15 -- results screen time before everyone goes back to the lobby
local MAX_BUYS_PER_SECOND = 5
local MONEY_EPSILON = 1e-6 -- pours add fractional coins; 19.9999999 must still buy a 20-coin item
local PROMPT_DISTANCE = 10
local DISTANCE_SLACK = 6 -- studs of latency allowance on the server's distance checks
local HOLD_SLACK = 0.75 -- seconds of latency allowance on the server's hold-time check (mobile lag spikes)
local TICKET_WAIT = 10 -- seconds to keep looking for the lobby's ticket

local Run = {}

local stagesFolder: Folder
local remotes: { [string]: RemoteEvent } = {}
local run = {
	phase = "waiting",
	stage = 0,
	current = 0,
	target = 0,
	scale = 1,
	difficulty = 1,
	members = nil :: { [number]: boolean }?, -- party user ids in a reserved server; nil = anyone
	expected = 0,
	firstArrival = nil :: number?,
	allLitres = {} :: { number }, -- per stage, every player including leavers
	results = nil :: { any }?, -- kept so a player who joins after the run still sees them
	started = false,
}
local states: { [Player]: any } = {}

local function setGlobal(name: string, value: any)
	ReplicatedStorage:SetAttribute(name, value)
end

local function stageModel(index: number): Model
	local model = stagesFolder:FindFirstChild(Config.stages[index].name)
	assert(model and model:IsA("Model"), `workspace.Stages is missing {Config.stages[index].name}`)
	return model
end

local function remote(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local r = folder:WaitForChild(name, 10)
	assert(r and r:IsA("RemoteEvent"), `ReplicatedStorage.Remotes is missing {name} (Rojo project)`)
	return r
end

local function nextOffer(state)
	if run.stage < 1 or run.stage > #Config.stages then
		return nil, nil
	end
	local missed = Ladder.missedFromEarlierStages(Config, run.stage, state.boughtPerStage)
	if missed[1] then
		return missed[1].stage, missed[1].item
	end
	return run.stage, Ladder.nextItem(Config, run.stage, state.boughtPerStage[run.stage] or 0)
end

local function publish(player: Player)
	local state = states[player]
	local _, item = nextOffer(state)
	player:SetAttribute("Money", state.money)
	player:SetAttribute("Carried", state.carried)
	player:SetAttribute("Capacity", state.stats.capacity)
	player:SetAttribute("WalkSpeed", state.stats.walkSpeed)
	player:SetAttribute("ActSeconds", state.stats.actSeconds)
	player:SetAttribute("ToolName", state.stats.toolName)
	player:SetAttribute("ToolModel", state.stats.toolModel)
	player:SetAttribute("ToolTier", Ladder.toolTier(Config, state.stats.toolName))
	player:SetAttribute("NextItemName", if item then item.name else "")
	player:SetAttribute("NextItemCost", if item then item.cost else -1)
end

local function applyWalkSpeed(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = states[player].stats.walkSpeed
	end
end

local function moveToSpawn(player: Player)
	local character = player.Character
	local index = if run.stage >= 1 and run.stage <= #Config.stages then run.stage else 1
	if character then
		character:PivotTo(Zones.part(stageModel(index), "Spawn").CFrame + Vector3.new(0, 3, 0))
	end
end

-- Live share, renormalised over the stages played so far so the board reads 0-100%.
local function updateShares()
	local weights = Config.stageWeights()
	local played = math.min(run.stage, #Config.stages)
	local total = 0
	for s = 1, played do
		total += weights[s]
	end
	local live = {}
	for s = 1, played do
		live[s] = weights[s] / total
	end
	for player, state in states do
		player:SetAttribute("Share", Rewards.shares(live, state.litres, run.allLitres))
	end
end

local function setWater(current: number, target: number)
	run.current, run.target = current, target
	setGlobal("Current", current)
	setGlobal("Target", target)
	setGlobal("Fill", if target > 0 then current / target else 0)
	if run.stage >= 1 and run.stage <= #Config.stages then
		Map.setFill(stageModel(run.stage), current / target)
	end
end

local function setPhase(phase: string)
	run.phase = phase
	setGlobal("Phase", phase)
end

local function card(text: string)
	remotes.Card:FireAllClients(text, CARD_SECONDS)
end

-- Sends players to the lobby. Studio can't teleport, so it only says so.
local function sendToLobby(players: { Player }, reason: string)
	if #players == 0 then
		return
	end
	if RunService:IsStudio() then
		warn(`[Run] would teleport {#players} player(s) to the lobby ({reason}); teleports don't run in Studio`)
		return
	end
	local ok, err = Retry.run("teleport to lobby", function()
		TeleportService:TeleportAsync(Places.LOBBY, players)
	end, 3, 1)
	if not ok then
		for _, player in players do
			player:Kick(`Couldn't return you to the lobby ({err}). Please rejoin.`)
		end
	end
end

local function saveRewards(results)
	local pending = 0
	for _, r in results do
		pending += 1
		task.spawn(function()
			local saved, err = PlayerData.addRun(r.userId, r.reward, run.difficulty)
			r.saved = saved ~= nil
			if saved then
				r.unlocked = saved.unlocked
				r.total = saved.raindrops
			else
				warn(`[Run] reward not saved for {r.name}: {err}`)
			end
			pending -= 1
		end)
	end
	local deadline = os.clock() + 12
	while pending > 0 and os.clock() < deadline do
		task.wait(0.2)
	end
end

local function endRun()
	updateShares()
	local weights = Config.stageWeights()
	local entries = {}
	for player, state in states do
		local everyStage = true
		for s = 1, #Config.stages do
			if (state.litres[s] or 0) <= 0 then
				everyStage = false
			end
		end
		local share = Rewards.shares(weights, state.litres, run.allLitres)
		table.insert(entries, { id = player, share = share, pouredEveryStage = everyStage })
	end
	local rewards = Rewards.split(entries)
	local multiplier = Difficulty.rewardMultiplier(run.difficulty)
	table.sort(entries, function(a, b)
		return a.share > b.share
	end)
	local results = {}
	for _, e in entries do
		table.insert(results, {
			name = e.id.DisplayName,
			userId = e.id.UserId,
			share = e.share,
			reward = math.floor(rewards[e.id] * multiplier + 0.5),
			saved = false,
		})
	end
	run.stage = #Config.stages + 1
	setGlobal("Stage", run.stage)
	setPhase("saving")
	for player in states do
		publish(player)
	end
	saveRewards(results)
	run.results = results
	setGlobal("ReturnAt", os.time() + RETURN_SECONDS)
	setPhase("results")
	remotes.Results:FireAllClients(results)
	task.wait(RETURN_SECONDS)
	sendToLobby(Players:GetPlayers(), "run finished")
end

local startStage

local function completeStage()
	setPhase("card")
	card("FULL!")
	task.wait(CARD_SECONDS)
	if run.stage < #Config.stages then
		startStage(run.stage + 1)
	else
		endRun()
	end
end

function startStage(index: number)
	setPhase("card")
	run.stage = index
	run.allLitres[index] = 0
	setGlobal("Stage", index)
	setWater(0, Water.target(Config.stages[index].waterPerPlayer, #Players:GetPlayers(), run.scale))
	card(`The sun drained the {Config.stages[index].name}!`)
	for player in states do
		moveToSpawn(player)
		publish(player)
	end
	updateShares()
	task.wait(CARD_SECONDS)
	setPhase("playing")
end

local function startRun()
	if run.started then
		return
	end
	run.started = true
	local scale = workspace:GetAttribute("WaterScale") -- Studio test shortcut
	local studioScale = if RunService:IsStudio() and type(scale) == "number" and scale > 0 then scale else 1
	run.scale = studioScale * Difficulty.waterMultiplier(run.difficulty)
	startStage(1)
end

local function partyPresent(): number
	local n = 0
	for player in states do
		if not run.members or run.members[player.UserId] then
			n += 1
		end
	end
	return n
end

-- Waiting room: start when the whole party is in, or after the wait runs out.
local function tryStart()
	if run.started or not run.firstArrival then
		return
	end
	setGlobal("Waiting", if run.members then `{partyPresent()}/{run.expected}` else "")
	local waited = os.clock() - run.firstArrival
	if run.members then
		if partyPresent() >= run.expected or waited >= PARTY_WAIT then
			task.spawn(startRun)
		end
	elseif waited >= START_DELAY then
		task.spawn(startRun)
	end
end

-- Player count changed: rescale the target, keep the fill fraction.
local function onPlayerCount(count: number)
	if run.stage < 1 or run.stage > #Config.stages or run.target <= 0 then
		return
	end
	local newTarget = Water.target(Config.stages[run.stage].waterPerPlayer, count, run.scale)
	setWater(Water.rescale(run.current, run.target, newTarget), newTarget)
end

local function onPlayerAdded(player: Player)
	if run.members and not run.members[player.UserId] then
		sendToLobby({ player }, "not in this party") -- default deny: only the lobby's party plays here
		return
	end
	states[player] = {
		money = 0,
		carried = 0,
		stats = table.clone(Config.start),
		boughtPerStage = {},
		litres = {},
		holds = {} :: { [ProximityPrompt]: { began: number, ended: number? } },
		buyWindowStart = 0,
		buysInWindow = 0,
	}
	publish(player)
	if run.results then
		remotes.Results:FireClient(player, run.results)
	end
	player.CharacterAdded:Connect(function()
		applyWalkSpeed(player)
		task.defer(moveToSpawn, player)
		run.firstArrival = run.firstArrival or os.clock()
	end)
	if player.Character then
		run.firstArrival = run.firstArrival or os.clock()
	end
	onPlayerCount(#Players:GetPlayers())
end

local function onBuy(player: Player)
	local state = states[player]
	if not state or (run.phase ~= "playing" and run.phase ~= "card") then
		return
	end
	local now = os.clock()
	if now - state.buyWindowStart >= 1 then
		state.buyWindowStart, state.buysInWindow = now, 0
	end
	if state.buysInWindow >= MAX_BUYS_PER_SECOND then
		return
	end
	state.buysInWindow += 1
	local stage, item = nextOffer(state)
	if not item or state.money + MONEY_EPSILON < item.cost then
		return
	end
	state.money = math.max(0, state.money - item.cost)
	state.boughtPerStage[stage] = (state.boughtPerStage[stage] or 0) + 1
	state.stats = Ladder.apply(state.stats, item)
	applyWalkSpeed(player)
	publish(player)
end

local function checkFull()
	if run.phase == "playing" and run.current >= run.target - 1e-6 then
		setPhase("card") -- stop further pours; completeStage runs the transition
		task.spawn(completeStage)
	end
end

local function nearPrompt(player: Player, prompt: ProximityPrompt): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local part = prompt.Parent
	return root ~= nil
		and part ~= nil
		and part:IsA("BasePart")
		and ((root :: BasePart).Position - part.Position).Magnitude <= PROMPT_DISTANCE + DISTANCE_SLACK
end

-- A trigger counts only in the current stage, close to the prompt, after a full hold that began
-- close to the prompt (so a hold can't be started while still walking over).
local function validTrigger(player: Player, prompt: ProximityPrompt, stageIndex: number): boolean
	local state = states[player]
	local hold = state and state.holds[prompt]
	if state then
		state.holds[prompt] = nil
	end
	if not (state and hold) or run.phase ~= "playing" or run.stage ~= stageIndex then
		return false
	end
	if not nearPrompt(player, prompt) then
		return false
	end
	-- HoldEnded can reach the server before Triggered, so measure the hold that actually happened
	local act = state.stats.actSeconds
	return (hold.ended or os.clock()) - hold.began >= act - math.min(HOLD_SLACK, act / 2)
end

local function onScoop(player: Player, prompt: ProximityPrompt, stageIndex: number)
	if not validTrigger(player, prompt, stageIndex) then
		return
	end
	local state = states[player]
	state.carried = state.stats.capacity
	publish(player)
end

local function onPour(player: Player, prompt: ProximityPrompt, stageIndex: number)
	if not validTrigger(player, prompt, stageIndex) then
		return
	end
	local state = states[player]
	local litres = Water.pourAmount(state.carried, run.current, run.target)
	if litres <= 0 then
		return
	end
	state.carried -= litres
	state.money += litres * Config.stages[stageIndex].coinsPerLitre
	state.litres[stageIndex] = (state.litres[stageIndex] or 0) + litres
	run.allLitres[stageIndex] += litres
	setWater(run.current + litres, run.target)
	publish(player)
	updateShares()
	checkFull()
end

-- Prompts are baked into each stage (Source.ScoopPrompt, PourPoint.PourPrompt); this wires them.
local function connectPrompt(part: BasePart, name: string, handler, stageIndex: number)
	local prompt = part:FindFirstChild(name)
	assert(prompt and prompt:IsA("ProximityPrompt"), `{part:GetFullName()} is missing {name}`)
	prompt.PromptButtonHoldBegan:Connect(function(player)
		local state = states[player]
		if state and nearPrompt(player, prompt) then
			state.holds[prompt] = { began = os.clock() }
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		local hold = states[player] and states[player].holds[prompt]
		if hold then
			hold.ended = os.clock()
		end
	end)
	prompt.Triggered:Connect(function(player)
		handler(player, prompt, stageIndex)
	end)
end

-- Reserved server: read the lobby's ticket. Without one, nobody should be here.
local function loadSession()
	local isReserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	if not isReserved then
		run.difficulty = Difficulty.clamp(workspace:GetAttribute("StudioDifficulty"))
		return
	end
	local ticket, err
	local deadline = os.clock() + TICKET_WAIT
	repeat
		ticket, err = RunTicket.read(game.PrivateServerId)
		if not ticket then
			task.wait(1)
		end
	until ticket or os.clock() > deadline
	if not ticket then
		warn(`[Run] no run ticket for {game.PrivateServerId} ({err or "missing"}); sending everyone back`)
		run.members = {}
		run.expected = 0
		sendToLobby(Players:GetPlayers(), "no run ticket")
		return
	end
	run.difficulty = Difficulty.clamp(ticket.difficulty)
	run.members = {}
	for _, userId in ticket.members do
		if type(userId) == "number" then
			(run.members :: { [number]: boolean })[userId] = true
			run.expected += 1
		end
	end
end

function Run.start(stages: Folder)
	stagesFolder = stages
	for _, name in { "Buy", "Card", "Results" } do
		remotes[name] = remote(name)
	end
	setGlobal("Stage", 0)
	setGlobal("Fill", 0)
	setGlobal("Waiting", "")
	setPhase("waiting")

	loadSession()
	setGlobal("Difficulty", run.difficulty)

	remotes.Buy.OnServerEvent:Connect(onBuy)
	for i in Config.stages do
		local model = stageModel(i)
		connectPrompt(Zones.part(model, "Source"), "ScoopPrompt", onScoop, i)
		connectPrompt(Zones.part(model, "PourPoint"), "PourPrompt", onPour, i)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if states[player] then
			states[player] = nil
			onPlayerCount(#Players:GetPlayers() - 1) -- the leaver is still listed during PlayerRemoving
		end
	end)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(`[Run] teleport failed for {player.Name}: {result} {message}`)
		player:Kick("Couldn't return you to the lobby. Please rejoin.")
	end)
	task.spawn(function()
		while not run.started do
			tryStart()
			task.wait(0.5)
		end
	end)

	-- Studio-only test shortcut: set workspace attribute StudioFillStage = true to fill the current stage.
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("StudioFillStage"):Connect(function()
			if workspace:GetAttribute("StudioFillStage") and run.phase == "playing" then
				workspace:SetAttribute("StudioFillStage", nil)
				setWater(run.target, run.target)
				checkFull()
			end
		end)
	end
end

return Run
