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

local Theme = require(ReplicatedStorage.Kit.UI.Themes["clear-tide"])

local OUTLINE = 0.1 -- icon outline width, as a share of the model's radius (~2 px on a hex, ~4 in the hotbar)

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


-- Where each item kind's model template lives (Config.Item `model`): a folder of ReplicatedStorage,
-- then a subfolder.
local ITEM_FOLDERS = {
	backpack = { "ToolModels", "Backpacks" },
	gadget = { "ToolModels", "Gadgets" },
	vehicle = { "Vehicles" },
	building = { "Buildings" },
	staff = { "Staff" },
}

-- Non-yielding: item `item`'s template (a Model, a backpack's Accessory), nil until it has replicated.
function ToolModels.itemModel(item): (Model | Accessory)?
	local node: Instance? = ReplicatedStorage
	for _, name in ITEM_FOLDERS[item.kind] do
		node = node and node:FindFirstChild(name)
	end
	local model = node and node:FindFirstChild(item.model)
	return if model and (model:IsA("Model") or model:IsA("Accessory")) then model else nil
end

-- An icon's outline: each visible part again, fattened by `margin` studs, flat dark, and moved out
-- along the camera's rays (scaled by k about the camera, so it projects exactly where it was) to
-- sit behind the whole model. Only its rim shows around the silhouette.
local function outline(model: Model, eye: Vector3, margin: number, k: number)
	local shell = Instance.new("Model")
	shell.Name = "Outline"
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part.Transparency >= 1 or part.Name:sub(-6) == "_Water" then
			continue
		end
		local copy = part:Clone()
		local grow = (part.Size + Vector3.one * 2 * margin) / part.Size * k
		for _, child in copy:GetChildren() do
			if child:IsA("SpecialMesh") and child.MeshType == Enum.MeshType.FileMesh then
				child.Scale *= grow -- a file mesh ignores the part's Size
				child.TextureId = ""
			elseif not child:IsA("DataModelMesh") then
				child:Destroy()
			end
		end
		if copy:IsA("MeshPart") then
			copy.TextureID = ""
		end
		copy.Size *= grow
		copy.CFrame = part.CFrame.Rotation + eye + (part.Position - eye) * k
		copy.Color = Theme.colors.outline
		copy.Material = Enum.Material.SmoothPlastic
		copy.Reflectance = 0
		copy.Transparency = 0
		copy.Parent = shell
	end
	shell.Parent = model.Parent
end

-- Client UI: puts a copy of a model (a tool, an item, a backpack's Accessory) in a ViewportFrame,
-- framed to fit (hotbar, honeycomb), with a dark outline.
function ToolModels.showIn(view: ViewportFrame, template: Model | Accessory)
	view:ClearAllChildren()
	local model: Model
	if template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		template:Clone().Parent = model
	end
	model:PivotTo(CFrame.new())
	model.Parent = view
	ToolModels.setWater(model, false)
	local camera = Instance.new("Camera")
	local center, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local direction = Vector3.new(1, 0.6, 1).Unit
	camera.FieldOfView = 40
	-- Room for the outline around the model.
	local distance = radius / math.tan(math.rad(20)) * 1.05 * (1 + 2 * OUTLINE)
	local eye = center.Position + direction * distance
	camera.CFrame = CFrame.lookAt(eye, center.Position)
	camera.Parent = view
	view.CurrentCamera = camera
	-- Push the outline past the model's far side.
	outline(model, eye, radius * OUTLINE, (distance + radius) / (distance - radius) * 1.05)
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
