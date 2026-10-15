--!strict
-- Starts the client: the data, the screen, the windows, the course and how it feels, the first-minutes guide.

local Players = game:GetService("Players")

local CourseController = require(script.Parent.Controllers.CourseController)
local DailyWindow = require(script.Parent.UI.DailyWindow)
local Effects = require(script.Parent.Controllers.Effects)
local Guide = require(script.Parent.Controllers.Guide)
local Hud = require(script.Parent.UI.Hud)
local RebirthWindow = require(script.Parent.UI.RebirthWindow)
local Store = require(script.Parent.Store)
local StoreWindow = require(script.Parent.UI.StoreWindow)
local UpgradesWindow = require(script.Parent.UI.UpgradesWindow)

local screen = Instance.new("ScreenGui")
screen.Name = "Cubedash"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

Store.init()
local upgrades = UpgradesWindow.new(screen)
local store = StoreWindow.new(screen)
local rebirth = RebirthWindow.new(screen)
local daily = DailyWindow.new(screen)

-- (one window open at a time)
local all = { upgrades, store, rebirth, daily }
local function open(window: any)
	for _, w in all do
		if w ~= window then
			w.close()
		end
	end
	window.toggle()
end

local hud = Hud.new(screen, {
	upgrades = function()
		open(upgrades)
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
	restart = CourseController.restart,
})
CourseController.onBanner = hud.banner
CourseController.onProgress = hud.progress
CourseController.onWallNear = hud.wallNear
Effects.init(screen)
CourseController.init()
Guide.init(screen)
