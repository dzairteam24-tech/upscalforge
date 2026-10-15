--!strict
-- Starts the client: the data, the screen, the windows, the farms and how they feel, the first-minutes guide.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local BarnWindow = require(script.Parent.UI.BarnWindow)
local Effects = require(script.Parent.Controllers.Effects)
local FarmController = require(script.Parent.Controllers.FarmController)
local Guide = require(script.Parent.Controllers.Guide)
local Hud = require(script.Parent.UI.Hud)
local SeedShop = require(script.Parent.UI.SeedShop)
local Store = require(script.Parent.Store)

local screen = Instance.new("ScreenGui")
screen.Name = "BrickFarm"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

Store.init()
local seeds = SeedShop.new(screen)
local barn = BarnWindow.new(screen)

-- (one window open at a time)
local all = { seeds, barn }
local function open(window: any)
	for _, w in all do
		if w ~= window then
			w.close()
		end
	end
	window.toggle()
end

local hud = Hud.new(screen, {
	seeds = function()
		open(seeds)
	end,
	barn = function()
		open(barn)
	end,
	land = function()
		Net.event("Expand"):FireServer()
	end,
	select = function(key)
		FarmController.select(key)
	end,
})
Net.event("OpenBarn").OnClientEvent:Connect(function()
	if not barn.isOpen() then
		open(barn)
	end
end)
FarmController.onSelected = hud.selected
FarmController.onTileInfo = function(text)
	hud.info(text)
end
Effects.onBanner = hud.banner
Effects.init(screen)
FarmController.init()
hud.selected(FarmController.selected)
Guide.init(screen)
