--!strict
--[[
	TrackCore: what the three cutscene tracks (animClip, animGait, animLook) share. Plain logic,
	loadable under Lune; the Roblox modules are required only inside prepare, when an actor turns
	out to be a real Instance, so the server and the Analyzer can require the handlers freely.

	The contract (roblox-cinematics/runtime/Tracks.luau):
	- prepare bakes everything once, before the cut takes the camera;
	- evaluate (the cut's render step, right after the camera) works out the frame and moves the
	  actor by PivotTo, so the camera sees the move the same frame;
	- pose (PreSimulation, after the Animator) writes the joints, so a playing Animator cannot
	  overwrite them. Transforms written then reach the screen on the next frame, one frame
	  after the PivotTo, so pose samples one frame ahead (the last frame's world step) and the
	  limbs land on the same instant as the body. In edit mode, or while time is held, that step
	  is zero;
	- stop puts every Transform back;
	- a track's clock is worldTime - (world time at its `at`), so hitstop freezes it and slow
	  motion slows it.

	A missing actor (never streamed in) or an unreadable one makes the track do nothing, with
	one warning.

	Test actors: a table { spec = RigSpec, pivot = X? } stands in for an Instance under Lune; the
	track writes its joints into actor.transforms[jointName] and its root into actor.pivot.
]]

local M = require("./Math")
local Rig = require("./Rig")
local Anatomy = require("./Anatomy")
local Baked = require("./Baked")
local Performance = require("./Performance")
local Gait = require("./Gait")
local Lint = require("./Lint")
local Templates = require("./Templates")
local Clock = require("./Clock")

type X = M.X
type V3 = M.V3

local TrackCore = {}

export type ValidationError = { path: string, expected: string, got: string }
export type Report = (rule: string, severity: string, message: string) -> ()

local GAIT_STYLES = { "auto", "walk", "run", "trot", "gallop", "hop", "slither", "hover", "roll", "slide" }

local function describe(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) == "table" then
		return "a table"
	end
	return tostring(v)
end

local function finite(v: any): boolean
	return M.finite(v)
end

local function vec3ok(v: any): boolean
	return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3])
end

-- Every `move` action in the cut on this actor (events, and actions inside shots).
local function movesOf(cut: any, actor: string): number
	local count = 0
	local function scan(list: any)
		if type(list) ~= "table" then
			return
		end
		for _, a in list do
			if type(a) == "table" and type(a.move) == "table" and a.move.actor == actor then
				count += 1
			end
		end
	end
	if type(cut) == "table" then
		scan(cut.events)
		if type(cut.shots) == "table" then
			for _, shot in cut.shots do
				if type(shot) == "table" then
					scan(shot.actions)
				end
			end
		end
	end
	return count
end

