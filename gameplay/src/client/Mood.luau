-- Lighting mood: a cozy sunny day. As the current basin fills it lifts to a slightly more
-- saturated, cloudier, sparklier look. Each stage starts dry again (the sun drained it).
-- Runs on the client only, so changes are local and smooth. All effects are baked into the place.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EASE = 1.5 -- how quickly the mood follows the fill (slow, so it reads as weather)

-- Two looks; everything in between is a blend by wetness (0 = dry, 1 = full).
-- Owner direction (2026-11-04): cozy and sunny, not deadly. The change from dry to wet is a
-- gentle "life comes back" lift, not desert vs oasis.
local DRY = {
	clockTime = 14.5,
	brightness = 2.7,
	ambient = Color3.fromRGB(118, 110, 112),
	outdoorAmbient = Color3.fromRGB(150, 140, 132),
	tint = Color3.fromRGB(255, 244, 228),
	saturation = 0.1,
	contrast = 0.06,
	atmosphereColor = Color3.fromRGB(205, 215, 230),
	atmosphereDecay = Color3.fromRGB(120, 145, 180),
	density = 0.27,
	haze = 0.7,
	glare = 0.15,
	bloom = 0.5,
	sunRays = 0.08,
	cloudCover = 0.5,
	cloudDensity = 0.45,
	cloudColor = Color3.fromRGB(255, 252, 248),
}
local WET = {
	clockTime = 15,
	brightness = 2.6,
	ambient = Color3.fromRGB(108, 112, 122),
	outdoorAmbient = Color3.fromRGB(140, 145, 150),
	tint = Color3.fromRGB(255, 250, 242),
	saturation = 0.22,
	contrast = 0.08,
	atmosphereColor = Color3.fromRGB(195, 215, 235),
	atmosphereDecay = Color3.fromRGB(105, 140, 185),
	density = 0.25,
	haze = 0.4,
	glare = 0.1,
	bloom = 0.45,
	sunRays = 0.06,
	cloudCover = 0.62,
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
	bloom.Size = 28
	bloom.Threshold = 1.1
	sunRays.Spread = 0.6
	depth.FocusDistance = 40
	depth.InFocusRadius = 70
	depth.NearIntensity = 0
	depth.FarIntensity = 0.18
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4

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
