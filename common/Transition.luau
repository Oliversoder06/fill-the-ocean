-- The teleport screen between the lobby and a run (client only): ReplicatedStorage.Transition, a
-- ScreenGui built in Studio (the lobby's is the one that travels; gameplay keeps a copy for Studio
-- tests). Two looks, one per way into a run:
--   Fresh   a run that opens on the intro: water floods the screen, then spins down a whirlpool into
--           the plughole and leaves black, the black the intro opens on.
--   Return  a run that goes straight into play: a wave sweeps an underwater screen in with the run's
--           card (logo, map, fill); in the run the water drains down off the screen onto the world.
-- The lobby's client/Session plays `out` and hands the gui to TeleportService:SetTeleportGui. Scripts
-- don't run during the hop, so each look ends on a still frame; gameplay's ReplicatedFirst.Arrival
-- puts it back up and its client/Arrival plays `rest`, `idle` and `reveal`.
-- Pieces, found by name: Fresh (Black; Water with Band and Foam above it; Pool, a circle, with
-- Arc1..ArcN, each a ring with a UIStroke, and Hole), Return.Body (Edge and EdgeFoam right of it, Top
-- and TopFoam above it, Rays, Bubbles, Card: UIScale Scale, a Vector2 attribute DesignSize, Logo,
-- MapName, FillBar.Fill, FillBar.Label, Status) and the Sounds Flood, Drain, Wave and Splash.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

export type Look = "fresh" | "return"
export type Run = { mapName: string, fill: number }

local FLOOD = 0.55 -- fresh: the water rises over the screen
local DRAIN = 0.9 -- then the whirlpool shrinks into the plughole
local SPIN = 1.75 -- turns the whirlpool makes on its way down
local ARC_LEAD = 0.6 -- each foam arc turns this much faster than the one outside it
local ARCS_IN = 0.2 -- seconds the foam arcs and the hole take to show
local SWEEP = 0.75 -- return: the wave crosses the screen
local CARD_AT = 0.45 -- into the sweep, the card pops in
local CARD_POP = 0.4
local CARD_OUT = 0.2 -- return's reveal: the card shrinks away
local SINK = 0.9 -- then the water drains down off the screen
local FADE = 0.6 -- fresh's reveal: the black fades (as Cutscene's cover does)
local BUBBLE_RISE = 0.03 -- screen heights a second, plus BUBBLE_RISE_PX per pixel of a bubble's size
local BUBBLE_RISE_PX = 0.004
local BUBBLE_WOBBLE = 6 -- pixels either side
local BUBBLE_WOBBLE_RATE = 2 -- radians a second
local RAY_SWAY = 14 -- pixels either side
local RAY_SWAY_RATE = 0.5

local Transition = {}

-- Every piece the code reads (Transition.missing).
local PIECES = {
	"Fresh.Black",
	"Fresh.Water.Foam",
	"Fresh.Pool.Arc1",
	"Fresh.Pool.Hole",
	"Return.Body.EdgeFoam",
	"Return.Body.TopFoam",
	"Return.Body.Rays",
	"Return.Body.Bubbles",
	"Return.Body.Card.Scale",
	"Return.Body.Card.MapName",
	"Return.Body.Card.FillBar.Fill",
	"Return.Body.Card.FillBar.Label",
	"Return.Body.Card.Status",
	"Flood",
	"Drain",
	"Wave",
	"Splash",
}

-- The lobby's out, the longer look's (fresh); the lobby server waits this (and a little more) before
-- it teleports the party.
Transition.OUT_SECONDS = FLOOD + DRAIN

type State = { anim: RBXScriptConnection?, idle: RBXScriptConnection? }
local states: { [ScreenGui]: State } = {}

local function find(root: Instance, path: string): any
	local node = root
	for name in path:gmatch("[^%.]+") do
		-- lihfolk-ignore: findfirstchild-chain (asserted on the next line)
		local child = node:FindFirstChild(name)
		assert(child, `{root:GetFullName()} is missing {path} (ReplicatedStorage.Transition, built in Studio)`)
		node = child
	end
	return node
end

local function ease(alpha: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): number
	return TweenService:GetValue(math.clamp(alpha, 0, 1), style, direction)
end

local function stateOf(gui: ScreenGui): State
	local state = states[gui]
	if not state then
		state = {}
		states[gui] = state
	end
	return state
end

-- Plays step(seconds in) every frame for `seconds`, the last frame exactly at its end, then done. A
-- new one on the same gui stops the last.
local function play(gui: ScreenGui, seconds: number, step: (number) -> (), done: () -> ())
	local state = stateOf(gui)
	if state.anim then
		state.anim:Disconnect()
	end
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		step(math.min(t, seconds))
		if t >= seconds then
			connection:Disconnect()
			if state.anim == connection then
				state.anim = nil
			end
			done()
		end
	end)
	state.anim = connection
end

local function sound(gui: ScreenGui, name: string)
	local found = find(gui, name)
	assert(found:IsA("Sound"), `Transition.{name} must be a Sound`)
	found:Play()
