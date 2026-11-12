local IntroClips = require("../src/shared/IntroClips")
local IntroCut = require("../src/shared/IntroCut")
local Rig = require("../vendor/Animation/Rig")
local Anatomy = require("../vendor/Animation/Anatomy")
local Templates = require("../vendor/Animation/Templates")
local Performance = require("../vendor/Animation/Performance")
local Gait = require("../vendor/Animation/Gait")
local Lint = require("../vendor/Animation/Lint")
local Baked = require("../vendor/Animation/Baked")

local tests = {}

-- Players' avatars are R15; the runtime's stand-in R15 judges timing, spacing and weight offline.
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

function tests.every_clip_lints_clean(t)
	local count = 0
	for name, clip in IntroClips.clips do
		count += 1
		local errors = Performance.validate(clip)
		t.expectEq(#errors, 0, `{name} validates{if errors[1] then `: {errors[1].path} {errors[1].expected}` else ""}`)
		local baked = Performance.bake(anatomy, clip)
		t.expectEq(Baked.finite(baked), true, `{name} bakes finite`)
		t.expectEq(#baked.warnings, 0, `{name}: {table.concat(baked.warnings, "; ")}`)
		t.expectEq(fixes(baked), "", `{name}'s lint`)
	end
	t.expectEq(count, 1, "lie")
end

function tests.walk_lints_clean(t)
	local baked = Gait.cycle(anatomy, IntroClips.gaits.walk)
	t.expectEq(#baked.warnings, 0, table.concat(baked.warnings, "; "))
	t.expectEq(fixes(baked), "", "the walk's lint")
end

-- The body moves up the beach at the walk cycle's own speed, so its feet don't slide.
function tests.walk_matches_the_cut(t)
	local from, to = IntroCut.places.walkFrom, IntroCut.places.walkTo
	local distance = math.sqrt((to[1] - from[1]) ^ 2 + (to[3] - from[3]) ^ 2)
	local seconds = IntroCut.beats.walkTo - IntroCut.beats.walkFrom
	t.expectNear(distance / seconds, IntroClips.gaits.walk.speed, 0.1, "studs a second along the walk")
	t.expectEq(IntroCut.walkSpeed, IntroClips.gaits.walk.speed)
end

-- The yawn starts as the cut's yawn beat comes (the clip starts on the lie beat), and the clip
-- lasts until your own eyes take over.
function tests.lie_lines_up_with_the_cut(t)
	local lie = IntroClips.clips.lie
	t.expectEq(lie.markers[1].name, "Yawn")
	t.expectNear(lie.markers[1].t, IntroCut.beats.yawn - IntroCut.beats.lie, 0.01, "the yawn")
	t.expectEq(IntroCut.beats.lie + lie.length >= IntroCut.beats.pov, true, "lies until the eyes take over")
end

return tests
