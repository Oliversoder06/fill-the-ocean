-- Lighting mood: a calm, comfortable sunny late afternoon. A drained basin is warm and a little
-- hazy with straw-coloured grass; as it fills, the colour, clear air and green grass come back.
-- Runs on the client only, so changes are local and smooth. All effects are baked into the place.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EASE = 1.5 -- how quickly the mood follows the fill (slow, so it reads as weather)

-- Two looks; everything in between is a blend by wetness (0 = dry, 1 = full).
-- Owner direction (2026-11-05): vibrant and happy (bright stylized sim lighting) AND cinematic:
-- late-afternoon sun with long shadows, distance fog that keeps the play area clear (Atmosphere
-- Offset pushes it out), soft sun rays and bloom, a light lens blur far away.
-- Owner (2026-11-11): calmer and comfortable: a blue horizon, no white wash near the sun, sand that
-- reads as sand (values tested in play).
-- Dry is the sun winning: warm and a little hazy, with straw-coloured grass.
-- Filling the basin brings the world back: colour, clear air and green grass (the place's own
-- terrain colours are the wet look).
local DRY = {
	clockTime = 15.6,
	brightness = 2.8,
	ambient = Color3.fromRGB(140, 128, 118),
	outdoorAmbient = Color3.fromRGB(168, 154, 140),
	tint = Color3.fromRGB(255, 238, 216),
	saturation = 0.14,
	contrast = 0.22,
	atmosphereColor = Color3.fromRGB(226, 228, 230),
	atmosphereDecay = Color3.fromRGB(156, 174, 204),
	density = 0.3,
	offset = 0.3,
	haze = 0.8,
	glare = 0.15,
	bloom = 0.3,
	sunRays = 0.05,
	cloudCover = 0.3,
	cloudDensity = 0.4,
	cloudColor = Color3.fromRGB(255, 240, 222),
}
local WET = {
	clockTime = 16.8,
	brightness = 2.6,
	ambient = Color3.fromRGB(132, 128, 128),
	outdoorAmbient = Color3.fromRGB(158, 154, 150),
	tint = Color3.fromRGB(255, 248, 240),
	saturation = 0.25,
	contrast = 0.2,
	atmosphereColor = Color3.fromRGB(210, 226, 244),
	atmosphereDecay = Color3.fromRGB(110, 150, 210),
	density = 0.28,
	offset = 0.35,
	haze = 0.5,
	glare = 0.08,
	bloom = 0.25,
	sunRays = 0.04,
	cloudCover = 0.56,
	cloudDensity = 0.6,
	cloudColor = Color3.fromRGB(255, 255, 255),
}

local Mood = {}

-- Dry terrain colours; the wet ones are read from the place at start.
local DRY_TERRAIN = {
	[Enum.Material.Grass] = Color3.fromRGB(190, 168, 96),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(182, 160, 92),
	[Enum.Material.Ground] = Color3.fromRGB(170, 140, 104),
}
local TERRAIN_STEP = 0.01 -- recolouring terrain is heavier than lighting, so do it in coarser steps

-- Effects are baked into Lighting in the place; a missing one is a place bug.
local function effect(className: string): Instance
	local found = Lighting:FindFirstChildOfClass(className)
	assert(found, `Lighting is missing a {className}`)
	return found
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Mood.start()
	local atmosphere = effect("Atmosphere") :: Atmosphere
	local bloom = effect("BloomEffect") :: BloomEffect
	local sunRays = effect("SunRaysEffect") :: SunRaysEffect
	local color = effect("ColorCorrectionEffect") :: ColorCorrectionEffect
	local depth = effect("DepthOfFieldEffect") :: DepthOfFieldEffect
	local sky = effect("Sky") :: Sky
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	assert(clouds, "Terrain is missing its Clouds")
	sky.CelestialBodiesShown = true -- the real sun disc

	-- Fixed settings that don't change with wetness
	bloom.Size = 24
	bloom.Threshold = 1.6
	sunRays.Spread = 0.6
	depth.FocusDistance = 60
	depth.InFocusRadius = 90
	depth.NearIntensity = 0
	depth.FarIntensity = 0.1
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.4

	local terrain = workspace.Terrain
	local wetTerrain = {}
	for material in DRY_TERRAIN do
		wetTerrain[material] = terrain:GetMaterialColor(material)
	end

	local wetness = 0
	local applied = -1
	local terrainApplied = -1
	RunService.RenderStepped:Connect(function(dt)
		local fill = ReplicatedStorage:GetAttribute("Fill")
		local target = if type(fill) == "number" then math.clamp(fill, 0, 1) else 0
		wetness += (target - wetness) * (1 - math.exp(-EASE * dt))
		if math.abs(wetness - applied) < 0.002 then
			return -- nothing visible changed; skip property writes
		end
		applied = wetness
		local t = wetness
		Lighting.ClockTime = lerp(DRY.clockTime, WET.clockTime, t)
		Lighting.Brightness = lerp(DRY.brightness, WET.brightness, t)
		Lighting.Ambient = DRY.ambient:Lerp(WET.ambient, t)
		Lighting.OutdoorAmbient = DRY.outdoorAmbient:Lerp(WET.outdoorAmbient, t)
		color.TintColor = DRY.tint:Lerp(WET.tint, t)
		color.Saturation = lerp(DRY.saturation, WET.saturation, t)
		color.Contrast = lerp(DRY.contrast, WET.contrast, t)
		atmosphere.Color = DRY.atmosphereColor:Lerp(WET.atmosphereColor, t)
		atmosphere.Decay = DRY.atmosphereDecay:Lerp(WET.atmosphereDecay, t)
		atmosphere.Density = lerp(DRY.density, WET.density, t)
		atmosphere.Offset = lerp(DRY.offset, WET.offset, t)
		atmosphere.Haze = lerp(DRY.haze, WET.haze, t)
		atmosphere.Glare = lerp(DRY.glare, WET.glare, t)
		bloom.Intensity = lerp(DRY.bloom, WET.bloom, t)
		sunRays.Intensity = lerp(DRY.sunRays, WET.sunRays, t)
		clouds.Cover = lerp(DRY.cloudCover, WET.cloudCover, t)
		clouds.Density = lerp(DRY.cloudDensity, WET.cloudDensity, t)
		clouds.Color = DRY.cloudColor:Lerp(WET.cloudColor, t)
		if math.abs(t - terrainApplied) >= TERRAIN_STEP or (t > 0.999 and terrainApplied < 1) or (t < 0.001 and terrainApplied > 0) then
			terrainApplied = if t > 0.999 then 1 elseif t < 0.001 then 0 else t
			for material, dry in DRY_TERRAIN do
				terrain:SetMaterialColor(material, dry:Lerp(wetTerrain[material], terrainApplied))
			end
		end
	end)
end

return Mood
