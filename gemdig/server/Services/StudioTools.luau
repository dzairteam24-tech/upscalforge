--!strict
-- Chat commands for trying the game quickly in Roblox Studio (they do nothing in the published game):
--   /coins N   /deep N   /shovel N   /pack N   /rebirths N   /daily   /gem Ruby   /help

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Backpack = require(Shared.Logic.Backpack)
local Depth = require(Shared.Logic.Depth)
local Gear = require(Shared.Config.Gear)
local Gems = require(Shared.Config.Gems)
local MineConfig = require(Shared.Config.Mine)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local StudioTools = {}

local HELP = "/coins N  /deep N  /shovel 1-5  /pack 1-5  /rebirths N  /daily  /gem Ruby"

-- Runs one command; true if it was one
function StudioTools.command(player: Player, text: string): boolean
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
	elseif word == "deep" and number then
		data.deepest = math.clamp(math.floor(number), 0, MineConfig.MAX_LAYER)
		data.checkpoint = Depth.checkpoint(data.deepest)
		say("deepest layer: " .. data.deepest .. " (the elevator applies on the next New Mine)")
	elseif word == "shovel" and number then
		data.shovel = math.clamp(math.floor(number), 1, #Gear.SHOVELS)
		say("shovel: " .. Gear.SHOVELS[data.shovel].name)
	elseif word == "pack" and number then
		data.pack = math.clamp(math.floor(number), 1, #Gear.PACKS)
		say("pack: " .. Gear.PACKS[data.pack].name)
	elseif word == "rebirths" and number then
		data.rebirths = math.max(0, math.floor(number))
		say("rebirths: " .. data.rebirths)
	elseif word == "daily" then
		data.daily.last = 0
		say("today's reward is waiting again")
	elseif word == "gem" and Gems.byId[argument] then
		local added = Backpack.add(data, { g = argument, s = "Huge", m = "Golden" })
		say(if added then "added a Golden Huge " .. argument else "backpack full")
	elseif word == "help" then
		say(HELP)
	else
		return false
	end
	return true
end

function StudioTools.init()
	if not RunService:IsStudio() then
		return
	end
	local function watch(player: Player)
		player.Chatted:Connect(function(message)
			StudioTools.command(player, message)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return StudioTools
