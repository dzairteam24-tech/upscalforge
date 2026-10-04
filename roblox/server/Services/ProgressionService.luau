-- Daily reward, quests, Battle Pass, cosmetics and the daily Pixel Rift.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Items = require(Shared.Config.Items)
local Progression = require(Shared.Config.Progression)
local World1 = require(Shared.Config.World1)
local Format = require(Shared.Logic.Format)
local Progress = require(Shared.Logic.Progress)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

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
	if reward.xp then
		local cap = Progression.PASS_LEVELS * Progression.PASS_XP_PER_LEVEL
		data.pass.xp = math.min(cap, data.pass.xp + reward.xp)
		table.insert(parts, ("+%d Pass XP"):format(reward.xp))
	end
	GameService.markDirty(player)
	return table.concat(parts, ", ")
end

local function refresh(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local now = os.time()
	local changed = Progress.refreshQuests(data.quests, now, player.UserId, bestEgg(data))
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
	else
		return
	end
	GameService.refreshTitles(player)
	GameService.markDirty(player)
end

function ProgressionService.init()
	GameService.Progress:Connect(onProgress)
	DataService.Loaded:Connect(function(player)
		refresh(player)
	end)
	Net.event("ClaimDaily").OnServerEvent:Connect(claimDaily)
	Net.event("ClaimQuest").OnServerEvent:Connect(claimQuest)
	Net.event("ClaimPass").OnServerEvent:Connect(claimPass)
	Net.event("EquipCosmetic").OnServerEvent:Connect(equipCosmetic)

	updateRift()
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
