-- Using, merging and mixing items.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Bag = require(Shared.Logic.Bag)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

local ItemService = {}

local function useItem(player: Player, itemId: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(itemId) ~= "string" then
		return
	end
	if not State.throttle(runtime, "UseItem", 0.2) then
		return
	end
	local item = Items.byId[itemId]
	if not item or item.kind ~= "Elixir" then
		return
	end
	if not Bag.take(data.items, itemId, 1) then
		GameService.notify(player, "You don't have that", "error")
		return
	end
	for _, boost in item.boosts do
		GameService.addBoost(player, boost.stat, boost.mult, item.duration)
	end
	GameService.notify(player, item.name .. " active: " .. item.description, "success")
	GameService.markDirty(player)
end

local function mergeItems(player: Player, itemId: any)
	local data = DataService.get(player)
	if not data or type(itemId) ~= "string" then
		return
	end
	local result, err = Bag.merge(data.items, itemId)
	if not result then
		GameService.notify(player, err or "Can't merge", "error")
		return
	end
	GameService.notify(player, "Made " .. Items.byId[result].name .. "!", "success")
	GameService.markDirty(player)
end

local function mixItems(player: Player, a: any, b: any)
	local data = DataService.get(player)
	if not data or type(a) ~= "string" or type(b) ~= "string" then
		return
	end
	local result, err = Bag.mix(data.items, a, b)
	if not result then
		GameService.notify(player, err or "Can't mix", "error")
		return
	end
	GameService.notify(player, "Mixed a " .. Items.byId[result].name .. "!", "success")
	GameService.markDirty(player)
end

function ItemService.init()
	Net.event("UseItem").OnServerEvent:Connect(useItem)
	Net.event("MergeItems").OnServerEvent:Connect(mergeItems)
	Net.event("MixItems").OnServerEvent:Connect(mixItems)
end

return ItemService
