-- The run: pool -> lake -> ocean. Owns money, carried water, purchases and the water level.
-- Clients send Act("scoop" | "pour") when they start a scoop sweep or a pour (aimed at the well or
-- the basin, see client/Action) and Buy(trackId); state goes out as attributes. The server checks
-- the distance and, for scoops, the pace (one per ActSeconds) when an action starts. A scoop is
-- credited when it ends, ActSeconds later; a pour is instant.
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
local Session = require(ReplicatedStorage.Shared.Session)
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
local ACT_REACH = 12 -- studs from Source / PourPoint; keep in step with client/Action REACH
local DISTANCE_SLACK = 6 -- studs of latency allowance on the server's distance checks
local HOLD_SLACK = 0.75 -- seconds of latency allowance on the server's action pace check (mobile lag spikes)
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
	session = nil :: Session.State?, -- who may play here (see shared/Session)
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

local function publish(player: Player)
	local state = states[player]
	player:SetAttribute("Money", state.money)
	player:SetAttribute("Carried", state.carried)
	player:SetAttribute("Capacity", state.stats.capacity)
	player:SetAttribute("WalkSpeed", state.stats.walkSpeed)
	player:SetAttribute("ActSeconds", state.stats.actSeconds)
	player:SetAttribute("Sweeps", state.stats.sweeps)
	player:SetAttribute("ToolName", state.stats.toolName)
	player:SetAttribute("ToolModel", state.stats.toolModel)
	player:SetAttribute("ToolTier", state.stats.toolTier)
	player:SetAttribute("Hold", state.stats.hold)
	player:SetAttribute("CoinBonus", state.stats.coinBonus)
	player:SetAttribute("Equipped", state.equipped)
	-- Levels bought per track ("Level_tool", "Level_walk", ...): the shop reads these.
	for _, track in Config.tracks do
		player:SetAttribute(`Level_{track.id}`, state.levels[track.id] or 0)
	end
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
	setGlobal("RunEndedAt", workspace:GetServerTimeNow()) -- stops the HUD stopwatch
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
	setGlobal("RunStartedAt", workspace:GetServerTimeNow()) -- the HUD stopwatch counts from here
	local scale = workspace:GetAttribute("WaterScale") -- Studio test shortcut
	local studioScale = if RunService:IsStudio() and type(scale) == "number" and scale > 0 then scale else 1
	run.scale = studioScale * Difficulty.waterMultiplier(run.difficulty)
	startStage(1)
end

local function partyPresent(): number
	local n = 0
	for player in states do
		if run.session and Session.admits(run.session, player.UserId) then
			n += 1
		end
	end
	return n
end

