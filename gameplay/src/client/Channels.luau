-- Poured water's trip to the ocean, client-side only. Each open area's channel (workspace.Areas.
-- <model>.Channel, server/Map) trickles: every Texture under its Water scrolls downstream. Every
-- accepted pour (ReplicatedStorage attribute LastPour, shared/PourFlow) at an area's Pour sends a wave
-- (a pooled clone of ReplicatedStorage.Vfx.ChannelWave) down its Channel.Path; where it meets the
-- ocean it splashes and the fill bar pulses (Hud.pulseFill). A pour into the ocean itself, or down a
-- channel not streamed in, just pulses the bar. The seabed's pour marker (workspace.Ocean.PourDecal)
-- fades out as the ocean fills. Numbers in Cues.channel. Also the texture scroll client/Buildings
-- uses for the aqueducts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local PourFlow = require(ReplicatedStorage.Shared.PourFlow)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Areas = require(ReplicatedStorage.Common.Areas)
local Feel = require(script.Parent.Feel)
local Hud = require(script.Parent.Hud)

local FIND_SECONDS = 1 -- seconds between looks for channel water and the marker (they stream in and out)

local Channels = {}

type Wave = {
	points: { Vector3 },
	lengths: { number },
	total: number,
	distance: number,
	litres: number,
	part: BasePart?, -- nil past Cues.channel.maxWaves: it still lands and pulses the bar, unseen
}

-- Every Texture in `root` (a part, or a model or folder of parts).
function Channels.textures(root: Instance): { Texture }
	local textures = {}
	for _, texture in root:GetDescendants() do
		if texture:IsA("Texture") then
			table.insert(textures, texture)
		end
	end
	return textures
end

-- Scrolls `textures` along V at `speed` studs a second (downstream, as the place lays them out).
function Channels.scroll(textures: { Texture }, speed: number, dt: number)
	for _, texture in textures do
		texture.OffsetStudsV = (texture.OffsetStudsV + speed * dt) % texture.StudsPerTileV
	end
end

local cue = Cues.channel
local template: BasePart
local pool: { BasePart } = {}
local emittersOf: { [BasePart]: { ParticleEmitter } } = {}
local waves: { Wave } = {}
local shown = 0 -- waves with a part out, landed ones still fading included
local trickles: { { Texture } } = {}
local markerBase: { [Decal]: number } = {} -- each marker decal's own transparency in the place

local function checkTemplate(): BasePart
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local wave = vfx:WaitForChild(cue.wave, 10)
	assert(wave and wave:IsA("BasePart"), `Vfx is missing {cue.wave} (a part holding ParticleEmitters)`)
	return wave
end

local function takePart(): BasePart?
	if shown >= cue.maxWaves then
		return nil
	end
	shown += 1
	local part = table.remove(pool)
	if not part then
		part = template:Clone()
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false -- aim rays see through it
		part.CanTouch = false
		local emitters = {}
		for _, emitter in part:GetDescendants() do
			if emitter:IsA("ParticleEmitter") then
				table.insert(emitters, emitter)
			end
		end
		emittersOf[part] = emitters
	end
	for _, emitter in emittersOf[part] do
		emitter.Enabled = true
	end
	return part
end

-- A landed wave's part stops emitting, lingers while its particles fade, then goes back to the pool.
local function releasePart(part: BasePart)
	for _, emitter in emittersOf[part] do
		emitter.Enabled = false
	end
	task.delay(cue.waveLinger, function()
		part.Parent = nil
		shown -= 1
		table.insert(pool, part)
	end)
end

-- Puts a wave's part where it is along its path, facing downstream (level, so drops don't flip it).
local function place(wave: Wave, part: BasePart)
	local i, f = PourFlow.along(wave.lengths, wave.distance)
	local from, to = wave.points[i], wave.points[i + 1]
	local at = from:Lerp(to, f)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	part.CFrame = if flat.Magnitude > 1e-3 then CFrame.lookAt(at, at + flat) else part.CFrame.Rotation + at
end

local function onPour()
	local value = ReplicatedStorage:GetAttribute("LastPour")
	local areaId, litres = PourFlow.decode(value)
	if not (areaId and litres) then
		warn(`[Channels] LastPour {tostring(value)} isn't "<areaId>@<litres>@<serverTime>" (server/Run)`)
		return
	end
	local area = Areas.byId(Config, areaId)
	local ocean = Hud.ocean()
	local points = if area and ocean then Zones.channelPath(ocean, area) else nil
	if not points then
		Hud.pulseFill(litres) -- into the ocean itself, or a channel not streamed in
		return
	end
	local lengths = {}
	for i = 1, #points - 1 do
		table.insert(lengths, (points[i + 1] - points[i]).Magnitude)
	end
	local wave: Wave = { points = points, lengths = lengths, total = PourFlow.total(lengths), distance = 0, litres = litres, part = nil }
	local part = takePart()
	if part then
		place(wave, part)
		part.Parent = workspace
	end
	wave.part = part
	table.insert(waves, wave)
end

-- Finds the open areas' channel water and the seabed marker again (streaming), and fades the marker.
local function refresh()
	local ocean = Hud.ocean()
	table.clear(trickles)
	if not ocean then
		return
	end
	local open = Areas.open(Hud.gatesOpen())
	for _, area in Config.areas do
		local model = if area.model and open[area.id] then Zones.areaModel(ocean, area) else nil
		local channel = model and model:FindFirstChild("Channel")
		local water = channel and channel:FindFirstChild("Water")
		if water then
			table.insert(trickles, Channels.textures(water))
		end
	end
	local marker = ocean:FindFirstChild("PourDecal")
	if not marker then
		return
	end
	local fill = ReplicatedStorage:GetAttribute("Fill")
	for _, decal in marker:GetChildren() do
		if decal:IsA("Decal") then
			local base = markerBase[decal] or decal.Transparency
			markerBase[decal] = base
			Hud.set(decal, "Transparency", PourFlow.markerTransparency(base, if type(fill) == "number" then fill else 0, cue.markerFadeFill))
		end
	end
end

function Channels.start()
	template = checkTemplate()
	ReplicatedStorage:GetAttributeChangedSignal("LastPour"):Connect(onPour)
	local nextRefresh = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		if now >= nextRefresh then
			nextRefresh = now + FIND_SECONDS
			refresh()
		end
		for _, textures in trickles do
			Channels.scroll(textures, cue.trickleSpeed, dt)
		end
		for i = #waves, 1, -1 do
			local wave = waves[i]
			wave.distance += cue.waveSpeed * dt
			local part = wave.part
			if part then
				place(wave, part)
			end
			if wave.distance >= wave.total then
				table.remove(waves, i)
				Hud.pulseFill(wave.litres)
				if part then
					Feel.splash(cue.splash, wave.points[#wave.points], 1, false)
					releasePart(part)
				end
			end
		end
	end)
end

return Channels
