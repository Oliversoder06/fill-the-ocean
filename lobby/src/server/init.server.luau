-- Server entry point. Start services from here.
local Profiles = require(script.Profiles)
local Queue = require(script.Queue)
local Telemetry = require(script.Telemetry)

Telemetry.start(Queue.inParty) -- first: it starts each player's visit before their profile loads
Profiles.start()
Queue.start()
