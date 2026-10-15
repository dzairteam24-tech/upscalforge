--!strict
-- Chat commands for trying the game quickly in Roblox Studio (they do nothing in the published game):
--   /coins N   /speed N   /stage N   /rebirths N   /daily   /guide   /help

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Logic.Economy)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local StudioTools = {}

local HELP = "/coins N  /speed N  /stage 1-11  /rebirths N  /daily  /guide"

-- Runs one command; true if it was one. `teleport(player, stage)` moves them (CourseService)
function StudioTools.command(player: Player, text: string, teleport: (Player, number?) -> ()): boolean
	local data = DataService.get(player)
	local word, argument = string.match(text, "^/(%a+)%s*(.*)$")
	if not data or not word then
		return false
	end
	local number = tonumber(argument)
	local function say(message: string)
		Net.event("Notify"):FireClient(player, message, "info")
		DataService.push(player)
	end
	if word == "coins" and number then
		data.coins = math.max(0, math.floor(number))
		say("coins: " .. data.coins)
	elseif word == "speed" and number then
		data.speed = math.max(0, math.floor(number))
		say("speed collected: " .. data.speed)
	elseif word == "stage" and number then
		data.stage = math.clamp(math.floor(number), 1, Economy.STAGES + 1)
		say("furthest stage: " .. data.stage)
		teleport(player, nil)
	elseif word == "rebirths" and number then
		data.rebirths = math.max(0, math.floor(number))
		say("rebirths: " .. data.rebirths)
	elseif word == "daily" then
		data.daily.last = 0
		say("today's reward is waiting again")
	elseif word == "guide" then
		data.guide = 0
		say("the guide starts again when you rejoin")
	elseif word == "help" then
		say(HELP)
	else
		return false
	end
	return true
end

function StudioTools.init(teleport: (Player, number?) -> ())
	if not RunService:IsStudio() then
		return
	end
	local function watch(player: Player)
		player.Chatted:Connect(function(message)
			StudioTools.command(player, message, teleport)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return StudioTools
