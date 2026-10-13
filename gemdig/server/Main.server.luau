--!strict
-- Starts the game's services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DataService = require(script.Parent.Services.DataService)
local EconomyService = require(script.Parent.Services.EconomyService)
local MineService = require(script.Parent.Services.MineService)
local PlotService = require(script.Parent.Services.PlotService)
local TownService = require(script.Parent.Services.TownService)

Net.init()
PlotService.init()
TownService.init(EconomyService.sell, function(player)
	Net.event("OpenShop"):FireClient(player)
end)
EconomyService.init()
MineService.init()
DataService.init()
