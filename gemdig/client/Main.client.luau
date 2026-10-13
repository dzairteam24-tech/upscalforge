--!strict
-- Starts the client: the data, the screen, the windows, digging, the first-minutes guide.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local BagWindow = require(script.Parent.UI.BagWindow)
local DailyWindow = require(script.Parent.UI.DailyWindow)
local DigController = require(script.Parent.Controllers.DigController)
local Effects = require(script.Parent.Effects)
local Guide = require(script.Parent.Controllers.Guide)
local Hud = require(script.Parent.UI.Hud)
local OfflineWindow = require(script.Parent.UI.OfflineWindow)
local RebirthWindow = require(script.Parent.UI.RebirthWindow)
local ShopWindow = require(script.Parent.UI.ShopWindow)
local Store = require(script.Parent.Store)
local StoreWindow = require(script.Parent.UI.StoreWindow)

local screen = Instance.new("ScreenGui")
screen.Name = "GemDig"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

Store.init()
local bag = BagWindow.new(screen)
local shop = ShopWindow.new(screen)
local store = StoreWindow.new(screen)
local rebirth = RebirthWindow.new(screen)
local daily = DailyWindow.new(screen)
local offline = OfflineWindow.new(screen)

-- (one window open at a time)
local all = { bag, shop, store, rebirth, daily, offline }
local function open(window: any)
	for _, w in all do
		if w ~= window then
			w.close()
		end
	end
	window.toggle()
end

Hud.init(screen, {
	bag = function()
		open(bag)
	end,
	shop = function()
		open(shop)
	end,
	store = function()
		open(store)
	end,
	rebirth = function()
		open(rebirth)
	end,
	daily = function()
		open(daily)
	end,
})
Net.event("OpenShop").OnClientEvent:Connect(function()
	for _, w in all do
		w.close()
	end
	shop.open()
end)
Effects.init()
DigController.init(screen, function()
	for _, w in all do
		w.close()
	end
	store.open()
end)
Guide.init(screen)
