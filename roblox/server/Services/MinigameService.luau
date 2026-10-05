-- Cube Stack (Config/Minigame): the server counts plays per day, times each game and pays out the score
-- only if it's possible for a person to reach it in that time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MinigameConfig = require(Shared.Config.Minigame)
local Minigame = require(Shared.Logic.Minigame)
local Progress = require(Shared.Logic.Progress)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

local MinigameService = {}

local started: { [Player]: number } = {}

local function today(data): number
	local day = Progress.day(os.time())
	if data.arcade.day ~= day then
		data.arcade.day = day
		data.arcade.plays = 0
	end
	return day
end

local function start(player: Player)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or not State.throttle(runtime, "StackStart", 1) then
		return
	end
	today(data)
	if data.arcade.plays >= MinigameConfig.PLAYS_PER_DAY then
		GameService.notify(player, "No plays left today. Come back tomorrow!", "error")
		return
	end
	data.arcade.plays += 1
	started[player] = os.clock()
	Net.event("StackGo"):FireClient(player)
	GameService.refresh(player)
end

local function finish(player: Player, score: any)
	local data = DataService.get(player)
	local began = started[player]
	started[player] = nil
	if not data or not began or type(score) ~= "number" then
		return
	end
	local seconds = os.clock() - began
	if not Minigame.plausible(score, seconds) then
		GameService.notify(player, "That score didn't count.", "error")
		return
	end
	local reward = Minigame.reward(score)
	data.gems += reward.gems
	data.tickets += reward.tickets
	local best = data.arcade.best or 0
	data.arcade.best = math.max(best, score)
	local parts = { ("%d cubes"):format(score) }
	if reward.gems > 0 then
		table.insert(parts, "💎 " .. reward.gems)
	end
	if reward.tickets > 0 then
		table.insert(parts, "🎟️ " .. reward.tickets)
	end
	if score > best and best > 0 then
		table.insert(parts, "new best!")
	end
	GameService.notify(player, "🧊 Cube Stack: " .. table.concat(parts, " · "), "success")
	GameService.refresh(player)
end

function MinigameService.init()
	Net.event("StackStart").OnServerEvent:Connect(start)
	Net.event("StackEnd").OnServerEvent:Connect(finish)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		started[player] = nil
	end)
end

return MinigameService
