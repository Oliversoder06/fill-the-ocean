-- The gate signs (workspace.Areas.<Area>.Gate.Sign, a SurfaceGui with a TextLabel "Label", built in
-- Studio): the area's name, then "Fill to 22% · 88,000" until the gate's fill, "Open <earlier area>
-- first" while an earlier gate is closed, its price once it is the next gate on sale, then "Open".
-- Its prompt shows only while it is on sale. The server sells and opens gates (server/Run onGate)
-- and checks every buy; this only shows their state from the Fill and GatesOpen attributes. Signs of
-- areas not streamed in yet are filled in once they arrive.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Areas = require(ReplicatedStorage.Common.Areas)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Hud = require(script.Parent.Hud)

local colors = Theme.colors
local Gates = {}

-- The sign text of an area's gate, its colour and whether the gate is on sale now: the area's name
-- over its fill and price until then, "<price> · hold E" once it is the next gate on sale, then
-- "Open". White, teal and orange on the navy outline read from a distance (Theme colours).
local function signOf(area, gatesOpen: { number }, fill: number): (string, Color3, boolean)
	local nextId, onSale = Areas.nextGate(Config, gatesOpen, fill)
	local title = area.name:upper()
	if table.find(gatesOpen, area.id) then
		return `{title}\nOpen`, colors.speedTag, false
	elseif nextId == area.id and onSale then
		return `{title}\n{Hud.money(area.gate.price)} · hold E`, colors.toolTag, true
	elseif fill >= area.gate.fill and nextId then
		return `{title}\nOpen {Areas.byId(Config, nextId).name} first`, colors.foam, false
	end
	return `{title}\nFill to {Format.percent(area.gate.fill)} · {Hud.money(area.gate.price)}`, colors.foam, false
end

-- An area's Gate model, or nil while it hasn't streamed in.
local function gateOf(ocean: Model, area): Instance?
	local model = Zones.areaModel(ocean, area)
	return model and model:FindFirstChild("Gate")
end

function Gates.start()
	local labels: { [any]: TextLabel } = {} -- each area's sign label once it has streamed in
	RunService.RenderStepped:Connect(function()
		local ocean = Hud.ocean()
		if not ocean then
			return
		end
		local raw = ReplicatedStorage:GetAttribute("Fill")
		local fill = if type(raw) == "number" then raw else 0
		local gatesOpen = Hud.gatesOpen()
		for _, area in Config.areas do
			if area.gate then
				local gate = gateOf(ocean, area)
				local label = labels[area]
				if not (label and label:IsDescendantOf(workspace)) then
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
				local text, color, onSale = signOf(area, gatesOpen, fill)
				if label then
					Hud.set(label, "Text", text)
					Hud.set(label, "TextColor3", color)
				end
				local holder = gate and gate:FindFirstChild("Prompt")
				local prompt = holder and holder:FindFirstChild("Prompt")
				if prompt and prompt:IsA("ProximityPrompt") then
					Hud.set(prompt, "Enabled", onSale)
				end
			end
		end
	end)
end

return Gates
