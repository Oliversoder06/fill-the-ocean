-- Lighting mood: a bright, vibrant, cinematic late afternoon. A drained basin is scorched and
-- hazy with straw-coloured grass; as it fills, the colour, clear air and green grass come back.
-- Each stage starts dry again (the sun drained it).
-- The villain is in the sky: Roblox draws its own sun disc so bright that a face burns out, so the
-- disc is hidden and the angry sun (ReplicatedStorage.Vfx.SkySun, a BillboardGui) is held far
-- away in the sun's direction every frame. The real sun still lights the world and casts shadows.
-- Runs on the client only, so changes are local and smooth. All effects are baked into the place.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EASE = 1.5 -- how quickly the mood follows the fill (slow, so it reads as weather)
local SUN_DISTANCE = 40 -- studs; close, so the Atmosphere haze barely veils it (far things are handled by the raycast)
local SUN_DEGREES = 20 -- apparent size of the angry sun
local SUN_OCCLUDE_RANGE = 2000 -- studs checked for something between you and the sun
local SUN_FADE = 12 -- how quickly the sun fades behind and out from behind things

-- Two looks; everything in between is a blend by wetness (0 = dry, 1 = full).
-- Owner direction (2026-11-05): vibrant and happy (bright stylized sim lighting) AND cinematic:
-- late-afternoon sun with long shadows, distance fog that keeps the play area clear (Atmosphere
-- Offset pushes it out), glare around the sun, sun rays, soft bloom, a light lens blur far away.
-- Dry is the sun winning: scorched, washed-out, hazy and glaring, with straw-coloured grass.
-- Filling the basin brings the world back: colour, clear air and green grass (the place's own
-- terrain colours are the wet look).
local DRY = {
	clockTime = 15.6,
	brightness = 3.5,
	ambient = Color3.fromRGB(158, 128, 104),
	outdoorAmbient = Color3.fromRGB(196, 160, 126),
	tint = Color3.fromRGB(255, 222, 182),
	saturation = 0.02,
	contrast = 0.2,
	atmosphereColor = Color3.fromRGB(244, 230, 200),
	atmosphereDecay = Color3.fromRGB(228, 190, 130),
	density = 0.38,
	offset = 0.25,
	haze = 1.9,
	glare = 0.6,
	bloom = 0.8,
	sunRays = 0.24,
	cloudCover = 0.3,
	cloudDensity = 0.4,
	cloudColor = Color3.fromRGB(255, 240, 222),
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
	sky.CelestialBodiesShown = false -- the angry sun billboard replaces the disc (see top)

	local vfx = ReplicatedStorage:WaitForChild("Vfx", 10)
	assert(vfx, "ReplicatedStorage.Vfx is missing (the effects are baked into the place)")
	local sunTemplate = vfx:WaitForChild("SkySun", 10)
	assert(sunTemplate and sunTemplate:IsA("Attachment"), "Vfx is missing SkySun (an Attachment)")
	local sun = sunTemplate:Clone() :: Attachment
	local sunGui = sun:FindFirstChildOfClass("BillboardGui")
	assert(sunGui, "Vfx.SkySun needs a BillboardGui")
	local face = sunGui:FindFirstChildOfClass("ImageLabel")
	assert(face, "Vfx.SkySun.Gui needs an ImageLabel")
	local span = 2 * SUN_DISTANCE * math.tan(math.rad(SUN_DEGREES / 2))
	sunGui.Size = UDim2.fromScale(span, span)
	sun.Parent = workspace.Terrain
	local sunParams = RaycastParams.new()
	sunParams.FilterType = Enum.RaycastFilterType.Exclude
	local shown = 1
	RunService:BindToRenderStep("MoodSun", Enum.RenderPriority.Camera.Value + 4, function(dt)
		local camera = workspace.CurrentCamera
		local origin = camera.CFrame.Position
		local direction = Lighting:GetSunDirection()
		-- follows the camera, so it sits in the sky like the real sun
		sun.WorldPosition = origin + direction * SUN_DISTANCE
		-- hidden behind trees, walls and hills: fade out while something blocks the view of it
		local character = Players.LocalPlayer.Character
		local ignore: { Instance } = if character then { camera, character } else { camera }
		local blocked = direction.Y <= 0
		for _ = 1, 4 do -- see-through parts (invisible map walls, zones) don't hide the sun
			if blocked then
				break
			end
			sunParams.FilterDescendantsInstances = ignore
			local hit = workspace:Raycast(origin, direction * SUN_OCCLUDE_RANGE, sunParams)
			if not hit then
				break
			elseif hit.Instance:IsA("BasePart") and hit.Instance.Transparency >= 0.95 then
				table.insert(ignore, hit.Instance)
			else
				blocked = true
			end
		end
		shown += ((if blocked then 0 else 1) - shown) * (1 - math.exp(-SUN_FADE * dt))
		local transparency = math.clamp(1 - shown, 0, 1)
		if math.abs(face.ImageTransparency - transparency) > 0.01 or (transparency >= 0.99) ~= (face.ImageTransparency >= 0.99) then
			face.ImageTransparency = if transparency > 0.99 then 1 else transparency
		end
	end)

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
