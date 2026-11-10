-- The run: one team's saved ocean. Owns the team's wallet and purchases, carried water, the water
-- level and the save. Everything bought is the team's (owner, 2026-11-10): one wallet every coin goes
-- into and every buy comes out of, track levels, items and their levels, buildings and staff (the
-- save's `team`, published on ReplicatedStorage); every player gets the same stats and their own
-- copy of what is worn or held. Prices scale with the save's team size (Items.price).
-- Clients send Act("scoop" | "pour") when they start a scoop sweep or a pour (aimed at an open
-- area's Source, the basin or an open area's Pour, see client/Action) and Buy(id, bought) for the
-- next TAB level (`bought`: the levels the client saw bought, so of two members buying the same level
-- at once only the first gets it); state goes
-- out as attributes. The server checks the distance and, for scoops, the pace (one per ActSeconds
-- x the area's scoopFactor) when an action starts. A scoop is credited when it ends; a pour is
-- instant. Gates (Config.areas) are bought through their ProximityPrompt or the honeycomb (Buy
-- "gate:<areaId>") and open for the whole team (save.gatesOpen, published as GatesOpen). Items
-- (Config.items, common/Items) are bought once through their area's stand prompt and levelled with
-- Buy(itemId); a worn backpack adds to Capacity. Gadgets (kind "gadget") with a hotbar slot are taken
-- out with Equip(itemId) instead of the tool: the Water Gun pours from its range (Act "pour"), the
-- Garden Hose clips to an area's Tap and pours from it while the player stays in reach and holds the
-- act input (Gadget "clip" / "spray"), and the Jetpack Tank flies while its fuel lasts (Gadget "fly";
-- server/HeldTools adds the lift only while Flying is set). Cloud Catcher (an area that `needs` an
-- item) is reached only with the Jetpack Tank: spawn, scoop and pour skip it without one. Each
-- accepted action is published as ActKind + ActAt (server time) so other clients can play it on
-- that player's body (client/Bodies); an accepted pour also goes out as LastPour (shared/PourFlow:
-- area, litres, server time) for the wave down that area's channel (client/Channels).
-- Clients also send Look(pitch in degrees) a few times a second; it goes out as the Look attribute.
-- Area mechanics (server/Mechanics, shared/AreaRules): steam vents, snow, the drifting cloud (the
-- Cloud Net scoops it from its range), ice blocks at the Glacier's Source (each sweep is a hit; the
-- last one frees a block of litres), Heat Gloves' faster sweeps in hot pools, the deeper pools
-- behind breakable rocks (1.5x litres a sweep; save.rocksBroken) and the golden spring (3x pay).
-- Vehicles (server/Vehicles) are bought at the Fire Station (a cove shop) and called, filled, sprayed
-- and dropped there; their water lands through the same pour as a tool's.
-- The team's buildings on the cove's plots (server/Buildings): Build(plot, itemId), TAB levels
-- through Buy(itemId), their water poured on a tick and paid into the wallet.
-- The team's staff (server/Staff): hired at the Lifeguard Tower, assigned with Staff("assign",
-- itemId, areaId) (saved in the team's `assign`), their water poured on a tick and paid into the
-- wallet, faster while a member works the same area (state.workArea, set by every accepted scoop and pour).
-- Ticked pay (buildings, staff) waits in server/Payroll and is paid in batches.
-- Milestones every 5% of the fill (shared/Milestones, Config.milestones) are granted once per run
-- (save.milestones): a boost for everyone, the team's toast, revived cove decorations (Revived),
-- Raindrops onto every member's profile (PlayerData.payMilestones), and Milestone for clients'
-- swoop and sightings (client/Milestones).
-- A player's own income (pours, the hose, their vehicle) also counts in their Earned attribute
-- (client/Payout flies it in as coins); a purchase is announced to the rest of the team.
-- Admins (shared/Admins) send Admin(fill fraction 0-1) to jump the ocean's fill, or Admin("reset")
-- to start the run over for the same team and map while everyone stays (client/Admin).
-- Session: in a reserved server the lobby's ticket gives the map, the save key and the party; in
-- Studio, workspace attribute StudioMap (default map1), the players present at the start are the
-- team, and there is no party wait.
-- Saving (common/RunStore): the run is locked to this server before its save is loaded, and the lock
-- is renewed while it plays. A run that can't be locked or loaded, belongs to another team or is
-- finished is never played (Studio plays it unsaved, with a warning), so a failed load never
-- overwrites a save; only a Studio test replaces a finished save with a fresh one. Saves every
-- AUTOSAVE_SECONDS, when a player leaves and when the server closes.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Admins = require(ReplicatedStorage.Shared.Admins)
local AreaRules = require(ReplicatedStorage.Shared.AreaRules)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local Boosts = require(ReplicatedStorage.Shared.Boosts)
local Gadgets = require(ReplicatedStorage.Shared.Gadgets)
local Honeycomb = require(ReplicatedStorage.Shared.Honeycomb)
local Milestones = require(ReplicatedStorage.Shared.Milestones)
local PourFlow = require(ReplicatedStorage.Shared.PourFlow)
local StaffRules = require(ReplicatedStorage.Shared.StaffRules)
local Water = require(ReplicatedStorage.Shared.Water)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Session = require(ReplicatedStorage.Shared.Session)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Maps = require(ReplicatedStorage.Common.Maps)
local Places = require(ReplicatedStorage.Common.Places)
local PlayerData = require(ReplicatedStorage.Common.PlayerData)
local Retry = require(ReplicatedStorage.Common.Retry)
local RunSave = require(ReplicatedStorage.Common.RunSave)
local RunStore = require(ReplicatedStorage.Common.RunStore)
local RunTicket = require(ReplicatedStorage.Common.RunTicket)
local HeldTools = require(script.Parent.HeldTools)
local Buildings = require(script.Parent.Buildings)
local Map = require(script.Parent.Map)
local Mechanics = require(script.Parent.Mechanics)
local Payroll = require(script.Parent.Payroll)
local Staff = require(script.Parent.Staff)
local Vehicles = require(script.Parent.Vehicles)

local START_DELAY = 5 -- no party (Studio): start this long after the first player spawns
local PARTY_WAIT = 20 -- party: start when everyone is in, or this long after the first arrival
local CARD_SECONDS = 3
local MILESTONE_CARD_SECONDS = 5
local MAX_BUYS_PER_SECOND = 5
local MAX_EQUIPS_PER_SECOND = 5 -- each one swaps the model in hand (server/HeldTools)
local MAX_GADGET_PER_SECOND = 10 -- clip / spray / fly toggles; water and fuel follow server time, not these
local HOSE_TICK = 0.5 -- seconds between the hose's credits while it sprays
local ACT_REACH = Zones.REACH -- studs from a Source or Pour / from where the water will be (as client/Action)
local DISTANCE_SLACK = 6 -- studs of latency allowance on the server's distance checks
local STAND_COOLDOWN = 0.5 -- seconds between accepted stand prompts per player (exploits can fire prompts)
local STAND_RACE = 2 -- seconds after a stand buy in which a teammate's press there buys nothing (they pressed for the same thing)
local HOLD_SLACK = 0.75 -- seconds of latency allowance on the server's action pace check (mobile lag spikes)
local TICKET_WAIT = 10 -- seconds to keep looking for the lobby's ticket
local LOOK_INTERVAL = 0.1 -- seconds between accepted Look updates per player (clients send less often)
local LOOK_LIMIT = 80 -- degrees up or down
local RESET_COOLDOWN = 10 -- seconds between admin run resets (each rebuilds the world and saves)
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
	boost = nil :: { id: string, token: number }?, -- the running milestone boost (Config.boosts)
	boostToken = 0,
}
local states: { [Player]: any } = {}
-- The team's wallet, levels and items (the save's `team`; a blank one until the save is applied).
local team: RunSave.Team = RunSave.newTeam()
-- The last stand buy per stand (keyed by area id or cove shop): a teammate's press there within
-- STAND_RACE was for the same thing, so it buys nothing (onStand).
local standBuys: { [any]: { at: number, by: Player, name: string } } = {}

