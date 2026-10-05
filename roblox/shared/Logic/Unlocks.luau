--!strict
-- Which systems a player has opened (see Config/Unlocks).

local Unlocks = require(script.Parent.Parent.Config.Unlocks)

local Logic = {}

-- Highest zone ever reached: the lifetime stat, or the unlocked gates (whichever is higher).
function Logic.bestZone(data: { stats: { [string]: number }, unlockedZones: { [string]: boolean } }): number
	local best = data.stats.bestZone or 0
	for key, open in data.unlockedZones do
		local zoneId = tonumber(key)
		if open and zoneId then
			best = math.max(best, zoneId)
		end
	end
	return best
end

function Logic.has(data: { stats: { [string]: number }, unlockedZones: { [string]: boolean } }, feature: string): boolean
	local unlock = Unlocks.byFeature[feature]
	return unlock == nil or Logic.bestZone(data) >= unlock.zone
end

function Logic.lockedText(feature: string): string
	local unlock = Unlocks.byFeature[feature]
	return if unlock then ("%s opens at zone %d"):format(unlock.label, unlock.zone) else "Not open yet"
end

-- Unlocks that open when the player first reaches `zoneId`.
function Logic.openedAt(zoneId: number): { Unlocks.Unlock }
	local out = {}
	for _, unlock in Unlocks.list do
		if unlock.zone == zoneId then
			table.insert(out, unlock)
		end
	end
	return out
end

return Logic
