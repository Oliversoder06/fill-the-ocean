-- Horizon: the bacon-hair drinking the sea far behind the pads, on this client only: a copy of
-- ReplicatedStorage.Scenery.BaconFat (built in the lobby place; its pivot is where he stands) in
-- World.folder(). He sways slowly; every slurpMin..slurpMax seconds he slurps through his straw (the
-- sound from his mouth, faint at the deck) while his Belly swells and settles (LobbyCues.swell); every
-- burpEvery-th slurp ends in a burp and a hop (LobbyCues.hop). Numbers in LobbyCues.horizon.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LobbyCues = require(ReplicatedStorage.Shared.LobbyCues)
local Sfx = require(script.Parent.Sfx)
local World = require(script.Parent.World)

local TAU = 2 * math.pi

local Horizon = {}

function Horizon.start()
	local cue = LobbyCues.horizon
	Sfx.need(cue.slurp)
	Sfx.need(cue.burp)
	local scenery = ReplicatedStorage:WaitForChild("Scenery", 10)
	local template = scenery and scenery:WaitForChild(cue.model, 10)
	assert(template and template:IsA("Model"), `ReplicatedStorage.Scenery.{cue.model} is missing (a Model, built in the lobby place)`)
	local him = template:Clone()
	local belly = him:FindFirstChild("Belly")
	assert(belly and belly:IsA("BasePart"), `Scenery.{cue.model} is missing its Belly part`)
	local head = him:FindFirstChild("Head")
	local mouth = head and head:FindFirstChild("Mouth")
	assert(mouth and mouth:IsA("Attachment"), `Scenery.{cue.model}.Head is missing its Mouth attachment`)
	him.Parent = World.folder()

	local rest = him:GetPivot()
	local bellySize = belly.Size
	local rng = Random.new()
	local start = os.clock()
	local slurps = 0
	local nextSlurp = rng:NextNumber(cue.slurpMin, cue.slurpMax) * 0.5 -- the first comes sooner
	local slurpAt = -math.huge
	local burpAt = math.huge -- when the pending burp goes (math.huge: none)
	local hopAt = -math.huge

	local function sound(name: string, volume: number)
		Sfx.play(name, {
			volume = volume,
			at = (mouth :: Attachment).WorldPosition,
			rollOffMin = cue.rollOffMin,
			rollOffMax = cue.rollOffMax,
		})
	end

	RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		if t >= nextSlurp then
			slurps += 1
			slurpAt = t
			nextSlurp = t + rng:NextNumber(cue.slurpMin, cue.slurpMax)
			sound(cue.slurp, cue.slurpVolume)
			if slurps % cue.burpEvery == 0 then
				burpAt = t + cue.swellIn + cue.burpDelay
			end
		end
		if t >= burpAt then
			burpAt = math.huge
			hopAt = t
			sound(cue.burp, cue.burpVolume)
		end

		local sway = math.rad(cue.swayDegrees) * math.sin(TAU * cue.swayHz * t)
		local lift = cue.hop * LobbyCues.hop(t - hopAt)
		him:PivotTo(rest * CFrame.Angles(0, 0, sway) + Vector3.new(0, lift, 0))
		local size = bellySize * (1 + cue.swell * LobbyCues.swell(t - slurpAt))
		if belly.Size ~= size then
			belly.Size = size
		end
	end)
end

return Horizon
