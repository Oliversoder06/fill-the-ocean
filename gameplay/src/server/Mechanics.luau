-- Area mechanics on the server (Config.areas `mechanic`, shared/AreaRules): steam vents, snow, the
-- drifting cloud, the rocks in front of the deeper pools and the golden spring. server/Run starts
-- it with hooks into the run, hands it the save (Mechanics.load) and asks it for the broken rocks
-- and the golden area when it credits a scoop; the scoop maths itself is AreaRules'.
-- Clients only show: every vent part gets VentState ("warn" | "burst") and VentAt (server time) for
-- client/Mechanics to play its emitters; ReplicatedStorage gets RocksBroken ("1,3"), Golden (an
-- area id, 0 for none) and GoldenEndsAt (server time). The cloud's Source moves by a server tween.
-- Vents, the cloud's drift and the golden spring run only between Mechanics.play and Mechanics.stop
-- (server/Run: while the phase is "playing").
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AreaRules = require(ReplicatedStorage.Shared.AreaRules)
local Config = require(ReplicatedStorage.Shared.Config)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local RunSave = require(ReplicatedStorage.Common.RunSave)
local Map = require(script.Parent.Map)

local SNOW_TICK = 0.25 -- seconds between checks of what each player stands on
local ROCK_COOLDOWN = 0.5 -- seconds between accepted rock prompts per player (exploits can fire prompts)
local PUSH_FORCE = 20 -- the steam push's strongest force, in body weights (it must beat walking)

export type Hooks = {
	states: { [Player]: any }, -- server/Run's player states (levels, owned, iceHits, onSnow, rockAt)
	playing: () -> boolean,
	openIds: () -> { number }, -- the open area ids (Areas.openIds)
	rootOf: (Player) -> BasePart?,
	inReach: (Player, ProximityPrompt) -> boolean,
	card: (string) -> (), -- a card for everyone
	tell: (Player, string) -> (), -- a card for one player
	walkChanged: (Player) -> (), -- re-apply a player's walk speed (state.onSnow changed)
	save: (string) -> (), -- save the run soon (the reason, for warnings)
}

local Mechanics = {}

local ocean: Model
local hooks: Hooks
local save: RunSave.Save? = nil -- the run's save once loaded (the same table server/Run writes)
local golden: { id: number, token: number }? = nil
local goldenToken = 0
local rng = Random.new()
local active = false -- between play and stop
local generation = 0 -- each play's loops run only while it is the current one
local tweens: { Tween } = {} -- the running cloud drifts

-- The area ids whose rock is broken (their deeper pool is open); none before the save is loaded.
function Mechanics.rocksBroken(): { number }
	return if save then save.rocksBroken else {}
end

-- The area whose Source is golden now, or nil.
function Mechanics.goldenId(): number?
	return golden and golden.id
end

local function publishRocks()
	ReplicatedStorage:SetAttribute("RocksBroken", table.concat(Mechanics.rocksBroken(), ","))
end

-- The run's save is in: its broken rocks stay broken, and the others stand (an admin reset loads a
-- blank save over a played one).
function Mechanics.load(runSave: RunSave.Save)
	save = runSave
	for _, area in Config.areas do
		if table.find(runSave.rocksBroken, area.id) then
			Map.breakRock(ocean, area)
		else
			Map.mendRock(ocean, area)
		end
	end
	publishRocks()
end

-- Steam pushes the player away from the vent and up for a moment. The character's physics belong
-- to its client, so the push is a constraint (it replicates and the client simulates it).
local function push(root: BasePart, from: Vector3)
	local steam = Config.steam
	local away = (root.Position - from) * Vector3.new(1, 0, 1)
	local direction = if away.Magnitude > 0.1 then away.Unit else -root.CFrame.LookVector
	local attachment = Instance.new("Attachment")
	attachment.Name = "SteamPushAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "SteamPush"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = direction * steam.push + Vector3.yAxis * steam.lift
	velocity.MaxForce = root.AssemblyMass * workspace.Gravity * PUSH_FORCE
	velocity.Parent = root
	Debris:AddItem(velocity, steam.pushSeconds)
	Debris:AddItem(attachment, steam.pushSeconds)
end

-- A vent bursts: every player close enough without Heat Gloves is pushed away.
local function burst(vent: BasePart)
	if not hooks.playing() then
		return
	end
	for player, state in hooks.states do
		local root = hooks.rootOf(player)
		if root and AreaRules.knocked((root.Position - vent.Position).Magnitude, Config.steam, Items.owned(state, "heatGloves")) then
			push(root, vent.Position)
		end
	end
end

