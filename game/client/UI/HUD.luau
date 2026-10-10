--!strict
-- The always-on screen: coins and what the island earns a second, the weather, and the bag and daily buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mutations = require(Shared.Config.Mutations)
local Format = require(Shared.Logic.Format)
local Daily = require(Shared.Logic.Daily)
local Weather = require(Shared.Logic.Weather)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local DailyWindow = require(script.Parent.DailyWindow)

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

	-- Home: back to the garden from anywhere
	local home = Theme.button(gui, "🏠 Home", Theme.green, function()
		Net.event("Travel"):FireServer("home")
	end)
	home.Size = UDim2.fromOffset(110, 48)
	home.Position = UDim2.new(0, 132, 0, 86)

	-- To the Wild's gate, and the player's speed (trained on the treadmill)
	local wild = Theme.button(gui, "🌿 Wild", Theme.gold, function()
		Net.event("Travel"):FireServer("wild")
	end)
	wild.Size = UDim2.fromOffset(110, 48)
	wild.Position = UDim2.new(0, 12, 0, 142)
	-- Today's tasks: gold when the egg is ready to claim
	local daily = Theme.button(gui, "📋 Daily", Theme.blue, function()
		Windows.toggle("Daily")
	end)
	daily.Size = UDim2.fromOffset(110, 48)
	daily.Position = UDim2.new(0, 12, 0, 198)
	-- On or off the floating seat (MoveService)
	local seat = Theme.button(gui, "", Theme.blue, function()
		local data = Store.data
		local riding = Players.LocalPlayer:GetAttribute("RideSeat")
		local on = type(riding) == "string" and riding ~= ""
		local owned = if data then data.seats else {}
		local first = if owned.Cloud then "Cloud" else next(owned)
		Net.event("Seat"):FireServer(if on then "" else (if data and data.seat ~= "" then data.seat else first) or "")
	end)
	seat.Size = UDim2.fromOffset(110, 48)
	seat.Position = UDim2.new(0, 132, 0, 198)
	local speed = Theme.text(gui, { Size = UDim2.fromOffset(110, 48), Position = UDim2.new(0, 132, 0, 142), TextColor3 = Color3.new(1, 1, 1) })
	speed.TextStrokeTransparency = 0.3

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

	-- A Peaceful private server says so (no bats or traps there: GearService)
	local peaceful = Instance.new("Frame")
	peaceful.Name = "Peaceful"
	peaceful.AnchorPoint = Vector2.new(0.5, 0)
	peaceful.Position = UDim2.new(0.5, 0, 0, 42)
	peaceful.Size = UDim2.fromOffset(280, 28)
	peaceful.BackgroundColor3 = Color3.fromRGB(40, 36, 54)
	peaceful.BackgroundTransparency = 0.2
	peaceful.Visible = false
	Theme.round(peaceful, 10)
	Theme.text(peaceful, { Text = "🕊️ Peaceful server: no bats or traps", Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), TextColor3 = Color3.new(1, 1, 1) })
	peaceful.Parent = gui

	task.spawn(function()
		while true do
			peaceful.Visible = workspace:GetAttribute("Peaceful") == true
			coins.Text = "🪙 " .. Format.abbrev(Store.coins())
			local today = DailyWindow.state()
			local ready = Daily.done(today) and not today.claimed
			daily.Text = if ready then "🎁 Daily!" else "📋 Daily"
			daily.BackgroundColor3 = if ready then Theme.gold else Theme.blue
			local riding = Players.LocalPlayer:GetAttribute("RideSeat")
			seat.Text = if type(riding) == "string" and riding ~= "" then "🚶 Walk" else "☁️ Seat"
			local playerSpeed = Players.LocalPlayer:GetAttribute("Speed")
			speed.Text = "⚡ " .. Format.abbrev(if type(playerSpeed) == "number" then math.floor(playerSpeed) else 0)
			local fedUntil = Players.LocalPlayer:GetAttribute("FedUntil")
			local fed = type(fedUntil) == "number" and fedUntil > workspace:GetServerTimeNow()
			rate.Text = ("+%s / second%s"):format(Format.abbrev(Store.rate()), if fed then " · 😋 fed" else "")
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
