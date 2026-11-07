-- The run: one team's saved ocean. Owns money, carried water, purchases, the water level and the save.
-- Clients send Act("scoop" | "pour") when they start a scoop sweep or a pour (aimed at the well or
-- the basin, see client/Action) and Buy(trackId); state goes out as attributes. The server checks
-- the distance and, for scoops, the pace (one per ActSeconds) when an action starts. A scoop is
-- credited when it ends, ActSeconds later; a pour is instant. Each accepted action is published as
-- ActKind + ActAt (server time) so other clients can play it on that player's body (client/Bodies).
-- Clients also send Look(pitch in degrees) a few times a second; it goes out as the Look attribute.
-- Admins (shared/Admins) send Admin(fill fraction 0-1) to jump the ocean's fill (client/Admin).
-- Session: in a reserved server the lobby's ticket gives the map, the save key and the party; in
-- Studio, workspace attribute StudioMap (default map1), the players present at the start are the
-- team, and there is no party wait.
-- Saving (common/RunStore): the run is locked to this server before its save is loaded, and the lock
-- is renewed while it plays. A run that can't be locked or loaded, belongs to another team or is
-- finished is never played (Studio plays it unsaved, with a warning), so a failed load never
-- overwrites a save. Saves every AUTOSAVE_SECONDS, when a player leaves and when the server closes.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Admins = require(ReplicatedStorage.Shared.Admins)
local Config = require(ReplicatedStorage.Shared.Config)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local Boosts = require(ReplicatedStorage.Shared.Boosts)
local Water = require(ReplicatedStorage.Shared.Water)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Session = require(ReplicatedStorage.Shared.Session)
local Maps = require(ReplicatedStorage.Common.Maps)
local Places = require(ReplicatedStorage.Common.Places)
local PlayerData = require(ReplicatedStorage.Common.PlayerData)
local Retry = require(ReplicatedStorage.Common.Retry)
local RunSave = require(ReplicatedStorage.Common.RunSave)
local RunStore = require(ReplicatedStorage.Common.RunStore)
local RunTicket = require(ReplicatedStorage.Common.RunTicket)
local Map = require(script.Parent.Map)

local START_DELAY = 5 -- no party (Studio): start this long after the first player spawns
local PARTY_WAIT = 20 -- party: start when everyone is in, or this long after the first arrival
local CARD_SECONDS = 3
local MAX_BUYS_PER_SECOND = 5
local MONEY_EPSILON = 1e-6 -- pours add fractional coins; 19.9999999 must still buy a 20-coin item
local ACT_REACH = Zones.REACH
local DISTANCE_SLACK = 6 -- studs of latency allowance on the server's distance checks
local HOLD_SLACK = 0.75 -- seconds of latency allowance on the server's action pace check (mobile lag spikes)
local TICKET_WAIT = 10 -- seconds to keep looking for the lobby's ticket
local LOOK_INTERVAL = 0.1 -- seconds between accepted Look updates per player (clients send less often)
local LOOK_LIMIT = 80 -- degrees up or down
local AUTOSAVE_SECONDS = 60
local CLOSE_SAVE_SECONDS = 25 -- BindToClose waits this long at most for the last save (Roblox allows 30)
local END_SAVE_SECONDS = 15 -- the ending waits this long at most for the finished run to be stored
local PROGRESS_SECONDS = 12 -- the ending waits this long at most for every member's Raindrops

-- Studio has no JobId; the lock still needs an id that is this server's alone.
local serverId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local Run = {}

local ocean: Model -- the one ocean (server/Map)
local remotes: { [string]: RemoteEvent } = {}
local run = {
	phase = "loading",
	current = 0,
	target = 0,
	teamSize = 1, -- the water needed scales with the team; fixed for the save
	waterScale = 1, -- the map's waterMultiplier, times WaterScale in Studio
	session = nil :: Session.State?, -- who may play here (see shared/Session)
	map = nil :: Maps.Map?,
	ticketKey = nil :: string?, -- the save key the lobby's ticket names
	firstArrival = nil :: number?,
	started = false,
	closed = false, -- this run can't be played here: everyone who joins goes to the lobby
	save = nil :: RunSave.Save?, -- set once the run is open
	key = nil :: string?, -- the save's key; nil = this run is not saved (a Studio test without storage)
	lockedAt = 0, -- os.clock() of the last time this server took or renewed the run's lock
	lockLost = false,
	playBase = 0, -- seconds played on this save before this session
	playSince = nil :: number?, -- os.clock() when playing started this session
	boost = nil :: { id: string, token: number }?, -- the running fill-milestone boost (Config.boosts)
	boostToken = 0,
}
local states: { [Player]: any } = {}

