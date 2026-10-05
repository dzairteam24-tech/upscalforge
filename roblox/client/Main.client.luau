-- Client entry point: builds the UI and starts the world and pet controllers.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Store = require(script.Parent:WaitForChild("Store"))
local Unlocks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("Unlocks"))
local UI = script.Parent:WaitForChild("UI")
local Controllers = script.Parent:WaitForChild("Controllers")

local Notify = require(UI.Notify)
local Windows = require(UI.Windows)
local HUD = require(UI.HUD)
local PetsPanel = require(UI.PetsPanel)
local ShopPanel = require(UI.ShopPanel)
local TradePanel = require(UI.TradePanel)
local EggPanel = require(UI.EggPanel)
local HatchPopup = require(UI.HatchPopup)
local BagPanel = require(UI.BagPanel)
local DailyPanel = require(UI.DailyPanel)
local QuestsPanel = require(UI.QuestsPanel)
local TripsPanel = require(UI.TripsPanel)
local ReloadPanel = require(UI.ReloadPanel)
local SettingsPanel = require(UI.SettingsPanel)
local SpinPanel = require(UI.SpinPanel)
local TeleportPanel = require(UI.TeleportPanel)
local BoothPanel = require(UI.BoothPanel)
local ClanPanel = require(UI.ClanPanel)
local EventPanel = require(UI.EventPanel)
local WorldClient = require(Controllers.WorldClient)
local PetFollow = require(Controllers.PetFollow)
local TutorialClient = require(Controllers.TutorialClient)
local SoundClient = require(Controllers.SoundClient)

Store.init()

-- Windows of systems that aren't open yet explain when they open instead
local WINDOW_FEATURES = { Trips = "Trips", Spin = "Spin", Clan = "Clans" }
Windows.setGate(function(name: string): boolean
	local feature = WINDOW_FEATURES[name]
	local data = Store.data
	if feature and data and not Unlocks.has(data :: any, feature) then
		Notify.show(Unlocks.lockedText(feature), "error", 3)
		return false
	end
	return true
end)

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
TripsPanel.mount(gui)
ReloadPanel.mount(gui)
SettingsPanel.mount(gui)
SpinPanel.mount(gui)
TeleportPanel.mount(gui)
BoothPanel.mount(gui)
ClanPanel.mount(gui)
EventPanel.mount(gui)
Notify.mount(gui)

WorldClient.init()
PetFollow.init()
TutorialClient.init(gui)
SoundClient.init()
