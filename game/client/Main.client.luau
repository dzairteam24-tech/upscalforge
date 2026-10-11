-- Client entry point: builds the screen and starts the controllers.

local Players = game:GetService("Players")

local Store = require(script.Parent:WaitForChild("Store"))
local UI = script.Parent:WaitForChild("UI")
local Controllers = script.Parent:WaitForChild("Controllers")

local BagWindow = require(UI.BagWindow)
local DailyWindow = require(UI.DailyWindow)
local FoodWindow = require(UI.FoodWindow)
local GearWindow = require(UI.GearWindow)
local HUD = require(UI.HUD)
local Notify = require(UI.Notify)
local Reveal = require(UI.Reveal)
local ShopWindow = require(UI.ShopWindow)
local Theme = require(UI.Theme)
local GardenClient = require(Controllers.GardenClient)
local Guide = require(Controllers.Guide)
local RideClient = require(Controllers.RideClient)
local SprintClient = require(Controllers.SprintClient)
local TreadmillClient = require(Controllers.TreadmillClient)
local EggHands = require(Controllers.EggHands)

Store.init()

local gui = Instance.new("ScreenGui")
gui.Name = "NestUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = Theme.root(gui) -- (scaled to the screen)

HUD.mount(root)
ShopWindow.mount(root)
BagWindow.mount(root)
DailyWindow.mount(root)
FoodWindow.mount(root)
GearWindow.mount(root)
Notify.mount(root)
Reveal.mount(root)
GardenClient.init()
Guide.init()
RideClient.init()
SprintClient.init()
TreadmillClient.init()
EggHands.init()