function TrackCore.validate(kind: string, data: any, path: string, cut: any): { ValidationError }
	local errs: { ValidationError } = {}
	local function fail(p: string, expected: string, got: any)
		table.insert(errs, { path = p, expected = expected, got = describe(got) })
	end
	if type(data) ~= "table" then
		fail(path, "a track table", data)
		return errs
	end
	if type(data.actor) ~= "string" or data.actor == "" then
		fail(path .. ".actor", "the name of one of the cut's actors", data.actor)
	elseif type(cut) == "table" and type(cut.actors) == "table" and cut.actors[data.actor] == nil then
		local names = {}
		for name in cut.actors do
			table.insert(names, name)
		end
		table.sort(names)
		fail(path .. ".actor", "one of the cut's actors (" .. table.concat(names, ", ") .. ")", data.actor)
	end
	if data.at ~= nil and (not finite(data.at) or data.at < 0) then
		fail(path .. ".at", "a cut time of 0 or more seconds", data.at)
	end
	if data.speed ~= nil and (not finite(data.speed) or data.speed <= 0) then
		fail(path .. ".speed", "a number greater than 0", data.speed)
	end
	for _, f in { "fadeIn", "fadeOut", "duration" } do
		if data[f] ~= nil and (not finite(data[f]) or data[f] < 0) then
			fail(path .. "." .. f, "seconds, 0 or more", data[f])
		end
	end
	if data.layer ~= nil and data.layer ~= "replace" and data.layer ~= "add" then
		fail(path .. ".layer", '"replace" or "add"', data.layer)
	end
	if data.rig ~= nil and type(data.rig) ~= "table" and not (type(data.rig) == "string" and Templates.get(data.rig) ~= nil) then
		fail(path .. ".rig", 'a template name ("R15", "R6") or a rig spec, for offline linting', data.rig)
	end
	local drivesRoot = false
	if kind == "animClip" then
		if data.clip == nil then
			fail(path .. ".clip", "a clip table (Performance format)", data.clip)
		else
			for _, e in Performance.validate(data.clip, path .. ".clip") do
				table.insert(errs, e)
			end
		end
		drivesRoot = data.rootMotion ~= false and (data.layer or "replace") == "replace"
	elseif kind == "animGait" then
		drivesRoot = true
		if type(data.path) ~= "table" or #data.path == 0 then
			fail(path .. ".path", "a list of { x, y, z } world points to walk through", data.path)
		else
			for i, p in data.path do
				if not vec3ok(p) then
					fail(string.format("%s.path[%d]", path, i), "{ x, y, z } with three finite numbers", p)
				end
			end
		end
		if data.style ~= nil and not table.find(GAIT_STYLES, data.style) then
			fail(path .. ".style", "one of " .. table.concat(GAIT_STYLES, ", "), data.style)
		end
		for _, f in { "face", "turnRate", "wait", "hold", "gravity" } do
			if data[f] ~= nil and not finite(data[f]) then
				fail(path .. "." .. f, "a finite number", data[f])
			end
		end
		if data.ground ~= nil and data.ground ~= "raycast" and data.ground ~= "flat" then
			fail(path .. ".ground", '"raycast" or "flat"', data.ground)
		end
		if data.look ~= nil then
			local lk = data.look
			if type(lk) ~= "table" or (type(lk.target) ~= "string" and not vec3ok(lk.target)) then
				fail(path .. ".look", "{ target = actor name or { x, y, z }, from = s, to = s }", lk)
			end
		end
	elseif kind == "animLook" then
		local target = data.target
		if type(target) == "string" then
			if type(cut) == "table" and type(cut.actors) == "table" and cut.actors[target] == nil then
				fail(path .. ".target", "an actor name or { x, y, z }", target)
			end
		elseif not vec3ok(target) then
			fail(path .. ".target", "an actor name or { x, y, z }", target)
		end
		if data.hold ~= nil and (not finite(data.hold) or data.hold < 0) then
			fail(path .. ".hold", "seconds, 0 or more", data.hold)
		end
		if data.ease ~= nil and (not finite(data.ease) or data.ease <= 0) then
			fail(path .. ".ease", "seconds greater than 0", data.ease)
		end
	end
	-- one thing moves an actor: the cut's moves, or a track
	if drivesRoot and type(data.actor) == "string" then
		local n = movesOf(cut, data.actor)
		if n > 0 then
			fail(
				path .. ".actor",
				string.format("an actor no `move` action drives (this track moves %s by its pivot; set rootMotion = false or drop the moves)", data.actor),
				string.format("%s with %d move action(s)", data.actor, n)
			)
		end
	end
	return errs
end

-- The rig an offline analysis uses: data.rig (a template name or a spec), else R15.
local function offlineAnatomy(data: any): (Anatomy.Anatomy, string)
	local spec: any = nil
	local label = "R15"
	if type(data.rig) == "table" then
		spec = data.rig
		label = if type(data.rig.name) == "string" then data.rig.name else "the given rig"
	elseif type(data.rig) == "string" then
		spec = Templates.get(data.rig)
		label = data.rig
	end
	if not spec then
		spec = Templates.R15()
	end
	local rig = Rig.build(spec)
	return Anatomy.classify(rig, data.overrides), label
end

