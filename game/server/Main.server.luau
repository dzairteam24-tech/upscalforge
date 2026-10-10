-- Server entry point: builds the world and starts the services.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Services = script.Parent.Services
local ArtService = require(Services.ArtService)
local DataService = require(Services.DataService)
local GearService = require(Services.GearService)
local HeistService = require(Services.HeistService)
local IslandService = require(Services.IslandService)
local MotherService = require(Services.MotherService)
local MoveService = require(Services.MoveService)
local PropService = require(Services.PropService)
local RaidService = require(Services.RaidService)
local ShopService = require(Services.ShopService)
local WildService = require(Services.WildService)
local WorldService = require(Services.WorldService)

Net.init()
WorldService.build()

-- (IslandService listens for loaded data, so it starts before DataService loads anyone)
IslandService.init()
ShopService.init()
HeistService.init()
MotherService.init()
RaidService.init()
WildService.init()
MoveService.init()
GearService.init()
DataService.init()

ArtService.init(function(name, model)
	if name == "TownModel" then
		WorldService.dressTown(model)
		PropService.decorate() -- (the town model holds props too)
	elseif name == "PropsModel" then
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
				root.CFrame = CFrame.new(0, 5, 16)
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end)
