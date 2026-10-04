-- Helpers for rewarded-ad buttons: daily limits, cooldowns and sending the watch request.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local AdLimits = require(Shared.Logic.AdLimits)
local Progress = require(Shared.Logic.Progress)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)

local AdButton = {}

local function now(): number
	return workspace:GetServerTimeNow()
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

-- True when the reward can be watched right now (limits only; the server checks the rest).
function AdButton.available(key: string): boolean
	local left = AdButton.left(key)
	return Products.adByKey[key] ~= nil and (left == nil or left > 0) and AdButton.cooldown(key) <= 0
end

function AdButton.watch(key: string, context: any?)
	Net.event("WatchAd"):FireServer(key, context)
end

return AdButton
