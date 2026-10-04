-- Coin shop (upgrades, zone gates) and Robux developer products (boosts, time skips, cosmetics).
-- Robux never buys eggs, luck, creatures or currency. Game passes, the Club and Premium live in
-- MembershipService.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local Upgrades = require(Shared.Config.Upgrades)
local World1 = require(Shared.Config.World1)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local AdsService = require(script.Parent.AdsService)
local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local RewardService = require(script.Parent.RewardService)
local State = require(script.Parent.State)

local ShopService = {}

local function buyUpgrade(player: Player, upgradeId: any)
	local data = DataService.get(player)
	if not data or type(upgradeId) ~= "string" then
		return
	end
	local upgrade = Upgrades.byId[upgradeId]
	if not upgrade then
		return
	end
	if upgrade.requires and (data.upgrades[upgrade.requires] or 0) < 1 then
		GameService.notify(player, ("Buy %s first"):format(Upgrades.byId[upgrade.requires].name), "error")
		return
	end
	local level = data.upgrades[upgradeId] or 0
	local cost = Upgrades.nextCost(upgradeId, level)
	if not cost then
		GameService.notify(player, "Already maxed", "error")
		return
	end
	if data.coins < cost then
		GameService.notify(player, "Not enough coins", "error")
		return
	end
	data.coins -= cost
	data.upgrades[upgradeId] = level + 1
	GameService.notify(player, ("%s upgraded!"):format(upgrade.name), "success")
	GameService.refresh(player)
end

local function unlockZone(player: Player, zoneId: any)
	local data = DataService.get(player)
	if not data or type(zoneId) ~= "number" then
		return
	end
	local zone = World1.zonesById[zoneId]
	if not zone or data.unlockedZones[tostring(zoneId)] then
		return
	end
	local reachable = false
	for _, neighbor in zone.links do
		if data.unlockedZones[tostring(neighbor)] then
			reachable = true
			break
		end
	end
	if not reachable then
		GameService.notify(player, "Unlock a zone next to it first", "error")
		return
	end
	if data.coins < zone.gateCost then
		GameService.notify(player, ("You need %s coins"):format(Format.abbrev(zone.gateCost)), "error")
		return
	end
	data.coins -= zone.gateCost
	data.unlockedZones[tostring(zoneId)] = true
	GameService.progress(player, "Zone", zoneId)
	GameService.notify(player, ("Unlocked %s!"):format(zone.name), "success")
	GameService.markDirty(player)
end

-- Developer product rewards. Must be idempotent: Roblox may call ProcessReceipt more than once.
local function grantProduct(player: Player, key: string): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	if key == "SupporterTitle" then
		data.titles.Supporter = true
		GameService.refreshTitles(player)
		GameService.notify(player, "Thanks for your support!", "success")
		return true
	elseif key == "PassPremium" then
		data.pass.premium = true
		GameService.notify(player, "Premium track unlocked for this season!", "success")
		GameService.markDirty(player)
		return true
	end
	if Products.adByKey[key] then
		return AdsService.grant(player, key)
	end
	local product = Products.productByKey[key]
	if product and product.reward then
		RewardService.grant(player, product.reward, key)
		GameService.markDirty(player)
		return true
	elseif product and product.boost then
		GameService.addBoost(player, product.boost.stat, product.boost.mult, product.boost.seconds)
		GameService.notify(player, product.name .. " is on. Thanks!", "success")
		return true
	end
	return false
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = player and DataService.get(player)
	if not player or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseKey = tostring(receipt.PurchaseId)
	if data.purchases[purchaseKey] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = Products.productById[receipt.ProductId]
	if not product or not grantProduct(player, product.key) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	data.purchases[purchaseKey] = true
	-- Save right away so the purchase isn't lost if the server shuts down
	if not DataService.save(player, false) and DataService.canSave(player) then
		data.purchases[purchaseKey] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	GameService.markDirty(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Robux purchase of a developer product. Checks first that the reward still makes sense (a trip to
-- finish, a quest to swap), remembers what it's for, then opens the Roblox prompt.
local function buyProduct(player: Player, key: any, context: any)
	local runtime = State.get(player)
	if not runtime or type(key) ~= "string" or not State.throttle(runtime, "BuyProduct", 1) then
		return
	end
	local product = Products.productByKey[key]
	if not product or product.adOnly then
		return
	end
	if product.id == 0 then
		GameService.notify(player, "This isn't on sale yet", "error")
		return
	end
	if product.reward then
		local ok, err = RewardService.canUse(player, product.reward, context)
		if not ok then
			GameService.notify(player, err or "Not available right now", "error")
			return
		end
		RewardService.setContext(player, key, context)
	end
	MarketplaceService:PromptProductPurchase(player, product.id)
end

function ShopService.init()
	Net.event("BuyUpgrade").OnServerEvent:Connect(buyUpgrade)
	Net.event("UnlockZone").OnServerEvent:Connect(unlockZone)
	Net.event("BuyProduct").OnServerEvent:Connect(buyProduct)

	MarketplaceService.ProcessReceipt = processReceipt

	-- Server Boost: coins x2 for everyone online
	RewardService.register("ServerBoost", {
		canUse = function()
			return true, nil
		end,
		grant = function(player)
			local boost = Products.SERVER_BOOST
			for other in State.all() do
				GameService.addBoost(other, boost.stat, boost.mult, boost.seconds)
			end
			GameService.notifyAll(
				("🚀 %s boosted the server! Coins x%g for everyone for %d minutes!"):format(player.DisplayName, boost.mult, boost.seconds // 60),
				"rare"
			)
			return true
		end,
	})
end

return ShopService
