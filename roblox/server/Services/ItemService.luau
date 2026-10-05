-- Using, merging and mixing items, equipping cartridges and opening keys.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Breakables = require(Shared.Config.Breakables)
local Items = require(Shared.Config.Items)
local World1 = require(Shared.Config.World1)
local Bag = require(Shared.Logic.Bag)
local Achievements = require(Shared.Logic.Achievements)
local Gear = require(Shared.Logic.Gear)
local Unlocks = require(Shared.Logic.Unlocks)
local Loot = require(Shared.Logic.Loot)
local Format = require(Shared.Logic.Format)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local BreakableService = require(script.Parent.BreakableService)
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

---------------------------------------------------------------------------------------------------------------
-- Gadgets: return true when used (and consumed). All of them need the player inside a play zone.

local BOMB_RADIUS = 40
local RAIN_SECONDS = 20
local RAIN_CHESTS_PER_SECOND = 0.5
local TOTEM_SECONDS = 5 * 60

local function playZone(player: Player, runtime: State.Runtime): World1.Zone?
	local zone = if runtime.zoneId then World1.zonesById[runtime.zoneId] else nil
	if not zone or zone.restoreGoal <= 0 then
		GameService.notify(player, "Use gadgets inside a zone", "error")
		return nil
	end
	return zone
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position else nil
end

local function placeTotemModel(position: Vector3, gadget: Items.Item, seconds: number)
	local base = Instance.new("Part")
	base.Name = "Totem"
	base.Anchored = true
	base.CanCollide = false
	base.Size = Vector3.new(3, 7, 3)
	base.Position = position + Vector3.new(4, 0.5, 0)
	base.Color = gadget.color
	base.Material = Enum.Material.Neon
	base.Transparency = 0.2
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = gadget.color
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = base
	base.Parent = workspace
	local ends = os.clock() + seconds
	task.spawn(function()
		while os.clock() < ends and base.Parent do
			local left = math.ceil(ends - os.clock())
			label.Text = ("%s %s · %d:%02d"):format(gadget.icon or "", gadget.name, left // 60, left % 60)
			task.wait(1)
		end
		base:Destroy()
	end)
end

local GADGET_ACTIONS: { [string]: (Player, PlayerData, State.Runtime) -> boolean } = {
	Gadget_Bomb = function(player, _data, runtime)
		local zone = playZone(player, runtime)
		local position = rootPosition(player)
		if not zone or not position then
			return false
		end
		local total, count = 0, 0
		for _, source in BreakableService.aliveInZone(zone.id) do
			if (source.part.Position - position).Magnitude <= BOMB_RADIUS then
				total += GameService.collectFrom(player, source, source.coinsLeft)
				count += 1
			end
		end
		if count == 0 then
			GameService.notify(player, "No coin sources nearby. Get closer!", "error")
			return false
		end
		GameService.notify(player, ("💣 Boom! %d sources, 🪙 %s"):format(count, Format.abbrev(total)), "success")
		return true
	end,
	Gadget_RainCloud = function(player, _data, runtime)
		local zone = playZone(player, runtime)
		if not zone then
			return false
		end
		local raw = Breakables.byId.Chest.coins * zone.scale * RAIN_CHESTS_PER_SECOND
		task.spawn(function()
			for _ = 1, RAIN_SECONDS do
				if not player.Parent then
					return
				end
				GameService.rewardCoins(player, raw, zone.id)
				task.wait(1)
			end
		end)
		GameService.notify(player, "🌧️ Coin rain for 20 seconds!", "success")
		return true
	end,
	Gadget_CoinTotem = function(player, _data, runtime)
		local zone = playZone(player, runtime)
		local position = rootPosition(player)
		if not zone or not position then
			return false
		end
		GameService.placeTotem(zone.id, "Coins", TOTEM_SECONDS)
		placeTotemModel(position, Items.byId.Gadget_CoinTotem, TOTEM_SECONDS)
		GameService.notifyZone(zone.id, ("🗿 %s placed a Coin Totem: coins +50%% here for 5 min!"):format(player.DisplayName), "success")
		return true
	end,
	Gadget_LuckTotem = function(player, _data, runtime)
		local zone = playZone(player, runtime)
		local position = rootPosition(player)
		if not zone or not position then
			return false
		end
		GameService.placeTotem(zone.id, "Luck", TOTEM_SECONDS)
		placeTotemModel(position, Items.byId.Gadget_LuckTotem, TOTEM_SECONDS)
		GameService.notifyZone(zone.id, ("🍀 %s placed a Luck Totem: luck +50%% here for 5 min!"):format(player.DisplayName), "success")
		return true
	end,
	Gadget_TimeSkip = function(player, _data, runtime)
		local zone = playZone(player, runtime)
		if not zone then
			return false
		end
		local count = 0
		for _, source in BreakableService.inZone(zone.id) do
			if not source.alive and not source.special then
				BreakableService.respawn(source, 0)
				count += 1
			end
		end
		if count == 0 then
			GameService.notify(player, "Every source here is already up", "error")
			return false
		end
		GameService.notify(player, ("⏰ %d sources are back!"):format(count), "success")
		return true
	end,
}

---------------------------------------------------------------------------------------------------------------
-- Stickers: moving one onto a creature takes it from the bag; the old one goes back.

local function applySticker(player: Player, petId: any, itemId: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(petId) ~= "string" or type(itemId) ~= "string" then
		return
	end
	if not State.throttle(runtime, "Sticker", 0.3) then
		return
	end
	if not Unlocks.has(data, "Stickers") then
		GameService.notify(player, Unlocks.lockedText("Stickers"), "error")
		return
	end
	local pet = data.pets[petId]
	local item = Items.byId[itemId]
	if not pet or not item or item.kind ~= "Sticker" or Bag.count(data.items, itemId) < 1 then
		return
	end
	if pet.ex then
		GameService.notify(player, "That creature is away on a trip", "error")
		return
	end
	Bag.take(data.items, itemId, 1)
	if pet.st then
		Bag.add(data.items, pet.st, 1)
	end
	pet.st = itemId
	GameService.notify(player, ("%s %s is on!"):format(item.icon or "", item.name), "success")
	GameService.refresh(player)
end

local function removeSticker(player: Player, petId: any)
	local data = DataService.get(player)
	if not data or type(petId) ~= "string" then
		return
	end
	local pet = data.pets[petId]
	if not pet or not pet.st then
		return
	end
	Bag.add(data.items, pet.st, 1)
	pet.st = nil
	GameService.refresh(player)
end

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
	elseif item.kind == "Gadget" then
		local action = GADGET_ACTIONS[itemId]
		if not Unlocks.has(data, "Gadgets") then
			GameService.notify(player, Unlocks.lockedText("Gadgets"), "error")
		elseif action and action(player, data, runtime) then
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
	if not Unlocks.has(data, "Cartridges") then
		GameService.notify(player, Unlocks.lockedText("Cartridges"), "error")
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
	Net.event("ApplySticker").OnServerEvent:Connect(applySticker)
	Net.event("RemoveSticker").OnServerEvent:Connect(removeSticker)
end

return ItemService
