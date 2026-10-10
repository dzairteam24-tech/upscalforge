--!strict
-- The latest data from the server (IslandService.push), with a signal for the UI. Coins come more often, as
-- an attribute on the player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Store = {
	data = nil :: { [string]: any }?,
	island = nil :: number?,
}

local changed = Instance.new("BindableEvent")
Store.Changed = changed.Event

function Store.coins(): number
	local coins = Players.LocalPlayer:GetAttribute("Coins")
	if type(coins) == "number" then
		return coins
	end
	return if Store.data then Store.data.coins else 0
end

function Store.rate(): number
	local rate = Players.LocalPlayer:GetAttribute("Rate")
	return if type(rate) == "number" then rate else 0
end

function Store.init()
	Net.event("Data").OnClientEvent:Connect(function(data, island)
		Store.data = data
		Store.island = island
		changed:Fire()
	end)
end

return Store