-- Waiting room: start when the whole party is in, or after the wait runs out. A closed server
-- never starts a run.
local function tryStart()
	local session = run.session
	if run.started or not run.firstArrival or not session or session.mode == "closed" then
		return
	end
	setGlobal("Waiting", if session.mode == "party" then `{partyPresent()}/{session.expected}` else "")
	local waited = os.clock() - run.firstArrival
	if session.mode == "party" then
		if partyPresent() >= session.expected or waited >= PARTY_WAIT then
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
	-- Default deny: only the lobby's party plays here. Anyone else (a friend who followed in, a
	-- direct link, a public or VIP server) goes to the lobby.
	if not (run.session and Session.admits(run.session, player.UserId)) then
		sendToLobby({ player }, "not part of a run from the lobby")
		return
	end
	states[player] = {
		money = 0,
		carried = 0,
		levels = {} :: { [string]: number },
		stats = Ladder.stats(Config, {}),
		litres = {},
		nextActAt = 0, -- os.clock() pace budget for Act (see onAct)
		buyWindowStart = 0,
		buysInWindow = 0,
		equipped = true,
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

-- Buy the next level of one upgrade track. Only levels unlocked by the current stage can be bought.
local function onBuy(player: Player, trackId: unknown)
	local state = states[player]
	if not state or type(trackId) ~= "string" or (run.phase ~= "playing" and run.phase ~= "card") then
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
	local level, status = Ladder.offer(Config, state.levels, trackId, run.stage)
	if status ~= "buy" or state.money + MONEY_EPSILON < level.cost then
		return
	end
	state.money = math.max(0, state.money - level.cost)
	state.levels[trackId] = (state.levels[trackId] or 0) + 1
	state.stats = Ladder.stats(Config, state.levels)
	applyWalkSpeed(player)
	publish(player)
end

-- Hotbar: the player puts their tool away or takes it out. Unequipped, they can't scoop or pour.
local function onEquip(player: Player, equipped: unknown)
	local state = states[player]
	if not state or type(equipped) ~= "boolean" or state.equipped == equipped then
		return
	end
	state.equipped = equipped
	publish(player)
end

local function checkFull()
	if run.phase == "playing" and run.current >= run.target - 1e-6 then
		setPhase("card") -- stop further pours; completeStage runs the transition
		task.spawn(completeStage)
	end
end

local function nearPart(player: Player, part: BasePart): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and ((root :: BasePart).Position - part.Position).Magnitude <= ACT_REACH + DISTANCE_SLACK
end

local function creditScoop(state)
	state.carried += Water.scoopAmount(state.carried, state.stats.capacity, state.stats.sweeps)
end

local function creditPour(state, stageIndex: number): boolean
	local litres = Water.pourAmount(state.carried, run.current, run.target)
	if litres <= 0 then
		return false
	end
	state.carried -= litres
	state.money += litres * Config.stages[stageIndex].coinsPerLitre * state.stats.coinBonus
	state.litres[stageIndex] = (state.litres[stageIndex] or 0) + litres
	run.allLitres[stageIndex] += litres
	setWater(run.current + litres, run.target)
	return true
end

-- A scoop sweep or a pour. Checked when it starts (stage, distance, room or water). A scoop is
-- credited when it ends (it always plays out in full on the client) and is paced: on average one
-- per actSeconds, with slack for latency. A pour is instant and needs no pacing: it empties the tool.
local function onAct(player: Player, kind: unknown)
	local state = states[player]
	if not state or (kind ~= "scoop" and kind ~= "pour") or not state.equipped or run.phase ~= "playing" then
		return
	end
	local stageIndex = run.stage
	local act = state.stats.actSeconds
	local slack = math.min(HOLD_SLACK, act / 2)
	local now = os.clock()
	if kind == "scoop" and now < state.nextActAt - slack then
		return
	end
	local part = Zones.part(stageModel(stageIndex), if kind == "scoop" then "Source" else "PourPoint")
	if not nearPart(player, part) then
		return
	end
	if kind == "scoop" and state.carried >= state.stats.capacity - 1e-9 then
		return
	elseif kind == "pour" and state.carried <= 0 then
		return
	end
	if kind == "pour" then
		if creditPour(state, stageIndex) then
			publish(player)
			updateShares()
			checkFull()
		end
		return
	end
	-- Keep up to `slack` of earned time, so a late packet doesn't make the next on-time one look early.
	state.nextActAt = math.max(state.nextActAt, now - slack) + act
	task.delay(act, function()
		if states[player] ~= state or run.phase ~= "playing" or run.stage ~= stageIndex or not state.equipped then
			return
		end
		creditScoop(state)
		publish(player)
	end)
end

-- Decides who may play here. Only a reserved server the lobby made (with its ticket) runs; the
-- ticket is read from MemoryStore, never from client teleport data.
local function loadSession()
	local isStudio = RunService:IsStudio()
	local reserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	local ticket, err = nil, nil
	if reserved and not isStudio then
		local deadline = os.clock() + TICKET_WAIT
		repeat
			ticket, err = RunTicket.read(game.PrivateServerId)
			if not ticket then
				task.wait(1)
			end
		until ticket or os.clock() > deadline
	end
	run.session = Session.decide({
		isStudio = isStudio,
		privateServerId = game.PrivateServerId,
		privateServerOwnerId = game.PrivateServerOwnerId,
		ticket = ticket,
		studioDifficulty = workspace:GetAttribute("StudioDifficulty"),
	}, Difficulty.clamp)
	run.difficulty = run.session.difficulty
	if run.session.mode == "closed" then
		warn(`[Run] closed server ({if reserved then `no run ticket: {err or "missing"}` else "not a lobby run"}); sending everyone to the lobby`)
		setGlobal("Waiting", "Taking you to the lobby...")
		sendToLobby(Players:GetPlayers(), "closed server")
	end
end

function Run.start(stages: Folder)
	stagesFolder = stages
	for _, name in { "Buy", "Card", "Results", "Equip", "Act" } do
		remotes[name] = remote(name)
	end
	setGlobal("Stage", 0)
	setGlobal("Fill", 0)
	setGlobal("Waiting", "")
	setPhase("waiting")

	loadSession()
	setGlobal("Difficulty", run.difficulty)

	remotes.Buy.OnServerEvent:Connect(onBuy)
	remotes.Equip.OnServerEvent:Connect(onEquip)
	remotes.Act.OnServerEvent:Connect(onAct)
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