end

local function viewOf(gui: ScreenGui): Vector2
	local view = gui.AbsoluteSize
	if view.X > 0 and view.Y > 0 then
		return view
	end
	local camera = workspace.CurrentCamera
	assert(camera, "Transition: no camera to measure the screen by")
	return camera.ViewportSize
end

-- The card is built at its DesignSize and shrunk to fit a smaller screen, never grown (as the lobby's
-- windows are).
local function cardFit(gui: ScreenGui): number
	local card = find(gui, "Return.Body.Card")
	local design = card:GetAttribute("DesignSize")
	assert(typeof(design) == "Vector2", "Transition.Return.Body.Card needs a Vector2 attribute DesignSize (built in Studio)")
	local view = viewOf(gui)
	return math.min(view.X / design.X, view.Y / design.Y, 1)
end

-- Stops what plays on the gui and destroys it.
function Transition.remove(gui: ScreenGui)
	local state = states[gui]
	if state then
		if state.anim then
			state.anim:Disconnect()
		end
		if state.idle then
			state.idle:Disconnect()
		end
		states[gui] = nil
	end
	gui:Destroy()
end

-- The look the gui shows, nil for neither.
function Transition.look(gui: ScreenGui): Look?
	if find(gui, "Fresh").Visible then
		return "fresh"
	elseif find(gui, "Return").Visible then
		return "return"
	end
	return nil
end

-- The pieces a gui lacks, as one line (a template built wrong, or a teleport that didn't carry
-- them), or nil when it has them all.
function Transition.missing(gui: Instance): string?
	local lacking = {}
	for _, path in PIECES do
		local node: Instance? = gui
		for name in path:gmatch("[^%.]+") do
			node = if node then node:FindFirstChild(name) else nil
		end
		if not node then
			table.insert(lacking, path)
		end
	end
	return if #lacking > 0 then table.concat(lacking, ", ") else nil
end

-- The return look's card: the run's map and how full its ocean is (as the lobby's Saved Runs cards).
function Transition.setRun(gui: ScreenGui, run: Run)
	local card = find(gui, "Return.Body.Card")
	local fill = math.clamp(run.fill, 0, 1)
	find(card, "MapName").Text = run.mapName
	local bar = find(card, "FillBar.Fill")
	bar.Size = UDim2.fromScale(fill, 1)
	bar.Visible = fill > 0 -- its round ends would show as a sliver at 0
	find(card, "FillBar.Label").Text = `{math.floor(fill * 100)}% full`
end

-- The return look's line under the card (the run's waiting text).
function Transition.setStatus(gui: ScreenGui, text: string)
	local status = find(gui, "Return.Body.Card.Status")
	if status.Text ~= text then
		status.Text = text
	end
end

-- The look's still frame, at once: the one it ends on in the lobby and holds through the hop.
function Transition.rest(gui: ScreenGui, look: Look)
	local fresh, back = find(gui, "Fresh"), find(gui, "Return")
	fresh.Visible = look == "fresh"
	back.Visible = look == "return"
	if look == "fresh" then
		find(fresh, "Black").BackgroundTransparency = 0
		find(fresh, "Water").Visible = false
		find(fresh, "Pool").Visible = false
	else
		find(back, "Body").Position = UDim2.new()
		find(back, "Body.Card.Scale").Scale = cardFit(gui)
	end
end

-- Return: bubbles rise (bigger ones faster) and come round again at the bottom; the light sways.
function Transition.idle(gui: ScreenGui)
	local state = stateOf(gui)
	if state.idle then
		return
	end
	local body = find(gui, "Return.Body")
	local bubbles, rays = {}, {}
	for i, bubble in find(body, "Bubbles"):GetChildren() do
		if bubble:IsA("GuiObject") then
			local at = bubble.Position
			local speed = BUBBLE_RISE + bubble.Size.X.Offset * BUBBLE_RISE_PX
			table.insert(bubbles, { frame = bubble, x = at.X.Scale, y = at.Y.Scale, speed = speed, phase = i * 1.7 })
		end
	end
	for i, ray in find(body, "Rays"):GetChildren() do
		if ray:IsA("GuiObject") then
			table.insert(rays, { frame = ray, at = ray.Position, phase = i * 1.3 })
		end
	end
	local start = os.clock()
	state.idle = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		for _, b in bubbles do
			local y = 1.05 - (1.05 - b.y + t * b.speed) % 1.1
			b.frame.Position = UDim2.new(b.x, math.sin(t * BUBBLE_WOBBLE_RATE + b.phase) * BUBBLE_WOBBLE, y, 0)
		end
		for _, r in rays do
			local sway = math.sin(t * RAY_SWAY_RATE + r.phase) * RAY_SWAY
			r.frame.Position = UDim2.new(r.at.X.Scale, sway, r.at.Y.Scale, r.at.Y.Offset)
		end
	end)
end