local function setGlobal(name: string, value: any)
	ReplicatedStorage:SetAttribute(name, value)
end

-- A player's stats with the running boost applied. state.stats stays what the team bought.
local function boosted(state)
	return Boosts.apply(Config, state.stats, run.boost and run.boost.id)
end

-- What the team's levels and gear add up to (a worn backpack adds to the tool's capacity); the same
-- for every player.
local function teamStats()
	return Items.withGear(Config, team, Ladder.stats(Config, team.levels))
end

-- What a listed price costs this team (Items.price: the save's team size).
local function price(cost: number): number
	return Items.price(Config, cost, run.teamSize)
end

local function remote(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local r = folder:WaitForChild(name, 10)
	assert(r and r:IsA("RemoteEvent"), `ReplicatedStorage.Remotes is missing {name} (Rojo project)`)
	return r
end

-- The jetpack's fuel, to a tenth of a second (it changes every frame while flying or refuelling).
-- Nil without a jetpack.
local function publishFuel(player: Player, state)
	local max = Items.gadgetStat(Config, team, "jetpackTank", "flightSeconds")
	player:SetAttribute("Fuel", if max then math.floor(math.min(state.fuel, max) * 10 + 0.5) / 10 else nil)
end

-- The team's economy, on ReplicatedStorage (client/Hud): Wallet, TeamSize and PriceScale
-- (Items.price), the levels bought per track ("Level_tool", ...), the items bought ("Owned":
-- "backpackTank,bigTank") and each one's upgrades ("ItemLevel_bigTank"). Nothing goes out before the
-- save is applied: clients would show the fresh start as the team's.
local function publishTeam()
	if not run.save then
		return
	end
	setGlobal("Wallet", team.wallet)
	setGlobal("TeamSize", run.teamSize)
	setGlobal("PriceScale", Items.priceScale(Config, run.teamSize))
	for _, track in Config.tracks do
		setGlobal(`Level_{track.id}`, team.levels[track.id] or 0)
	end
	setGlobal("Owned", table.concat(team.owned, ","))
	for _, item in Config.items do
		setGlobal(`ItemLevel_{item.id}`, team.itemLevels[item.id] or 0)
	end
end

-- A player's own state. Nothing goes out before the save is applied.
local function publish(player: Player)
	local state = states[player]
	if not run.save then
		return
	end
	player:SetAttribute("Earned", state.earned)
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
	-- The worn backpack's model ("" for none; server/HeldTools puts it on the back).
	local worn = Items.backpack(Config, team)
	player:SetAttribute("Backpack", if worn then worn.model else "")
	-- The gadget in hand (an item id, "" for none), the area whose Tap the hose is clipped to (0 for
	-- none) and whether it sprays, and the jetpack: Flying and Fuel (seconds of thrust left).
	player:SetAttribute("Gadget", state.gadget)
	player:SetAttribute("HoseArea", if state.hose then state.hose.area.id else 0)
	player:SetAttribute("Spraying", state.hose ~= nil and state.hose.spraying)
	player:SetAttribute("Flying", state.flying)
	publishFuel(player, state)
	player:SetAttribute("IceHits", state.iceHits) -- hits on the Glacier's current ice block
	-- The hose's rope and the jetpack's lift follow the state at once (server/HeldTools).
	local hose = state.hose
	local reach = if hose then Items.gadgetStat(Config, team, "gardenHose", "reach") :: number else 0
	HeldTools.setHose(player, hose and hose.tap, reach)
	HeldTools.setLift(player, if state.flying then Items.get(Config, "jetpackTank").riseSpeed else nil)
end


local function applyWalkSpeed(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local state = states[player]
		local walk = AreaRules.walkSpeed(Config, boosted(state).walkSpeed, state.onSnow)
		humanoid.WalkSpeed = walk * StaffRules.walkFactor(Config, state.nearLifeguard)
	end
end

-- The save's open gates (area ids); none before the save is loaded.
local function gatesOpen(): { number }
	return if run.save then run.save.gatesOpen else {}
end

-- Moving away takes the hose off its tap first (its rope would yank the character back).
local function moveTo(player: Player, spawn: BasePart)
	local state = states[player]
	if state and state.hose then
		state.hose = nil
		publish(player)
	end
	local character = player.Character
	if character then
		character:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))
	end
end

-- An area's part that Map.ensure checked is there.
local function areaPart(area, name: string): BasePart
	return Zones.areaPart(ocean, area, name) :: BasePart
end

-- The open area ids the team reaches, in order (Items.reachable: Cloud Catcher needs the jetpack).
local function reachableIds(): { number }
	return Items.reachable(Config, team, Areas.openIds(gatesOpen()))
end

-- Players appear at the furthest open area they reach.
local function moveToSpawn(player: Player)
	local open = reachableIds()
	moveTo(player, areaPart(Areas.byId(Config, open[#open]), "Spawn"))
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

-- Areas open so far (Ladder.openAreas).
local function openAreas(): number
	return Ladder.openAreas(Config, gatesOpen())
end

local function setWater(current: number)
	run.current = current
	local fill = fillOf(current)
	setGlobal("Current", current)
	setGlobal("Target", run.target)
	setGlobal("Fill", fill)
	Map.setFill(ocean, fill)
end

-- Leaving "playing" also stops every jetpack lift and takes every hose off its tap (the gadget
-- ticks only run while playing, so nothing else would end them) and stops the area mechanics
-- (server/Mechanics: vents, the cloud's drift, the golden spring) and puts every vehicle away;
-- "playing" starts the mechanics.
local function setPhase(phase: string)
	run.phase = phase
	setGlobal("Phase", phase)
	if phase == "playing" then
		Mechanics.play()
	else
		Mechanics.stop()
		Vehicles.stop()
		for player, state in states do
			if state.flying or state.hose then
				state.flying, state.hose = false, nil
				publish(player)
			end
		end
	end
end

local function card(text: string)
	remotes.Card:FireAllClients(text, CARD_SECONDS)
end

-- The open gates go out as "2,3" (client/Hud.gatesOpen).
local function publishGates()
	setGlobal("GatesOpen", table.concat(gatesOpen(), ","))
end

-- Boost start and end change everyone's walk speed and sweeps at once.
local function refreshAll()
	for player in states do
		applyWalkSpeed(player)
		publish(player)
	end
end

-- The team bought something: everyone's stats follow it, and the team's state goes out.
local function teamChanged()
	local stats = teamStats()
	for _, state in states do
		state.stats = stats
	end
	publishTeam()
	refreshAll()
end

-- `coins` go into the team's wallet. `player`: whose own income it is (their pour, hose or vehicle):
-- it also counts in their Earned, which client/Payout flies in as coins.
local function earn(player: Player?, coins: number)
	team.wallet += coins
	setGlobal("Wallet", team.wallet)
	local state = player and states[player]
	if player and state then
		state.earned += coins
		player:SetAttribute("Earned", state.earned)
	end
end

-- `coins` (already checked with Items.affords) leave the team's wallet.
local function spend(coins: number)
	team.wallet = math.max(0, team.wallet - coins)
	setGlobal("Wallet", team.wallet)
end

-- Tells the rest of the team what `buyer` bought with the team's coins.
local function announce(buyer: Player, thing: string)
	for other in states do
		if other ~= buyer then
			remotes.Card:FireClient(other, `{buyer.DisplayName} bought {thing} for the team`, CARD_SECONDS)
		end
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
	refreshAll()
	task.delay(Config.boosts.seconds, function()
		if run.boost and run.boost.token == token then
			endBoost()
		end
	end)
end

-- The cove decorations the run's milestones brought back go out as Revived ("1,2,5").
local function publishRevived()
	setGlobal("Revived", table.concat(Milestones.revived(Config, (run.save :: RunSave.Save).milestones :: { number }), ","))
end

-- Milestone Raindrops (index -> Raindrops) go onto every member's profile; each run pays a member
-- for a milestone once (Progress.payMilestones). Only a saved run pays, as the ending does.
local function payRaindrops(raindrops: { [number]: number })
	local key = run.key
	if not key then
		return
	end
	for _, userId in (run.save :: RunSave.Save).members do
		task.spawn(function()
			local paid, err = PlayerData.payMilestones(userId, key, raindrops)
			if not paid then
				warn(`[Run] milestone Raindrops not paid to {userId} (run {key}): {err}`)
			end
		end)
	end
end

-- The fill moved from `before` to `after`: every milestone passed that this run hasn't reached yet
-- is granted once (save.milestones): the decorations it revives, its Raindrops and, for the last one
-- (a jump may pass several), the toast, Milestone for clients and its boost. 100% is the ending's.
local function checkMilestones(before: number, after: number)
	local save = run.save :: RunSave.Save
	local new = Milestones.reach(Config, save.milestones :: { number }, before, after)
	if #new == 0 then
		return
	end
	local raindrops = Milestones.raindrops(Config, new, {})
	local last = nil
	for _, index in new do
		if not Milestones.reward(Config, index).ending then
			last = index
		end
	end
	publishRevived()
	if next(raindrops) then
		payRaindrops(raindrops)
	end
	if last and after < 1 then
		setGlobal("Milestone", Milestones.encode(last, workspace:GetServerTimeNow()))
		remotes.Card:FireAllClients(Milestones.card(Config, last), MILESTONE_CARD_SECONDS)
		startBoost(Milestones.reward(Config, last).boost)
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

-- A member's own litres go into the save (on every save, and when they leave). Each entry is a new
-- table that is never changed afterwards, so a copy of the players map is a snapshot.
local function keepPlayer(player: Player, state)
	local save = run.save
	if save and table.find(save.members, player.UserId) then
		save.players[tostring(player.UserId)] = { litres = state.litres }
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
	copy.team = RunSave.copyTeam(save.team)
	copy.players = table.clone(save.players)
	copy.gatesOpen = table.clone(save.gatesOpen)
	copy.buildings = table.clone(save.buildings)
	copy.plots = table.clone(save.plots)
	copy.rocksBroken = table.clone(save.rocksBroken)
	copy.milestones = table.clone(save.milestones :: { number })
	copy.milestonesSkipped = table.clone(save.milestonesSkipped)
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
-- back to the lobby. The run stays finished here even if the store is slow (later saves carry it).
-- Each member is paid once per run (Progress.clearMap), so an ending that runs again (the finished
-- save never landed) can't pay twice; a member whose payment fails here is paid on their next lobby
-- join (lobby/Profiles).
local function endRun()
	endBoost()
	card("The ocean is full!")
	local shownUntil = os.clock() + CARD_SECONDS
	run.playBase, run.playSince = playSeconds(), nil
	local save = run.save :: RunSave.Save
	local map = run.map :: Maps.Map
	save.finished = true
	Payroll.payNow()
	if run.key then
		local key = run.key
		if not saveNow("ocean full", END_SAVE_SECONDS) then
			warn(`[Run] the finished run {key} isn't confirmed stored; if it never lands, it ends again on its next load`)
		end
		eachMember(PROGRESS_SECONDS, function(userId)
			local cleared, err = PlayerData.clearMap(userId, map.id, map.rewardRaindrops, key)
			if not cleared then
				warn(`[Run] {map.id} not cleared for {userId} ({map.rewardRaindrops} Raindrops): {err}; paid on their next lobby join`)
			end
			addRun(userId)
		end)
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
-- another team's save or a finished run is never played, so it can't be overwritten. Only a Studio
-- test (replaceFinished) starts a fresh save in place of a finished one, so the team can test again.
local function openRun(key: string, mapId: string, members: { number }, replaceFinished: boolean): (RunSave.Save?, string?)
	local locked, lockErr = RunStore.lock(key, serverId)
	if not locked then
		warn(`[Run] couldn't lock run {key}: {lockErr}`)
		return nil, "This run is already open"
	end
	run.lockedAt = os.clock()
	local save, loadErr = RunStore.load(key, Config)
	local problem = nil
	if loadErr then
		warn(`[Run] couldn't load run {key}: {loadErr}`)
		problem = "Couldn't load your run. Please try again."
	elseif save and (save.mapId ~= mapId or not RunSave.sameTeam(save, members)) then
		warn(`[Run] run {key} belongs to another team or map; not loaded`)
		problem = "This run belongs to another team"
	elseif save and save.finished and replaceFinished then
		warn(`[Run] Studio: run {key} is finished; starting a fresh save in its place`)
		local fresh = RunSave.new(mapId, members)
		fresh.updatedAt = save.updatedAt -- the first write lands above it (snapshot adds 1)
		return fresh, nil
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

-- Gives a player what the save holds for them (their litres); a member with nothing saved starts at 0.
local function applySaved(player: Player)
	local saved = (run.save :: RunSave.Save).players[tostring(player.UserId)]
	local state = states[player]
	state.litres = if saved then saved.litres else 0
	state.stats = teamStats()
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
		save, problem = openRun(key, map.id, members, session.mode == "test")
	end
	if not save then
		if session.mode ~= "test" then
			closeRun(problem :: string)
			return
		end
		warn(`[Run] Studio: playing without saving: {problem} (see the warning above for the cause)`)
		save = RunSave.new(map.id, members)
	else
		run.key = key
	end
	run.save = save
	team = save.team
	for _, id in save.gatesOpen do
		Map.openGate(ocean, Areas.byId(Config, id))
	end
	publishGates()
	Mechanics.load(save)
	Buildings.load(save)

	local scale = workspace:GetAttribute("WaterScale") -- Studio test shortcut
	local studioScale = if RunService:IsStudio() and type(scale) == "number" and scale > 0 then scale else 1
	run.waterScale = map.waterMultiplier * studioScale
	run.teamSize = if session.mode == "party" then #save.members else #Players:GetPlayers()
	run.target = litresAt(1)
	setWater(math.min(save.current, run.target))
	if not save.milestones then -- a save from before milestones: those below its fill count as reached, ungranted
		save.milestones = Milestones.reachedBy(Config, fillOf(run.current))
		save.milestonesSkipped = table.clone(save.milestones :: { number })
	end
	publishRevived()
	-- A payment that failed last time is retried; members already paid for a milestone aren't written.
	local owed = Milestones.raindrops(Config, save.milestones :: { number }, save.milestonesSkipped)
	if next(owed) then
		payRaindrops(owed)
	end
	for player in states do
		applySaved(player)
		moveToSpawn(player) -- those who spawned before the load go to the furthest open area
	end
	teamChanged()
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

-- A player's state at the start of a run (and after an admin reset): only what is their own; what
-- is bought is the team's.
local function newState()
	return {
		earned = 0, -- coins their own pours, hose and vehicle brought the team this session
		carried = 0, -- litres in the tool
		carriedValue = 0, -- their coins before coinBonus (Water.mix: each area's litres at its pay)
		stats = teamStats(),
		litres = 0,
		nextActAt = 0, -- os.clock() pace budget for Act (see onAct)
		windows = {} :: { [string]: { start: number, count: number } }, -- per-remote rate limits (allow)
		lastLookAt = 0, -- os.clock() of the last accepted Look
		standAt = 0, -- os.clock() of the last accepted stand prompt
		equipped = true, -- the tool is in hand
		gadget = "", -- the hotbar gadget in hand instead (an item id), "" for none
		hose = nil :: { area: any, tap: BasePart, spraying: boolean, due: number }?, -- clipped Garden Hose
		flying = false, -- the jetpack's lift is on (server/HeldTools)
		fuel = math.huge, -- jetpack seconds left; Gadgets.fuel clamps it to the tank's size
		iceHits = 0, -- hits on the current ice block (server/Mechanics, AreaRules.sweep)
		onSnow = false, -- standing on snow terrain (server/Mechanics): walking is slower
		rockAt = 0, -- os.clock() of the last accepted rock prompt (server/Mechanics)
		workArea = 0, -- the area of the last accepted scoop or pour, at os.clock() workedAt (server/Staff)
		workedAt = -math.huge,
		nearLifeguard = false, -- near a Source a Lifeguard works (server/Staff): walking is faster
	}
end

local function onPlayerAdded(player: Player)
	-- Default deny: only the lobby's party plays here. Anyone else (a friend who followed in, a
	-- direct link, a public or VIP server) goes to the lobby, as does everyone once the run is closed.
	if run.closed or not (run.session and Session.admits(run.session, player.UserId)) then
		sendToLobby({ player }, "not part of a run from the lobby")
		return
	end
	states[player] = newState()
	if run.save then
		applySaved(player)
	end
	publish(player)
	player.CharacterAdded:Connect(function()
		local state = states[player]
		if state and (state.flying or state.hose) then -- a new body starts on the ground, unclipped
			state.flying, state.hose = false, nil
			publish(player)
		end
		applyWalkSpeed(player)
		task.defer(moveToSpawn, player)
		run.firstArrival = run.firstArrival or os.clock()
	end)
	if player.Character then
		run.firstArrival = run.firstArrival or os.clock()
	end
end

-- Whether a player may send one more `key` request this second (at most `max`); counts it.
local function allow(state, key: string, max: number): boolean
	local now = os.clock()
	local window = state.windows[key]
	if not window or now - window.start >= 1 then
		window = { start = now, count = 0 }
		state.windows[key] = window
	end
	if window.count >= max then
		return false
	end
	window.count += 1
	return true
end

-- Buy(id, bought): the next level of one upgrade track (only levels of the open areas), the next
-- upgrade of an owned item, or of a built building (server/Buildings), for the whole team from its
-- wallet at the team's price. `bought` is how many levels of `id` the buyer's client saw bought (-1:
-- an item not owned, a building not built): when a teammate bought that level first, the buyer is
-- told instead of buying the one after it. Items themselves are bought at their stand (onStand).
-- What TAB sells is Items.tabOffer, plus the gates (Areas.gateId(areaId), `bought` 0: openGate, as
-- the gate prompt but from anywhere). A buy sets the buyer's LastBuy (shared/Honeycomb.encodeBuy),
-- so only their client plays it as theirs.
local openGate: (Player, any, boolean) -> boolean -- below, by the gate prompt's other checks
local function onBuy(player: Player, id: unknown, bought: unknown)
	local state = states[player]
	local save = run.save
	if not state or not save or type(id) ~= "string" or type(bought) ~= "number" or run.phase ~= "playing" or not allow(state, "buy", MAX_BUYS_PER_SECOND) then
		return
	end
	local gate = Areas.fromGateId(Config, id)
	if gate then
		if bought == 0 and openGate(player, gate, false) then
			player:SetAttribute("LastBuy", Honeycomb.encodeBuy(id, 1, workspace:GetServerTimeNow()))
		end
		return
	end
	local item = Items.get(Config, id)
	local isTrack = Config.track(id) ~= nil
	local isBuilding = item ~= nil and item.kind == "building"
	local counts = if isTrack then team.levels elseif isBuilding then save.buildings else team.itemLevels
	local have = counts[id] or (if isTrack then 0 else -1)
	local function publishBuy()
		player:SetAttribute("LastBuy", Honeycomb.encodeBuy(id, have + 1, workspace:GetServerTimeNow()))
	end
	if bought < have then
		remotes.Card:FireClient(player, "A teammate just bought that", CARD_SECONDS)
		return
	elseif bought ~= have then
		return
	elseif isBuilding then
		if Buildings.buy(player, id) then
			publishBuy()
		end
		return
	end
	local level, status = Items.tabOffer(Config, team.levels, team, save.buildings, id, openAreas(), Ladder.helps(Config, team.levels, id))
	local cost = if status == "buy" then price(level.cost) else 0
	if status ~= "buy" or not Items.affords(team.wallet, cost) then
		return
	end
	spend(cost)
	counts[id] = have + 1
	teamChanged()
	publishBuy()
	local track = Config.track(id)
	announce(player, if track then Format.levelName(track, have + 1, level) else `the {(item :: Config.Item).name} Lv {have + 2}`)
end

-- Hotbar: true takes the tool out, false puts whatever is in hand away, and a gadget's id takes that
-- owned hotbar gadget (Items.slots) out instead of the tool. Without the tool they can't scoop, and
-- pour only with the Water Gun. Putting the hose away unclips it; putting the jetpack away stops it.
local function onEquip(player: Player, value: unknown)
	local state = states[player]
	if not state or not allow(state, "equip", MAX_EQUIPS_PER_SECOND) then
		return
	end
	local equipped, gadget
	if type(value) == "boolean" then
		equipped, gadget = value, ""
	else
		local item = Items.get(Config, value)
		if not (item and table.find(Items.slots(Config, team), item)) then
			return
		end
		equipped, gadget = false, item.id
	end
	if state.equipped == equipped and state.gadget == gadget then
		return
	end
	state.equipped, state.gadget = equipped, gadget
	if gadget ~= "gardenHose" then
		state.hose = nil
	end
	if gadget ~= "jetpackTank" then
		state.flying = false
	end
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

-- Sets the ocean's fill to `fraction` (admin window, Studio shortcut). As with pours, the milestones
-- passed are granted and 100% ends the run.
local function jumpFill(fraction: number)
	local before = fillOf(run.current)
	setWater(litresAt(fraction))
	checkMilestones(before, fillOf(run.current))
	checkFull()
end

-- Admin "Reset run": the run starts over for the same team and map while everyone stays. A blank save
-- (RunSave.blank: no water, wallet, levels, items, staff posts, gates, rocks, buildings or milestones)
-- replaces it, every player starts fresh, the world is rebuilt from it (gates shut, rocks back, plots
-- empty), and it is saved. Leaving "playing" for the swap puts vehicles, hoses and jetpacks away and
-- drops scoops in flight (their state is replaced).
local function resetRun()
	setPhase("loading")
	endBoost()
	Payroll.payNow() -- so nothing earned before the reset is paid after it
	local save = RunSave.blank(run.save :: RunSave.Save, os.time())
	run.save = save
	team = save.team
	table.clear(standBuys)
	for _, area in Config.areas do
		if area.model then
			Map.closeGate(ocean, area)
		end
	end
	publishGates()
	Mechanics.load(save)
	Buildings.load(save)
	setWater(0)
	publishRevived()
	for player in states do
		states[player] = newState()
		moveToSpawn(player)
	end
	teamChanged()
	run.playBase, run.playSince = 0, os.clock()
	setGlobal("PlaySeconds", 0)
	setGlobal("RunStartedAt", workspace:GetServerTimeNow())
	setPhase("playing")
	card("The run was reset")
	task.spawn(saveRun, "admin reset")
end

local lastResetAt = -math.huge

-- Admin window (client/Admin): jump the ocean's fill to a fraction 0-1, or "reset" the run (at most
-- once per RESET_COOLDOWN). Only while playing, so it never races the ending (checkFull leaves
-- "playing" at once, which also stops repeat clicks).
local function onAdmin(player: Player, value: unknown)
	if not Admins[player.UserId] or run.phase ~= "playing" then
		return
	end
	if value == "reset" then
		local now = os.clock()
		if now - lastResetAt >= RESET_COOLDOWN then
			lastResetAt = now
			resetRun()
		end
		return
	end
	if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
		return
	end
	jumpFill(value)
end

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Whether the player stands within a prompt's reach (with latency slack). The prompt sits in a
-- part or an attachment.
local function inReach(player: Player, prompt: ProximityPrompt): boolean
	local root = rootOf(player)
	local holder = prompt.Parent
	local at = if holder and holder:IsA("BasePart")
		then holder.Position
		elseif holder and holder:IsA("Attachment") then holder.WorldPosition
		else nil
	return root ~= nil and at ~= nil and (root.Position - at).Magnitude <= prompt.MaxActivationDistance + DISTANCE_SLACK
end

-- The open area the player reaches whose Source (scoop), Pour (pour) or Tap (hose) they stand
-- within `reach` studs of (Zones.REACH by default), and that part.
local function openSpot(player: Player, name: string, reach: number?)
	local root = rootOf(player)
	if not root then
		return nil, nil
	end
	local reached = Areas.open(reachableIds())
	return Zones.openSpot(ocean, Config, reached, name, root.Position, (reach or ACT_REACH) + DISTANCE_SLACK)
end

-- Where the player scoops (Zones.scoopSpot): an open area's Source they reach, a deep pool behind a
-- broken rock, or the drifting cloud from the Cloud Net's range. The area and whether it is a deep pool.
local function scoopSpot(player: Player)
	local root = rootOf(player)
	if not root then
		return nil, false
	end
	local reached = Areas.open(reachableIds())
	local net = Items.gadgetStat(Config, team, "cloudNet", "range")
	local area, _, deep = Zones.scoopSpot(ocean, Config, reached, Mechanics.rocksBroken(), root.Position, ACT_REACH + DISTANCE_SLACK, net and net + DISTANCE_SLACK)
	return area, deep
end

-- Pouring works anywhere within `reach` studs (Zones.REACH by default) of where the ocean's water
-- will be (shared/Zones.nearFlood).
local function nearFlood(player: Player, reach: number?): boolean
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
	return Zones.nearFlood(ocean, (root :: BasePart).Position, (reach or ACT_REACH) + DISTANCE_SLACK, characters)
end

-- A sweep at `area`'s Source (deep: its deeper pool): its litres are worth that area's pay, times
-- the golden spring's. AreaRules.sweep scales the litres (an ice hit brings none until the block is free).
local function creditScoop(state, area, deep: boolean)
	local pick = Items.gadgetStat(Config, team, "icePick", "hits")
	local hits, scale = AreaRules.sweep(Config, area, deep, state.iceHits, pick)
	state.iceHits = hits
	if scale <= 0 then
		return
	end
	-- A freed ice block or a deep pool's bigger sweep only fills the room left in the tool (accepted).
	local litres = Water.scoopAmount(state.carried, state.stats.capacity, boosted(state).sweeps / scale)
	local pay = Config.ocean.coinsPerLitre * area.payMultiplier * AreaRules.payScale(Config, area.id, deep, Mechanics.goldenId())
	state.carried += litres
	state.carriedValue = Water.mix(state.carriedValue, litres, pay)
end

-- Tells every client an accepted action started, so they can play it on this player's body.
local function publishAct(player: Player, kind: string)
	player:SetAttribute("ActKind", kind)
	player:SetAttribute("ActAt", workspace:GetServerTimeNow())
end

-- The player works in area `id` now: their staff there work faster for a while (server/Staff).
local function worked(state, id: number)
	state.workArea, state.workedAt = id, os.clock()
end

-- `litres` land in the ocean: the water rises and the milestones passed are granted. Callers
-- check that the ocean takes them (Water.pourAmount) and then checkFull.
local function raise(litres: number)
	local before = fillOf(run.current)
	setWater(run.current + litres)
	checkMilestones(before, fillOf(run.current))
end

-- `litres` worth `value` coins (before the tip and boosts) land in the ocean: the team earns them as
-- `player`'s income and the water rises. Callers check that the ocean takes them
-- (Water.pourAmount) and then checkFull.
local function pourIn(player: Player, litres: number, value: number)
	local state = states[player]
	state.litres += litres
	earn(player, value * boosted(state).coinBonus)
	raise(litres)
end

local function creditPour(player: Player): boolean
	local state = states[player]
	local litres = Water.pourAmount(state.carried, run.current, run.target)
	if litres <= 0 then
		return false
	end
	-- The poured share of the carried value (all of it, unless the ocean takes less than the tool holds).
	local value = Water.share(state.carriedValue, state.carried, litres)
	state.carried -= litres
	state.carriedValue = if state.carried > 0 then state.carriedValue - value else 0
	pourIn(player, litres, value)
	return true
end

-- A scoop sweep or a pour. Checked when it starts (distance, room or water). A scoop is at an open
-- area's Source (or deep pool, scoopSpot) and is credited when it ends (it always plays out in full on
-- the client); it is paced: on average one per AreaRules.scoopSeconds, with slack for latency. A pour is
-- by the ocean or at an open area's Pour, instant and needs no pacing: it empties the tool. With the
-- Water Gun in hand instead of the tool, a pour reaches the gun's range.
-- lihfolk-ignore: remote-unvalidated-args (kind is checked against exactly "scoop" / "pour" below)
local function onAct(player: Player, kind: unknown)
	local state = states[player]
	if not state or (kind ~= "scoop" and kind ~= "pour") or run.phase ~= "playing" then
		return
	end
	local gun = kind == "pour" and state.gadget == "waterGun"
	if not (state.equipped or gun) then
		return
	end
	local reach = if gun then Items.gadgetStat(Config, team, "waterGun", "range") :: number else ACT_REACH
	local area, deep, poured = nil, false, 0
	if kind == "scoop" then
		area, deep = scoopSpot(player)
		if not area then
			return
		end
	else
		-- where the water goes: the ocean (the cove's) or an open area's Pour
		local into = if nearFlood(player, reach) then Areas.byId(Config, 1) else openSpot(player, "Pour", reach)
		if not into then
			return
		end
		poured = into.id
	end
	local hotFill = Items.gadgetStat(Config, team, "heatGloves", "hotFill")
	local act = if area then AreaRules.scoopSeconds(state.stats.actSeconds, area, hotFill) else state.stats.actSeconds
	local slack = math.min(HOLD_SLACK, act / 2)
	local now = os.clock()
	if kind == "scoop" and now < state.nextActAt - slack then
		return
	end
	if kind == "scoop" and state.carried >= state.stats.capacity - 1e-9 then
		return
	elseif kind == "pour" and state.carried <= 0 then
		return
	end
	if kind == "pour" then
		local before = state.carried
		if creditPour(player) then
			worked(state, poured)
			publishAct(player, kind)
			setGlobal("LastPour", PourFlow.encode(poured, before - state.carried, workspace:GetServerTimeNow()))
			publish(player)
			checkFull()
		end
		return
	end
	-- Keep up to `slack` of earned time, so a late packet doesn't make the next on-time one look early.
	state.nextActAt = math.max(state.nextActAt, now - slack) + act
	worked(state, area.id)
	publishAct(player, kind)
	task.delay(act, function()
		if states[player] ~= state or run.phase ~= "playing" or not state.equipped then
			return
		end
		creditScoop(state, area, deep)
		publish(player)
	end)
end

-- Opens `area`'s gate for the whole team when it is the next gate and on sale (Areas.gateOffer) and
-- the team's wallet pays its price; true when it opened. `reach`: the buyer must stand by its
-- prompt (the gate prompt; the honeycomb's Buy skips it).
openGate = function(player: Player, area, reach: boolean): boolean
	local state = states[player]
	local save = run.save
	if not state or not save or run.phase ~= "playing" then
		return false
	end
	local status = Areas.gateOffer(Config, save.gatesOpen, fillOf(run.current), area.id)
	if status == "open" then
		remotes.Card:FireClient(player, `A teammate already opened {area.name}`, CARD_SECONDS)
		return false
	end
	local cost = price(area.gate.price)
	if status ~= "buy" or not Items.affords(team.wallet, cost) then
		return false
	end
	if reach and not inReach(player, Map.gatePrompt(Map.gate(ocean, area))) then
		return false
	end
	spend(cost)
	table.insert(save.gatesOpen, area.id)
	Map.openGate(ocean, area)
	publishGates()
	card(`{player.DisplayName} opened {area.name} for the team!`)
	task.spawn(saveRun, `gate {area.id} opened`)
	return true
end

-- The stand prompt of `area`: buys the cheapest item sold there that the team can buy now
-- (Items.standPick; one prompt per stand), or says why it can't (Items.standOffer). `stand`: a cove
-- shop (Config.stands) selling its own items instead. The area must be open, the item not owned and
-- affordable at the team's price, and the player by the stand.
local function onStand(player: Player, area, prompt: ProximityPrompt, stand: string?)
	local state = states[player]
	local now = os.clock()
	if not state or run.phase ~= "playing" or now - state.standAt < STAND_COOLDOWN then
		return
	end
	state.standAt = now
	if not Areas.open(gatesOpen())[area.id] or not inReach(player, prompt) then
		return
	end
	local key = stand or area.id
	local last = standBuys[key]
	if last and last.by ~= player and now - last.at < STAND_RACE then
		remotes.Card:FireClient(player, `{last.by.DisplayName} just bought the {last.name} for the team`, CARD_SECONDS)
		return
	end
	local item, status = Items.standOffer(Config, team, area.id, openAreas(), team.wallet, stand, run.teamSize)
	if status ~= "buy" then
		local why = Format.standCard(item, status, team.wallet, item and Areas.byId(Config, item.area), fillOf(run.current), price)
		remotes.Card:FireClient(player, why, CARD_SECONDS)
		return
	end
	spend(price(item.price))
	table.insert(team.owned, item.id)
	team.itemLevels[item.id] = 0
	standBuys[key] = { at = now, by = player, name = item.name }
	teamChanged()
	local bought = if item.kind == "staff" then `You hired a {item.name} for the team! Assign them in TAB (Staff)` else `You bought the {item.name} for the team!`
	remotes.Card:FireClient(player, bought, CARD_SECONDS)
	announce(player, `the {item.name}`)
	task.spawn(saveRun, `{player.Name} bought {item.id}`)
end

-- Gadget requests from the hotbar gadget in hand (client/Action, client/Jetpack):
--   "clip": clip the Garden Hose to the Tap of a reachable open area within Zones.REACH;
--   "spray", on: the clipped hose pours (credited in tickHose) while the act input is held;
--   "fly", on: the Jetpack Tank's lift on or off (off by itself when its fuel runs out).
-- Water and fuel follow the server's clock, so toggles only switch things; they are rate-limited.
local function onGadget(player: Player, action: unknown, on: unknown)
	local state = states[player]
	if not state or run.phase ~= "playing" or not allow(state, "gadget", MAX_GADGET_PER_SECOND) then
		return
	end
	if action == "clip" and state.gadget == "gardenHose" and not state.hose then
		local area, tap = openSpot(player, "Tap")
		if area then
			state.hose = { area = area, tap = tap, spraying = false, due = 0 }
			publish(player)
		end
	elseif action == "spray" and type(on) == "boolean" and state.hose and state.hose.spraying ~= on then
		if on then
			Vehicles.stopSpray(player) -- never both hoses at once
		end
		state.hose.spraying, state.hose.due = on, 0
		publish(player)
	elseif action == "fly" and type(on) == "boolean" and state.gadget == "jetpackTank" and state.flying ~= on then
		if on and state.fuel <= 0 then
			return
		end
		state.flying = on
		publish(player)
	end
end

-- Whether the character stands on something (the jetpack refuels only then).
local function grounded(player: Player, root: BasePart): boolean
	return Zones.ground(player.Character :: Model, root) ~= nil
end

-- The jetpack's fuel burns while flying and refills on the ground; the lift stops when it is empty.
local function tickJetpack(player: Player, state, dt: number)
	local max = Items.gadgetStat(Config, team, "jetpackTank", "flightSeconds")
	if not max then
		return
	end
	local root = rootOf(player)
	local onGround = not state.flying and state.fuel < max and root ~= nil and grounded(player, root)
	local jet = Items.get(Config, "jetpackTank")
	state.fuel = Gadgets.fuel(state.fuel, max, dt, state.flying, onGround, jet.rechargeSeconds)
	if state.flying and state.fuel <= 0 then
		state.flying = false
		publish(player)
	else
		publishFuel(player, state)
	end
end

-- The clipped hose pours `rate` litres a second at its tap's area pay while it sprays. Walking
-- further from the tap than its reach (the rope holds you, so only a lag spike or a teleport does)
-- takes it off.
local function tickHose(player: Player, state, dt: number)
	local hose = state.hose
	if not hose then
		return
	end
	local root = rootOf(player)
	local reach = Items.gadgetStat(Config, team, "gardenHose", "reach") :: number
	if not root or (root.Position - hose.tap.Position).Magnitude > reach + DISTANCE_SLACK then
		state.hose = nil
		publish(player)
		remotes.Card:FireClient(player, "The hose came off the tap", CARD_SECONDS)
		return
	end
	if not hose.spraying then
		return
	end
	hose.due += dt
	if hose.due < HOSE_TICK then
		return
	end
	local rate = Items.gadgetStat(Config, team, "gardenHose", "rate") :: number
	local litres = Water.pourAmount(rate * hose.due, run.current, run.target)
	hose.due = 0
	if litres > 0 then
		pourIn(player, litres, litres * Config.ocean.coinsPerLitre * hose.area.payMultiplier)
		publish(player)
		checkFull()
	end
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
	for _, name in { "Buy", "Card", "Equip", "Act", "Look", "Admin", "Gadget", "Vehicle", "Build", "Staff" } do
		remotes[name] = remote(name)
	end
	setGlobal("Fill", 0)
	setGlobal("Waiting", "")
	publishGates()
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
	remotes.Gadget.OnServerEvent:Connect(onGadget)
	-- What the area mechanics, the vehicles, the buildings and the staff may see and do in the run.
	local hooks = {
		states = states,
		team = function()
			return team
		end,
		price = price,
		spend = spend,
		pay = function(coins)
			earn(nil, coins)
		end,
		playing = function()
			return run.phase == "playing"
		end,
		loaded = function()
			return run.save ~= nil
		end,
		openIds = function()
			return Areas.openIds(gatesOpen())
		end,
		openAreas = openAreas,
		rootOf = rootOf,
		inReach = inReach,
		card = card,
		tell = function(player, text)
			remotes.Card:FireClient(player, text, CARD_SECONDS)
		end,
		walkChanged = applyWalkSpeed,
		save = function(reason)
			task.spawn(saveRun, reason)
		end,
		allow = allow,
		nearFlood = function(player)
			return nearFlood(player)
		end,
		water = function()
			return run.current, run.target
		end,
		pour = function(player, litres, value, areaId)
			pourIn(player, litres, value)
			worked(states[player], areaId) -- running the vehicle's loop speeds up the Firefighters on it
			publish(player)
			checkFull()
		end,
		-- Building and staff pay is raw: no Tip Jar or boost (those are a player's own pours).
		fill = function(litres)
			local taken = Water.pourAmount(litres, run.current, run.target)
			if taken > 0 then
				raise(taken)
				checkFull()
			end
			return taken
		end,
		stopHose = function(player)
			local state = states[player]
			if state and state.hose and state.hose.spraying then
				state.hose.spraying = false
				publish(player)
			end
		end,
		vehicle = remotes.Vehicle,
	}
	Payroll.start(hooks)
	Mechanics.start(ocean, hooks)
	Vehicles.start(ocean, hooks)
	Buildings.start(hooks, remotes.Build)
	Staff.start(ocean, hooks, remotes.Staff)
	RunService.Heartbeat:Connect(function(dt)
		if run.phase ~= "playing" then
			return
		end
		for player, state in states do
			tickJetpack(player, state, dt)
			tickHose(player, state, dt)
		end
	end)
	for _, area in Config.areas do
		if area.model then
			Map.gatePrompt(Map.gate(ocean, area)).Triggered:Connect(function(player)
				openGate(player, area, true)
			end)
		end
		local stand = Map.stand(ocean, area)
		local prompt = stand and Map.standPrompt(stand)
		if prompt then
			prompt.Triggered:Connect(function(player)
				onStand(player, area, prompt)
			end)
		else
			warn(`[Run] {area.name}'s stand has no ProximityPrompt "Prompt" (Studio); its items can't be bought yet`)
		end
	end
	-- The cove shops that sell their own items (Config.stands, Item.stand).
	for name in Config.stands do
		local prompt = Map.shopPrompt(name)
		prompt.Triggered:Connect(function(player)
			onStand(player, Areas.byId(Config, 1), prompt, name)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		Vehicles.leave(player)
		local state = states[player]
		if state then
			Payroll.payNow() -- the ticked pay so far goes into this save
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
		Payroll.payNow()
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
		-- StudioMoney: a number of coins put into the team's wallet.
		workspace:GetAttributeChangedSignal("StudioMoney"):Connect(function()
			local coins = workspace:GetAttribute("StudioMoney")
			if type(coins) == "number" and coins > 0 and run.phase == "playing" then
				workspace:SetAttribute("StudioMoney", nil)
				earn(nil, coins)
			end
		end)
	end
end

return Run
