--!strict
-- The always-on screen: coins and what the island earns a second, the weather, and the bag and daily buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mutations = require(Shared.Config.Mutations)
local Format = require(Shared.Logic.Format)
local Daily = require(Shared.Logic.Daily)
local Night = require(Shared.Logic.Night)
local NightConfig = require(Shared.Config.Night)
local Weather = require(Shared.Logic.Weather)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local DailyWindow = require(script.Parent.DailyWindow)

local HUD = {}

function HUD.mount(gui: Instance)
	-- Coins: a gold bar with the coin, and what the garden earns a second under it
	local money = Instance.new("Frame")
	money.Name = "Money"
	money.Position = UDim2.fromOffset(46, 14)
	money.Size = UDim2.fromOffset(230, 52)
	Theme.gradient(money, Theme.gold, 0.3, 0.15)
	Theme.round(money, 26)
	Theme.stroke(money, Theme.outline, 3)
	local coinIcon = Theme.text(money, { Text = "🪙", Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(-36, -5) })
	coinIcon.ZIndex = 2
	local coins = Theme.bold(money, { Size = UDim2.new(1, -40, 1, -10), Position = UDim2.fromOffset(32, 5), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 34 })
	money.Parent = gui
	local rate = Theme.bold(gui, { Size = UDim2.fromOffset(230, 24), Position = UDim2.fromOffset(60, 68), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 240, 160), MaxText = 22 })

	-- Speed (trained on the treadmill)
	local speedBar = Instance.new("Frame")
	speedBar.Name = "Speed"
	speedBar.Position = UDim2.fromOffset(46, 98)
	speedBar.Size = UDim2.fromOffset(170, 40)
	Theme.gradient(speedBar, Theme.blue, 0.3, 0.15)
	Theme.round(speedBar, 20)
	Theme.stroke(speedBar, Theme.outline, 3)
	local speedIcon = Theme.text(speedBar, { Text = "⚡", Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(-30, -4) })
	speedIcon.ZIndex = 2
	local speed = Theme.bold(speedBar, { Size = UDim2.new(1, -36, 1, -8), Position = UDim2.fromOffset(26, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 28 })
	speedBar.Parent = gui

	-- The big buttons down the left side
	local column = Instance.new("Frame")
	column.Name = "Buttons"
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(0, 0.5)
	column.Position = UDim2.new(0, 14, 0.56, 0)
	column.Size = UDim2.fromOffset(160, 420)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(74, 74)
	grid.CellPadding = UDim2.fromOffset(10, 12)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = column
	column.Parent = gui
	local bag = Theme.iconButton(column, "🎒", "Bag", Theme.blue, function()
		Windows.toggle("Bag")
	end)
	bag.LayoutOrder = 1
	local daily, dailyName = Theme.iconButton(column, "📋", "Daily", Theme.purple, function()
		Windows.toggle("Daily")
	end)
	daily.LayoutOrder = 2
	local badge = Theme.bold(daily, { Text = "!", Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -16, 0, -10), BackgroundTransparency = 0, BackgroundColor3 = Theme.red, Font = Theme.title, MaxText = 22 })
	Theme.round(badge, 13)
	badge.ZIndex = 3
	-- Home: back to the garden from anywhere
	local home = Theme.iconButton(column, "🏠", "Home", Theme.green, function()
		Net.event("Travel"):FireServer("home")
	end)
	home.LayoutOrder = 3
	-- To the Wild's gate
	local wild = Theme.iconButton(column, "🌿", "Wild", Color3.fromRGB(240, 150, 50), function()
		Net.event("Travel"):FireServer("wild")
	end)
	wild.LayoutOrder = 4
	-- On or off the floating seat (MoveService)
	local seat, seatName = Theme.iconButton(column, "☁️", "Seat", Theme.pink, function()
		local data = Store.data
		local riding = Players.LocalPlayer:GetAttribute("RideSeat")
		local on = type(riding) == "string" and riding ~= ""
		local owned = if data then data.seats else {}
		local first = if owned.Cloud then "Cloud" else next(owned)
		Net.event("Seat"):FireServer(if on then "" else (if data and data.seat ~= "" then data.seat else first) or "")
	end)
	seat.LayoutOrder = 5

	-- The weather
	local banner = Instance.new("Frame")
	banner.Name = "Weather"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 8)
	banner.Size = UDim2.fromOffset(460, 38)
	banner.BackgroundColor3 = Color3.fromRGB(40, 36, 54)
	banner.BackgroundTransparency = 0.15
	Theme.round(banner, 19)
	local stroke = Theme.stroke(banner, Theme.gold, 3)
	local weatherText = Theme.bold(banner, { Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), Font = Theme.font, MaxText = 22 })
	banner.Parent = gui

	-- The night: coming soon, or on (eggs grow faster)
	local nightBar = Instance.new("Frame")
	nightBar.Name = "Night"
	nightBar.AnchorPoint = Vector2.new(0.5, 0)
	nightBar.Position = UDim2.new(0.5, 0, 0, 52)
	nightBar.Size = UDim2.fromOffset(340, 32)
	nightBar.BackgroundColor3 = Color3.fromRGB(40, 46, 110)
	nightBar.Visible = false
	Theme.round(nightBar, 16)
	Theme.stroke(nightBar, Color3.fromRGB(170, 180, 255), 2)
	local nightText = Theme.bold(nightBar, { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), Font = Theme.font, MaxText = 20 })
	nightBar.Parent = gui

	-- A Peaceful private server says so (no bats or traps there: GearService)
	local peaceful = Instance.new("Frame")
	peaceful.Name = "Peaceful"
	peaceful.AnchorPoint = Vector2.new(0.5, 0)
	peaceful.Position = UDim2.new(0.5, 0, 0, 90)
	peaceful.Size = UDim2.fromOffset(300, 30)
	Theme.gradient(peaceful, Theme.green, 0.2, 0.15)
	peaceful.Visible = false
	Theme.round(peaceful, 15)
	Theme.stroke(peaceful, Theme.outline, 2)
	Theme.bold(peaceful, { Text = "🕊️ Peaceful server: no bats or traps", Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Font = Theme.font, MaxText = 20 })
	peaceful.Parent = gui

	task.spawn(function()
		while true do
			peaceful.Visible = workspace:GetAttribute("Peaceful") == true
			coins.Text = Format.abbrev(Store.coins())
			local today = DailyWindow.state()
			local ready = Daily.done(today) and not today.claimed
			badge.Visible = ready
			dailyName.Text = if ready then "Claim!" else "Daily"
			local riding = Players.LocalPlayer:GetAttribute("RideSeat")
			seatName.Text = if type(riding) == "string" and riding ~= "" then "Walk" else "Seat"
			local playerSpeed = Players.LocalPlayer:GetAttribute("Speed")
			speed.Text = Format.abbrev(if type(playerSpeed) == "number" then math.floor(playerSpeed) else 0)
			local fedUntil = Players.LocalPlayer:GetAttribute("FedUntil")
			local fed = type(fedUntil) == "number" and fedUntil > workspace:GetServerTimeNow()
			rate.Text = ("+%s/s%s"):format(Format.abbrev(Store.rate()), if fed then " · 😋 fed" else "")
			local now = workspace:GetServerTimeNow()
			local nightFrom, nightTo = Night.window(now)
			if Night.isNight(now) then
				nightBar.Visible = true
				nightText.Text = ("🌙 NIGHT! Eggs grow ×%d · %s"):format(NightConfig.SPEED, Format.time(math.max(0, math.ceil(nightTo - now))))
			elseif nightFrom - now <= NightConfig.WARNING then
				nightBar.Visible = true
				nightText.Text = ("🌙 Night in %s: eggs grow ×%d"):format(Format.time(math.max(0, math.ceil(nightFrom - now))), NightConfig.SPEED)
			else
				nightBar.Visible = false
			end
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
