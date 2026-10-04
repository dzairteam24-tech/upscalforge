-- Server entry point. Order matters: listeners are connected before player data starts loading.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Services = script.Parent:WaitForChild("Services")
local WorldBuilder = require(Services.WorldBuilder)
local BreakableService = require(Services.BreakableService)
local GameService = require(Services.GameService)
local PetService = require(Services.PetService)
local ShopService = require(Services.ShopService)
local TradeService = require(Services.TradeService)
local DataService = require(Services.DataService)

Net.init()
WorldBuilder.build()
BreakableService.build()

GameService.init()
PetService.init()
ShopService.init()
TradeService.init()

DataService.init()

print("[Cubelings] Server ready")
