--!strict
-- How players get around besides walking: Sprint (Config/Wild SPRINT) while it's held, never while carrying an
-- egg; and the floating seat they ride (SeatModel, drawn by RideClient), which is only a look: everyone moves
-- the same.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local WildService = require(script.Parent.WildService)

local MoveService = {}

local wants: { [Player]: boolean } = {} -- holding Sprint

local function setSprinting(player: Player, on: boolean)
	if (player:GetAttribute("Sprinting") == true) ~= on then
		player:SetAttribute("Sprinting", on)
		WildService.applySpeed(player)
	end
end

local function step()
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.3
		setSprinting(player, wants[player] == true and moving and not WildService.busy(player))
	end
end

-- Puts the player on their floating seat (or off it)
local function applySeat(player: Player)
	local data = DataService.get(player)
	player:SetAttribute("RideSeat", if data and data.seats[data.seat] then data.seat else "")
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
	Net.event("Sprint").OnServerEvent:Connect(function(player, on)
		wants[player] = on == true
	end)
	Net.event("Seat").OnServerEvent:Connect(chooseSeat)
	DataService.onLoaded(function(player)
		applySeat(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		wants[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return MoveService