-- Each steam area's vents take turns: a puff, then warnSeconds later a burst, every period.
local function startVents(area)
	local vents = Map.vents(ocean, area)
	local last = workspace:GetServerTimeNow()
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		if not active then
			last = now
			return
		end
		for i, vent in vents do
			local warned, burstNow = AreaRules.ventEvents(last, now, AreaRules.ventOffset(i, #vents, Config.steam.period), Config.steam)
			if warned or burstNow then
				vent:SetAttribute("VentState", if burstNow then "burst" else "warn")
				vent:SetAttribute("VentAt", now)
			end
			if burstNow then
				burst(vent)
			end
		end
		last = now
	end)
end

-- The cloud's Source drifts from point to point of its CloudPath, round and round, until stop.
local function startCloud(area, run: number)
	local source = Zones.areaPart(ocean, area, "Source") :: BasePart
	local path = Map.cloudPath(ocean, area)
	local leg = TweenInfo.new(Config.cloud.legSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	task.spawn(function()
		local i = 1
		while generation == run do
			local goal = source.CFrame.Rotation + path[i].Position
			local tween = TweenService:Create(source, leg, { CFrame = goal })
			table.insert(tweens, tween)
			tween:Play()
			tween.Completed:Wait()
			table.remove(tweens, table.find(tweens, tween))
			i = i % #path + 1
		end
	end)
end

-- Snow terrain under the feet slows walking (AreaRules.walkSpeed, applied by server/Run); in the
-- air it keeps what it was.
local function checkSnow()
	for player, state in hooks.states do
		local root = hooks.rootOf(player)
		local hit = root and Zones.ground(player.Character :: Model, root)
		if hit then
			local onSnow = hit.Instance == workspace.Terrain and hit.Material == Enum.Material.Snow
			if onSnow ~= state.onSnow then
				state.onSnow = onSnow
				hooks.walkChanged(player)
			end
		end
	end
end

-- An area's rock prompt: a player holding the area's top tool (AreaRules.canBreak) breaks it for
-- the whole team, and the deeper pool behind it opens. Saved in save.rocksBroken.
local function onRock(player: Player, area, prompt: ProximityPrompt)
	local state = hooks.states[player]
	local now = os.clock()
	if not state or not save or not hooks.playing() or now - state.rockAt < ROCK_COOLDOWN then
		return
	end
	state.rockAt = now
	if table.find(save.rocksBroken, area.id) or not table.find(hooks.openIds(), area.id) or not hooks.inReach(player, prompt) then
		return
	end
	if not state.equipped then -- the tool must be in hand, not a gadget or nothing
		hooks.tell(player, "Take your tool out to break the rock")
		return
	end
	if not AreaRules.canBreak(Config, state.levels, area.id) then
		local _, tool = AreaRules.rockTool(Config, area.id)
		hooks.tell(player, `Only the {tool.name} or bigger breaks this rock`)
		return
	end
	table.insert(save.rocksBroken, area.id)
	Map.breakRock(ocean, area)
	publishRocks()
	hooks.card(`{player.DisplayName} broke the rock: a deeper pool in {area.name}!`)
	hooks.save(`rock {area.id} broken`)
end

local function endGolden(token: number)
	if golden and golden.token == token then
		golden = nil
		ReplicatedStorage:SetAttribute("Golden", 0)
	end
end

-- One open area's Source turns golden for Config.golden.seconds and everyone is told.
local function startGolden()
	local area = Areas.byId(Config, AreaRules.goldenPick(hooks.openIds(), rng:NextNumber()))
	goldenToken += 1
	local token = goldenToken
	golden = { id = area.id, token = token }
	local g = Config.golden
	ReplicatedStorage:SetAttribute("GoldenEndsAt", workspace:GetServerTimeNow() + g.seconds)
	ReplicatedStorage:SetAttribute("Golden", area.id)
	hooks.card(`The {area.name} spring turned gold! {g.pay}x pay for {math.round(g.seconds / 60)} minutes`)
	task.delay(g.seconds, endGolden, token)
end

-- Play starts (or resumes): vents puff and burst, clouds drift and golden springs come every
-- goldenDelay seconds.
function Mechanics.play()
	if active then
		return
	end
	active = true
	generation += 1
	local run = generation
	for _, area in Config.areas do
		if area.mechanic == "cloud" then
			startCloud(area, run)
		end
	end
	task.spawn(function()
		while true do
			task.wait(AreaRules.goldenDelay(Config, rng:NextNumber()))
			if generation ~= run then
				return
			end
			if not golden then
				startGolden()
			end
		end
	end)
end

-- Play ended: the vents go quiet, the clouds stop and a golden spring ends at once (no new one).
function Mechanics.stop()
	active = false
	generation += 1
	for _, tween in table.clone(tweens) do
		tween:Cancel()
	end
	if golden then
		endGolden(golden.token)
	end
end

function Mechanics.start(oceanModel: Model, runHooks: Hooks)
	ocean, hooks = oceanModel, runHooks
	ReplicatedStorage:SetAttribute("Golden", 0)
	publishRocks()
	for _, area in Config.areas do
		local prompt = Map.rockPrompt(Map.rock(ocean, area))
		prompt.Triggered:Connect(function(player)
			onRock(player, area, prompt)
		end)
		if area.mechanic == "steam" then
			startVents(area)
		end
	end

	local sinceSnow = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceSnow += dt
		if sinceSnow >= SNOW_TICK then
			sinceSnow = 0
			checkSnow()
		end
	end)

	-- Studio-only test shortcut: set workspace attribute StudioGolden to true to start one now.
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("StudioGolden"):Connect(function()
			if workspace:GetAttribute("StudioGolden") == true and active then
				workspace:SetAttribute("StudioGolden", nil)
				startGolden()
			end
		end)
	end
end

return Mechanics
