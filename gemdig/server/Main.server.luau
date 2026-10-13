--!strict
-- Starts the game's services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DataService = require(script.Parent.Services.DataService)
local EconomyService = require(script.Parent.Services.EconomyService)
local MineService = require(script.Parent.Services.MineService)
local PlotService = require(script.Parent.Services.PlotService)
local RobuxService = require(script.Parent.Services.RobuxService)
local StudioTools = require(script.Parent.Services.StudioTools)
local TownService = require(script.Parent.Services.TownService)

Net.init()
PlotService.init()
TownService.init(EconomyService.sell, function(player)
	Net.event("OpenShop"):FireClient(player)
end)
EconomyService.init()
MineService.init()
RobuxService.init(function(player)
	local data = DataService.get(player)
	return if data then EconomyService.perMinute(data) else 0
end, EconomyService.welcomeBack)
DataService.init()
StudioTools.init() -- (chat commands for trying things, in Studio only)
