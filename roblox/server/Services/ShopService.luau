-- Coin shop (upgrades, zone gates) and Robux products (VIP game pass, cosmetic developer products).
-- Robux never buys eggs, luck or currency.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local Upgrades = require(Shared.Config.Upgrades)
local World1 = require(Shared.Config.World1)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)

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
	local ad = Products.adByKey[key]
	if ad then
		if ad.boost then
			GameService.addBoost(player, ad.boost.stat, ad.boost.mult, ad.boost.seconds)
		end
		if ad.freeEggs then
			GameService.grantFreeEggs(player, ad.freeEggs, 1)
		end
		GameService.notify(player, "Reward: " .. ad.label, "success")
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

function ShopService.init()
	Net.event("BuyUpgrade").OnServerEvent:Connect(buyUpgrade)
	Net.event("UnlockZone").OnServerEvent:Connect(unlockZone)

	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local vip = Products.passByKey.VIP
		if purchased and vip and passId == vip.id then
			GameService.setVip(player, true)
			GameService.notify(player, "Welcome to VIP!", "success")
		end
	end)
end

return ShopService
