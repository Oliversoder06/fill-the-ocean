-- World: the lobby's scenery moving on its own, on this client only. Every palm in
-- workspace.Lobby.Decor.Palms tilts about its base by LobbyCues.sway while it is within
-- LobbyCues.palms.range of the camera (farther ones rest where they stood). LobbyCues.gulls.count copies
-- of ReplicatedStorage.Scenery.Gull circle over the beach (LobbyCues.gullAt), banking into the turn and
-- flapping now and then (LobbyCues.flap: each wing turns about its Hinge attachment). Stream-safe: a
-- palm is remembered at the place it arrived and forgotten when it leaves. World.folder() is the
-- client-only workspace.LobbyScenery the copies live in (client/Horizon's too).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LobbyCues = require(ReplicatedStorage.Shared.LobbyCues)

local World = {}

type Gull = {
	parts: { BasePart },
	offsets: { CFrame }, -- each body part from the root
	wings: { { part: BasePart, side: number, hinge: CFrame, back: CFrame } }, -- hinge from the root, wing from its hinge
}

local folder: Folder? = nil

function World.folder(): Folder
	if not folder then
		local made = Instance.new("Folder")
		made.Name = "LobbyScenery"
		made.Parent = workspace
		folder = made
	end
	return folder :: Folder
end

-- A palm's own rhythm, from where it stands (the same every session).
local function seedOf(rest: CFrame): number
	return math.floor(math.abs(rest.X * 7.3 + rest.Z * 3.1)) % 97 + 1
end

local function makeGull(template: Model): Gull
	local copy = template:Clone()
	local root = copy.PrimaryPart :: BasePart
	local gull: Gull = { parts = {}, offsets = {}, wings = {} }
	for _, part in copy:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local side = if part.Name == "WingL" then -1 elseif part.Name == "WingR" then 1 else 0
		if side ~= 0 then
			local hinge = part:FindFirstChild("Hinge")
			assert(hinge and hinge:IsA("Attachment"), `Scenery.Gull.{part.Name} is missing its Hinge attachment (built in Studio)`)
			table.insert(gull.wings, {
				part = part,
				side = side,
				hinge = root.CFrame:ToObjectSpace(part.CFrame * hinge.CFrame),
				back = hinge.CFrame:Inverse(),
			})
		else
			table.insert(gull.parts, part)
			table.insert(gull.offsets, root.CFrame:ToObjectSpace(part.CFrame))
		end
	end
	assert(#gull.wings == 2, "Scenery.Gull needs two wings, WingL and WingR (built in Studio)")
	copy.Parent = World.folder()
	return gull
end

function World.start()
	local palmCue, gullCue = LobbyCues.palms, LobbyCues.gulls
	local lobby = workspace:WaitForChild("Lobby", 10)
	local decor = lobby and lobby:WaitForChild("Decor", 10)
	local palms = decor and decor:WaitForChild("Palms", 10)
	assert(palms, "workspace.Lobby.Decor.Palms is missing (built in the lobby place)")
	local scenery = ReplicatedStorage:WaitForChild("Scenery", 10)
	local template = scenery and scenery:WaitForChild(gullCue.model, 10)
	assert(template and template:IsA("Model") and template.PrimaryPart, `ReplicatedStorage.Scenery.{gullCue.model} is missing (a Model with a PrimaryPart, built in Studio)`)

	local gulls: { Gull } = {}
	for _ = 1, gullCue.count do
		table.insert(gulls, makeGull(template :: Model))
	end
	local bank = math.rad(gullCue.bankDegrees)

	local rests: { [BasePart]: CFrame } = {}
	local moved: { [BasePart]: boolean } = {}
	palms.ChildRemoved:Connect(function(palm)
		if palm:IsA("BasePart") then
			rests[palm], moved[palm] = nil, nil
		end
	end)

	local start = os.clock()
	RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		local camera = workspace.CurrentCamera
		local parts: { BasePart } = {}
		local cframes: { CFrame } = {}

		local eye = camera and camera.CFrame.Position
		for _, palm in palms:GetChildren() do
			if not palm:IsA("BasePart") then
				continue
			end
			local rest = rests[palm]
			if not rest then
				rest = palm.CFrame
				rests[palm] = rest
			end
			local here = rest :: CFrame
			if eye and (here.Position - eye).Magnitude <= palmCue.range then
				local ax, az = LobbyCues.sway(t, seedOf(here))
				local half = palm.Size.Y / 2
				table.insert(parts, palm)
				table.insert(cframes, here * CFrame.new(0, -half, 0) * CFrame.Angles(ax, 0, az) * CFrame.new(0, half, 0))
				moved[palm] = true
			elseif moved[palm] then
				table.insert(parts, palm)
				table.insert(cframes, here)
				moved[palm] = nil
			end
		end

		for i, gull in gulls do
			local x, y, z, dx, dz, turn = LobbyCues.gullAt(t, i)
			local at = Vector3.new(x, y, z)
			-- the circle's centre is on the right of a gull turning +1: it leans that way
			local root = CFrame.lookAt(at, at + Vector3.new(dx, 0, dz)) * CFrame.Angles(0, 0, -turn * bank)
			for j, part in gull.parts do
				table.insert(parts, part)
				table.insert(cframes, root * gull.offsets[j])
			end
			local angle = LobbyCues.flap(t, i)
			for _, wing in gull.wings do
				table.insert(parts, wing.part)
				table.insert(cframes, root * wing.hinge * CFrame.Angles(0, 0, wing.side * angle) * wing.back)
			end
		end

		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return World
