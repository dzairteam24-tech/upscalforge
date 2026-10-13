--!strict
-- What a gem sells for is its value times this: rebirths, passes and boosts all ADD to it (they don't multiply
-- each other, so it never runs away).

local RebirthConfig = require(script.Parent.Parent.Config.Rebirth)

local Multiplier = {}

export type Holder = { rebirths: number, passes: { [string]: boolean }, boostUntil: number }

function Multiplier.boosted(data: Holder, now: number): boolean
	return data.boostUntil > now
end

function Multiplier.sell(data: Holder, now: number): number
	local m = 1 + RebirthConfig.BONUS * data.rebirths
	if data.passes.Coins2 then
		m += 1
	end
	if data.passes.Vip then
		m += 0.25
	end
	if data.boostUntil > now then
		m += 1
	end
	return m
end

return Multiplier
