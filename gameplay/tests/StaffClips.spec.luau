local StaffClips = require("../src/shared/StaffClips")
local Rig = require("../vendor/Animation/Rig")
local Anatomy = require("../vendor/Animation/Anatomy")
local Templates = require("../vendor/Animation/Templates")
local Performance = require("../vendor/Animation/Performance")
local Gait = require("../vendor/Animation/Gait")
local Lint = require("../vendor/Animation/Lint")
local Baked = require("../vendor/Animation/Baked")

local tests = {}

-- The staff are R15 rigs; the runtime's stand-in R15 judges timing, spacing and weight offline.
local anatomy = Anatomy.classify(Rig.build(Templates.R15()))

local function fixes(baked): string
	local bad = {}
	for _, finding in Lint.run(baked, anatomy) do
		if finding.severity == "fix" then
			table.insert(bad, `{finding.rule}: {finding.message}`)
		end
	end
	return table.concat(bad, "\n    ")
end

-- The carrying walk: the walk cycle with the carry hold's arms laid over it (as client/Staff bakes it).
local function walkCarry()
	local top = Baked.compact(Performance.bake(anatomy, StaffClips.clips.carry))
	return StaffClips.overlay(Gait.cycle(anatomy, StaffClips.gaits.walkCarry), top)
end

-- Every staff clip validates, bakes on R15 without warnings and lints with no [fix].
function tests.every_clip_lints_clean(t)
	local count = 0
	for name, clip in StaffClips.clips do
		count += 1
		local errors = Performance.validate(clip)
		t.expectEq(#errors, 0, `{name} validates{if errors[1] then `: {errors[1].path} {errors[1].expected}` else ""}`)
		local baked = Performance.bake(anatomy, clip)
		t.expectEq(Baked.finite(baked), true, `{name} bakes finite`)
		t.expectEq(#baked.warnings, 0, `{name}: {table.concat(baked.warnings, "; ")}`)
		t.expectEq(fixes(baked), "", `{name}'s lint`)
	end
	t.expectEq(count, 9, "idle, carry, scoop, pour, cheer and the four signature moves")
end

-- Both walks are clean loops whose feet stay planted (no slide, no over-reach warnings).
function tests.walks_lint_clean(t)
	for name, opts in StaffClips.gaits do
		local baked = Gait.cycle(anatomy, opts)
		t.expectEq(#baked.warnings, 0, `{name}: {table.concat(baked.warnings, "; ")}`)
		t.expectEq(fixes(baked), "", `{name}'s lint`)
	end
	t.expectEq(fixes(walkCarry()), "", "the carrying walk's lint")
end

-- The carrying walk holds the carry pose in its arms and keeps the walk everywhere else.
function tests.overlay_holds_the_arms(t)
	local walk = Gait.cycle(anatomy, StaffClips.gaits.walkCarry)
	local carried = walkCarry()
	local top = Baked.compact(Performance.bake(anatomy, StaffClips.clips.carry))
	t.expectEq(top.nch, 4, "the carry clip moves only the upper arms and forearms")
	local moved = 0
	for c = 1, carried.nch do
		local held = table.find(top.joints, carried.joints[c]) ~= nil
		local a, b = Baked.get(carried, 0, c), Baked.get(carried, carried.count // 2, c)
		if held then
			moved += 1
			t.expectEq(a.q.x == b.q.x and a.q.w == b.q.w, true, `channel {c} is held`)
		else
			local w = Baked.get(walk, carried.count // 2, c)
			t.expectEq(b.q.x == w.q.x and b.q.w == w.q.w, true, `channel {c} keeps the walk`)
		end
	end
	t.expectEq(moved, 4)
end

function tests.every_job_has_a_signature_move(t)
	for _, id in { "helper", "lifeguard", "firefighter", "plumber" } do
		local name = StaffClips.signature[id]
		t.expectEq(StaffClips.clips[name] ~= nil, true, `{id}'s move {name}`)
	end
	for _, name in { "idle", "carry", "scoop", "pour", "cheer" } do
		t.expectEq(StaffClips.clips[name] ~= nil, true, name)
	end
	t.expectEq(StaffClips.clips.idle.loop, true, "the idle loops")
end

return tests
