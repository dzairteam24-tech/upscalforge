-- Rewarded videos and their Robux versions.
--   AdButton.supported()  can this player watch ads at all (13+, supported country, game eligible)?
--   AdButton.available()  is a given ad reward watchable right now (limits, cooldown, set up)?
--   AdButton.offer()      "ad" when the video can play, else "robux" when the product is on sale
--   AdButton.take()       watches the ad or opens the Robux prompt

local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local AdLimits = require(Shared.Logic.AdLimits)
local Progress = require(Shared.Logic.Progress)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)

local AdButton = {}

local CHECK_EVERY = 60
local adsSupported = false

local function checkAds()
	local ok, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	if not ok then
		adsSupported = false
		return
	end
	local status = result
	if typeof(result) == "Instance" or type(result) == "table" or type(result) == "userdata" then
		local inner = (result :: any).AdAvailabilityResult
		if inner ~= nil then
			status = inner
		end
	end
	adsSupported = status == Enum.AdAvailabilityResult.IsAvailable
end

task.spawn(function()
	while true do
		checkAds()
		task.wait(CHECK_EVERY)
	end
end)

local function now(): number
	return workspace:GetServerTimeNow()
end

function AdButton.supported(): boolean
	return adsSupported
end

-- Watches left today, or nil when the reward has no daily limit.
function AdButton.left(key: string): number?
	local data = Store.data
	if not data or not data.ads then
		return nil
	end
	return AdLimits.left(data.ads, key, Progress.day(now()))
end

function AdButton.cooldown(key: string): number
	local data = Store.data
	if not data or not data.ads then
		return 0
	end
	return AdLimits.cooldownLeft(data.ads, key, now())
end

-- True when the ad reward can be watched right now.
function AdButton.available(key: string): boolean
	local product = Products.productByKey[key]
	local left = AdButton.left(key)
	return adsSupported
		and product ~= nil
		and product.id ~= 0
		and Products.adByKey[key] ~= nil
		and (left == nil or left > 0)
		and AdButton.cooldown(key) <= 0
end

function AdButton.watch(key: string, context: any?)
	Net.event("WatchAd"):FireServer(key, context)
end

-- Which way the player can get a reward: "ad", "robux" or nil (nothing on sale yet).
function AdButton.offer(adKey: string, productKey: string): string?
	if AdButton.available(adKey) then
		return "ad"
	end
	local product = Products.productByKey[productKey]
	if product and product.id ~= 0 then
		return "robux"
	end
	return nil
end

-- Button text for an offer, e.g. "▶ Finish now" or "R$25 Finish now".
function AdButton.label(adKey: string, productKey: string, text: string): string
	local mode = AdButton.offer(adKey, productKey)
	if mode == "ad" then
		return "▶ " .. text
	end
	local product = Products.productByKey[productKey]
	return ("R$%d %s"):format(if product then product.price else 0, text)
end

function AdButton.take(adKey: string, productKey: string, context: any?)
	local mode = AdButton.offer(adKey, productKey)
	if mode == "ad" then
		AdButton.watch(adKey, context)
	elseif mode == "robux" then
		Net.event("BuyProduct"):FireServer(productKey, context)
	end
end

function AdButton.buy(productKey: string, context: any?)
	Net.event("BuyProduct"):FireServer(productKey, context)
end

return AdButton
