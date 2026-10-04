-- First-time guide: moves through the steps on progress events and gives a reward at the end.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Tutorial = require(Shared.Config.Tutorial)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)

type PlayerData = Types.PlayerData

local TutorialService = {}

local function finish(player: Player, data: PlayerData)
	data.tutorial = 0
	data.gems += Tutorial.REWARD_GEMS
	GameService.giveItem(player, Tutorial.REWARD_ITEM, 1, false)
	GameService.notify(
		player,
		("Guide complete! 💎 %d and a %s. Have fun!"):format(Tutorial.REWARD_GEMS, Items.byId[Tutorial.REWARD_ITEM].name),
		"success"
	)
end

local function onProgress(player: Player, event: string, _amount: number)
	local data = DataService.get(player)
	if not data or data.tutorial <= 0 then
		return
	end
	local step = Tutorial.steps[data.tutorial]
	if not step then
		data.tutorial = 0
		return
	end
	if step.event ~= event then
		return
	end
	if data.tutorial >= #Tutorial.steps then
		finish(player, data)
	else
		data.tutorial += 1
	end
	GameService.markDirty(player)
end

function TutorialService.init()
	GameService.Progress:Connect(onProgress)
	DataService.Loaded:Connect(function(_player: Player, data: PlayerData)
		-- Players from before the guide existed skip it
		if data.tutorial > 0 and (data.stats.hatches or 0) > 0 then
			data.tutorial = 0
		end
	end)
	Net.event("SkipTutorial").OnServerEvent:Connect(function(player)
		local data = DataService.get(player)
		if data and data.tutorial > 0 then
			data.tutorial = 0
			GameService.markDirty(player)
		end
	end)
end

return TutorialService
