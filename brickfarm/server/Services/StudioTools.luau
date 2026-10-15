--!strict
-- Chat commands for trying the game quickly in Roblox Studio (they do nothing in the published game):
--   /coins N   /level N   /tiles N   /grow (everything planted is ready)   /seeds key N   /guide   /help

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crops = require(Shared.Config.Crops)
local Land = require(Shared.Logic.Land)
local Level = require(Shared.Logic.Level)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local StudioTools = {}

local HELP = "/coins N  /level N  /tiles N  /grow  /seeds carrot 10  /guide"

-- Runs one command; true if it was one. `show(player)` puts their farm back on its tiles (FarmService)
function StudioTools.command(player: Player, text: string, show: (Player) -> ()): boolean
	local data = DataService.get(player)
	local word, argument = string.match(text, "^/(%a+)%s*(.*)$")
	if not data or not word then
		return false
	end
	local number = tonumber(argument)
	local function say(message: string)
		Net.event("Notify"):FireClient(player, message, "info")
		show(player)
		DataService.push(player)
	end
	if word == "coins" and number then
		data.coins = math.max(0, math.floor(number))
		say("coins: " .. data.coins)
	elseif word == "level" and number then
		data.xp = Level.total(math.clamp(math.floor(number), 1, Level.MAX))
		say("level: " .. math.floor(number))
	elseif word == "tiles" and number then
		data.tiles = math.clamp(math.floor(number), Land.START, Land.MAX)
		say("tiles: " .. data.tiles)
	elseif word == "grow" then
		for _, planted in data.plots do
			planted.t = 0
		end
		say("everything planted is ready")
	elseif word == "seeds" then
		local key, count = string.match(argument, "^(%a+)%s*(%d*)$")
		if key and Crops.byKey[key] then
			data.seeds[key] = (data.seeds[key] or 0) + (tonumber(count) or 10)
			say("seeds: " .. key)
		else
			return false
		end
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

function StudioTools.init(show: (Player) -> ())
	if not RunService:IsStudio() then
		return
	end
	local function watch(player: Player)
		player.Chatted:Connect(function(message)
			StudioTools.command(player, message, show)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return StudioTools
