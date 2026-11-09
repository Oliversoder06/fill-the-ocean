--!strict
--[[
	Gait: one entry point for getting any creature from A to B.

	It picks the motion from the anatomy and says why: legged locomotion for one leg or more
	(Locomotion: pogo, walk, run, rotating tripod, walk/trot/gallop, alternating tripod,
	metachronal ripple, or the general solver), legless motion by shape otherwise (Legless: hop,
	slither, hover, roll, slide). A creature flagged as flying hovers unless asked to walk. A
	style can be forced; one that does not fit the body (a slither for a rigid egg) falls back
	with a warning instead of failing.

	bake() travels a path and returns a world-space bake for a cutscene; cycle() returns an
	in-place loop for gameplay (AnimPlayer and Follow advance it by the distance actually moved,
	so the feet stay planted whatever the speed).
]]

local Anatomy = require("./Anatomy")
local Baked = require("./Baked")
local GaitPlan = require("./GaitPlan")
local Locomotion = require("./Locomotion")
local Legless = require("./Legless")

local Gait = {}

local LEGLESS: { [string]: boolean } = { hop = true, slither = true, hover = true, roll = true, slide = true }

-- Which engine and why: ("legs" | "legless", reason).
function Gait.choose(anatomy: Anatomy.Anatomy, opts: any?): (string, string)
	local o = if type(opts) == "table" then opts else {}
	local style = o.style
	if type(style) == "string" and LEGLESS[style] then
		return "legless", "style " .. style .. " asked for"
	end
	if #anatomy.legs == 0 then
		local mode, why = Legless.choose(anatomy, nil)
		return "legless", "no legs: " .. mode .. " (" .. why .. ")"
	end
	if anatomy.flying and style ~= "walk" and style ~= "run" then
		return "legless", "flagged as flying: hover"
	end
	return "legs", string.format("%d leg%s", #anatomy.legs, if #anatomy.legs == 1 then "" else "s")
end

function Gait.bake(anatomy: Anatomy.Anatomy, opts: any?): Baked.Baked
	local o: any = if type(opts) == "table" then table.clone(opts) else {}
	local engine, why = Gait.choose(anatomy, o)
	local b: Baked.Baked
	if engine == "legless" then
		if #anatomy.legs > 0 and o.style == nil and anatomy.flying then
			o.style = "hover"
		end
		b = Legless.bake(anatomy, o)
	else
		b = Locomotion.bake(anatomy, o)
	end
	b.info.engine = engine
	b.info.why = why
	-- standing still at either end of a path, a body still breathes: drift in the holds, on
	-- everything but the legs (which stay where their feet are) and the root (which the feet
	-- are baked to). `drift = 0` turns it off.
	local drift = if type(o.drift) == "number" then o.drift else 1
	if drift > 0 and not b.loop then
		local Polish = require("./Polish")
		local Rng = require("./Rng")
		Polish.drift(b, anatomy, drift, Rng.new(o.seed or anatomy.rig.name), false)
	end
	return b
end

function Gait.cycle(anatomy: Anatomy.Anatomy, opts: any?): Baked.Baked
	local o: any = if type(opts) == "table" then table.clone(opts) else {}
	o.loop = true
	return Gait.bake(anatomy, o)
end

function Gait.flap(anatomy: Anatomy.Anatomy, opts: any?): Baked.Baked
	return Legless.flap(anatomy, opts)
end

-- The plan in words, for the agent to show before building.
function Gait.describe(anatomy: Anatomy.Anatomy, opts: any?): string
	local o = if type(opts) == "table" then opts else {}
	local engine, why = Gait.choose(anatomy, o)
	if engine == "legless" then
		local mode, reason = Legless.choose(anatomy, o.style)
		return string.format("%s: %s (%s)", anatomy.rig.name, mode, reason)
	end
	local plan = GaitPlan.plan(anatomy, o)
	return string.format(
		"%s: %s, %s at %.3g studs/s (Froude %.2f): cycle %.2f s, duty %.2f, stride %.3g studs, %d foot/feet always down%s. %s",
		anatomy.rig.name,
		why,
		plan.kind,
		plan.speed,
		plan.froude,
		plan.period,
		plan.duty,
		plan.stride,
		plan.minSupport,
		if plan.flight then ", with flight" else "",
		table.concat(plan.reasons, "; ")
	)
end

return Gait
