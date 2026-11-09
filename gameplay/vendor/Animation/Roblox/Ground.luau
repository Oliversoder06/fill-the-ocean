--!strict
--[[
	Ground (Roblox only): the height of the floor under (x, z), for baking feet onto real
	terrain and parts.

	Rays are cast once per point of a grid (cell size set from the creature, about a tenth of its
	hip height) and cached; heights between grid points are blended bilinearly, so a foot sliding
	from one cell to the next sees a smooth floor, not a staircase. Everything happens at bake
	time (a track's prepare), never per frame.

	A ray that hits nothing returns the fallback height (the floor under the start).
]]

local Ground = {}

export type Options = {
	-- instances the rays ignore (the actor itself, other actors)
	exclude: { Instance }?,
	cell: number?,
	-- rays start this far above the asked height and look this far below it
	above: number?,
	below: number?,
	fallback: number,
	-- the height to ask around (the start's floor)
	near: number,
}

function Ground.raycaster(opts: Options): (number, number) -> number
	local Workspace = game:GetService("Workspace")
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = opts.exclude or {}
	rayParams.IgnoreWater = true
	local cell = math.max(opts.cell or 0.5, 0.02)
	local above = opts.above or 20
	local below = opts.below or 60
	local fallback = opts.fallback
	local near = opts.near
	local cache: { [number]: { [number]: number } } = {}
	local function at(ix: number, iz: number): number
		local row = cache[ix]
		if not row then
			row = {}
			cache[ix] = row
		end
		local v = row[iz]
		if v == nil then
			local x, z = ix * cell, iz * cell
			local origin = Vector3.new(x, near + above, z)
			local ok, hit = pcall(function()
				return Workspace:Raycast(origin, Vector3.new(0, -(above + below), 0), rayParams)
			end)
			v = if ok and hit then hit.Position.Y else fallback
			row[iz] = v
		end
		return v :: number
	end
	return function(x: number, z: number): number
		local fx, fz = x / cell, z / cell
		local ix, iz = math.floor(fx), math.floor(fz)
		local u, w = fx - ix, fz - iz
		local a = at(ix, iz)
		local b = at(ix + 1, iz)
		local c = at(ix, iz + 1)
		local d = at(ix + 1, iz + 1)
		return (a * (1 - u) + b * u) * (1 - w) + (c * (1 - u) + d * u) * w
	end
end

return Ground
