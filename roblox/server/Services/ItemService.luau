-- Using, merging and mixing items, equipping cartridges and opening keys.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Breakables = require(Shared.Config.Breakables)
local Items = require(Shared.Config.Items)
local World1 = require(Shared.Config.World1)
local Bag = require(Shared.Logic.Bag)
local Achievements = require(Shared.Logic.Achievements)
local Gear = require(Shared.Logic.Gear)
local Loot = require(Shared.Logic.Loot)
local Format = require(Shared.Logic.Format)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local HuntService = require(script.Parent.HuntService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData

local ItemService = {}

local rng = Random.new()

local function random(): number
	return rng:NextNumber()
end

-- Keys return true when they were used (and should be consumed).
local KEY_ACTIONS: { [string]: (Player, PlayerData, State.Runtime) -> boolean } = {
	Key_Zone = function(player, _data, runtime)
		local zone = if runtime.zoneId then World1.zonesById[runtime.zoneId] else nil
		if not zone or zone.eggPrice <= 0 then
			GameService.notify(player, "Use the Zone Key inside a zone", "error")
			return false
		end
		local raw = 5 * Breakables.byId.Vault.coins * zone.scale
		local gained = GameService.rewardCoins(player, raw, zone.id)
		for _ = 1, 2 do
			GameService.giveItem(player, Loot.randomElixir(2, 3 + Loot.zoneTierBonus(zone.id), random), 1, false)
		end
		GameService.notify(player, ("Treasure vault opened! 🪙 %s and 2 elixirs"):format(Format.abbrev(gained)), "success")
		return true
	end,
	Key_Golden = function(player, _data, _runtime)
		GameService.grantFreeEggs(player, 3, 1, "Golden")
		GameService.notify(player, "Golden chest opened!", "success")
		return true
	end,
	Key_Titan = function(player, data, runtime)
		local zone = if runtime.zoneId then World1.zonesById[runtime.zoneId] else nil
		if not zone or zone.restoreGoal <= 0 then
			GameService.notify(player, "Use the Titan Key inside a zone", "error")
			return false
		end
		if (data.zoneProgress[tostring(zone.id)] or 0) < zone.restoreGoal then
			GameService.notify(player, "Restore this zone to 100% first", "error")
			return false
		end
		if os.time() >= (data.guardians[tostring(zone.id)] or 0) then
			GameService.notify(player, "The guardian is already ready here", "error")
			return false
		end
		HuntService.resetGuardian(player, zone.id)
		GameService.notify(player, "The guardian of " .. zone.name .. " is coming!", "rare")
		return true
	end,
}

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
	if not item or Bag.count(data.items, itemId) < 1 then
		return
	end
	if item.kind == "Elixir" then
		Bag.take(data.items, itemId, 1)
		for _, boost in item.boosts do
			GameService.addBoost(player, boost.stat, boost.mult, item.duration)
		end
		GameService.notify(player, item.name .. " active: " .. item.description, "success")
	elseif item.kind == "Key" then
		local action = KEY_ACTIONS[itemId]
		if action and action(player, data, runtime) then
			Bag.take(data.items, itemId, 1)
		end
	end
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

-- Equipping moves the cartridge out of the bag; unequipping puts it back.
local function equipCartridge(player: Player, itemId: any)
	local data = DataService.get(player)
	if not data or type(itemId) ~= "string" or Bag.count(data.items, itemId) < 1 then
		return
	end
	local _, perks = Achievements.forData(data)
	local ok, err = Gear.canEquip(data.cartridges, itemId, Gear.slots(data.reloads, perks.cartridgeSlots))
	if not ok then
		GameService.notify(player, err or "Can't equip", "error")
		return
	end
	Bag.take(data.items, itemId, 1)
	table.insert(data.cartridges, itemId)
	GameService.refresh(player)
end

local function unequipCartridge(player: Player, itemId: any)
	local data = DataService.get(player)
	if not data or type(itemId) ~= "string" then
		return
	end
	local index = table.find(data.cartridges, itemId)
	if not index then
		return
	end
	table.remove(data.cartridges, index)
	Bag.add(data.items, itemId, 1)
	GameService.refresh(player)
end

function ItemService.init()
	Net.event("UseItem").OnServerEvent:Connect(useItem)
	Net.event("MergeItems").OnServerEvent:Connect(mergeItems)
	Net.event("MixItems").OnServerEvent:Connect(mixItems)
	Net.event("EquipCartridge").OnServerEvent:Connect(equipCartridge)
	Net.event("UnequipCartridge").OnServerEvent:Connect(unequipCartridge)
end

return ItemService
