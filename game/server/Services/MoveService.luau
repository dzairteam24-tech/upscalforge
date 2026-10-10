--!strict
-- The floating seat (SeatModel, drawn by RideClient): the player gets on and off it with the HUD's button, and
-- rides it faster than they walk (Config/Wild SEAT_SPEED, WildService.applySpeed), but never while carrying an
-- egg. Everyone has the Cloud seat; the others are only looks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local WildService = require(script.Parent.WildService)

local MoveService = {}

-- Puts the player on their floating seat (or off it)
local function applySeat(player: Player)
	local data = DataService.get(player)
	player:SetAttribute("RideSeat", if data and data.seats[data.seat] then data.seat else "")
	WildService.applySpeed(player)
end

local function chooseSeat(player: Player, name: any)
	local data = DataService.get(player)
	if not data or type(name) ~= "string" or (name ~= "" and not data.seats[name]) then
		return
	end
	data.seat = name
	applySeat(player)
end

function MoveService.init()
	Net.event("Seat").OnServerEvent:Connect(chooseSeat)
	DataService.onLoaded(function(player)
		applySeat(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			applySeat(player)
		end)
	end)
	-- Picking up or losing an egg (the Heist's, a raid's) changes what the seat gives: kept up to date here
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("RideSeat") ~= "" and player:GetAttribute("RideSeat") ~= nil then
					WildService.applySpeed(player)
				end
			end
		end
	end)
end

return MoveService
