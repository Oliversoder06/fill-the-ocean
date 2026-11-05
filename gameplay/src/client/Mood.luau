-- Lighting mood: a bright, vibrant, cinematic late afternoon. As the current basin fills it lifts to a slightly
-- more saturated, cloudier look. Each stage starts dry again (the sun drained it).
-- Runs on the client only, so changes are local and smooth. All effects are baked into the place.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EASE = 1.5 -- how quickly the mood follows the fill (slow, so it reads as weather)

-- Two looks; everything in between is a blend by wetness (0 = dry, 1 = full).
-- Owner direction (2026-11-05): vibrant and happy (bright stylized sim lighting) AND cinematic:
-- late-afternoon sun with long shadows, distance fog that keeps the play area clear (Atmosphere
-- Offset pushes it out), glare around the sun, sun rays, soft bloom, a light lens blur far away.
-- Filling a basin clears the air a little and adds saturation.
local DRY = {
	clockTime = 16.4,
	brightness = 3.1,
	ambient = Color3.fromRGB(140, 128, 122),
	outdoorAmbient = Color3.fromRGB(176, 162, 150),
	tint = Color3.fromRGB(255, 244, 228),
	saturation = 0.3,
	contrast = 0.16,
	atmosphereColor = Color3.fromRGB(214, 228, 246),
	atmosphereDecay = Color3.fromRGB(120, 160, 214),
	density = 0.36,
	offset = 0.3,
	haze = 1.4,
	glare = 0.45,
	bloom = 0.55,
	sunRays = 0.12,
	cloudCover = 0.48,
	cloudDensity = 0.55,
	cloudColor = Color3.fromRGB(255, 250, 244),
}
local WET = {
	clockTime = 16.8,
	brightness = 3.1,
	ambient = Color3.fromRGB(136, 130, 128),
	outdoorAmbient = Color3.fromRGB(170, 164, 158),
	tint = Color3.fromRGB(255, 246, 236),
	saturation = 0.38,
	contrast = 0.17,
	atmosphereColor = Color3.fromRGB(206, 228, 250),
	atmosphereDecay = Color3.fromRGB(108, 156, 216),
	density = 0.3,
	offset = 0.35,
	haze = 1.0,
	glare = 0.35,
	bloom = 0.5,
	sunRays = 0.1,
	cloudCover = 0.56,
	cloudDensity = 0.6,
	cloudColor = Color3.fromRGB(255, 255, 255),
}

local Mood = {}

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
	sky.SunAngularSize = 14 -- a friendly, slightly big sun
	sky.CelestialBodiesShown = true

	-- Fixed settings that don't change with wetness
	bloom.Size = 36
	bloom.Threshold = 0.95
	sunRays.Spread = 0.85
	depth.FocusDistance = 60
	depth.InFocusRadius = 90
	depth.NearIntensity = 0
	depth.FarIntensity = 0.22
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.6

	local wetness = 0
	local applied = -1
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
	end)
end

return Mood
