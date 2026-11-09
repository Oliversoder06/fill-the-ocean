-- Area mechanics you see (server/Mechanics runs them): each steam vent puffs a warning and then
-- bursts when the server says so (vent attributes VentState + VentAt), and the golden spring's
-- Source glows while ReplicatedStorage's Golden names its area. Emitter and effect names are in
-- Cues.mechanics. Areas not streamed in yet are picked up once they arrive.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Areas = require(ReplicatedStorage.Common.Areas)
local Hud = require(script.Parent.Hud)

local SCAN_SECONDS = 0.5 -- how often to look for vents and the golden Source that streamed in

local Mechanics = {}

-- One of a vent's emitters by name; a missing one is a place bug.
local function emitter(vent: BasePart, name: string): ParticleEmitter
	local found = vent:FindFirstChild(name)
	assert(found and found:IsA("ParticleEmitter"), `{vent:GetFullName()} is missing ParticleEmitter {name}`)
	assert(type(found:GetAttribute("Burst")) == "number", `{found:GetFullName()} needs a number attribute Burst`)
	return found
end

local function watchVent(vent: BasePart)
	local puff, burst = emitter(vent, Cues.mechanics.puff), emitter(vent, Cues.mechanics.burst)
	vent:GetAttributeChangedSignal("VentAt"):Connect(function()
		local e = if vent:GetAttribute("VentState") == "burst" then burst else puff
		e:Emit(e:GetAttribute("Burst"))
	end)
end

function Mechanics.start()
	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local glowTemplate = vfx:WaitForChild(Cues.mechanics.golden, 10)
	assert(glowTemplate and glowTemplate:IsA("Attachment"), `Vfx is missing {Cues.mechanics.golden} (an Attachment)`)

	local watched: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local glow: Attachment? = nil

	local function scan()
		local ocean = Hud.ocean()
		if not ocean then
			return
		end
		for _, area in Config.areas do
			local model = if area.mechanic == "steam" then Zones.areaModel(ocean, area) else nil
			local vents = model and model:FindFirstChild("Vents")
			if vents then
				for _, vent in vents:GetChildren() do
					if vent:IsA("BasePart") and not watched[vent] then
						watched[vent] = true
						watchVent(vent)
					end
				end
			end
		end
		-- The golden Source glows; a Source that streamed out takes its glow with it.
		local area = Areas.byId(Config, ReplicatedStorage:GetAttribute("Golden"))
		local source = area and Zones.areaPart(ocean, area, "Source")
		if glow and (glow.Parent ~= source or not source) then
			glow:Destroy()
			glow = nil
		end
		if source and not glow then
			local new = glowTemplate:Clone()
			new.Parent = source
			glow = new
		end
	end

	local since = SCAN_SECONDS
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= SCAN_SECONDS then
			since = 0
			scan()
		end
	end)
end

return Mechanics
