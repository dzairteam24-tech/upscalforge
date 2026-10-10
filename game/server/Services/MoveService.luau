--!strict
-- Going faster than walking (WildService.applySpeed), but never while carrying an egg: Sprint while it's held
-- (Config/Wild SPRINT), and the floating seat (SeatModel, drawn by RideClient), which the player gets on and off
-- with the HUD's button and rides SEAT_SPEED times faster. Everyone has the Cloud seat; the others are looks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local WildService = require(script.Parent.WildService)

local MoveService = {}

local wants: { [Player]: boolean } = {} -- holding Sprint

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
	Net.event("Sprint").OnServerEvent:Connect(function(player, on)
		wants[player] = on == true
	end)
	Players.PlayerRemoving:Connect(function(player)
		wants[player] = nil
	end)
	DataService.onLoaded(function(player)
		applySeat(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			applySeat(player)
		end)
	end)
	-- Sprinting while holding it and moving; and picking up or losing an egg (the Heist's, the Wild's) changes
	-- what the seat or Sprint gives: kept up to date here
	task.spawn(function()
		while true do
			task.wait(0.1)
			for _, player in Players:GetPlayers() do
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.3
				local sprinting = wants[player] == true and moving and not WildService.slowed(player)
				local riding = player:GetAttribute("RideSeat") ~= "" and player:GetAttribute("RideSeat") ~= nil
				if (player:GetAttribute("Sprinting") == true) ~= sprinting then
					player:SetAttribute("Sprinting", sprinting)
					WildService.applySpeed(player)
				elseif riding or sprinting then
					WildService.applySpeed(player)
				end
			end
		end
	end)
end

return MoveService
