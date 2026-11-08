-- The gate signs (workspace.Areas.<Area>.Gate.Sign, a SurfaceGui with a TextLabel "Label", built in
-- Studio): "Fill the ocean to 22%" until the gate is on sale, then its price, then "Open". The
-- server sells and opens gates (server/Run onGate); this only shows their state from the Fill and
-- GatesOpen attributes. Signs of areas not streamed in yet are filled in once they arrive.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Hud = require(script.Parent.Hud)

local colors = Theme.colors
local Gates = {}

-- The sign text of an area's gate and its colour.
local function signOf(area, gatesOpen: { number }, fill: number): (string, Color3)
	if table.find(gatesOpen, area.id) then
		return "Open", colors.speedTag
	elseif fill >= area.gate.fill then
		return `{Hud.money(area.gate.price)} coins - hold E`, colors.toolTag
	end
	return `Fill the ocean to {math.round(area.gate.fill * 100)}%`, colors.sunRim
end

function Gates.start()
	local labels: { [any]: TextLabel } = {} -- each area's sign label once it has streamed in
	RunService.RenderStepped:Connect(function()
		local ocean = Hud.ocean()
		if not ocean then
			return
		end
		local fill = ReplicatedStorage:GetAttribute("Fill")
		local gatesOpen = Hud.gatesOpen()
		for _, area in Config.areas do
			if area.gate then
				local label = labels[area]
				if not (label and label:IsDescendantOf(workspace)) then
					local model = Zones.areaModel(ocean, area)
					local gate = model and model:FindFirstChild("Gate")
					local sign = gate and gate:FindFirstChild("Sign")
					local found = sign and sign:FindFirstChild("Label", true)
					label = if found and found:IsA("TextLabel") then found else nil
					labels[area] = label
					if label then
						label.FontFace = Theme.fonts.title
						label.TextStrokeColor3 = colors.outline
						label.TextStrokeTransparency = 0
					end
				end
				if label then
					local text, color = signOf(area, gatesOpen, if type(fill) == "number" then fill else 0)
					Hud.set(label, "Text", text)
					Hud.set(label, "TextColor3", color)
				end
			end
		end
	end)
end

return Gates
