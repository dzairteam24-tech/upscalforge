-- Describes rewards (daily, quests, pass) the same way the server will give them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Items = require(Shared.Config.Items)
local Progression = require(Shared.Config.Progression)
local World1 = require(Shared.Config.World1)
local Format = require(Shared.Logic.Format)

local Rewards = {}

function Rewards.bestEgg(data: { [string]: any }?): number
	local best = 100
	if data then
		for _, zone in World1.zones do
			if zone.eggPrice > 0 and data.unlockedZones[tostring(zone.id)] then
				best = math.max(best, zone.eggPrice)
			end
		end
	end
	return best
end

function Rewards.describe(reward: Progression.Reward, data: { [string]: any }?): string
	local parts = {}
	if reward.coinsInEggs then
		table.insert(parts, "🪙 " .. Format.abbrev(reward.coinsInEggs * Rewards.bestEgg(data)))
	end
	if reward.gems then
		table.insert(parts, "💎 " .. Format.abbrev(reward.gems))
	end
	if reward.items then
		for _, entry in reward.items do
			local item = Items.byId[entry.id]
			table.insert(parts, (if item then item.name else entry.id) .. (if entry.amount > 1 then " x" .. entry.amount else ""))
		end
	end
	if reward.freeEggs then
		table.insert(parts, ("🥚 %d free eggs"):format(reward.freeEggs))
	end
	if reward.title then
		local title = Cosmetics.titleById[reward.title]
		table.insert(parts, "🏷️ " .. (if title then title.text else reward.title))
	end
	if reward.trail then
		local trail = Cosmetics.trailById[reward.trail]
		table.insert(parts, "✨ " .. (if trail then trail.name else reward.trail))
	end
	if reward.xp then
		table.insert(parts, ("⭐ %d XP"):format(reward.xp))
	end
	return table.concat(parts, "\n")
end

return Rewards
