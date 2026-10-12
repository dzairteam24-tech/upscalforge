-- Server entry point: builds the world and starts the services.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Logic.Layout)
local Net = require(Shared.Net)

local Services = script.Parent.Services
local ArtService = require(Services.ArtService)
local CarryService = require(Services.CarryService)
local DataService = require(Services.DataService)
local HeistService = require(Services.HeistService)
local IndexService = require(Services.IndexService)
local IslandService = require(Services.IslandService)
local MotherService = require(Services.MotherService)
local MoveService = require(Services.MoveService)
local PropService = require(Services.PropService)
local RobuxService = require(Services.RobuxService)
local TrailService = require(Services.TrailService)
local ShopService = require(Services.ShopService)
local StealService = require(Services.StealService)
local StorageService = require(Services.StorageService)
local WildService = require(Services.WildService)
local WorldService = require(Services.WorldService)

Net.init()
WorldService.build()

-- (IslandService listens for loaded data, so it starts before DataService loads anyone)
IslandService.init()
ShopService.init()
StorageService.init()
StealService.init()
HeistService.init()
MotherService.init()
WildService.init()
MoveService.init()
CarryService.init()
IndexService.init()
RobuxService.init()
TrailService.init()
DataService.init()

ArtService.init(function(name, model)
	if name == "TownModel" or name == "PropsModel" then -- (the gardens' corner props)
		PropService.decorate()
	elseif name == "CreatureModels" then
		IslandService.redraw()
		WildService.redraw()
	end
end)

-- Anyone who falls off the islands comes back to the plaza
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and root.Position.Y < -40 then
				root.CFrame = Layout.SPAWN + Vector3.new(0, 5, 0)
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end)