-- The clip an animLook track plays, in the looker's frame. `target` is in that frame.
function TrackCore.lookClip(data: any, target: V3, anatomy: Anatomy.Anatomy): any
	local ease = if finite(data.ease) then math.max(data.ease, 0.05) else 0.45
	local hold = if finite(data.hold) then math.max(data.hold, 0) else 1.5
	local amount = if finite(data.amount) then math.clamp(data.amount, 0, 1) else 1
	-- a point straight ahead at the target's distance, to start from and return to
	local headY = if anatomy.head then anatomy.rig.joints[anatomy.head :: number].world.p.y else anatomy.height * 0.4
	local dist = math.max(math.sqrt(target.x * target.x + target.z * target.z), 1)
	local ahead = { 0, headY, -dist }
	local blendTo = {
		ahead[1] + (target.x - ahead[1]) * amount,
		ahead[2] + (target.y - ahead[2]) * amount,
		ahead[3] + (target.z - ahead[3]) * amount,
	}
	-- the chest follows a fifth of the way round, a little after the head starts
	local yaw = math.deg(math.atan2(-target.x, -target.z)) * amount
	local chestYaw = math.clamp(yaw * 0.2, -15, 15)
	local lag = math.min(0.2, ease * 0.5)
	local keys: { any } = {
		{ t = 0, pose = { head = { look = ahead }, chest = { rot = { 0, 0, 0 } } } },
		{ t = ease, pose = { head = { look = blendTo } } },
		{ t = ease + lag, pose = { chest = { rot = { 0, chestYaw, 0 } } } },
		{ t = ease + hold, pose = { head = { look = blendTo }, chest = { rot = { 0, chestYaw, 0 } } } },
		{ t = 2 * ease + hold, pose = { head = { look = ahead } } },
		{ t = 2 * ease + hold + lag, pose = { chest = { rot = { 0, 0, 0 } } } },
	}
	return {
		name = "Look",
		units = "studs",
		keys = keys,
		plant = false,
		polish = { drift = 0, mirror = false },
		waive = { "no-wind-up", "frozen-hold" },
	}
end

local function gaitOptions(data: any, start: X, ground: ((number, number) -> number)?, look: any?): any
	local pathSpec: any = { points = data.path, speed = data.speed, face = data.face, turnRate = data.turnRate, wait = data.wait, hold = data.hold }
	return {
		path = pathSpec,
		speed = data.speed,
		style = data.style,
		gravity = data.gravity,
		start = start,
		ground = ground,
		bob = data.bob,
		lean = data.lean,
		arms = data.arms,
		look = look,
		name = data.name,
	}
end

