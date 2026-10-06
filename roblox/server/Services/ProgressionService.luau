-- Daily reward, quests, Battle Pass, cosmetics and the daily Pixel Rift.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Codes = require(Shared.Config.Codes)
local Cosmetics = require(Shared.Config.Cosmetics)
local Items = require(Shared.Config.Items)
local Progression = require(Shared.Config.Progression)
local World1 = require(Shared.Config.World1)
local Unlocks = require(Shared.Logic.Unlocks)
local Format = require(Shared.Logic.Format)
local Progress = require(Shared.Logic.Progress)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local RewardService = require(script.Parent.RewardService)
local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData

local ProgressionService = {}

local PLAY_ZONES = 0
for _, zone in World1.zones do
	if zone.eggPrice > 0 then
		PLAY_ZONES += 1
	end
end

-- Price of the best egg the player can open: rewards in "eggs" scale with it.
local function bestEgg(data: PlayerData): number
	local best = 100
	for _, zone in World1.zones do
		if zone.eggPrice > 0 and data.unlockedZones[tostring(zone.id)] then
			best = math.max(best, zone.eggPrice)
		end
	end
	return best
end

local function questText(quest: Types.Quest): string
	local template = Progress.template(quest.id)
	if not template then
		return quest.id
	end
	return (template.text:gsub("{goal}", Format.abbrev(quest.goal)))
end

-- Gives a reward and returns a short summary for the notification.
local function grant(player: Player, data: PlayerData, reward: Progression.Reward): string
	local parts = {}
	if reward.coinsInEggs then
		local coins = reward.coinsInEggs * bestEgg(data)
		data.coins += coins
		table.insert(parts, "🪙 " .. Format.abbrev(coins))
	end
	if reward.gems then
		data.gems += reward.gems
		table.insert(parts, "💎 " .. Format.abbrev(reward.gems))
	end
	if reward.items then
		for _, entry in reward.items do
			GameService.giveItem(player, entry.id, entry.amount, false)
			local item = Items.byId[entry.id]
			table.insert(parts, (if item then item.name else entry.id) .. (if entry.amount > 1 then " x" .. entry.amount else ""))
		end
	end
	if reward.freeEggs then
		GameService.grantFreeEggs(player, reward.freeEggs, reward.freeEggLuck or 1)
		table.insert(parts, ("%d free eggs"):format(reward.freeEggs))
	end
	if reward.title then
		data.titles[reward.title] = true
		local title = Cosmetics.titleById[reward.title]
		table.insert(parts, "Title: " .. (if title then title.text else reward.title))
	end
	if reward.trail then
		data.trails[reward.trail] = true
		local trail = Cosmetics.trailById[reward.trail]
		table.insert(parts, if trail then trail.name else reward.trail)
	end
	if reward.ride then
		data.rides[reward.ride] = true
		local ride = Cosmetics.rideById[reward.ride]
		table.insert(parts, "Ride: " .. (if ride then ride.name else reward.ride))
	end
	if reward.tickets then
		data.tickets += reward.tickets
		table.insert(parts, "🎟️ " .. reward.tickets)
	end
	if reward.xp then
		local cap = Progression.PASS_LEVELS * Progression.PASS_XP_PER_LEVEL
		data.pass.xp = math.min(cap, data.pass.xp + reward.xp)
		table.insert(parts, ("+%d Pass XP"):format(reward.xp))
	end
	GameService.markDirty(player)
	return table.concat(parts, ", ")
end

-- Quests the player can actually do today (QuestTemplate.needs)
local function questFilter(data: PlayerData): Progress.QuestFilter
	return function(template)
		if template.needs == "Rift" then
			return GameService.riftZone > 0 and data.unlockedZones[tostring(GameService.riftZone)] == true
		elseif template.needs == "Trips" then
			return Unlocks.has(data, "Trips")
		elseif template.needs == "Restored" then
			for _, zone in World1.zones do
				if zone.restoreGoal > 0 and (data.zoneProgress[tostring(zone.id)] or 0) >= zone.restoreGoal then
					return true
				end
			end
			return false
		end
		return true
	end
end

