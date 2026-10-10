--!strict
-- The always-on screen: coins and what the island earns a second, the weather, and the bag button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mutations = require(Shared.Config.Mutations)
local Format = require(Shared.Logic.Format)
local Weather = require(Shared.Logic.Weather)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local HUD = {}

function HUD.mount(gui: ScreenGui)
	-- Coins
	local money = Instance.new("Frame")
	money.Name = "Money"
	money.Position = UDim2.fromOffset(12, 12)
	money.Size = UDim2.fromOffset(230, 64)
	money.BackgroundColor3 = Theme.panel
	Theme.round(money, 14)
	Theme.stroke(money, Theme.gold, 3)
	local coins = Theme.text(money, { Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(10, 4), TextXAlignment = Enum.TextXAlignment.Left })
	local rate = Theme.text(money, { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(10, 38), TextColor3 = Theme.soft, TextXAlignment = Enum.TextXAlignment.Left })
	money.Parent = gui

	-- The bag
	local bag = Theme.button(gui, "🎒 Bag", Theme.blue, function()
		Windows.toggle("Bag")
	end)
	bag.Size = UDim2.fromOffset(110, 48)
	bag.Position = UDim2.new(0, 12, 0, 86)

	-- The weather
	local banner = Instance.new("Frame")
	banner.Name = "Weather"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 6)
	banner.Size = UDim2.fromOffset(400, 32)
	banner.BackgroundColor3 = Color3.fromRGB(40, 36, 54)
	banner.BackgroundTransparency = 0.2
	Theme.round(banner, 12)
	Theme.stroke(banner, Theme.gold, 2)
	local weatherText = Theme.text(banner, { Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 3), TextColor3 = Color3.new(1, 1, 1) })
	local stroke = banner:FindFirstChildOfClass("UIStroke") :: UIStroke
	banner.Parent = gui

	task.spawn(function()
		while true do
			coins.Text = "🪙 " .. Format.abbrev(Store.coins())
			rate.Text = ("+%s / second"):format(Format.abbrev(Store.rate()))
			local now = workspace:GetServerTimeNow()
			local weather, ends = Weather.at(math.floor(now))
			local left = Format.time(math.max(0, math.ceil(ends - now)))
			if weather.mutation then
				weatherText.Text = ("%s %s: eggs hatching now are %s+ · %s"):format(weather.icon, weather.name, weather.mutation, left)
				stroke.Color = Mutations.byId[weather.mutation].color
			else
				weatherText.Text = ("%s %s · next weather in %s"):format(weather.icon, weather.name, left)
				stroke.Color = weather.color
			end
			task.wait(0.25)
		end
	end)
end

return HUD