local function setGlobal(name: string, value: any)
	ReplicatedStorage:SetAttribute(name, value)
end

-- A player's stats with the running boost applied. state.stats stays what they bought.
local function boosted(state)
	return Boosts.apply(Config, state.stats, run.boost and run.boost.id)
end

local function remote(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local r = folder:WaitForChild(name, 10)
	assert(r and r:IsA("RemoteEvent"), `ReplicatedStorage.Remotes is missing {name} (Rojo project)`)
	return r
end

-- Nothing goes out before the save is applied: clients would show the fresh start as the player's
-- money and levels.
local function publish(player: Player)
	local state = states[player]
	if not run.save then
		return
	end
	player:SetAttribute("Money", state.money)
	player:SetAttribute("Carried", state.carried)
	player:SetAttribute("Capacity", state.stats.capacity)
	player:SetAttribute("WalkSpeed", state.stats.walkSpeed)
	player:SetAttribute("ActSeconds", state.stats.actSeconds)
	player:SetAttribute("Sweeps", boosted(state).sweeps)
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
		humanoid.WalkSpeed = boosted(states[player]).walkSpeed
	end
end

local function moveToSpawn(player: Player)
	local character = player.Character
	if character then
		character:PivotTo(Zones.part(ocean, "Spawn").CFrame + Vector3.new(0, 3, 0))
	end
end

-- The fill fraction for `litres` of water: Water.fill's curve for the team, scaled by the map.
local function fillOf(litres: number): number
	if run.target > 0 and litres >= run.target - 1e-6 then
		return 1 -- full as checkFull counts it, whatever the rounding of the scaling and the last pour
	end
	return Water.fill(litres / run.waterScale, Config.ocean, run.teamSize)
end

-- The litres that fill the ocean to `fraction`; the inverse of fillOf.
local function litresAt(fraction: number): number
	return Water.litresAt(fraction, Config.ocean, run.teamSize) * run.waterScale
end

-- Areas open so far (Ladder.openAreas: stand-in fill points until Phase 2 builds the gates).
local function openAreas(): number
	return Ladder.openAreas(Config, fillOf(run.current))
end

local function setWater(current: number)
	run.current = current
	local fill = fillOf(current)
	setGlobal("Current", current)
	setGlobal("Target", run.target)
	setGlobal("Fill", fill)
	Map.setFill(ocean, fill)
end

local function setPhase(phase: string)
	run.phase = phase
	setGlobal("Phase", phase)
end

local function card(text: string)
	remotes.Card:FireAllClients(text, CARD_SECONDS)
end

-- Boost start and end change everyone's walk speed and sweeps at once.
local function refreshAll()
	for player in states do
		applyWalkSpeed(player)
		publish(player)
	end
end

local function endBoost()
	if run.boost then
		run.boost = nil
		setGlobal("Boost", "")
		refreshAll()
	end
end

local function startBoost(id: string)
	local kind = Boosts.kind(Config, id)
	assert(kind, `unknown boost {id}`)
	run.boostToken += 1
	local token = run.boostToken
	run.boost = { id = id, token = token }
	setGlobal("Boost", id)
	setGlobal("BoostEndsAt", workspace:GetServerTimeNow() + Config.boosts.seconds)
	card(kind.card)
	refreshAll()
	task.delay(Config.boosts.seconds, function()
		if run.boost and run.boost.token == token then
			endBoost()
		end
	end)
end

-- The fill moved from `before` to `after`: crossing a milestone starts a boost this save hasn't
-- played yet (each plays once per save), unless the ocean just filled.
local function checkBoost(before: number, after: number)
	local save = run.save :: RunSave.Save
	if not Boosts.crossed(Config.boosts.milestones, before, after) or after >= 1 then
		return
	end
	local left = {}
	for _, kind in Config.boosts.kinds do
		if not table.find(save.boostsPlayed, kind.id) then
			table.insert(left, kind.id)
		end
	end
	if #left > 0 then
		local id = left[math.random(#left)]
		table.insert(save.boostsPlayed, id)
		startBoost(id)
	end
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

-- Nobody plays this run here: say why and send everyone, and everyone who joins later, to the lobby.
local function closeRun(message: string)
	run.closed = true
	setGlobal("Waiting", message)
	sendToLobby(Players:GetPlayers(), message)
end

local function playSeconds(): number
	return run.playBase + (if run.playSince then os.clock() - run.playSince else 0)
end

-- A member's money, levels and litres go into the save (on every save, and when they leave). Each
-- entry is a new table that is never changed afterwards, so a copy of the players map is a snapshot.
local function keepPlayer(player: Player, state)
	local save = run.save
	if save and table.find(save.members, player.UserId) then
		save.players[tostring(player.UserId)] = {
			money = state.money,
			levels = table.clone(state.levels),
			litres = state.litres,
		}
	end
end

-- The save to write now. A copy, so play can go on changing the run while the write is in flight.
local function snapshot(): RunSave.Save
	local save = run.save :: RunSave.Save
	for player, state in states do
		keepPlayer(player, state)
	end
	save.current = run.current
	save.playSeconds = playSeconds()
	-- always newer than what this run loaded or last wrote, even if this server's clock is behind
	save.updatedAt = math.max(os.time(), save.updatedAt + 1)
	local copy = table.clone(save)
	copy.players = table.clone(save.players)
	copy.boostsPlayed = table.clone(save.boostsPlayed)
	return copy
end

local saving, saveAgain, lastSaveOk = false, false, false

-- Writes the run. One write at a time: a call during a write asks for one more after it, so the
-- newest state always lands last. Never writes an unsaved run or one whose lock is lost.
local function saveRun(reason: string)
	if not run.key or run.lockLost then
		return
	end
	if saving then
		saveAgain = true
		return
	end
	saving = true
	repeat
		saveAgain = false
		local ok, err = RunStore.save(run.key, snapshot())
		lastSaveOk = ok
		if not ok then
			warn(`[Run] run {run.key} not saved ({reason}): {err}`)
		end
	until not saveAgain
	saving = false
end

-- Saves now and waits for it, at most `seconds`. True only when the newest state is stored.
local function saveNow(reason: string, seconds: number): boolean
	if not run.key or run.lockLost then
		return false
	end
	task.spawn(saveRun, reason)
	local deadline = os.clock() + seconds
	while saving and os.clock() < deadline do
		task.wait(0.1)
	end
	return not saving and lastSaveOk
end

-- Renews the run's lock while it plays. If it can't be renewed in time, another server may take the
-- run once the lock runs out: stop writing it and send everyone back to the lobby.
local function keepLock()
	while not run.lockLost do
		task.wait(RunStore.RENEW_SECONDS)
		local ok, err = RunStore.lock(run.key :: string, serverId)
		if ok then
			run.lockedAt = os.clock()
		else
			warn(`[Run] couldn't renew the lock on run {run.key}: {err}`)
			if os.clock() - run.lockedAt >= RunStore.LOCK_SECONDS - RunStore.RENEW_SECONDS then
				run.lockLost = true
				warn(`[Run] lost the lock on run {run.key}: no more saves; sending everyone to the lobby`)
				sendToLobby(Players:GetPlayers(), "lost the run's lock")
			end
		end
	end
end

-- Runs fn(userId) for every member of the team at once and waits for them all, at most `seconds`.
local function eachMember(seconds: number, fn: (number) -> ())
	local pending = 0
	for _, userId in (run.save :: RunSave.Save).members do
		pending += 1
		task.spawn(function()
			fn(userId)
			pending -= 1
		end)
	end
	local deadline = os.clock() + seconds
	while pending > 0 and os.clock() < deadline do
		task.wait(0.2)
	end
end

-- Puts the run first in the member's saved runs (the lobby's Saved Runs list).
local function addRun(userId: number)
	local saved, err = PlayerData.addRun(userId, run.key :: string)
	if not saved then
		warn(`[Run] run {run.key} not added to {userId}'s saved runs: {err}`)
	end
end

-- The ocean is full: store the finished run, pay every member the map's Raindrops and send everyone
-- back to the lobby. Raindrops are paid only once the finished run is stored, so loading it again
-- can't pay twice; if it can't be stored, the run stays unfinished and ends again on its next load.
local function endRun()
	endBoost()
	card("The ocean is full!")
	local shownUntil = os.clock() + CARD_SECONDS
	run.playBase, run.playSince = playSeconds(), nil
	local save = run.save :: RunSave.Save
	local map = run.map :: Maps.Map
	save.finished = true
	if run.key then
		if saveNow("ocean full", END_SAVE_SECONDS) then
			eachMember(PROGRESS_SECONDS, function(userId)
				local cleared, err = PlayerData.clearMap(userId, map.id, map.rewardRaindrops)
				if not cleared then
					warn(`[Run] {map.id} not cleared for {userId} ({map.rewardRaindrops} Raindrops): {err}`)
				end
				addRun(userId)
			end)
		else
			save.finished = false
			warn(`[Run] the finished run {run.key} wasn't stored, so no Raindrops were paid; it ends again on its next load`)
		end
	end
	task.wait(math.max(0, shownUntil - os.clock()))
	setPhase("done")
	sendToLobby(Players:GetPlayers(), "ocean full")
end

local function checkFull()
	if run.phase == "playing" and run.current >= run.target - 1e-6 then
		setPhase("ending") -- stops further pours; endRun stores and ends the run
		task.spawn(endRun)
	end
end

-- Locks the run to this server, then loads its save (a new one if there is none yet). Returns the
-- save, or nil and what to tell the players. Nothing is loaded without the lock, and a failed load,
-- another team's save or a finished run is never played, so it can't be overwritten.
local function openRun(key: string, mapId: string, members: { number }): (RunSave.Save?, string?)
	local locked, lockErr = RunStore.lock(key, serverId)
	if not locked then
		warn(`[Run] couldn't lock run {key}: {lockErr}`)
		return nil, "This run is already open"
	end
	run.lockedAt = os.clock()
	local save, loadErr = RunStore.load(key)
	local problem = nil
	if loadErr then
		warn(`[Run] couldn't load run {key}: {loadErr}`)
		problem = "Couldn't load your run. Please try again."
	elseif save and (save.mapId ~= mapId or not RunSave.sameTeam(save, members)) then
		warn(`[Run] run {key} belongs to another team or map; not loaded`)
		problem = "This run belongs to another team"
	elseif save and save.finished then
		problem = "This run is already finished"
	end
	if problem then
		local unlocked, unlockErr = RunStore.unlock(key, serverId)
		if not unlocked then
			warn(`[Run] couldn't unlock run {key}: {unlockErr}; its lock runs out by itself`)
		end
		return nil, problem
	end
	return save or RunSave.new(mapId, members), nil
end

-- Gives a player what the save holds for them; a member with nothing saved keeps the fresh start.
local function applySaved(player: Player)
	local saved = (run.save :: RunSave.Save).players[tostring(player.UserId)]
	if saved then
		local state = states[player]
		state.money, state.levels, state.litres = saved.money, table.clone(saved.levels), saved.litres
		state.stats = Ladder.stats(Config, state.levels)
	end
end

-- The team is in: open their run, apply it and play.
local function startRun()
	if run.started then
		return
	end
	run.started = true
	local session = run.session :: Session.State
	local map = run.map :: Maps.Map
	local members = {}
	if session.mode == "party" then
		for userId in session.members do
			table.insert(members, userId)
		end
	else
		for _, player in Players:GetPlayers() do
			if player.UserId > 0 then -- Studio's test accounts have negative ids and can't save
				table.insert(members, player.UserId)
			end
		end
	end
	setGlobal("Waiting", "Loading your run...")
	local key = RunSave.key(map.id, members)
	local save, problem = nil, nil
	if session.mode == "party" and run.ticketKey ~= key then
		warn(`[Run] the ticket's run {run.ticketKey} doesn't match its team ({key})`)
		problem = "Couldn't load your run. Please try again."
	elseif #members == 0 then
		problem = "no team that can save (Studio test accounts)"
	else
		save, problem = openRun(key, map.id, members)
	end
	if not save then
		if session.mode ~= "test" then
			closeRun(problem :: string)
			return
		end
		warn(`[Run] Studio: playing without saving ({problem}). Saving needs Studio API access.`)
		save = RunSave.new(map.id, members)
	else
		run.key = key
	end
	run.save = save

	local scale = workspace:GetAttribute("WaterScale") -- Studio test shortcut
	local studioScale = if RunService:IsStudio() and type(scale) == "number" and scale > 0 then scale else 1
	run.waterScale = map.waterMultiplier * studioScale
	run.teamSize = if session.mode == "party" then #save.members else #Players:GetPlayers()
	run.target = litresAt(1)
	setWater(math.min(save.current, run.target))
	for player in states do
		applySaved(player)
	end
	refreshAll()
	run.playBase, run.playSince = save.playSeconds, os.clock()
	setGlobal("PlaySeconds", save.playSeconds)
	setGlobal("RunStartedAt", workspace:GetServerTimeNow()) -- the HUD stopwatch counts from here
	setGlobal("Waiting", "")
	-- The intro (phase "intro", only while save.introSeen is false) comes with the story cutscenes;
	-- until then it is skipped.
	setPhase("playing")
	if run.key then
		task.spawn(keepLock)
		task.spawn(saveRun, "run opened")
		task.spawn(eachMember, PROGRESS_SECONDS, addRun)
		task.spawn(function()
			while true do
				task.wait(AUTOSAVE_SECONDS)
				saveRun("autosave")
			end
		end)
	end
	checkFull() -- a save stored full but not finished ends now
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
	if run.started or run.closed or not run.firstArrival or not session or session.mode == "closed" then
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

local function onPlayerAdded(player: Player)
	-- Default deny: only the lobby's party plays here. Anyone else (a friend who followed in, a
	-- direct link, a public or VIP server) goes to the lobby, as does everyone once the run is closed.
	if run.closed or not (run.session and Session.admits(run.session, player.UserId)) then
		sendToLobby({ player }, "not part of a run from the lobby")
		return
	end
	states[player] = {
		money = 0,
		carried = 0,
		levels = {} :: { [string]: number },
		stats = Ladder.stats(Config, {}),
		litres = 0,
		nextActAt = 0, -- os.clock() pace budget for Act (see onAct)
		buyWindowStart = 0,
		buysInWindow = 0,
		lastLookAt = 0, -- os.clock() of the last accepted Look
		equipped = true,
	}
	if run.save then
		applySaved(player)
	end
	publish(player)
	player.CharacterAdded:Connect(function()
		applyWalkSpeed(player)
		task.defer(moveToSpawn, player)
		run.firstArrival = run.firstArrival or os.clock()
	end)
	if player.Character then
		run.firstArrival = run.firstArrival or os.clock()
	end
end

-- Buy the next level of one upgrade track. Only levels of the open areas can be bought.
local function onBuy(player: Player, trackId: unknown)
	local state = states[player]
	if not state or type(trackId) ~= "string" or run.phase ~= "playing" then
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
	local level, status = Ladder.offer(Config, state.levels, trackId, openAreas())
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

-- Where the player looks, for other clients to turn their head (client/Bodies). Cosmetic, so it is
-- only range-checked and rate-limited.
local function onLook(player: Player, pitch: unknown)
	local state = states[player]
	if not state or type(pitch) ~= "number" or pitch ~= pitch or math.abs(pitch) == math.huge then
		return
	end
	local now = os.clock()
	if now - state.lastLookAt < LOOK_INTERVAL then
		return
	end
	state.lastLookAt = now
	player:SetAttribute("Look", math.round(math.clamp(pitch, -LOOK_LIMIT, LOOK_LIMIT)))
end

-- Sets the ocean's fill to `fraction` (admin window, Studio shortcut). As with pours, crossing a
-- milestone starts its boost and 100% ends the run.
local function jumpFill(fraction: number)
	local before = fillOf(run.current)
	setWater(litresAt(fraction))
	checkBoost(before, fillOf(run.current))
	checkFull()
end

-- Admin window (client/Admin): jump the ocean's fill to a fraction 0-1. Only while playing, so it
-- never races the ending (checkFull leaves "playing" at once, which also stops repeat clicks).
local function onAdmin(player: Player, fraction: unknown)
	if not Admins[player.UserId] or run.phase ~= "playing" then
		return
	end
	if type(fraction) ~= "number" or fraction ~= fraction or fraction < 0 or fraction > 1 then
		return
	end
	jumpFill(fraction)
end

local function nearPart(player: Player, part: BasePart): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and ((root :: BasePart).Position - part.Position).Magnitude <= ACT_REACH + DISTANCE_SLACK
end

-- Pouring works anywhere next to where the ocean's water will be (shared/Zones.nearFlood).
local function nearFlood(player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local characters = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(characters, other.Character)
		end
	end
	return Zones.nearFlood(ocean, (root :: BasePart).Position, ACT_REACH + DISTANCE_SLACK, characters)
end

local function creditScoop(state)
	state.carried += Water.scoopAmount(state.carried, state.stats.capacity, boosted(state).sweeps)
end

-- Tells every client an accepted action started, so they can play it on this player's body.
local function publishAct(player: Player, kind: string)
	player:SetAttribute("ActKind", kind)
	player:SetAttribute("ActAt", workspace:GetServerTimeNow())
end

local function creditPour(state): boolean
	local litres = Water.pourAmount(state.carried, run.current, run.target)
	if litres <= 0 then
		return false
	end
	state.carried -= litres
	state.money += litres * Config.ocean.coinsPerLitre * boosted(state).coinBonus
	state.litres += litres
	local before = fillOf(run.current)
	setWater(run.current + litres)
	checkBoost(before, fillOf(run.current))
	return true
end

-- A scoop sweep or a pour. Checked when it starts (distance, room or water). A scoop is
-- credited when it ends (it always plays out in full on the client) and is paced: on average one
-- per actSeconds, with slack for latency. A pour is instant and needs no pacing: it empties the tool.
local function onAct(player: Player, kind: unknown)
	local state = states[player]
	if not state or (kind ~= "scoop" and kind ~= "pour") or not state.equipped or run.phase ~= "playing" then
		return
	end
	local act = state.stats.actSeconds
	local slack = math.min(HOLD_SLACK, act / 2)
	local now = os.clock()
	if kind == "scoop" and now < state.nextActAt - slack then
		return
	end
	if not (if kind == "scoop" then nearPart(player, Zones.part(ocean, "Source")) else nearFlood(player)) then
		return
	end
	if kind == "scoop" and state.carried >= state.stats.capacity - 1e-9 then
		return
	elseif kind == "pour" and state.carried <= 0 then
		return
	end
	if kind == "pour" then
		if creditPour(state) then
			publishAct(player, kind)
			publish(player)
			checkFull()
		end
		return
	end
	-- Keep up to `slack` of earned time, so a late packet doesn't make the next on-time one look early.
	state.nextActAt = math.max(state.nextActAt, now - slack) + act
	publishAct(player, kind)
	task.delay(act, function()
		if states[player] ~= state or run.phase ~= "playing" or not state.equipped then
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
		studioMap = workspace:GetAttribute("StudioMap"),
	}, Maps.get)
	run.map = Maps.get(run.session.mapId) -- Session.decide only returns listed maps
	run.ticketKey = ticket and ticket.key
	if run.session.mode == "closed" then
		warn(`[Run] closed server ({if reserved then `no run ticket: {err or "missing"}` else "not a lobby run"}); sending everyone to the lobby`)
		closeRun("Taking you to the lobby...")
	end
end

function Run.start(oceanModel: Model)
	ocean = oceanModel
	for _, name in { "Buy", "Card", "Equip", "Act", "Look", "Admin" } do
		remotes[name] = remote(name)
	end
	setGlobal("Fill", 0)
	setGlobal("Waiting", "")
	setPhase("loading")

	loadSession()
	local map = run.map :: Maps.Map
	setGlobal("MapId", map.id)
	setGlobal("MapName", map.name)

	remotes.Buy.OnServerEvent:Connect(onBuy)
	remotes.Equip.OnServerEvent:Connect(onEquip)
	remotes.Act.OnServerEvent:Connect(onAct)
	remotes.Look.OnServerEvent:Connect(onLook)
	remotes.Admin.OnServerEvent:Connect(onAdmin)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then
			keepPlayer(player, state)
			states[player] = nil
			task.spawn(saveRun, `{player.Name} left`)
		end
	end)
	-- The last save before the server goes (Roblox waits up to 30 s), then the lock is released so the
	-- team can load the run again at once. A save still in flight keeps the lock until it runs out.
	game:BindToClose(function()
		if not run.key or run.lockLost then
			return
		end
		if saveNow("server closing", CLOSE_SAVE_SECONDS) then
			local ok, err = RunStore.unlock(run.key, serverId)
			if not ok then
				warn(`[Run] couldn't unlock run {run.key}: {err}; its lock runs out by itself`)
			end
		else
			warn(`[Run] run {run.key}: the last save didn't finish within {CLOSE_SAVE_SECONDS} s; its lock runs out by itself`)
		end
	end)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(`[Run] teleport failed for {player.Name}: {result} {message}`)
		player:Kick("Couldn't return you to the lobby. Please rejoin.")
	end)
	task.spawn(function()
		while not run.started and not run.closed do
			tryStart()
			task.wait(0.5)
		end
	end)

	-- Studio-only test shortcut: set workspace attribute StudioFill to a fraction 0-1 to jump the fill.
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("StudioFill"):Connect(function()
			local fraction = workspace:GetAttribute("StudioFill")
			if type(fraction) == "number" and fraction >= 0 and fraction <= 1 and run.phase == "playing" then
				workspace:SetAttribute("StudioFill", nil)
				jumpFill(fraction)
			end
		end)
	end
end

return Run
