-- Puts each player's current tool in their character's right hand so other players see it.
-- Follows the player attributes ToolModel and Carried that Run publishes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local ToolView = require(ReplicatedStorage.Shared.ToolView)

local HELD_NAME = "HeldTool"

local HeldTools = {}

local function hand(character: Model): BasePart?
	local h = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if h and h:IsA("BasePart") then h else nil
end

local function refresh(player: Player)
	local character = player.Character
	local modelName = player:GetAttribute("ToolModel")
	local h = character and hand(character)
	if not (character and h and type(modelName) == "string") then
		return
	end
	local held = character:FindFirstChild(HELD_NAME)
	if not held or held:GetAttribute("ModelName") ~= modelName then
		if held then
			held:Destroy()
		end
		local model = ToolModels.get(modelName):Clone()
		local extents = model:GetExtentsSize()
		local scale = ToolView.heldScale(math.max(extents.X, extents.Y, extents.Z))
		if scale < 1 then
			model:ScaleTo(scale)
		end
		model.Name = HELD_NAME
		model:SetAttribute("ModelName", modelName)
		model:PivotTo(h.CFrame * CFrame.new(0, -h.Size.Y / 2, 0))
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = h
				weld.Part1 = d
				weld.Parent = d
			end
		end
		model.Parent = character
		held = model
	end
	ToolModels.setWater(held :: Model, (player:GetAttribute("Carried") or 0) > 0)
end

local function track(player: Player)
	player:GetAttributeChangedSignal("ToolModel"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("Carried"):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("RightHand", 5)
		refresh(player)
	end)
	refresh(player)
end

function HeldTools.start(config)
	ToolModels.check(config)
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
end

return HeldTools
