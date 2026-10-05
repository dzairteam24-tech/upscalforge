-- Daily Bounty (Config/Bounty, Logic/Bounty): three creatures to hatch each day. Rewards are given as soon
-- as a bounty is done, plus a bonus for all three.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BountyConfig = require(Shared.Config.Bounty)
local Bounty = require(Shared.Logic.Bounty)
local Progress = require(Shared.Logic.Progress)
local Unlocks = require(Shared.Logic.Unlocks)
local Types = require(Shared.Logic.Types)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local ProgressionService = require(script.Parent.ProgressionService)

local BountyService = {}

-- New targets when a new UTC day starts
local function ensure(player: Player, data: Types.PlayerData): boolean
	local today = Progress.day(os.time())
	if data.bounty.day == today then
		return false
	end
	data.bounty = {
		day = today,
		targets = Bounty.forDay(today, Unlocks.bestZone(data), player.UserId),
		done = { false, false, false },
	}
	return true
end

local function onHatched(player: Player, species: string, variant: string)
	local data = DataService.get(player)
	if not data then
		return
	end
	ensure(player, data)
	for index, target in data.bounty.targets do
		if not data.bounty.done[index] and Bounty.matches(target, species, variant) then
			data.bounty.done[index] = true
			local summary = ProgressionService.grant(player, BountyConfig.REWARDS[target.tier])
			GameService.notify(player, ("🎯 %s Bounty done! %s"):format(BountyConfig.TIER_NAMES[target.tier], summary), "rare")
			local all = true
			for i = 1, #data.bounty.targets do
				all = all and data.bounty.done[i] == true
			end
			if all then
				GameService.notify(player, "🎯 All bounties done! " .. ProgressionService.grant(player, BountyConfig.ALL_DONE), "rare")
			end
			GameService.refresh(player)
		end
	end
end

function BountyService.init()
	GameService.Hatched:Connect(onHatched)
	DataService.Loaded:Connect(function(player, data)
		if ensure(player, data) then
			GameService.refresh(player)
		end
	end)
	-- Roll over at midnight UTC for players who stay online
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data and ensure(player, data) then
					GameService.notify(player, "🎯 New Daily Bounties are out!", "info")
					GameService.refresh(player)
				end
			end
		end
	end)
end

return BountyService
