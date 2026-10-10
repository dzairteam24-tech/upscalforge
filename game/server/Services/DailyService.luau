--!strict
-- Daily tasks (Config/Daily, Logic/Daily): the other services tell it what a player did, it counts toward the
-- day's tasks, and tells the player as they get done. The claim itself (an egg) is IslandService's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DailyConfig = require(Shared.Config.Daily)
local Daily = require(Shared.Logic.Daily)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local DailyService = {}

-- Counts `amount` of task `id` for a player, if it's one of today's
function DailyService.add(player: Player, id: string, amount: number?)
	local data = DataService.get(player)
	local task = DailyConfig.byId[id]
	if not data or not task then
		return
	end
	Daily.today(data.daily, Daily.day(os.time()))
	if data.daily.claimed or not table.find(Daily.tasks(data.daily.day), id) then
		return
	end
	local before = data.daily.progress[id] or 0
	if before >= task.goal then
		return
	end
	data.daily.progress[id] = math.min(task.goal, before + (amount or 1))
	if data.daily.progress[id] >= task.goal then
		local notify = Net.event("Notify")
		if Daily.done(data.daily) then
			notify:FireClient(player, "🎁 All daily tasks done! Claim your free egg in 📋 Daily", "rare")
		else
			notify:FireClient(player, ("✅ Daily task done: %s"):format(task.text:format(task.goal)), "success")
		end
	end
end

-- Marks today's reward claimed; false when it isn't ready (or already taken)
function DailyService.claim(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	Daily.today(data.daily, Daily.day(os.time()))
	if data.daily.claimed or not Daily.done(data.daily) then
		return false
	end
	data.daily.claimed = true
	return true
end

return DailyService