--[[
	Offline lint for the Analyzer: bakes on a stand-in rig and reports every [fix] and
	[consider]. Pure; never throws (a failure becomes one finding).
]]
function TrackCore.analyze(kind: string, data: any, cut: any, report: Report)
	-- (packed: the function returns nothing, so pcall's second result exists only on an error)
	local result = table.pack(pcall(function()
		local anatomy, label = offlineAnatomy(data)
		local baked: Baked.Baked
		if kind == "animClip" then
			if type(data.clip) ~= "table" then
				return
			end
			baked = Performance.bake(anatomy, data.clip)
		elseif kind == "animGait" then
			if type(data.path) ~= "table" then
				return
			end
			-- walk the path from the first point's neighbour as if the actor stood at the origin
			local pts = {}
			local origin = data.path[1]
			for i, p in data.path do
				if i > 1 and type(p) == "table" and type(origin) == "table" then
					table.insert(pts, { p[1] - origin[1], 0, p[3] - origin[3] })
				end
			end
			local d = table.clone(data)
			d.path = pts
			baked = Gait.bake(anatomy, gaitOptions(d, { p = { x = 0, y = -anatomy.rig.ground, z = 0 }, q = M.qid() }, nil, nil))
		else
			local target = if type(data.target) == "table" then { x = data.target[1], y = data.target[2], z = data.target[3] } else { x = 3, y = 0, z = -6 }
			baked = Performance.bake(anatomy, TrackCore.lookClip(data, target, anatomy))
		end
		for _, w in baked.warnings do
			report("bake", "consider", w .. " (on " .. label .. ")")
		end
		local findings = Lint.run(baked, anatomy)
		for _, f in findings do
			if f.severity ~= "info" then
				report(f.rule, f.severity, f.message .. (if label ~= "R15" or data.rig then "" else " (linted on a stand-in R15; give the track rig = ... for this actor's own)"))
			end
		end
	end))
	local ok, err = result[1], result[2]
	if not ok then
		report("analyze-failed", "fix", tostring(err))
	end
	local _ = cut
end

-- Prepare -----------------------------------------------------------------------------------------

export type State = {
	kind: string,
	dead: boolean,
	baked: Baked.Baked?,
	buffer: { number },
	poseBuffer: { number },
	worldAt: number,
	speed: number,
	hold: boolean,
	loop: boolean,
	duration: number?,
	fadeIn: number,
	fadeOut: number,
	rootMotion: boolean,
	active: boolean,
	weight: number,
	tau: number,
	lastWorld: number?,
	lead: number,
	useLead: boolean,
	writeJoints: (({ number }, number) -> ())?,
	place: (({ number }) -> ())?,
	restore: (() -> ())?,
	warnings: { string },
}

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[Animation] " .. message)
end

local function deadState(kind: string): State
	return {
		kind = kind,
		dead = true,
		baked = nil,
		buffer = {},
		poseBuffer = {},
		worldAt = 0,
		speed = 1,
		hold = true,
		loop = false,
		duration = nil,
		fadeIn = 0,
		fadeOut = 0,
		rootMotion = false,
		active = false,
		weight = 0,
		tau = 0,
		lastWorld = nil,
		lead = 0,
		useLead = false,
		writeJoints = nil,
		place = nil,
		restore = nil,
		warnings = {},
	}
end

-- A Lune stand-in actor: { spec = RigSpec, pivot = X? }.
local function dataActor(actor: any, rig: Rig.Rig, baked: Baked.Baked): (({ number }, number) -> (), ({ number }) -> (), () -> (), X)
	actor.transforms = actor.transforms or {}
	local start: X = if actor.pivot then (M.readX(actor.pivot)) else { p = { x = 0, y = -rig.ground, z = 0 }, q = M.qid() }
	local function write(buf: { number }, weight: number)
		for c = 1, baked.nch do
			local k = baked.joints[c]
			local o = c * 7
			actor.transforms[rig.joints[k].name] = {
				p = { x = buf[o + 1], y = buf[o + 2], z = buf[o + 3] },
				q = { x = buf[o + 4], y = buf[o + 5], z = buf[o + 6], w = buf[o + 7] },
				weight = weight,
			}
		end
	end
	local function place(buf: { number })
		local x = { p = { x = buf[1], y = buf[2], z = buf[3] }, q = { x = buf[4], y = buf[5], z = buf[6], w = buf[7] } }
		actor.pivot = if baked.rootMode == "world" then x else M.xmul(start, x)
	end
	local function restore()
		table.clear(actor.transforms)
	end
	return write, place, restore, start
end

function TrackCore.prepare(kind: string, data: any, ctx: any): State
	local actorName = data.actor
	local actor = if type(ctx) == "table" and type(ctx.actors) == "table" then ctx.actors[actorName] else nil
	if actor == nil then
		warnOnce(kind .. ":" .. tostring(actorName), string.format("%s: actor %q is not in the scene (not streamed in?); the track does nothing", kind, tostring(actorName)))
		return deadState(kind)
	end
	local state = deadState(kind)
	state.dead = false
	state.speed = if finite(data.speed) and kind ~= "animGait" then data.speed else 1
	state.fadeIn = if finite(data.fadeIn) then data.fadeIn else 0
	state.fadeOut = if finite(data.fadeOut) then data.fadeOut else 0
	state.duration = if finite(data.duration) then data.duration else nil
	local at = if finite(data.at) then data.at else 0
	local w, clockWarning = Clock.worldAt(if ctx then ctx.cut else nil, at)
	state.worldAt = w
	if clockWarning then
		warnOnce(kind .. ":clock", clockWarning)
	end

	local isInstance = typeof(actor) == "Instance"
	local read: any = nil
	local spec: any
	if isInstance then
		local okRead, result = pcall(function()
			local RigReader = require("./Roblox/RigReader")
			return RigReader.read(actor, { ignore = data.ignore })
		end)
		if not okRead then
			warnOnce(kind .. ":" .. actorName .. ":read", string.format("%s: could not read %s's rig (%s); the track does nothing", kind, actorName, tostring(result)))
			return deadState(kind)
		end
		read = result
		spec = result.spec
	elseif type(actor) == "table" and type(actor.spec) == "table" then
		spec = actor.spec
	else
		warnOnce(kind .. ":" .. actorName .. ":kind", string.format("%s: actor %q is a %s, not a model; the track does nothing", kind, actorName, typeof(actor)))
		return deadState(kind)
	end
	local rig = Rig.build(spec)
	local anatomy = Anatomy.classify(rig, data.overrides)

	-- where the actor stands now: the frame clips are relative to and gaits start from
	local start: X
	if isInstance and read.root then
		start = (M.readX((read.root :: any).CFrame))
	elseif not isInstance and actor.pivot then
		start = (M.readX(actor.pivot))
	else
		start = { p = { x = 0, y = -rig.ground, z = 0 }, q = M.qid() }
	end

	local baked: Baked.Baked
	local layer = data.layer or (if kind == "animLook" then "add" else "replace")
	local okBake, bakeErr = pcall(function()
		if kind == "animClip" then
			baked = Performance.bake(anatomy, data.clip)
		elseif kind == "animGait" then
			local ground: ((number, number) -> number)? = nil
			if isInstance and data.ground ~= "flat" then
				local Ground = require("./Roblox/Ground")
				local exclude = {}
				for _, inst in ctx.actors do
					if typeof(inst) == "Instance" then
						table.insert(exclude, inst)
					end
				end
				ground = Ground.raycaster({
					exclude = exclude,
					cell = math.max(anatomy.hipHeight / 10, 0.05),
					fallback = start.p.y + rig.ground,
					near = start.p.y + rig.ground,
					above = 2 * anatomy.height + 5,
					below = 4 * anatomy.height + 20,
				})
			end
			local look: any = nil
			if type(data.look) == "table" then
				local t = TrackCore.targetPoint(data.look.target, ctx)
				if t then
					look = { target = t, from = data.look.from or 0, to = data.look.to or math.huge }
				end
			end
			baked = Gait.bake(anatomy, gaitOptions(data, start, ground, look))
		else
			local tw = TrackCore.targetPoint(data.target, ctx)
			if not tw then
				error("the look target is not in the scene")
			end
			local local_ = M.qinvrot(start.q, M.vsub(tw :: V3, start.p))
			baked = Performance.bake(anatomy, TrackCore.lookClip(data, local_, anatomy))
		end
	end)
	if not okBake then
		warnOnce(kind .. ":" .. actorName .. ":bake", string.format("%s on %s could not bake (%s); the track does nothing", kind, actorName, tostring(bakeErr)))
		return deadState(kind)
	end
	local b = baked :: Baked.Baked
	state.baked = b
	state.buffer = Baked.buffer(b)
	state.poseBuffer = Baked.buffer(b)
	state.loop = b.loop or data.loop == true
	state.hold = data.hold ~= false or kind == "animGait"
	for _, msg in b.warnings do
		table.insert(state.warnings, msg)
	end
	-- a clip's root channel moves the actor only when it replaces the pose and moves at all
	local rootMoves = b.rootMode == "world"
	if not rootMoves then
		for s = 0, b.count - 1 do
			local r = Baked.get(b, s, 0)
			if M.vlen(r.p) > 1e-5 or M.qangle(r.q) > 1e-5 then
				rootMoves = true
				break
			end
		end
	end
	state.rootMotion = rootMoves and data.rootMotion ~= false and layer == "replace"

	if isInstance then
		local PoseWriter = require("./Roblox/PoseWriter")
		local writer = PoseWriter.new(read, rig, b, layer)
		local anchor: CFrame = (read.root :: any).CFrame
		state.writeJoints = function(buf: { number }, weight: number)
			PoseWriter.write(writer, buf, weight)
		end
		state.place = function(buf: { number })
			PoseWriter.place(writer, PoseWriter.rootCFrame(writer, buf, anchor))
		end
		state.restore = function()
			PoseWriter.restore(writer)
		end
		local okRun, running = pcall(function()
			return game:GetService("RunService"):IsRunning()
		end)
		state.useLead = okRun and running == true
	else
		local write, place, restore = dataActor(actor, rig, b)
		state.writeJoints = write
		state.place = place
		state.restore = restore
		state.useLead = data.lead == true
	end
	return state
end

-- A world point for a look target: an actor's head (or pivot), or { x, y, z }.
function TrackCore.targetPoint(target: any, ctx: any): V3?
	if type(target) == "table" and vec3ok(target) then
		return { x = target[1], y = target[2], z = target[3] }
	end
	if type(target) ~= "string" or type(ctx) ~= "table" or type(ctx.actors) ~= "table" then
		return nil
	end
	local inst = ctx.actors[target]
	if inst == nil then
		return nil
	end
	if typeof(inst) == "Instance" then
		local ok, p = pcall(function()
			local head = (inst :: any):FindFirstChild("Head", true)
			if head ~= nil and head:IsA("BasePart") then
				return head.Position
			end
			if (inst :: any):IsA("Model") then
				local cf, size = (inst :: any):GetBoundingBox()
				return cf.Position + Vector3.new(0, size.Y * 0.4, 0)
			end
			return (inst :: any).Position
		end)
		if ok and typeof(p) == "Vector3" then
			return { x = p.X, y = p.Y, z = p.Z }
		end
		return nil
	end
	if type(inst) == "table" and inst.pivot then
		local x = M.readX(inst.pivot)
		return x.p
	end
	return nil
end

-- Track time and weight at world time w (pure).
local function clockAt(state: State, worldTime: number): (number, number, boolean)
	local b = state.baked :: Baked.Baked
	local tau = (worldTime - state.worldAt) * state.speed
	if tau < 0 then
		return tau, 0, false
	end
	local length = b.length
	local weight = 1
	if state.fadeIn > 0 then
		weight = math.min(1, tau / state.fadeIn)
	end
	local playing = true
	local limit = state.duration or (if state.loop then math.huge else length)
	if tau > limit then
		if state.hold then
			tau = if state.loop then limit else length
		else
			local out = tau - limit
			if state.fadeOut > 0 and out < state.fadeOut then
				weight *= 1 - out / state.fadeOut
				tau = if state.loop then tau else length
			else
				playing = false
			end
		end
	end
	return tau, weight, playing
end

function TrackCore.evaluate(state: State, cutTime: number, worldTime: number)
	if state.dead or not state.baked then
		return
	end
	local _ = cutTime
	local tau, weight, playing = clockAt(state, worldTime)
	if tau < 0 or not playing then
		if state.active and state.restore then
			state.restore()
		end
		state.active = false
		state.lastWorld = worldTime
		return
	end
	-- the step since the last frame: how far ahead pose must look to land with the root
	if state.useLead and state.lastWorld then
		state.lead = math.clamp(worldTime - (state.lastWorld :: number), 0, 0.1)
	else
		state.lead = 0
	end
	state.lastWorld = worldTime
	state.active = true
	state.weight = weight
	state.tau = tau
	local b = state.baked :: Baked.Baked
	Baked.sample(b, tau, state.buffer)
	if state.rootMotion and state.place then
		state.place(state.buffer)
	end
end

function TrackCore.pose(state: State, cutTime: number, worldTime: number)
	if state.dead or not state.active or not state.baked or not state.writeJoints then
		return
	end
	local _ = cutTime
	local _w = worldTime
	local b = state.baked :: Baked.Baked
	local tau = state.tau
	if state.lead > 0 then
		local limit = state.duration or (if state.loop then math.huge else b.length)
		tau = math.min(tau + state.lead * state.speed, limit)
	end
	Baked.sample(b, tau, state.poseBuffer)
	state.writeJoints(state.poseBuffer, state.weight)
end

function TrackCore.stop(state: State)
	if state.restore then
		pcall(state.restore :: any)
	end
	state.active = false
	state.dead = true
end

return TrackCore