local function freshOut(gui: ScreenGui, done: () -> ())
	local fresh = find(gui, "Fresh")
	local black, water, pool = find(fresh, "Black"), find(fresh, "Water"), find(fresh, "Pool")
	local hole = find(pool, "Hole")
	local crest = -find(water, "Foam").Position.Y.Offset -- the band and foam ride above the water's top
	local arcs = {}
	for _, ring in pool:GetChildren() do
		if ring:IsA("GuiObject") and ring.Name:match("^Arc%d+$") then
			local stroke = ring:FindFirstChildOfClass("UIStroke")
			assert(stroke, `{ring:GetFullName()} needs a UIStroke`)
			table.insert(arcs, { frame = ring, stroke = stroke, thickness = stroke.Thickness, rest = stroke.Transparency, order = tonumber(ring.Name:match("%d+")) :: number })
		end
	end
	assert(#arcs > 0, "Transition.Fresh.Pool has no Arc1..ArcN")
	local diameter = viewOf(gui).Magnitude + 8 -- the whole screen, corners too
	local holeRest = hole.BackgroundTransparency

	fresh.Visible = true
	find(gui, "Return").Visible = false
	black.BackgroundTransparency = 1
	water.Visible = true
	water.Position = UDim2.new(0, 0, 1, crest)
	pool.Visible = false
	sound(gui, "Flood")
	play(gui, FLOOD + DRAIN, function(t)
		if t < FLOOD then
			local a = ease(t / FLOOD, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			water.Position = UDim2.new(0, 0, 1 - a, crest * (1 - a))
			return
		end
		if water.Visible then -- the screen is under water: the whirlpool, the same colour, takes it from here
			water.Visible = false
			black.BackgroundTransparency = 0
			pool.Visible = true
			sound(gui, "Drain")
		end
		local u = (t - FLOOD) / DRAIN
		local sucked = ease(u, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local size = 1 - sucked
		local show = math.clamp((t - FLOOD) / ARCS_IN, 0, 1)
		pool.Size = UDim2.fromOffset(diameter * size, diameter * size)
		pool.Rotation = sucked * SPIN * 360
		hole.BackgroundTransparency = 1 - show * (1 - holeRest)
		for _, arc in arcs do
			arc.frame.Rotation = sucked * SPIN * 360 * ARC_LEAD * (arc.order - 1)
			arc.stroke.Thickness = arc.thickness * size
			arc.stroke.Transparency = 1 - show * (1 - arc.rest)
		end
	end, function()
		pool.Visible = false
		done()
	end)
end

local function returnOut(gui: ScreenGui, done: () -> ())
	local back = find(gui, "Return")
	local body = find(back, "Body")
	local foam = find(body, "EdgeFoam")
	local scale = find(body, "Card.Scale")
	local behind = foam.Position.X.Offset + foam.Size.X.Offset -- the crest runs ahead of the water
	local fit = cardFit(gui)

	find(gui, "Fresh").Visible = false
	back.Visible = true
	body.Position = UDim2.new(-1, -behind, 0, 0)
	scale.Scale = 0
	sound(gui, "Wave")
	Transition.idle(gui)
	play(gui, math.max(SWEEP, CARD_AT + CARD_POP), function(t)
		local a = ease(t / SWEEP, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		body.Position = UDim2.new(a - 1, -behind * (1 - a), 0, 0)
		scale.Scale = fit * ease((t - CARD_AT) / CARD_POP, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end, done)
end

-- The lobby's half: covers the screen in the look, then calls done on its still frame.
function Transition.out(gui: ScreenGui, look: Look, done: () -> ())
	if look == "fresh" then
		freshOut(gui, done)
	else
		returnOut(gui, done)
	end
end

-- Opens onto whatever is under the gui (the world, or the black the intro opens on), then removes it
-- and calls done. Fresh's black fades; return's card shrinks away and the water drains down.
function Transition.reveal(gui: ScreenGui, done: (() -> ())?)
	local function finish()
		Transition.remove(gui)
		if done then
			done()
		end
	end
	if Transition.look(gui) == "fresh" then
		local fresh = find(gui, "Fresh")
		local black = find(fresh, "Black")
		local from = black.BackgroundTransparency
		find(fresh, "Water").Visible = false
		find(fresh, "Pool").Visible = false
		play(gui, FADE, function(t)
			black.BackgroundTransparency = from + (1 - from) * (t / FADE)
		end, finish)
		return
	end
	local body = find(gui, "Return.Body")
	local scale = find(body, "Card.Scale")
	local from, x = scale.Scale, body.Position.X
	local crest = -find(body, "TopFoam").Position.Y.Offset -- the surface rides above the water's top
	sound(gui, "Splash")
	play(gui, CARD_OUT + SINK, function(t)
		scale.Scale = from * (1 - ease(t / CARD_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
		local a = ease((t - CARD_OUT) / SINK, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		body.Position = UDim2.new(x.Scale, x.Offset, a, crest * a)
	end, finish)
end

return Transition
