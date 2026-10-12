--!strict
-- Going faster than walking (WildService.applySpeed), but never while carrying an egg: Sprint while it's held
-- (Config/Wild SPRINT).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local WildService = require(script.Parent.WildService)

local MoveService = {}

local wants: { [Player]: boolean } = {} -- holding Sprint

function MoveService.init()
	Net.event("Sprint").OnServerEvent:Connect(function(player, on)
		wants[player] = on == true
	end)
	Players.PlayerRemoving:Connect(function(player)
		wants[player] = nil
	end)
	-- Sprinting while holding it and moving; and picking up or losing an egg (the Heist's, the Wild's) changes
	-- what Sprint gives: kept up to date here
	task.spawn(function()
		while true do
			task.wait(0.1)
			for _, player in Players:GetPlayers() do
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.3
				local sprinting = wants[player] == true and moving and not WildService.slowed(player)
				if (player:GetAttribute("Sprinting") == true) ~= sprinting then
					player:SetAttribute("Sprinting", sprinting)
					WildService.applySpeed(player)
				elseif sprinting then
					WildService.applySpeed(player)
				end
			end
		end
	end)
end

return MoveService
