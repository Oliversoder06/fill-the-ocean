-- The Jetpack Tank (a hotbar gadget): while it is out, holding jump flies as long as its fuel lasts.
-- The server owns the lift and the fuel (server/Run onGadget "fly", server/HeldTools.setLift); this
-- only tells it when the player wants to fly. Fuel and the hint show in client/Hotbar and Action.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RESEND_SECONDS = 0.25 -- while the server's Flying disagrees with the input, ask again this often

local player = Players.LocalPlayer
local Jetpack = {}

function Jetpack.start()
	local gadgetRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gadget") :: RemoteEvent
	local sentAt = -math.huge
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local jumpHeld = UserInputService:IsKeyDown(Enum.KeyCode.Space)
			or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
			or (humanoid ~= nil and humanoid.Jump) -- the touch jump button
		local want = player:GetAttribute("Gadget") == "jetpackTank"
			and ReplicatedStorage:GetAttribute("Phase") == "playing"
			and humanoid ~= nil
			and humanoid.Health > 0
			and (player:GetAttribute("Fuel") or 0) > 0
			and jumpHeld
		local now = os.clock()
		if want ~= (player:GetAttribute("Flying") == true) and now - sentAt >= RESEND_SECONDS then
			sentAt = now
			gadgetRemote:FireServer("fly", want)
		end
	end)
end

return Jetpack
