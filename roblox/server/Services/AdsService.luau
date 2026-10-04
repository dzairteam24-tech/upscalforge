-- Rewarded video ads. The player chooses to watch; Roblox then grants the linked Developer Product,
-- which ShopService turns into the reward in ProcessReceipt (PurchaseChannel = AdReward).
-- Requirements from Roblox: ads-eligible experience (13+ creator, ID verified, enough monthly visitors).

local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local Net = require(Shared.Net)

local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

local AdsService = {}

local watching: { [Player]: boolean } = {}

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

local function watch(player: Player, key: any)
	local runtime = State.get(player)
	if not runtime or type(key) ~= "string" or watching[player] then
		return
	end
	if not State.throttle(runtime, "WatchAd", 2) then
		return
	end
	local product = Products.productByKey[key]
	if not product or not product.adOnly or product.id == 0 or not Products.adByKey[key] then
		GameService.notify(player, "This reward isn't set up yet", "error")
		return
	end
	local available, reason = isAvailable()
	if not available then
		GameService.notify(player, reason or "No ad available", "error")
		return
	end
	watching[player] = true
	local ok, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(product.id)
		return AdService:ShowRewardedVideoAdAsync(player, reward)
	end)
	watching[player] = nil
	if not ok then
		GameService.notify(player, "The ad couldn't play", "error")
	elseif result ~= Enum.ShowAdResult.ShowCompleted then
		GameService.notify(player, "Watch the whole ad to get the reward", "error")
	end
	-- On ShowCompleted the reward arrives through ProcessReceipt.
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

function AdsService.init()
	Net.event("WatchAd").OnServerEvent:Connect(watch)
end

return AdsService
