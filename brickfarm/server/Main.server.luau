--!strict
-- Starts Brick Farm's services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DataService = require(script.Parent.Services.DataService)
local FarmService = require(script.Parent.Services.FarmService)
local StudioTools = require(script.Parent.Services.StudioTools)

Net.init()
FarmService.init()
DataService.init()
StudioTools.init(FarmService.show) -- (chat commands for trying things, in Studio only)
