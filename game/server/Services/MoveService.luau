--!strict
-- How players get around besides walking: Sprint (Config/Wild SPRINT), with stamina that runs out and fills up
-- again, never while carrying an egg; and the floating seat they ride (SeatModel, drawn by RideClient), which
-- is only a look: everyone moves the same.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WildConfig = require(Shared.Config.Wild)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local WildService = require(script.Parent.WildService)

local MoveService = {}

local stamina: { [Player]: number } = {} -- seconds of sprint left
local wants: { [Player]: boolean } = {} -- holding Sprint
local tired: { [Player]: boolean } = {} -- ran out: no sprint until it's partly back
local RESTED = 0.3 -- (this share of it)

local function setSprinting(player: Player, on: boolean)
	if (player:GetAttribute("Sprinting") == true) ~= on then
		player:SetAttribute("Sprinting", on)
		WildService.applySpeed(player)
	end
end

local function step(dt: number)
	for _, player in Players:GetPlayers() do
		local left = stamina[player] or WildConfig.STAMINA
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.3
		local can = wants[player] == true and moving and not tired[player] and not WildService.busy(player)
		if can then
			left = math.max(0, left - dt)
			tired[player] = left <= 0
		else
			left = math.min(WildConfig.STAMINA, left + dt * WildConfig.STAMINA / WildConfig.STAMINA_REFILL)
			if left >= WildConfig.STAMINA * RESTED then
				tired[player] = nil
			end
		end
		stamina[player] = left
		setSprinting(player, can and left > 0)
		-- (rounded, so it doesn't replicate every frame)
		local shown = math.floor(left / WildConfig.STAMINA * 20 + 0.5) / 20
		if player:GetAttribute("Stamina") ~= shown then
			player:SetAttribute("Stamina", shown)
		end
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
		stamina[player] = nil
		wants[player] = nil
		tired[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return MoveService
