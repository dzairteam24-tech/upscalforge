-- Rewarded video ads. The player chooses to watch; Roblox then grants the linked Developer Product,
-- which ShopService hands to AdsService.grant in ProcessReceipt (PurchaseChannel = AdReward).
-- Requirements from Roblox: ads-eligible experience (13+ creator, ID verified, enough monthly visitors).
--
-- Some rewards need context (which trip to finish, which quest to swap). Services register a handler:
-- `canUse` runs before the ad plays, `grant` after. The context sent with WatchAd is kept until the reward
-- arrives. If it can't be applied any more (for example after a rejoin), the player gets Coins x2 instead.

local AdService = game:GetService("AdService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local World1 = require(Shared.Config.World1)
local AdLimits = require(Shared.Logic.AdLimits)
local Items = require(Shared.Config.Items)
local Loot = require(Shared.Logic.Loot)
local Progress = require(Shared.Logic.Progress)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

local AdsService = {}

export type Handler = {
	canUse: (player: Player, context: any) -> (boolean, string?),
	grant: (player: Player, context: any) -> boolean,
}

local handlers: { [string]: Handler } = {}
local contexts: { [Player]: { [string]: any } } = {}
local watching: { [Player]: boolean } = {}
local rng = Random.new()

function AdsService.register(key: string, handler: Handler)
	handlers[key] = handler
end

local function isAvailable(): (boolean, string?)
	local ok, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	if not ok then
		return false, "Ads aren't available right now"
	end
	-- The call returns either the enum or an object holding it, depending on the engine version.
	local status = result
	if typeof(result) == "Instance" or type(result) == "table" or type(result) == "userdata" then
		local inner = (result :: any).AdAvailabilityResult
		if inner ~= nil then
			status = inner
		end
	end
	if status == Enum.AdAvailabilityResult.IsAvailable then
		return true, nil
	end
	return false, "No ad available right now. Try again later."
end

local function watch(player: Player, key: any, context: any)
	local runtime = State.get(player)
	local data = DataService.get(player)
	if not runtime or not data or type(key) ~= "string" or watching[player] then
		return
	end
	if not State.throttle(runtime, "WatchAd", 2) then
		return
	end
	local product = Products.productByKey[key]
	local reward = Products.adByKey[key]
	if not product or not product.adOnly or product.id == 0 or not reward then
		GameService.notify(player, "This reward isn't set up yet", "error")
		return
	end
	local now = os.time()
	local allowed, why = AdLimits.canWatch(data.ads, key, now, Progress.day(now))
	if not allowed then
		GameService.notify(player, why or "Not available", "error")
		return
	end
	if reward.custom then
		local handler = handlers[key]
		if not handler then
			GameService.notify(player, "This reward isn't set up yet", "error")
			return
		end
		local ok, err = handler.canUse(player, context)
		if not ok then
			GameService.notify(player, err or "Not available right now", "error")
			return
		end
	end
	local available, reason = isAvailable()
	if not available then
		GameService.notify(player, reason or "No ad available", "error")
		return
	end
	contexts[player] = contexts[player] or {}
	contexts[player][key] = context
	watching[player] = true
	local ok, result = pcall(function()
		local adReward = AdService:CreateAdRewardFromDevProductId(product.id)
		return AdService:ShowRewardedVideoAdAsync(player, adReward)
	end)
	watching[player] = nil
	if not ok then
		GameService.notify(player, "The ad couldn't play", "error")
	elseif result ~= Enum.ShowAdResult.ShowCompleted then
		GameService.notify(player, "Watch the whole ad to get the reward", "error")
	end
	-- On ShowCompleted the reward arrives through ProcessReceipt.
end

-- Applies an ad reward. Called from ProcessReceipt; always succeeds so the receipt is never stuck.
function AdsService.grant(player: Player, key: string): boolean
	local reward = Products.adByKey[key]
	local data = DataService.get(player)
	if not reward or not data then
		return false
	end
	if reward.custom then
		local handler = handlers[key]
		local context = contexts[player] and contexts[player][key]
		if contexts[player] then
			contexts[player][key] = nil
		end
		local applied = false
		if handler then
			local ok, result = pcall(handler.grant, player, context)
			applied = ok and result == true
			if not ok then
				warn("[Ads] grant error", key, result)
			end
		end
		if not applied then
			GameService.addBoost(player, "Coins", 2, 1800)
			GameService.notify(player, "That reward wasn't needed any more, so here's Coins x2 for 30 min!", "success")
		end
	else
		if reward.boost then
			GameService.addBoost(player, reward.boost.stat, reward.boost.mult, reward.boost.seconds)
		end
		if reward.freeEggs then
			GameService.grantFreeEggs(player, reward.freeEggs, 1)
		end
		GameService.notify(player, "Reward: " .. reward.label, "success")
	end
	local now = os.time()
	AdLimits.record(data.ads, key, now, Progress.day(now))
	GameService.markDirty(player)
	return true
end

function AdsService.adsConfigured(): boolean
	for _, reward in Products.adRewards do
		local product = Products.productByKey[reward.key]
		if product and product.id ~= 0 then
			return true
		end
	end
	return false
end

local function bestZone(player: Player): number
	local data = DataService.get(player)
	local best = 1
	if data then
		for _, zone in World1.zones do
			if zone.eggPrice > 0 and data.unlockedZones[tostring(zone.id)] then
				best = math.max(best, zone.id)
			end
		end
	end
	return best
end

function AdsService.init()
	Net.event("WatchAd").OnServerEvent:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		contexts[player] = nil
		watching[player] = nil
	end)

	-- Free elixir, once an hour
	AdsService.register("AdElixir", {
		canUse = function()
			return true, nil
		end,
		grant = function(player)
			local bonus = Loot.zoneTierBonus(bestZone(player))
			local id = Loot.randomElixir(2 + bonus, 3 + bonus, function()
				return rng:NextNumber()
			end)
			GameService.giveItem(player, id, 1, false)
			GameService.notify(player, "Free elixir: " .. Items.byId[id].name .. "!", "success")
			return true
		end,
	})
end

return AdsService
