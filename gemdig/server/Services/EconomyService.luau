--!strict
-- Coins: selling the backpack at the Sell stand, and buying shovels and backpacks at the Shop (one level at a time).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Backpack = require(Shared.Logic.Backpack)
local Gear = require(Shared.Config.Gear)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local EconomyService = {}

local function notify(player: Player, text: string, kind: string)
	Net.event("Notify"):FireClient(player, text, kind)
end

function EconomyService.sell(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local count, coins = Backpack.sellAll(data)
	if count == 0 then
		notify(player, "Your backpack is empty: go dig!", "info")
		return
	end
	notify(player, ("Sold %d gems for %s coins"):format(count, tostring(coins)), "good")
	DataService.push(player)
end

-- Buys the next shovel or backpack (kind "shovel" or "pack"; `index` must be the one after the player's own)
function EconomyService.buy(player: Player, kind: any, index: any): boolean
	local data = DataService.get(player)
	if not data or type(index) ~= "number" or (kind ~= "shovel" and kind ~= "pack") then
		return false
	end
	local list = if kind == "shovel" then Gear.SHOVELS else Gear.PACKS
	local owned = if kind == "shovel" then data.shovel else data.pack
	if index ~= owned + 1 or not list[index] then
		return false
	end
	local item = list[index]
	if data.coins < item.price then
		notify(player, "Not enough coins", "bad")
		return false
	end
	data.coins -= item.price
	if kind == "shovel" then
		data.shovel = index
	else
		data.pack = index
	end
	notify(player, "Bought " .. item.name, "good")
	DataService.push(player)
	return true
end

function EconomyService.init()
	Net.event("Buy").OnServerEvent:Connect(function(player, kind, index)
		EconomyService.buy(player, kind, index)
	end)
end

return EconomyService
