-- Client entry point. Start controllers from here.
local CameraFeel = require(script.CameraFeel)
local Hotbar = require(script.Hotbar)
local Hud = require(script.Hud)
local Mood = require(script.Mood)
local Shop = require(script.Shop)
local Viewmodel = require(script.Viewmodel)

Mood.start()
CameraFeel.start()
Viewmodel.start()
Hud.start()
Shop.start()
Hotbar.start()
