--!strict
-- Coins: upgrades, rebirth, the daily reward.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Daily = require(Shared.Logic.Daily)
local Economy = require(Shared.Logic.Economy)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)
local Progress = require(Shared.Logic.Progress)

local DataService = require(script.Parent.DataService)

local EconomyService = {}

local function notify(player: Player, text: string, kind: string)
	Net.event("Notify"):FireClient(player, text, kind)
end

function EconomyService.buy(player: Player, key: any): boolean
	local data = DataService.get(player)
	if not data or type(key) ~= "string" then
		return false
	end
	local level, why = Progress.buy(data, key)
	if not level then
		if why == "coins" then
			notify(player, "Not enough coins yet", "bad")
		elseif why == "max" then
			notify(player, "That's maxed out!", "info")
		end
		return false
	end
	local upgrade = Economy.upgrade(key) :: Economy.Upgrade
	notify(player, ("%s level %d!"):format(upgrade.name, level), "good")
	DataService.push(player)
	return true
end

-- `teleport(player, stage)`: back to the start (CourseService)
function EconomyService.rebirth(player: Player, teleport: (Player, number) -> ()): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local ok, why = Progress.canRebirth(data)
	if not ok then
		notify(player, why or "Not yet", "bad")
		return false
	end
	Progress.rebirth(data)
	notify(player, ("Rebirth %d! Every orb and coin is now worth +%d%%."):format(data.rebirths, math.floor(data.rebirths * Economy.REBIRTH_BONUS * 100 + 0.5)), "gold")
	DataService.push(player)
	teleport(player, 1)
	return true
end

function EconomyService.daily(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local now = os.time()
	local coins, boost, index = Daily.claim(data, now, Progress.perMinute(data, now))
	if coins <= 0 then
		notify(player, "Come back tomorrow for the next one", "info")
		return false
	end
	data.coins += coins
	if boost > 0 then
		data.boostUntil = math.max(now, data.boostUntil) + boost * 60
	end
	notify(player, ("Day %d: +%s coins%s"):format(index, Format.short(coins), if boost > 0 then (" and %d min of 2x coins"):format(boost) else ""), "gold")
	DataService.push(player)
	return true
end

function EconomyService.init(teleport: (Player, number) -> ())
	Net.event("Buy").OnServerEvent:Connect(EconomyService.buy)
	Net.event("Rebirth").OnServerEvent:Connect(function(player)
		EconomyService.rebirth(player, teleport)
	end)
	Net.event("Daily").OnServerEvent:Connect(EconomyService.daily)
	Net.event("GuideDone").OnServerEvent:Connect(function(player, step)
		local data = DataService.get(player)
		if data and type(step) == "number" and step == math.floor(step) and step >= 0 and step <= 20 then
			data.guide = math.max(data.guide, step)
		end
	end)
end

return EconomyService
