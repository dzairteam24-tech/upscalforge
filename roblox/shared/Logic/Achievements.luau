--!strict
-- Achievement progress, stars and Rank perks. Pure: works on player data only.

local Achievements = require(script.Parent.Parent.Config.Achievements)
local Types = require(script.Parent.Types)

type PlayerData = Types.PlayerData

export type Completed = { id: string, tier: number }

export type Perks = {
	storage: number,
	tripSlots: number,
	cartridgeSlots: number,
	titles: { string },
}

local Logic = {}

-- Index key for a creature: species and variant ("Kitty|Golden").
function Logic.indexKey(pet: { s: string, v: string }): string
	return pet.s .. "|" .. pet.v
end

function Logic.discovered(index: { [string]: boolean }?): number
	if not index then
		return 0
	end
	local n = 0
	for _ in index do
		n += 1
	end
	return n
end

-- Current value of an achievement stat.
function Logic.value(data: PlayerData, stat: string): number
	if stat == "discovered" then
		return Logic.discovered(data.index)
	elseif stat == "reloads" then
		return data.reloads or 0
	end
	return data.stats[stat] or 0
end

function Logic.tier(data: PlayerData, id: string): number
	return data.achievements[id] or 0
end

-- Marks every newly reached tier and returns them (the caller grants the rewards).
function Logic.check(data: PlayerData): { Completed }
	local completed: { Completed } = {}
	for _, achievement in Achievements.list do
		local tier = Logic.tier(data, achievement.id)
		local value = Logic.value(data, achievement.stat)
		while tier < #achievement.goals and value >= achievement.goals[tier + 1] do
			tier += 1
			table.insert(completed, { id = achievement.id, tier = tier })
		end
		if tier > 0 then
			data.achievements[achievement.id] = tier
		end
	end
	return completed
end

function Logic.stars(done: { [string]: number }): number
	local stars = 0
	for id, tier in done do
		local achievement = Achievements.byId[id]
		if achievement then
			stars += math.min(tier, #achievement.goals)
		end
	end
	return stars
end

function Logic.maxStars(): number
	local stars = 0
	for _, achievement in Achievements.list do
		stars += #achievement.goals
	end
	return stars
end

function Logic.rank(stars: number): number
	return 1 + math.floor(stars / Achievements.STARS_PER_RANK)
end

function Logic.perks(rank: number): Perks
	local perks: Perks = { storage = 0, tripSlots = 0, cartridgeSlots = 0, titles = {} }
	for _, perk in Achievements.rankPerks do
		if rank >= perk.rank then
			perks.storage += perk.storage or 0
			perks.tripSlots += perk.tripSlots or 0
			perks.cartridgeSlots += perk.cartridgeSlots or 0
			if perk.title then
				table.insert(perks.titles, perk.title)
			end
		end
	end
	return perks
end

-- Rank and perks straight from player data.
function Logic.forData(data: PlayerData): (number, Perks)
	local rank = Logic.rank(Logic.stars(data.achievements or {}))
	return rank, Logic.perks(rank)
end

-- The next perk to unlock, or nil when all are unlocked.
function Logic.nextPerk(rank: number): Achievements.RankPerk?
	for _, perk in Achievements.rankPerks do
		if perk.rank > rank then
			return perk
		end
	end
	return nil
end

return Logic
