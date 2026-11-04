-- Client entry point. Start controllers from here.
local CameraFeel = require(script.CameraFeel)
local Hud = require(script.Hud)
local Mood = require(script.Mood)
local Viewmodel = require(script.Viewmodel)

Mood.start()
CameraFeel.start()
Viewmodel.start()
Hud.start()
