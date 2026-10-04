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
local ItemService = require(Services.ItemService)
local AdsService = require(Services.AdsService)
local HuntService = require(Services.HuntService)
local ProgressionService = require(Services.ProgressionService)
local DataService = require(Services.DataService)

Net.init()
WorldBuilder.build()
BreakableService.build()

GameService.init()
PetService.init()
ShopService.init()
TradeService.init()
ItemService.init()
AdsService.init()
HuntService.init()
ProgressionService.init()

DataService.init()

print("[Cubelings] Server ready")
