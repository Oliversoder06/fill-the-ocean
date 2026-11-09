-- Lune test runner. Run from gameplay/: lune run tests/run
-- Each spec returns { [testName] = function(t) ... end }, where t holds the expect helpers.
local process = require("@lune/process")

local SPECS = { "Config", "Ladder", "Boosts", "Water", "ToolView", "Ease", "Cues", "CoinBurst", "Reveal", "Steps", "BodyPose", "Session", "SessionRules", "RunSave", "Progress", "Maps", "Areas", "Items", "Gadgets", "AreaRules", "VehicleRules", "BuildingRules", "StaffRules", "StaffClips", "GuideTrail", "PourFlow", "Format", "NextGoal" }

local t = {}

function t.expectEq(actual, expected, label)
	if actual ~= expected then
		error(`{label or "expectEq"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

function t.expectNear(actual, expected, tolerance, label)
	if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		error(`{label or "expectNear"}: expected {expected} ± {tolerance}, got {tostring(actual)}`, 2)
	end
end

local passed, failed = 0, 0

for _, name in SPECS do
	local loaded, spec = pcall(require, `./{name}.spec`)
	if not loaded then
		failed += 1
		print(`FAIL {name}.spec (load): {spec}`)
		continue
	end
	local names = {}
	for testName in spec do
		table.insert(names, testName)
	end
	table.sort(names)
	for _, testName in names do
		local ok, err = pcall(spec[testName], t)
		if ok then
			passed += 1
			print(`PASS {name}.{testName}`)
		else
			failed += 1
			print(`FAIL {name}.{testName}: {err}`)
		end
	end
end

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed > 0 then 1 else 0)
