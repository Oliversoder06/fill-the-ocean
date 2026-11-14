-- What this client tells the server's analytics (server/Telemetry, through the Telemetry remote):
-- its frame rate over each minute of play (measured only while playing with no cutscene, so a
-- loading burst never counts), how it plays (Hud.input), its first few distinct errors and warnings
-- (Roblox's Error Report never sees a warn()), and the moments other modules report (the honeycomb,
-- the guide). Only names listed in common/Analytics.CLIENT; the server checks and paces everything.
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Analytics = require(ReplicatedStorage.Common.Analytics)
local Hud = require(script.Parent.Hud)

local FPS_WINDOW = 60 -- seconds of play per fps report
local TEXT_SPACING = Analytics.CLIENT.error.gap + 0.1 -- the server takes one text a gap

local DEVICES = { touch = "Touch", gamepad = "Gamepad", mouse = "Mouse" }

local Telemetry = {}

local remote: RemoteEvent? = nil

-- One report (a name from Analytics.CLIENT and its argument). Before start: dropped, never queued.
function Telemetry.report(name: string, arg: any?)
	assert(Analytics.CLIENT[name], `Telemetry.report: {name} isn't listed in common/Analytics.CLIENT`)
	if remote then
		remote:FireServer(name, arg)
	end
end

function Telemetry.start()
	local found = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Telemetry", 10)
	assert(found and found:IsA("RemoteEvent"), "ReplicatedStorage.Remotes is missing Telemetry (Rojo project; restart rojo serve)")
	remote = found

	local device = ""
	local function onInput()
		local now = DEVICES[Hud.input()]
		if now ~= device then
			device = now
			Telemetry.report("device", now)
		end
	end
	UserInputService.LastInputTypeChanged:Connect(onInput)
	onInput()

	local frames, elapsed = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		if ReplicatedStorage:GetAttribute("Phase") ~= "playing" or Hud.cutscene then
			return
		end
		frames += 1
		elapsed += dt
		if elapsed >= FPS_WINDOW then
			Telemetry.report("fps", frames / elapsed)
			frames, elapsed = 0, 0
		end
	end)

	-- The first Analytics.ERRORS_MAX distinct errors and warnings, sent one per server gap.
	local seen = { error = {}, warn = {} }
	local queue = {}
	LogService.MessageOut:Connect(function(message, kind)
		local name = if kind == Enum.MessageType.MessageError then "error" elseif kind == Enum.MessageType.MessageWarning then "warn" else nil
		if not name then
			return
		end
		local text = message:sub(1, Analytics.TEXT_MAX)
		local list = seen[name]
		if #list < Analytics.ERRORS_MAX and not table.find(list, text) then
			table.insert(list, text)
			table.insert(queue, { name = name, text = text })
		end
	end)
	task.spawn(function()
		while true do
			task.wait(TEXT_SPACING)
			local item = table.remove(queue, 1)
			if item then
				Telemetry.report(item.name, item.text)
			end
		end
	end)
end

return Telemetry
