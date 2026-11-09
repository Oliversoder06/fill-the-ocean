-- Held tool models. Templates live in ReplicatedStorage.ToolModels (baked into the place), one
-- Model per hero tool (Spoon, Cup, Bucket, ...); levels like "Cup Lv2" reuse their hero's model.
-- Gadgets (Config.items kind "gadget") have theirs in the subfolder ToolModels.Gadgets, named by the
-- item's `model` (WaterGun, GardenHose, ...), with the same pivot contract.
-- Contract for real models (art prompt):
--   the Model's pivot is the grip point, the opening faces up, it pours forward (-Z),
--   an optional child "<Name>_Water" is shown only while the player carries water.
-- The baked models are imported from art/models/tools (3D Importer); each MeshPart's texture is a
-- SurfaceAppearance ColorMap, because the imported TextureID rendered grey.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolModels = {}

-- Hero model names in ladder order, each once: the starting tool, then each new model.
function ToolModels.order(config): { string }
	local names, seen = { config.start.toolModel }, { [config.start.toolModel] = true }
	for _, level in config.track("tool").levels do
		if not seen[level.model] then
			seen[level.model] = true
			table.insert(names, level.model)
		end
	end
	return names
end

-- Server start: every hero tool must have a template in ReplicatedStorage.ToolModels, and every
-- gadget one in ToolModels.Gadgets.
function ToolModels.check(config)
	local folder = ReplicatedStorage:FindFirstChild("ToolModels")
	assert(folder, "ReplicatedStorage.ToolModels is missing: the tool templates live in the place")
	for _, name in ToolModels.order(config) do
		local model = folder:FindFirstChild(name)
		assert(model and model:IsA("Model"), `ReplicatedStorage.ToolModels is missing {name}`)
	end
	for _, item in config.items do
		if item.kind == "gadget" then
			local gadgets = folder:FindFirstChild("Gadgets")
			local model = gadgets and gadgets:FindFirstChild(item.model)
			assert(model and model:IsA("Model"), `ReplicatedStorage.ToolModels.Gadgets is missing {item.model} (a Model)`)
		end
	end
end

-- Non-yielding lookup for per-frame code; nil until the template has replicated. `sub`: a subfolder
-- of ToolModels ("Gadgets").
function ToolModels.find(name: string, sub: string?): Model?
	local folder = ReplicatedStorage:FindFirstChild("ToolModels")
	if folder and sub then
		folder = folder:FindFirstChild(sub)
	end
	local model = folder and folder:FindFirstChild(name)
	return if model and model:IsA("Model") then model else nil
end

function ToolModels.get(name: string, sub: string?): Model
	local folder = ReplicatedStorage:WaitForChild("ToolModels")
	if sub then
		folder = folder:WaitForChild(sub, 10)
		assert(folder, `ToolModels is missing the folder {sub}`)
	end
	local model = folder:WaitForChild(name, 10)
	assert(model and model:IsA("Model"), `ToolModels is missing {name}`)
	return model
end


-- Client UI: puts a copy of the tool model in a ViewportFrame, framed to fit (hotbar, shop).
function ToolModels.showIn(view: ViewportFrame, template: Model)
	view:ClearAllChildren()
	local model = template:Clone()
	model:PivotTo(CFrame.new())
	model.Parent = view
	ToolModels.setWater(model, false)
	local camera = Instance.new("Camera")
	local center, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local direction = Vector3.new(1, 0.6, 1).Unit
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(center.Position + direction * radius / math.tan(math.rad(20)) * 1.05, center.Position)
	camera.Parent = view
	view.CurrentCamera = camera
end

-- Show or hide the "<Name>_Water" piece if the model has one.
function ToolModels.setWater(model: Model, visible: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(-6) == "_Water" then
			d.LocalTransparencyModifier = 0
			d.Transparency = if visible then 0.15 else 1
		end
	end
end

return ToolModels