local function refresh(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local now = os.time()
	local changed = Progress.refreshQuests(data.quests, now, player.UserId, bestEgg(data), questFilter(data))
	-- Free daily luck for everyone, no ad needed
	local today = Progress.day(now)
	if data.freeLuckDay ~= today then
		data.freeLuckDay = today
		local luck = Progression.FREE_DAILY_LUCK
		GameService.addBoost(player, "Luck", luck.mult, luck.seconds)
		GameService.notify(player, ("🍀 Daily gift: Luck x%g for %d minutes!"):format(luck.mult, luck.seconds // 60), "success")
		changed = true
	end
	changed = Progress.refreshPass(data.pass, now) or changed
	if changed then
		GameService.markDirty(player)
	end
end

local function updateRift()
	local zoneId = Progress.riftZone(Progress.day(os.time()), PLAY_ZONES)
	if GameService.riftZone ~= zoneId then
		GameService.riftZone = zoneId
		ReplicatedStorage:SetAttribute("RiftZone", zoneId)
		GameService.notifyAll(("The Pixel Rift opened in %s! Coins x%g, Pixel chance x%g"):format(
			World1.zonesById[zoneId].name,
			Progression.RIFT_COINS,
			Progression.RIFT_PIXEL_CHANCE
		), "rare")
	end
end

local function onProgress(player: Player, event: string, amount: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	local completed = Progress.addQuestProgress(data.quests, event, amount)
	for _, quest in completed do
		GameService.notify(player, "Quest complete: " .. questText(quest) .. ". Claim it in Quests!", "success")
	end
	if #completed > 0 then
		GameService.markDirty(player)
	end
end

local function claimDaily(player: Player)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or not State.throttle(runtime, "ClaimDaily", 1) then
		return
	end
	local cycleDay = Progress.claimDaily(data.daily, Progress.day(os.time()))
	if not cycleDay then
		GameService.notify(player, "Come back tomorrow for the next reward!", "error")
		return
	end
	GameService.progress(player, "Streak", data.daily.streak)
	local summary = grant(player, data, Progression.DAILY[cycleDay])
	GameService.notify(player, ("Day %d reward: %s"):format(cycleDay, summary), "success")
end

local function claimQuest(player: Player, kind: any, index: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(kind) ~= "string" or type(index) ~= "number" then
		return
	end
	if not State.throttle(runtime, "ClaimQuest", 0.3) then
		return
	end
	refresh(player)
	local reward = Progress.claimQuest(data.quests, kind, index)
	if not reward then
		return
	end
	GameService.notify(player, "Quest reward: " .. grant(player, data, reward), "success")
end

local function claimGift(player: Player)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or not State.throttle(runtime, "ClaimGift", 0.5) then
		return
	end
	Progress.refreshPlaytime(data.playtime, Progress.day(os.time()))
	local number, reward = Progress.claimGift(data.playtime)
	if not number or not reward then
		return
	end
	GameService.notify(player, ("🎁 Gift %d: %s"):format(number, grant(player, data, reward)), "success")
end

-- Counts playtime and tells the player when a gift is ready.
local PLAYTIME_STEP = 5
local function tickPlaytime()
	local today = Progress.day(os.time())
	for player in State.all() do
		local data = DataService.get(player)
		if not data then
			continue
		end
		local state = data.playtime
		Progress.refreshPlaytime(state, today)
		local before = Progress.giftSecondsLeft(state)
		state.seconds += PLAYTIME_STEP
		if before and before > 0 and Progress.giftSecondsLeft(state) == 0 then
			GameService.notify(player, "🎁 A playtime gift is ready!", "success")
			GameService.markDirty(player)
		end
	end
end

local function claimPass(player: Player, level: any, premium: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(level) ~= "number" or type(premium) ~= "boolean" then
		return
	end
	if not State.throttle(runtime, "ClaimPass", 0.2) then
		return
	end
	refresh(player)
	local reward, err = Progress.claimPass(data.pass, level, premium)
	if not reward then
		GameService.notify(player, err or "Can't claim", "error")
		return
	end
	GameService.notify(player, ("Level %d: %s"):format(level, grant(player, data, reward)), "success")
end

local function equipCosmetic(player: Player, kind: any, id: any)
	local data = DataService.get(player)
	if not data or type(kind) ~= "string" or type(id) ~= "string" then
		return
	end
	if kind == "title" then
		if id ~= "" and not data.titles[id] then
			return
		end
		data.equippedTitle = if id == "" then nil else id
	elseif kind == "trail" then
		if id ~= "" and not data.trails[id] then
			return
		end
		data.equippedTrail = if id == "" then nil else id
	elseif kind == "ride" then
		if id ~= "" and not data.rides[id] then
			return
		end
		data.equippedRide = if id == "" then nil else id
		GameService.refresh(player)
	elseif kind == "aura" then
		if id ~= "" and not data.auras[id] then
			return
		end
		data.equippedAura = if id == "" then nil else id
	elseif kind == "hatchFx" then
		if id ~= "" and not data.hatchFx[id] then
			return
		end
		data.equippedHatchFx = if id == "" then nil else id
		GameService.refresh(player)
		GameService.markDirty(player)
		return
	else
		return
	end
	GameService.refreshTitles(player)
	GameService.markDirty(player)
end

-- Gives a reward (daily, quests, pass, gifts, Lucky Spin) and returns a short summary.
function ProgressionService.grant(player: Player, reward: Progression.Reward): string
	local data = DataService.get(player)
	if not data then
		return ""
	end
	return grant(player, data, reward)
end

-- Codes from Config/Codes: once per player, until they end.
local function redeemCode(player: Player, text: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(text) ~= "string" or #text > Codes.MAX_LENGTH * 2 then
		return
	end
	if not State.throttle(runtime, "RedeemCode", 2) then
		GameService.notify(player, "Wait a moment before trying another code", "error")
		return
	end
	local key = Codes.normalize(text)
	local entry = Codes.byCode[key]
	if not entry or (entry.ends and os.time() >= entry.ends) then
		GameService.notify(player, if entry then "That code has ended" else "That code doesn't exist", "error")
		return
	end
	if data.codes[key] then
		GameService.notify(player, "You already used that code", "error")
		return
	end
	data.codes[key] = true
	GameService.notify(player, ("Code %s: %s"):format(key, grant(player, data, entry.reward)), "success")
	GameService.markDirty(player)
end

function ProgressionService.init()
	Net.event("RedeemCode").OnServerEvent:Connect(redeemCode)
	GameService.Progress:Connect(onProgress)
	DataService.Loaded:Connect(function(player)
		refresh(player)
	end)
	Net.event("ClaimDaily").OnServerEvent:Connect(claimDaily)
	Net.event("ClaimQuest").OnServerEvent:Connect(claimQuest)
	Net.event("ClaimPass").OnServerEvent:Connect(claimPass)
	Net.event("EquipCosmetic").OnServerEvent:Connect(equipCosmetic)
	Net.event("ClaimGift").OnServerEvent:Connect(claimGift)

	-- Ad or Robux: keep the daily streak after missing a few days
	RewardService.register("StreakSave", {
		canUse = function(player)
			local data = DataService.get(player)
			if not data or not Progress.streakSavable(data.daily, Progress.day(os.time())) then
				return false, "Your streak doesn't need saving"
			end
			return true, nil
		end,
		grant = function(player)
			local data = DataService.get(player)
			if not data or not Progress.saveStreak(data.daily, Progress.day(os.time())) then
				return false
			end
			GameService.notify(player, ("Streak saved! Day %d is waiting for you."):format(data.daily.streak + 1), "success")
			GameService.markDirty(player)
			return true
		end,
	})

	-- Ad or Robux: swap an unfinished daily quest for another one
	local function rerollable(player: Player, index: any): boolean
		local data = DataService.get(player)
		local quest = data and type(index) == "number" and data.quests.daily[index]
		return quest ~= nil and quest ~= false and not quest.claimed and quest.progress < quest.goal
	end
	RewardService.register("QuestSwap", {
		canUse = function(player, index)
			if not rerollable(player, index) then
				return false, "Pick an unfinished daily quest"
			end
			return true, nil
		end,
		grant = function(player, index)
			local data = DataService.get(player)
			if not data or not rerollable(player, index) then
				return false
			end
			refresh(player)
			local seed = os.time() + player.UserId + math.floor(os.clock() * 1000)
			if not Progress.rerollQuest(data.quests, index, seed, bestEgg(data), questFilter(data)) then
				return false
			end
			GameService.notify(player, "New quest: " .. questText(data.quests.daily[index]), "success")
			GameService.markDirty(player)
			return true
		end,
	})

	updateRift()
	task.spawn(function()
		while true do
			task.wait(PLAYTIME_STEP)
			local ok, err = pcall(tickPlaytime)
			if not ok then
				warn("[Progression] playtime error", err)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(30)
			updateRift()
			for player in State.all() do
				refresh(player)
			end
		end
	end)
end

return ProgressionService
