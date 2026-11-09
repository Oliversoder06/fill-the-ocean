--!strict
--[[
	Clock: the world time at a cut time, for a track that starts part-way into a cut.

	A track's own clock is worldTime - worldAt(at): hitstops freeze it and slow motion slows it
	exactly as they do the cut's animations, because the player hands evaluate the world time.
	The world time at the track's start comes, in order of preference, from:
	1. the cinematics runtime's own Types module (installed beside the Tracks module), which
	   knows every effect the cut format has;
	2. a module handed in with Clock.useTypes (tests do this);
	3. a reading of the cut's own hitstop actions (events, and shot actions at shot start + at)
	   merged into windows. Slow motion is not modelled here; a cut that uses it before a track
	   starts gets a one-line warning.
]]

local Clock = {}

local injected: any = nil

function Clock.useTypes(types: any)
	injected = types
end

local function installedTypes(): any
	if injected then
		return injected
	end
	local here: any = script
	if typeof(here) == "Instance" then
		-- this module lives in Cutscenes.Animation; the cinematics Types module in Cutscenes
		local folder = here.Parent and here.Parent.Parent
		local types = folder and folder:FindFirstChild("Types")
		if types and types:IsA("ModuleScript") then
			local ok, m = pcall(require, types)
			if ok and type(m) == "table" then
				return m
			end
		end
	end
	return nil
end

-- World seconds elapsed by cut time `at`, and a warning when only approximated.
function Clock.worldAt(cut: any, at: number): (number, string?)
	if type(at) ~= "number" or at <= 0 then
		return if type(at) == "number" then at else 0, nil
	end
	local types = installedTypes()
	if types and type(types.compile) == "function" and type(types.worldTime) == "function" and type(cut) == "table" then
		local ok, w = pcall(function()
			return types.worldTime(types.compile(cut), at)
		end)
		if ok and type(w) == "number" then
			return w, nil
		end
	end
	-- fall back: merge hitstop windows that start before `at`
	local windows: { { number } } = {}
	local slow = false
	local function consider(a: any, start: number)
		if type(a) ~= "table" or type(a.at) ~= "number" then
			return
		end
		local t0 = start + a.at
		if type(a.hitstop) == "number" and a.hitstop > 0 then
			table.insert(windows, { t0, t0 + a.hitstop })
		end
		if a.slowmo ~= nil and t0 < at then
			slow = true
		end
	end
	if type(cut) == "table" then
		if type(cut.events) == "table" then
			for _, a in cut.events do
				consider(a, 0)
			end
		end
		if type(cut.shots) == "table" then
			local start = 0
			for _, shot in cut.shots do
				if type(shot) == "table" then
					if type(shot.actions) == "table" then
						for _, a in shot.actions do
							consider(a, start)
						end
					end
					start += if type(shot.duration) == "number" then shot.duration else 0
				end
			end
		end
	end
	table.sort(windows, function(x, y)
		return x[1] < y[1]
	end)
	local lost = 0
	local curA, curB = nil :: number?, nil :: number?
	local function flush()
		if curA and curB then
			local a, b = curA :: number, math.min(curB :: number, at)
			if b > a then
				lost += b - a
			end
		end
	end
	for _, w in windows do
		if curB and w[1] <= (curB :: number) then
			curB = math.max(curB :: number, w[2])
		else
			flush()
			curA, curB = w[1], w[2]
		end
	end
	flush()
	return at - lost, if slow then "slow motion before this track starts is not counted in its start time (install the cinematics Types module beside Tracks)" else nil
end

return Clock
