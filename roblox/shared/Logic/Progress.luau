--!strict
-- Calendar, daily reward streak, quests, Battle Pass levels and the daily Pixel Rift zone.
-- All pure: callers pass the time and ids, so everything is testable.

local Progression = require(script.Parent.Parent.Config.Progression)
local Types = require(script.Parent.Types)

type Quest = Types.Quest
type QuestBook = Types.QuestBook
type PassState = Types.PassState

local Progress = {}

---------------------------------------------------------------------------------------------------------------
-- Calendar (UTC)

function Progress.day(unixTime: number): number
	return unixTime // 86400
end

-- Weeks start on Monday. Day 0 (1970-01-01) was a Thursday.
function Progress.week(unixTime: number): number
	return (Progress.day(unixTime) + 3) // 7
end

function Progress.secondsToNextDay(unixTime: number): number
	return 86400 - unixTime % 86400
end

---------------------------------------------------------------------------------------------------------------
-- Daily reward

-- Which cycle day (1..7) the player would claim today, or nil if already claimed.
function Progress.dailyNext(daily: { streak: number, lastDay: number }, today: number): number?
	if daily.lastDay == today then
		return nil
	end
	local streak = if daily.lastDay == today - 1 then daily.streak + 1 else 1
	return ((streak - 1) % #Progression.DAILY) + 1
end

-- Claims today's reward. Returns the cycle day claimed (1..7), or nil if already claimed.
function Progress.claimDaily(daily: { streak: number, lastDay: number }, today: number): number?
	local cycleDay = Progress.dailyNext(daily, today)
	if not cycleDay then
		return nil
	end
	daily.streak = if daily.lastDay == today - 1 then daily.streak + 1 else 1
	daily.lastDay = today
	return cycleDay
end

-- A broken streak (a few missed days, nothing claimed today) can be saved by watching an ad.
function Progress.streakSavable(daily: { streak: number, lastDay: number }, today: number): boolean
	local missed = today - daily.lastDay - 1
	return daily.streak >= 2 and missed >= 1 and missed <= Progression.STREAK_SAVE_DAYS
end

-- Pretends yesterday was claimed, so today's claim continues the streak.
function Progress.saveStreak(daily: { streak: number, lastDay: number }, today: number): boolean
	if not Progress.streakSavable(daily, today) then
		return false
	end
	daily.lastDay = today - 1
	return true
end

---------------------------------------------------------------------------------------------------------------
-- Playtime gifts

function Progress.refreshPlaytime(state: Types.Playtime, today: number)
	if state.day ~= today then
		state.day = today
		state.seconds = 0
		state.claimed = 0
	end
end

-- Seconds until the next gift (0 when one is ready), or nil when today's gifts are all opened.
function Progress.giftSecondsLeft(state: Types.Playtime): number?
	local nextIndex = state.claimed + 1
	if nextIndex > #Progression.PLAYTIME_GIFTS then
		return nil
	end
	return math.max(0, nextIndex * Progression.GIFT_SECONDS - state.seconds)
end

-- Opens the next gift if it's ready. Returns its number and reward.
function Progress.claimGift(state: Types.Playtime): (number?, Progression.Reward?)
	if Progress.giftSecondsLeft(state) ~= 0 then
		return nil, nil
	end
	state.claimed += 1
	return state.claimed, Progression.PLAYTIME_GIFTS[state.claimed]
end

---------------------------------------------------------------------------------------------------------------
-- Quests

local function pick(templates: { Progression.QuestTemplate }, count: number, seed: number): { Progression.QuestTemplate }
	local pool = table.clone(templates)
	local chosen = {}
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	for _ = 1, math.min(count, #pool) do
		state = (state * 48271) % 2147483647
		local index = (state % #pool) + 1
		table.insert(chosen, table.remove(pool, index) :: Progression.QuestTemplate)
	end
	return chosen
end

local function build(templates: { Progression.QuestTemplate }, bestEgg: number): { Quest }
	local quests = {}
	for _, template in templates do
		local goal = template.goal
		if template.scaleWithEgg then
			goal *= math.max(1, bestEgg)
		end
		table.insert(quests, { id = template.id, goal = goal, progress = 0, claimed = false })
	end
	return quests
end

-- Rolls new daily/weekly quests when the day or week changes. Same player + day always gets the same set.
function Progress.refreshQuests(book: QuestBook, now: number, userId: number, bestEgg: number): boolean
	local changed = false
	local today, week = Progress.day(now), Progress.week(now)
	if book.day ~= today then
		book.day = today
		book.daily = build(pick(Progression.DAILY_TEMPLATES, Progression.DAILY_QUESTS, userId * 31 + today), bestEgg)
		changed = true
	end
	if book.week ~= week then
		book.week = week
		book.weekly = build(pick(Progression.WEEKLY_TEMPLATES, Progression.WEEKLY_QUESTS, userId * 17 + week * 7), bestEgg)
		changed = true
	end
	return changed
end

function Progress.template(id: string): Progression.QuestTemplate?
	for _, list in { Progression.DAILY_TEMPLATES, Progression.WEEKLY_TEMPLATES } do
		for _, template in list do
			if template.id == id then
				return template
			end
		end
	end
	return nil
end

-- Adds progress for an event. Returns quests that just became complete.
function Progress.addQuestProgress(book: QuestBook, event: string, amount: number): { Quest }
	local completed = {}
	for _, list in { book.daily, book.weekly } do
		for _, quest in list do
			local template = Progress.template(quest.id)
			if template and template.event == event and quest.progress < quest.goal then
				if template.max then
					quest.progress = math.max(quest.progress, amount)
				else
					quest.progress += amount
				end
				if quest.progress >= quest.goal then
					quest.progress = quest.goal
					table.insert(completed, quest)
				end
			end
		end
	end
	return completed
end

-- Swaps an unfinished daily quest for one the player doesn't have today (ad reward).
function Progress.rerollQuest(book: QuestBook, index: number, seed: number, bestEgg: number): boolean
	local quest = book.daily[index]
	if not quest or quest.claimed or quest.progress >= quest.goal then
		return false
	end
	local used: { [string]: boolean } = {}
	for _, other in book.daily do
		used[other.id] = true
	end
	local pool = {}
	for _, template in Progression.DAILY_TEMPLATES do
		if not used[template.id] then
			table.insert(pool, template)
		end
	end
	if #pool == 0 then
		return false
	end
	local template = pool[(math.abs(math.floor(seed)) % #pool) + 1]
	book.daily[index] = build({ template }, bestEgg)[1]
	return true
end

-- Marks a finished quest as claimed. Returns its reward, or nil.
function Progress.claimQuest(book: QuestBook, kind: string, index: number): Progression.Reward?
	local list = if kind == "daily" then book.daily elseif kind == "weekly" then book.weekly else nil
	local quest = list and list[index]
	if not quest or quest.claimed or quest.progress < quest.goal then
		return nil
	end
	quest.claimed = true
	return if kind == "daily" then Progression.DAILY_QUEST_REWARD else Progression.WEEKLY_QUEST_REWARD
end

---------------------------------------------------------------------------------------------------------------
-- Battle Pass

function Progress.season(now: number): number
	local days = Progress.day(now) - Progression.SEASON_START_DAY
	return 1 + math.max(0, days) // Progression.SEASON_DAYS
end

function Progress.seasonSecondsLeft(now: number): number
	local days = math.max(0, Progress.day(now) - Progression.SEASON_START_DAY)
	local endDay = Progression.SEASON_START_DAY + (days // Progression.SEASON_DAYS + 1) * Progression.SEASON_DAYS
	return endDay * 86400 - now
end

-- Starts a fresh pass when a new season begins. Cosmetics already earned stay forever.
function Progress.refreshPass(pass: PassState, now: number): boolean
	local season = Progress.season(now)
	if pass.season == season then
		return false
	end
	pass.season = season
	pass.xp = 0
	pass.premium = false
	pass.claimedFree = {}
	pass.claimedPremium = {}
	return true
end

function Progress.passLevel(xp: number): number
	return math.min(Progression.PASS_LEVELS, xp // Progression.PASS_XP_PER_LEVEL)
end

-- Returns the reward for a level if it can be claimed now, or nil and a reason.
function Progress.claimPass(pass: PassState, level: number, premium: boolean): (Progression.Reward?, string?)
	if level < 1 or level > Progression.PASS_LEVELS or level ~= math.floor(level) then
		return nil, "Invalid level"
	end
	if Progress.passLevel(pass.xp) < level then
		return nil, "Reach this level first"
	end
	if premium and not pass.premium then
		return nil, "Unlock the premium track first"
	end
	local claimed = if premium then pass.claimedPremium else pass.claimedFree
	local key = tostring(level)
	if claimed[key] then
		return nil, "Already claimed"
	end
	local reward = Progression.passReward(level, premium)
	if not reward then
		return nil, "Nothing at this level"
	end
	claimed[key] = true
	return reward, nil
end

---------------------------------------------------------------------------------------------------------------
-- Pixel Rift: one zone per UTC day, the same for every server

function Progress.riftZone(today: number, zoneCount: number): number
	local hash = (today * 2654435761) % 4294967296
	return (hash % zoneCount) + 1
end

return Progress
