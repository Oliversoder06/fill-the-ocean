--!strict
-- This client's own sea (shared/Zones.setOpenSea) at the run's Fill: a sheet over the whole ocean,
-- out to the horizon (the server's water over the seabed near you, Zones.setFill, streams in on top of
-- it the same); put back every MEND_SECONDS where streaming out took it away. A cutscene holds it
-- full or dry for a while (Sea.hold, client/Cutscene).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Zones)
local Hud = require(script.Parent.Hud)

local MEND_SECONDS = 2 -- how often the open sea is put back where streaming took it away

local Sea = {}

local held: number? = nil

local function refresh()
	local ocean = Hud.ocean()
	local fill = if held then held else ReplicatedStorage:GetAttribute("Fill")
	if ocean and type(fill) == "number" then
		Zones.setOpenSea(ocean, fill)
	end
end

-- Holds the open sea at a fill fraction (a cut's full or dry sea); nil gives it the run's Fill back.
function Sea.hold(fraction: number?)
	held = fraction
	refresh()
end

function Sea.start()
	ReplicatedStorage:GetAttributeChangedSignal("Fill"):Connect(refresh)
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Ocean" then
			refresh()
		end
	end)
	refresh()
	task.spawn(function()
		while true do
			task.wait(MEND_SECONDS)
			local ocean = Hud.ocean()
			if ocean then
				Zones.mendOpenSea(ocean)
			end
		end
	end)
end

return Sea
