--!strict
-- Coin shop upgrades. `costs[n]` is the price of level n. Effects are read through the helpers below.

export type Upgrade = {
	id: string,
	name: string,
	description: string,
	costs: { number },
	requires: string?, -- another upgrade that must be owned first
}

local function geometric(first: number, ratio: number, count: number): { number }
	local costs = {}
	for level = 1, count do
		costs[level] = first * ratio ^ (level - 1)
	end
	return costs
end

local list: { Upgrade } = {
	{
		id = "TeamSlots",
		name = "Team Slot",
		description = "+1 creature in your team",
		costs = { 1e3, 1e4, 1e5, 1e6, 1e7, 1e8 },
	},
	{
		id = "CoinMult",
		name = "Coin Multiplier",
		description = "+25% coins per level",
		costs = geometric(1e3, 5, 10),
	},
	{
		id = "TapPower",
		name = "Tap Power",
		description = "Your taps hit harder",
		costs = geometric(200, 10, 5),
	},
	{
		id = "WalkSpeed",
		name = "Walk Speed",
		description = "+10% walk speed per level",
		costs = geometric(500, 10, 5),
	},
	{
		id = "Storage",
		name = "Storage",
		description = "+50 creature storage",
		costs = geometric(1e3, 2.5, 18), -- the last level is about 6B, reachable in World 1
	},
	{
		id = "OfflineTime",
		name = "Offline Time",
		description = "+2 hours of offline earnings",
		costs = geometric(5e3, 10, 5),
	},
	{
		id = "Hatch3",
		name = "Triple Hatch",
		description = "Open 3 eggs at once",
		costs = { 5e3 },
	},
	{
		id = "Hatch8",
		name = "Octo Hatch",
		description = "Open 8 eggs at once",
		costs = { 5e6 },
		requires = "Hatch3",
	},
	{
		id = "AutoHatch",
		name = "Auto Hatch",
		description = "Keep hatching while you stand at an egg",
		costs = { 5e4 },
	},
}

local byId: { [string]: Upgrade } = {}
for _, upgrade in list do
	byId[upgrade.id] = upgrade
end

local Upgrades = {
	list = list,
	byId = byId,
}

function Upgrades.nextCost(id: string, level: number): number?
	local upgrade = byId[id]
	if not upgrade then
		return nil
	end
	return upgrade.costs[level + 1]
end

function Upgrades.maxLevel(id: string): number
	local upgrade = byId[id]
	return if upgrade then #upgrade.costs else 0
end

function Upgrades.coinMult(level: number): number
	return 1 + 0.25 * level
end

function Upgrades.walkSpeedMult(level: number): number
	return 1 + 0.1 * level
end

function Upgrades.offlineHours(level: number, baseHours: number): number
	return baseHours + 2 * level
end

function Upgrades.storageBonus(level: number): number
	return 50 * level
end

-- Fraction of team power added to each tap.
function Upgrades.tapShare(level: number): number
	return 0.05 * (level + 1)
end

return Upgrades
