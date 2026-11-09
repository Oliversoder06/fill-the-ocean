--!strict
--[[
	AnimPlayer (Roblox only): plays baked clips and gait cycles on a model during gameplay.

		local player = AnimPlayer.new(model)                   -- reads the rig once
		local punch = player:bake(Clips.Cross)                -- or Gait.cycle(player.anatomy, ...)
		local h = player:play(punch, { fadeIn = 0.05, onMarker = function(name) ... end })
		h:stop(0.2)
		player:destroy()                                       -- puts every Transform back

	One RunService.PreSimulation connection drives every player: that step runs after the
	Animator has written its frame, so these poses win over playing animations and are the ones
	Roblox applies before it draws. A handle in "add" mode layers on top (a look over a walk).

	Time comes from the frame's delta, so a clip plays at the same speed at any frame rate; a
	paused game (delta 0) holds the pose. Markers fire once each time playback passes them.
]]

local RunService: RunService = game:GetService("RunService")

local Rig = require("../Rig")
local Anatomy = require("../Anatomy")
local Baked = require("../Baked")
local Performance = require("../Performance")
local RigReader = require("./RigReader")
local PoseWriter = require("./PoseWriter")

local AnimPlayer = {}
AnimPlayer.__index = AnimPlayer

export type PlayOptions = {
	loop: boolean?,
	speed: number?,
	fadeIn: number?,
	fadeOut: number?,
	weight: number?,
	layer: string?,
	-- move the model by the clip's root channel (anchored models; never a Humanoid's own root)
	rootMotion: boolean?,
	onMarker: ((name: string, value: string?) -> ())?,
	onEnded: (() -> ())?,
}

export type Handle = {
	baked: Baked.Baked,
	time: number,
	speed: number,
	weight: number,
	fade: number,
	fadeIn: number,
	fadeOut: number,
	stopping: boolean,
	stopAt: number,
	loop: boolean,
	writer: PoseWriter.Writer,
	buffer: { number },
	anchor: CFrame,
	rootMotion: boolean,
	onMarker: ((string, string?) -> ())?,
	onEnded: (() -> ())?,
	done: boolean,
	player: any,
	stop: (self: Handle, fadeOut: number?) -> (),
	setSpeed: (self: Handle, speed: number) -> (),
	setWeight: (self: Handle, weight: number) -> (),
	seek: (self: Handle, t: number) -> (),
}

local players: { any } = {}
local connection: RBXScriptConnection? = nil

local function stepHandle(h: Handle, dt: number)
	local b = h.baked
	local prev = h.time
	if h.stopping then
		h.fade = math.max(0, h.fade - (if h.fadeOut > 0 then dt / h.fadeOut else 1))
	else
		h.fade = math.min(1, h.fade + (if h.fadeIn > 0 then dt / h.fadeIn else 1))
	end
	h.time += dt * h.speed
	if not h.loop and h.time >= b.length then
		h.time = b.length
		if not h.stopping then
			h.stopping = true
			h.stopAt = h.time
		end
	end
	-- markers passed this frame (wrapping for loops)
	if h.onMarker and #b.markers > 0 and h.time ~= prev then
		for _, mk in b.markers do
			local passed: boolean
			if h.loop and b.length > 0 then
				local a = prev % b.length
				local c = h.time % b.length
				if c >= a then
					passed = mk.time > a and mk.time <= c
				else
					passed = mk.time > a or mk.time <= c
				end
			else
				passed = mk.time > prev and mk.time <= h.time
			end
			if passed then
				task.spawn(h.onMarker :: any, mk.name, mk.value)
			end
		end
	end
	Baked.sample(b, h.time, h.buffer)
	PoseWriter.write(h.writer, h.buffer, h.weight * h.fade)
	if h.rootMotion then
		PoseWriter.place(h.writer, PoseWriter.rootCFrame(h.writer, h.buffer, h.anchor))
	end
	if h.stopping and h.fade <= 0 then
		h.done = true
	end
