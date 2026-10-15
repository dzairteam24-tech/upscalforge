--!strict
-- Starts Brick Farm's services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DataService = require(script.Parent.Services.DataService)
local FarmService = require(script.Parent.Services.FarmService)
local MarketService = require(script.Parent.Services.MarketService)
local StudioTools = require(script.Parent.Services.StudioTools)
local TractorService = require(script.Parent.Services.TractorService)

Net.init()
FarmService.init()
MarketService.init(FarmService.farmOf, FarmService.ownerOf, FarmService.levelUp)
TractorService.init(FarmService.farmOf, DataService.onLoaded, DataService.onLeaving)
DataService.init()
StudioTools.init(FarmService.show) -- (chat commands for trying things, in Studio only)
