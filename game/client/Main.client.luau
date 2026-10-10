-- Client entry point: builds the screen and starts the controllers.

local Players = game:GetService("Players")

local Store = require(script.Parent:WaitForChild("Store"))
local UI = script.Parent:WaitForChild("UI")
local Controllers = script.Parent:WaitForChild("Controllers")

local BagWindow = require(UI.BagWindow)
local DailyWindow = require(UI.DailyWindow)
local FoodWindow = require(UI.FoodWindow)
local HUD = require(UI.HUD)
local Notify = require(UI.Notify)
local ShopWindow = require(UI.ShopWindow)
local GardenClient = require(Controllers.GardenClient)
local Guide = require(Controllers.Guide)
local RideClient = require(Controllers.RideClient)
local SprintClient = require(Controllers.SprintClient)

Store.init()

local gui = Instance.new("ScreenGui")
gui.Name = "NestUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

HUD.mount(gui)
ShopWindow.mount(gui)
BagWindow.mount(gui)
DailyWindow.mount(gui)
FoodWindow.mount(gui)
Notify.mount(gui)
GardenClient.init()
Guide.init()
RideClient.init()
SprintClient.init()
