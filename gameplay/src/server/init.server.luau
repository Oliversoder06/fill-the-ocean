-- Server entry point. Start services from here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HeldTools = require(script.HeldTools)
local Map = require(script.Map)
local Run = require(script.Run)

HeldTools.start(Config)
Run.start(Map.ensure(Config))
