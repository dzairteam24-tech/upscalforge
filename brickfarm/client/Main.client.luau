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
local OrdersWindow = require(script.Parent.UI.OrdersWindow)
local StandWindow = require(script.Parent.UI.StandWindow)
local TractorController = require(script.Parent.Controllers.TractorController)
local TradeWindow = require(script.Parent.UI.TradeWindow)
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
local orders = OrdersWindow.new(screen)
local stand = StandWindow.new(screen)
local trade = TradeWindow.new(screen)

-- (one window open at a time)
local all = { seeds, barn, orders, stand, trade }
local function open(window: any)
	for _, w in all do
		if w ~= window then
			w.close()
		end
	end
	window.toggle()
end

local hud
hud = Hud.new(screen, {
	seeds = function()
		open(seeds)
	end,
	barn = function()
		open(barn)
	end,
	land = function()
		FarmController.setLandMode(not FarmController.landMode)
		hud.landMode(FarmController.landMode)
	end,
	tractor = function()
		Net.event("CallTractor"):FireServer()
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
Net.event("OpenOrders").OnClientEvent:Connect(function()
	if not orders.isOpen() then
		open(orders)
	end
end)
Net.event("OpenStand").OnClientEvent:Connect(function(index: number, name: string, stock: any, own: boolean)
	stand.show(index, name, stock, own)
	if not stand.isOpen() then
		open(stand)
	end
end)
FarmController.onSelected = hud.selected
FarmController.onTileInfo = function(text)
	hud.info(text)
end
Effects.onBanner = hud.banner
Effects.init(screen)
FarmController.init()
TractorController.init()
hud.selected(FarmController.selected)
Guide.init(screen)
