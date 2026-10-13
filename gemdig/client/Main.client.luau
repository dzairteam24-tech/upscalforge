--!strict
-- Starts the client: the data, the screen, digging.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Effects = require(script.Parent.Effects)
local Store = require(script.Parent.Store)
local BagWindow = require(script.Parent.UI.BagWindow)
local DigController = require(script.Parent.Controllers.DigController)
local Hud = require(script.Parent.UI.Hud)
local ShopWindow = require(script.Parent.UI.ShopWindow)

local screen = Instance.new("ScreenGui")
screen.Name = "GemDig"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

Store.init()
local bag = BagWindow.new(screen)
local shop = ShopWindow.new(screen)
Hud.init(screen, function()
	shop.close()
	bag.toggle()
end, function()
	bag.close()
	shop.toggle()
end)
Net.event("OpenShop").OnClientEvent:Connect(function()
	bag.close()
	shop.open()
end)
Effects.init()
DigController.init()
