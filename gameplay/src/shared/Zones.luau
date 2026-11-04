--!strict
-- Stage parts from the map contract in server/Map.luau, and server-side distance checks.

local Zones = {}

-- A stage child the map contract requires; a missing one is a map bug, so fail loudly.
function Zones.part(stage: Model, name: string): BasePart
	local child = stage:FindFirstChild(name)
	assert(child and child:IsA("BasePart"), `Stage {stage.Name} is missing part {name}`)
	return child
end

function Zones.near(stage: Model, name: string, position: Vector3, radius: number): boolean
	return (position - Zones.part(stage, name).Position).Magnitude <= radius
end

return Zones
