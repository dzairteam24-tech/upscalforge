-- Rewards that need a service and some context (which trip, which quest). The same handler serves the
-- rewarded video and the Robux product of a reward, e.g. "TripSkip" for AdTripSkip and the TripSkip product.
--   canUse  runs before the ad plays or the purchase prompt opens
--   grant   runs when the reward arrives (ProcessReceipt)
-- The context sent by the client is kept per player and product until the reward arrives. If the reward
-- can't be applied any more (for example after a rejoin), the player gets Coins x2 for 30 min instead.

local Players = game:GetService("Players")

local GameService = require(script.Parent.GameService)

local RewardService = {}

export type Handler = {
	canUse: (player: Player, context: any) -> (boolean, string?),
	grant: (player: Player, context: any) -> boolean,
}

local handlers: { [string]: Handler } = {}
local contexts: { [Player]: { [string]: any } } = {}

function RewardService.register(key: string, handler: Handler)
	handlers[key] = handler
end

function RewardService.has(key: string): boolean
	return handlers[key] ~= nil
end

function RewardService.canUse(player: Player, key: string, context: any): (boolean, string?)
	local handler = handlers[key]
	if not handler then
		return false, "This reward isn't set up yet"
	end
	return handler.canUse(player, context)
end

-- Remembers what the player picked for a product (ad or Robux) until its reward arrives.
function RewardService.setContext(player: Player, productKey: string, context: any)
	contexts[player] = contexts[player] or {}
	contexts[player][productKey] = context
end

-- Applies a handler reward for a product. Always gives something.
function RewardService.grant(player: Player, key: string, productKey: string)
	local handler = handlers[key]
	local context = contexts[player] and contexts[player][productKey]
	if contexts[player] then
		contexts[player][productKey] = nil
	end
	local applied = false
	if handler then
		local ok, result = pcall(handler.grant, player, context)
		applied = ok and result == true
		if not ok then
			warn("[Rewards] grant error", key, result)
		end
	end
	if not applied then
		GameService.addBoost(player, "Coins", 2, 1800)
		GameService.notify(player, "That reward wasn't needed any more, so here's Coins x2 for 30 min!", "success")
	end
end

function RewardService.init()
	Players.PlayerRemoving:Connect(function(player)
		contexts[player] = nil
	end)
end

return RewardService
