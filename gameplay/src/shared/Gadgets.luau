--!strict
-- Gadget maths (Config.items kind "gadget"). Pure: no requires, so Lune tests and Roblox load it the
-- same way.

local Gadgets = {}

-- The Jetpack Tank's fuel (seconds of thrust left) after `dt` seconds: it burns while flying,
-- refills on the ground from empty to `max` in `rechargeSeconds`, and keeps what is left in the air.
function Gadgets.fuel(fuel: number, max: number, dt: number, flying: boolean, grounded: boolean, rechargeSeconds: number): number
	if flying then
		fuel -= dt
	elseif grounded then
		fuel += dt * max / rechargeSeconds
	end
	return math.clamp(fuel, 0, max)
end

return Gadgets
