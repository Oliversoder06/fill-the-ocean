-- The Phase 4 targets (tools/Simulator): the whole map played solo and by teams of 2 and 4 meets
-- every target with the tuned Config.
local Simulator = require("../tools/Simulator")

local tests = {}

function tests.config_meets_every_target(t)
	local rows, ok = Simulator.targets()
	if not ok then
		error(Simulator.formatTargets(rows))
	end
	t.expectEq(ok, true)
end

return tests
