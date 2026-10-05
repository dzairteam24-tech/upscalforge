-- Achievements and Rank: counts lifetime stats from progress events, grants tiers (gems, titles) and
-- Rank perks (storage, trip and cartridge slots, titles). Also keeps the creature index up to date.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AchievementConfig = require(Shared.Config.Achievements)
local Cosmetics = require(Shared.Config.Cosmetics)
local World1 = require(Shared.Config.World1)
local Achievements = require(Shared.Logic.Achievements)
local Format = require(Shared.Logic.Format)
local Types = require(Shared.Logic.Types)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData

local AchievementService = {}

local ROMAN = { "I", "II", "III", "IV", "V" }

-- Progress events that feed a lifetime stat. Hatches, coins and trades are counted where they happen.
local EVENT_STATS: { [string]: { stat: string, max: boolean? } } = {
	Break = { stat = "breaks" },
	Combo = { stat = "bestCombo", max = true },
	Fuse = { stat = "fusions" },
	Big = { stat = "bigsDefeated" },
	BigCatch = { stat = "bigsCaught" },
	Guardian = { stat = "guardians" },
	Titan = { stat = "titans" },
	Golden = { stat = "goldens" },
	Pixel = { stat = "pixels" },
	Restore = { stat = "restores" },
	Expedition = { stat = "trips" },
	Zone = { stat = "bestZone", max = true },
	Streak = { stat = "bestStreak", max = true },
}

local function indexPets(data: PlayerData)
	for _, pet in data.pets do
		data.index[Achievements.indexKey(pet)] = true
	end
end

local function grantTitle(data: PlayerData, titleId: string): string?
	if data.titles[titleId] then
		return nil
	end
	data.titles[titleId] = true
	local title = Cosmetics.titleById[titleId]
	return if title then title.text else titleId
end

local function check(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local rankBefore = Achievements.forData(data)
	local completed = Achievements.check(data)
	if #completed == 0 then
		return
	end
	local newTitles = false
	for _, done in completed do
		local achievement = AchievementConfig.byId[done.id]
		local gems = achievement.gems[done.tier] or 0
		data.gems += gems
		local parts = { ("🏆 %s %s!"):format(achievement.name, ROMAN[done.tier] or tostring(done.tier)) }
		if gems > 0 then
			table.insert(parts, "💎 " .. Format.abbrev(gems))
		end
		local titleId = achievement.titles and achievement.titles[done.tier]
		local titleText = titleId and grantTitle(data, titleId)
		if titleText then
			table.insert(parts, "Title: " .. titleText)
			newTitles = true
		end
		GameService.notify(player, table.concat(parts, " · "), "success")
	end

	local rankAfter, perks = Achievements.forData(data)
	if rankAfter > rankBefore then
		for _, titleId in perks.titles do
			if grantTitle(data, titleId) then
				newTitles = true
			end
		end
		for _, rideId in perks.rides do
			data.rides[rideId] = true
		end
		local lines = { ("⭐ Rank %d!"):format(rankAfter) }
		for _, perk in AchievementConfig.rankPerks do
			if perk.rank > rankBefore and perk.rank <= rankAfter then
				table.insert(lines, perk.text)
			end
		end
		GameService.notify(player, table.concat(lines, " · "), "rare")
	end
	if newTitles or rankAfter > rankBefore then
		GameService.refreshTitles(player)
	end
	GameService.refresh(player)
end

local function onProgress(player: Player, event: string, amount: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	local entry = EVENT_STATS[event]
	if entry then
		local current = data.stats[entry.stat] or 0
		data.stats[entry.stat] = if entry.max then math.max(current, amount) else current + amount
	end
	-- Coins fire many times a second; the periodic check covers them
	if event ~= "Coins" then
		check(player)
	end
end

-- Fills in stats for players from before achievements existed.
local function backfill(data: PlayerData)
	indexPets(data)
	local best = data.stats.bestZone or 0
	for _, zone in World1.zones do
		if data.unlockedZones[tostring(zone.id)] then
			best = math.max(best, zone.id)
		end
	end
	data.stats.bestZone = best
	data.stats.bestStreak = math.max(data.stats.bestStreak or 0, data.daily.streak)
end

function AchievementService.init()
	GameService.Progress:Connect(onProgress)
	DataService.Loaded:Connect(function(player: Player, data: PlayerData)
		backfill(data)
		check(player)
	end)
	task.spawn(function()
		while true do
			task.wait(10)
			for player in State.all() do
				local ok, err = pcall(check, player)
				if not ok then
					warn("[Achievements] check error", err)
				end
			end
		end
	end)
end

return AchievementService
