--!strict
-- Rebirth: coins, shovel, backpack and depth go back to the start; the sell bonus stays for good (and the catalog,
-- passes and everything bought with Robux). What it costs and when it's allowed.

local RebirthConfig = require(script.Parent.Parent.Config.Rebirth)

export type Holder = { coins: number, shovel: number, pack: number, items: { [string]: any }, deepest: number, rebirths: number, checkpoint: number }

local Rebirth = {}

function Rebirth.cost(rebirths: number): number
	return math.floor(RebirthConfig.BASE_COST * RebirthConfig.GROWTH ^ rebirths)
end

-- Whether they can rebirth now; if not, why (shown to the player)
function Rebirth.can(data: Holder): (boolean, string?)
	if data.deepest < RebirthConfig.LAYER then
		return false, ("Reach layer %d first (your deepest: %d)"):format(RebirthConfig.LAYER, data.deepest)
	end
	local cost = Rebirth.cost(data.rebirths)
	if data.coins < cost then
		return false, ("You need %d coins (you have %d)"):format(cost, math.floor(data.coins))
	end
	return true, nil
end

function Rebirth.apply(data: Holder)
	data.coins = 0
	data.shovel = 1
	data.pack = 1
	data.items = {}
	data.deepest = 0
	data.checkpoint = 0
	data.rebirths += 1
end

return Rebirth
