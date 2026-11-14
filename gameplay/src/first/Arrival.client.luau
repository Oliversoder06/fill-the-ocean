-- Puts the teleport screen you arrived behind (the lobby's ReplicatedStorage.Transition, played by its
-- client/Session with common/Transition) back up the moment this place starts loading, instead of
-- Roblox's loading screen, so the lobby, the hop and the arrival are one picture. client/Arrival
-- takes it from here (PlayerGui.Arrival) once the place has loaded. Without one (Studio, a join
-- that didn't come through the lobby's screen) Roblox's own loading screen stays.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")

local gui = TeleportService:GetArrivingTeleportGui()
if gui then
	assert(gui:IsA("ScreenGui"), `the arriving teleport gui is a {gui.ClassName}, not a ScreenGui`)
	gui.Name = "Arrival"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	gui.Enabled = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end
