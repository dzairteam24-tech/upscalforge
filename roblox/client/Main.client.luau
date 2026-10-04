-- Client entry point: builds the UI and starts the world and pet controllers.

local Players = game:GetService("Players")

local Store = require(script.Parent:WaitForChild("Store"))
local UI = script.Parent:WaitForChild("UI")
local Controllers = script.Parent:WaitForChild("Controllers")

local Notify = require(UI.Notify)
local HUD = require(UI.HUD)
local PetsPanel = require(UI.PetsPanel)
local ShopPanel = require(UI.ShopPanel)
local TradePanel = require(UI.TradePanel)
local EggPanel = require(UI.EggPanel)
local HatchPopup = require(UI.HatchPopup)
local BagPanel = require(UI.BagPanel)
local DailyPanel = require(UI.DailyPanel)
local QuestsPanel = require(UI.QuestsPanel)
local WorldClient = require(Controllers.WorldClient)
local PetFollow = require(Controllers.PetFollow)

Store.init()

local gui = Instance.new("ScreenGui")
gui.Name = "CubelingsUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

HUD.mount(gui)
EggPanel.mount(gui)
HatchPopup.mount(gui)
PetsPanel.mount(gui)
ShopPanel.mount(gui)
TradePanel.mount(gui)
BagPanel.mount(gui)
DailyPanel.mount(gui)
QuestsPanel.mount(gui)
Notify.mount(gui)

WorldClient.init()
PetFollow.init()
