-- The teleport screen you arrive behind (common/Transition): the lobby's client/Session covered the
-- lobby with it and sent it along with the teleport; ReplicatedFirst.Arrival (src/first) put it up
-- again as PlayerGui.Arrival before the place loaded. This plays it into the run:
--   fresh (the run opens on the intro): black. It goes once Cutscene.cover's black is up (the same
--     black), so the run's waiting text shows as it always has and the intro opens on black.
--   return: the underwater screen with the run's card; bubbles rise and its Status line shows the
--     waiting text while the run loads. When play starts the water drains down off the screen onto
--     the world (Cutscene.cover drops its own black under it at once), or onto the cover's black
--     should the run open on the intro after all.
-- A run already playing when you load (a teammate skipped the intro) opens at once. Studio has no
-- teleports: the workspace attribute StudioTransition ("fresh" or "return") puts up a copy of
-- ReplicatedStorage.Transition instead.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Transition = require(ReplicatedStorage.Common.Transition)
local Hud = require(script.Parent.Hud)

local FRESH_WATCHDOG = 20 -- seconds: Cutscene.cover's black takes over long before this

local player = Players.LocalPlayer
local Arrival = {}

local shown: { gui: ScreenGui, look: Transition.Look, leaving: boolean, links: { RBXScriptConnection } }? = nil

-- The phases Cutscene.cover holds its black for.
local function holds(phase: any): boolean
	return phase == nil or phase == "loading" or phase == "intro"
end

local function unlink(s)
	for _, link in s.links do
		link:Disconnect()
	end
	table.clear(s.links)
end

local function close()
	local s = shown
	if s then
		shown = nil
		unlink(s)
		Transition.remove(s.gui)
	end
end

-- Opens onto whatever is under it: play, or the cover's black. It covers until it is gone.
local function reveal()
	local s = shown
	if not s or s.leaving then
		return
	end
	s.leaving = true
	unlink(s)
	Transition.reveal(s.gui, function()
		if shown == s then
			shown = nil
		end
	end)
end

-- Cutscene.cover's black is up for `phase`: fresh gives way to it; return stays over it while the run
-- loads and drains onto it when the run opens on the intro.
function Arrival.underBlack(phase: any)
	local s = shown
	if not s or s.leaving then
		return
	end
	if s.look == "fresh" then
		close()
	elseif phase == "intro" then
		reveal()
	end
end

-- Whether an arrival screen is up: when play starts Cutscene.cover then drops its black at once, as
-- this opens onto play itself.
function Arrival.covering(): boolean
	return shown ~= nil
end

local function studioCopy(): ScreenGui?
	local look = workspace:GetAttribute("StudioTransition")
	if look == nil then
		return nil
	end
	assert(look == "fresh" or look == "return", `workspace.StudioTransition must be "fresh" or "return", not {look}`)
	local template = ReplicatedStorage:WaitForChild("Transition", 10)
	assert(template and template:IsA("ScreenGui"), "ReplicatedStorage is missing Transition (a ScreenGui: a copy of the lobby's, built in Studio)")
	local gui = template:Clone() :: ScreenGui
	gui.Name = "Arrival"
	gui.Parent = player:WaitForChild("PlayerGui")
	local mapName, fill = ReplicatedStorage:GetAttribute("MapName"), ReplicatedStorage:GetAttribute("Fill")
	Transition.setRun(gui, {
		mapName = if type(mapName) == "string" then mapName else "",
		fill = if type(fill) == "number" then fill else 0,
	})
	Transition.rest(gui, look)
	return gui
end

-- What is wrong with the screen you arrived behind, or nil: a broken one comes down (loudly) so the
-- run's own black takes over, never an error that stops the client.
local function problemOf(gui: Instance): string?
	if not gui:IsA("ScreenGui") then
		return `is a {gui.ClassName}, not a ScreenGui`
	end
	local lacking = Transition.missing(gui)
	if lacking then
		return `is missing {lacking}`
	end
	if not Transition.look(gui) then
		return "shows neither look (Fresh, Return)"
	end
	return nil
end

-- First thing on the client: the arrival screen stays up until the run takes the screen.
function Arrival.start()
	local found = player:WaitForChild("PlayerGui"):FindFirstChild("Arrival")
	local gui = if found then found elseif RunService:IsStudio() then studioCopy() else nil
	if not gui then
		return
	end
	local problem = problemOf(gui)
	if problem then
		warn(`[Arrival] PlayerGui.Arrival {problem}; taking it down`)
		gui:Destroy()
		return
	end
	local look = Transition.look(gui) :: Transition.Look
	local s = { gui = gui, look = look, leaving = false, links = {} }
	shown = s
	Transition.rest(gui, look) -- whatever frame the hop froze on: its still one
	if look == "return" then
		Transition.idle(gui)
		local function status()
			Transition.setStatus(gui, Hud.waitingText())
		end
		table.insert(s.links, ReplicatedStorage:GetAttributeChangedSignal("Waiting"):Connect(status))
		status()
	else
		task.delay(FRESH_WATCHDOG, function()
			if shown == s and not s.leaving then
				warn("[Arrival] Cutscene.cover's black never took over the fresh arrival screen; taking it down")
				close()
			end
		end)
	end
	local function onPhase()
		if not holds(ReplicatedStorage:GetAttribute("Phase")) then
			reveal()
		end
	end
	table.insert(s.links, ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(onPhase))
	onPhase()
end

return Arrival
