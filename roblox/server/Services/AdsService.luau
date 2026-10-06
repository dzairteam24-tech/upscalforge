-- Rewarded video ads. The player chooses to watch; Roblox then grants the linked Developer Product,
-- which ShopService hands to AdsService.grant in ProcessReceipt (PurchaseChannel = AdReward).
-- Requirements from Roblox: ads-eligible experience (13+ creator, ID verified, 2,000 monthly visitors),
-- and ads only show to players 13+ in supported countries. The client hides ad buttons when no ad can
-- play, and every important reward also has a Robux version (see Products).

local AdService = game:GetService("AdService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Products = require(Shared.Config.Products)
local World1 = require(Shared.Config.World1)
local AdLimits = require(Shared.Logic.AdLimits)
local Loot = require(Shared.Logic.Loot)
local Progress = require(Shared.Logic.Progress)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local RewardService = require(script.Parent.RewardService)
local State = require(script.Parent.State)

local AdsService = {}

local watching: { [Player]: boolean } = {}
local rng = Random.new()

local function isAvailable(): (boolean, string?)
	local ok, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	if not ok then
		return false, "Ads aren't available right now"
	end
	-- The call returns either the enum or an object holding it, depending on the engine version.
	local status = result
	if typeof(result) ~= "EnumItem" then
		-- An object holding the result; reading a missing property throws, so guard it
		local okInner, inner = pcall(function()
			return (result :: any).AdAvailabilityResult
		end)
		if okInner and inner ~= nil then
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
	if reward.reward then
		local ok, err = RewardService.canUse(player, reward.reward, context)
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
	RewardService.setContext(player, key, context)
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
	if reward.reward then
		RewardService.grant(player, reward.reward, key)
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
		watching[player] = nil
	end)

	-- Free elixir, once an hour (ads only: elixirs include luck, which is never sold)
	RewardService.register("Elixir", {
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
