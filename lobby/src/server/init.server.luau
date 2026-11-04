-- Server entry point. Start services from here.
local Profiles = require(script.Profiles)
local Queue = require(script.Queue)

Profiles.start()
Queue.start()
