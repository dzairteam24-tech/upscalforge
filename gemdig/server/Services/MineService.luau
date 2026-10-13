--!strict
-- Players' mines: one is built when a player's data loads, the shovel swings and teleports are handled here, and
-- every character gets a headlamp (it's dark down there) and starts on their plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gems = require(Shared.Config.Gems)
local Gem = require(Shared.Logic.Gem)
local Layout = require(Shared.Logic.Layout)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local Mine = require(script.Parent.Parent.Mine)
local PlotService = require(script.Parent.PlotService)

local MineService = {}

local mines: { [Player]: Mine.Mine } = {}
local random = Random.new()

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
	local outcome = mine:swing(data, x, layer, z, root.Position, os.clock(), random)
	if not outcome.ok then
		if outcome.reason == "full" then
			Net.event("Notify"):FireClient(player, MESSAGES.full, "bad")
		end
		return
	end
	local fx = Net.event("Fx")
	if outcome.broke then
		fx:FireClient(player, "Break", outcome.position, outcome.color)
		local item = outcome.item
		if item then
			fx:FireClient(player, "Gem", outcome.position, Gems.byId[item.g].color)
			local rarity = Gems.byId[item.g].rarity
			Net.event("Notify"):FireClient(player, "+ " .. Gem.name(item) .. " (" .. Gem.value(item) .. " coins)", if rarity == "Common" then "info" else rarity)
		end
		DataService.push(player)
	else
		fx:FireClient(player, "Hit", outcome.position, outcome.color)
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
	Net.event("Dig").OnServerEvent:Connect(onDig)
	Net.event("Teleport").OnServerEvent:Connect(onTeleport)
	DataService.onLoaded(function(player, data)
		local index = PlotService.assign(player)
		if not index then
			Net.event("Notify"):FireClient(player, "The server is full", "bad")
			return
		end
		local mine = Mine.new(index, data.seed, player.UserId, workspace)
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
