--!strict
-- Players' mines: one is built when a player's data loads, the shovel swings and teleports are handled here, and
-- every character gets a headlamp (it's dark down there) and starts on their plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Depth = require(Shared.Logic.Depth)
local Gear = require(Shared.Config.Gear)
local Gems = require(Shared.Config.Gems)
local Gem = require(Shared.Logic.Gem)
local Layout = require(Shared.Logic.Layout)
local MineConfig = require(Shared.Config.Mine)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local Mine = require(script.Parent.Parent.Mine)
local PlotService = require(script.Parent.PlotService)

local MineService = {}

local mines: { [Player]: Mine.Mine } = {}
local random = Random.new()
local lastReset: { [Player]: number } = {}
local lastWarning: { [Player]: number } = {} -- (a message about a cube that's too hard isn't repeated every swing)

local MESSAGES = {
	full = "Backpack full! Sell your gems at the town",
}

function MineService.mineOf(player: Player): Mine.Mine?
	return mines[player]
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function teleport(player: Player, spot: Vector3)
	local root = rootOf(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.new(spot)
	end
end

local function onDig(player: Player, x: any, layer: any, z: any)
	local mine, data = mines[player], DataService.get(player)
	local root = rootOf(player)
	if not mine or not data or not root or type(x) ~= "number" or type(layer) ~= "number" or type(z) ~= "number" then
		return
	end
	local now = os.clock()
	local outcome = mine:swing(data, x, layer, z, root.Position, now, random)
	if not outcome.ok then
		local text: string? = nil
		if outcome.reason == "full" then
			text = MESSAGES.full
		elseif outcome.reason == "tooHard" then
			local needed = Gear.SHOVELS[outcome.needs or 1]
			text = "Too hard! You need the " .. (if needed then needed.name else "next shovel")
		end
		if text and now - (lastWarning[player] or -math.huge) > 1.5 then
			lastWarning[player] = now
			Net.event("Notify"):FireClient(player, text, "bad")
		end
		return
	end
	local fx = Net.event("Fx")
	if outcome.broke then
		fx:FireClient(player, if outcome.geode then "Geode" else "Break", outcome.position, outcome.color)
		local items = outcome.items
		if items then
			local rarest = items[1]
			for _, item in items do
				local gem = Gems.byId[item.g]
				fx:FireClient(player, "Gem", outcome.position, gem.color)
				if Gem.value(item) > Gem.value(rarest) then
					rarest = item
				end
				local rarity = gem.rarity
				Net.event("Notify"):FireClient(player, "+ " .. Gem.name(item) .. " (" .. Gem.value(item) .. " coins)", if rarity == "Common" then "info" else rarity)
			end
		end
		data.checkpoint = Depth.checkpoint(data.deepest)
		DataService.push(player)
	else
		fx:FireClient(player, "Hit", outcome.position, outcome.color)
	end
end

-- Starts the player's mine again (a new seed: the gems are somewhere else; the elevator shaft down to their saved
-- depth cleared) and puts them on their plot. `force`: no cooldown (a rebirth)
function MineService.resetMine(player: Player, force: boolean?): boolean
	local mine, data, index = mines[player], DataService.get(player), PlotService.index(player)
	if not mine or not data or not index then
		return false
	end
	local now = os.clock()
	if not force and now - (lastReset[player] or -math.huge) < MineConfig.RESET_COOLDOWN then
		Net.event("Notify"):FireClient(player, "The mine was just reset: a moment", "bad")
		return false
	end
	lastReset[player] = now
	data.seed = random:NextInteger(1, 1000000)
	data.checkpoint = Depth.checkpoint(data.deepest)
	mine:reset(data.seed, data.checkpoint)
	teleport(player, Layout.plotSpawn(index))
	Net.event("Notify"):FireClient(player, "New mine: fresh gems!", "good")
	return true
end

-- Builds the layers round wherever the player is (they may be falling down the elevator shaft)
function MineService.follow(player: Player)
	local mine, index, root = mines[player], PlotService.index(player), rootOf(player)
	if not mine or not index or not root then
		return
	end
	local _, layer = Layout.cellAt(index, root.Position)
	if layer then
		mine:ensure(math.min(layer, MineConfig.MAX_LAYER))
	end
end

local function onTeleport(player: Player, where: any)
	local mine = mines[player]
	local index = PlotService.index(player)
	if not mine or not index then
		return
	end
	if where == "surface" then
		teleport(player, Layout.hubSpawn())
	elseif where == "plot" then
		teleport(player, Layout.plotSpawn(index))
	elseif where == "depth" then
		local spot = mine:depthSpot()
		if spot then
			teleport(player, spot)
		else
			teleport(player, Layout.plotSpawn(index))
		end
	end
end

local function lamp(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Name = "Headlamp"
		light.Brightness = 1.6
		light.Range = 34
		light.Color = Color3.fromRGB(255, 240, 210)
		light.Parent = root
	end
end

function MineService.init()
	task.spawn(function()
		while true do
			task.wait(0.25)
			for player in mines do
				local ok, err = pcall(MineService.follow, player)
				if not ok then
					warn("[Mine] " .. tostring(err))
				end
			end
		end
	end)
	Net.event("Dig").OnServerEvent:Connect(onDig)
	Net.event("Teleport").OnServerEvent:Connect(onTeleport)
	Net.event("ResetMine").OnServerEvent:Connect(function(player)
		MineService.resetMine(player, false)
	end)
	DataService.onLoaded(function(player, data)
		local index = PlotService.assign(player)
		if not index then
			Net.event("Notify"):FireClient(player, "The server is full", "bad")
			return
		end
		data.checkpoint = Depth.checkpoint(data.deepest)
		local mine = Mine.new(index, data.seed, player.UserId, workspace, data.checkpoint)
		mine:ensure(1)
		mines[player] = mine
		-- (a character already here goes to the plot; later ones, on every respawn)
		if player.Character then
			teleport(player, Layout.plotSpawn(index))
		end
	end)
	DataService.onLeaving(function(player)
		local mine = mines[player]
		if mine then
			mine:destroy()
			mines[player] = nil
		end
		lastReset[player] = nil
		lastWarning[player] = nil
		PlotService.release(player)
	end)
	local function track(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(lamp, character)
			-- (wait for the mine, then stand on the plot)
			task.spawn(function()
				for _ = 1, 100 do
					local index = PlotService.index(player)
					if index and mines[player] then
						task.wait(0.1)
						teleport(player, Layout.plotSpawn(index))
						return
					end
					task.wait(0.1)
				end
			end)
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
end

return MineService
