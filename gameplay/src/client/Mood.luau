-- Lighting mood: a bright, vibrant sunny day. As the current basin fills it lifts to a slightly
-- more saturated, cloudier look. Each stage starts dry again (the sun drained it).
-- Runs on the client only, so changes are local and smooth. All effects are baked into the place.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EASE = 1.5 -- how quickly the mood follows the fill (slow, so it reads as weather)

-- Two looks; everything in between is a blend by wetness (0 = dry, 1 = full).
-- Owner direction (2026-11-04): vibrant, happy and alive (reference: bright stylized sim
-- lighting): deep blue sky, strong warm sun, crisp shadows, no grey haze, punchy colour.
-- Filling a basin lifts it a little more (more saturation, puffier clouds).
local DRY = {
	clockTime = 13.8,
	brightness = 3.2,
	ambient = Color3.fromRGB(130, 126, 140),
	outdoorAmbient = Color3.fromRGB(165, 160, 170),
	tint = Color3.fromRGB(255, 250, 240),
	saturation = 0.3,
	contrast = 0.12,
	atmosphereColor = Color3.fromRGB(199, 226, 255),
	atmosphereDecay = Color3.fromRGB(92, 140, 200),
	density = 0.22,
	haze = 0,
	glare = 0,
	bloom = 0.35,
	sunRays = 0.05,
	cloudCover = 0.45,
	cloudDensity = 0.55,
	cloudColor = Color3.fromRGB(255, 255, 255),
}
local WET = {
	clockTime = 14.2,
	brightness = 3.2,
	ambient = Color3.fromRGB(128, 130, 145),
	outdoorAmbient = Color3.fromRGB(160, 165, 175),
	tint = Color3.fromRGB(252, 252, 255),
	saturation = 0.38,
	contrast = 0.14,
	atmosphereColor = Color3.fromRGB(195, 225, 255),
	atmosphereDecay = Color3.fromRGB(85, 140, 205),
	density = 0.2,
	haze = 0,
	glare = 0,
	bloom = 0.35,
	sunRays = 0.05,
	cloudCover = 0.55,
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
	depth.FarIntensity = 0.06
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