end

local function step(dt: number)
	for i = #players, 1, -1 do
		local p = players[i]
		local handles: { Handle } = p.handles
		for k = #handles, 1, -1 do
			local h = handles[k]
			local ok, err = pcall(stepHandle :: any, h, dt)
			if not ok then
				warn("[Animation] a playing clip failed and was stopped: " .. tostring(err))
				h.done = true
			end
			if h.done then
				table.remove(handles, k)
				PoseWriter.restore(h.writer)
				if h.onEnded then
					task.spawn(h.onEnded :: any)
				end
			end
		end
	end
end

local function ensureConnected()
	if connection == nil then
		connection = RunService.PreSimulation:Connect(step)
	end
end

local function disconnectIfIdle()
	if #players == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

--[[
	Reads the model's rig. `opts.overrides` goes to Anatomy.classify (legs, flying, ...).
]]
function AnimPlayer.new(model: Instance, opts: { [string]: any }?)
	local o: { [string]: any } = opts or {}
	local read = RigReader.read(model, o)
	local rig = Rig.build(read.spec)
	local anatomy = Anatomy.classify(rig, o.overrides)
	local self = setmetatable({
		model = model,
		read = read,
		rig = rig,
		anatomy = anatomy,
		handles = {} :: { Handle },
	}, AnimPlayer)
	for _, w in read.warnings do
		warn("[Animation] " .. model:GetFullName() .. ": " .. w)
	end
	table.insert(players, self)
	return self
end

-- Bakes a clip for this model's rig.
function AnimPlayer.bake(self: any, clip: any): Baked.Baked
	return Performance.bake(self.anatomy, clip)
end

function AnimPlayer.play(self: any, baked: Baked.Baked, opts: PlayOptions?): Handle
	local o: PlayOptions = opts or {}
	ensureConnected()
	local writer = PoseWriter.new(self.read, self.rig, baked, o.layer)
	local anchor = CFrame.identity
	if self.read.root then
		anchor = (self.read.root :: BasePart).CFrame
	end
	local h: Handle = {
		baked = baked,
		time = 0,
		speed = if type(o.speed) == "number" then o.speed else 1,
		weight = if type(o.weight) == "number" then o.weight else 1,
		fade = 0,
		fadeIn = if type(o.fadeIn) == "number" then math.max(0, o.fadeIn) else 0.15,
		fadeOut = if type(o.fadeOut) == "number" then math.max(0, o.fadeOut) else 0.2,
		stopping = false,
		stopAt = 0,
		loop = if o.loop == nil then baked.loop else o.loop == true,
		writer = writer,
		buffer = Baked.buffer(baked),
		anchor = anchor,
		rootMotion = o.rootMotion == true,
		onMarker = o.onMarker,
		onEnded = o.onEnded,
		done = false,
		player = self,
		stop = function(h: Handle, fadeOut: number?)
			if type(fadeOut) == "number" then
				h.fadeOut = math.max(0, fadeOut)
			end
			h.stopping = true
		end,
		setSpeed = function(h: Handle, speed: number)
			h.speed = speed
		end,
		setWeight = function(h: Handle, weight: number)
			h.weight = math.clamp(weight, 0, 1)
		end,
		seek = function(h: Handle, t: number)
			h.time = t
		end,
	}
	table.insert(self.handles, h)
	return h
end

function AnimPlayer.stopAll(self: any, fadeOut: number?)
	for _, h in self.handles do
		h:stop(fadeOut)
	end
end

-- Stops everything at once and puts every Transform back.
function AnimPlayer.destroy(self: any)
	for _, h in self.handles do
		PoseWriter.restore(h.writer)
	end
	table.clear(self.handles)
	local i = table.find(players, self)
	if i then
		table.remove(players, i)
	end
	disconnectIfIdle()
end

-- For tests and tools: advance every player by dt now.
AnimPlayer._step = step

return AnimPlayer
