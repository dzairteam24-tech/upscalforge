--!strict
-- The always-on screen, laid out like Steal an Egg: big Shop, Index and Bag buttons on the left; speed, coins
-- (and what the garden earns a second) and the friend boost down the bottom left; Daily, Home, Wild and Seat
-- down the right; the night's countdown in the bottom right; the weather over the top; and the server's players
-- with their coins a second and speed in the top right.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mutations = require(Shared.Config.Mutations)
local NightConfig = require(Shared.Config.Night)
local Daily = require(Shared.Logic.Daily)
local Format = require(Shared.Logic.Format)
local Night = require(Shared.Logic.Night)
local Weather = require(Shared.Logic.Weather)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)
local DailyWindow = require(script.Parent.DailyWindow)

local HUD = {}

local LOCAL = Players.LocalPlayer
local BOARD_ROWS = 6

-- A wide button with an icon and a word, like the big games' left-side buttons
local function wideButton(parent: Instance, icon: string, label: string, color: Color3, order: number, onClick: () -> ()): TextButton
	local button = Theme.button(parent, "", color, onClick)
	button.LayoutOrder = order
	Theme.text(button, { Text = icon, Size = UDim2.new(0.3, 0, 1, 0), Position = UDim2.fromScale(0, 0) })
	Theme.bold(button, { Text = label, Size = UDim2.new(0.7, -4, 1, 0), Position = UDim2.fromScale(0.3, 0), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 34 })
	return button
end

function HUD.mount(gui: Instance)
	-- Left: Shop, Index, Bag
	local left = Instance.new("Frame")
	left.Name = "Left"
	left.BackgroundTransparency = 1
	left.AnchorPoint = Vector2.new(0, 0.5)
	left.Position = UDim2.new(0, 16, 0.45, 0)
	left.Size = UDim2.fromOffset(190, 210)
	local leftLayout = Instance.new("UIListLayout")
	leftLayout.Padding = UDim.new(0, 10)
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leftLayout.Parent = left
	left.Parent = gui
	for _, b in {
		wideButton(left, "🛒", "Shop", Theme.green, 1, function()
			Windows.toggle("Store")
		end),
		wideButton(left, "📖", "Index", Color3.fromRGB(60, 190, 240), 2, function()
			Windows.toggle("Index")
		end),
		wideButton(left, "🎒", "Bag", Color3.fromRGB(240, 150, 50), 3, function()
			Windows.toggle("Bag")
		end),
	} do
		b.Size = UDim2.new(1, 0, 0, 60)
	end

	-- Bottom left: speed, coins and what they earn, the friend boost
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundTransparency = 1
	stats.AnchorPoint = Vector2.new(0, 1)
	stats.Position = UDim2.new(0, 16, 1, -12)
	stats.Size = UDim2.fromOffset(380, 150)
	stats.Parent = gui
	local speed = Theme.bold(stats, { Size = UDim2.fromOffset(360, 44), Position = UDim2.fromOffset(0, 0), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 44 })
	local coins = Theme.bold(stats, { Size = UDim2.fromOffset(360, 48), Position = UDim2.fromOffset(0, 46), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(110, 255, 110), MaxText = 48 })
	local rate = Theme.bold(stats, { Size = UDim2.fromOffset(360, 24), Position = UDim2.fromOffset(4, 94), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 240, 160), Font = Theme.font, MaxText = 22 })
	local friends = Theme.bold(stats, { Size = UDim2.fromOffset(360, 28), Position = UDim2.fromOffset(0, 120), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 28 })

	-- Right: Daily, Home, Wild, Seat
	local right = Instance.new("Frame")
	right.Name = "Right"
	right.BackgroundTransparency = 1
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.new(1, -16, 0.5, 0)
	right.Size = UDim2.fromOffset(84, 360)
	local rightLayout = Instance.new("UIListLayout")
	rightLayout.Padding = UDim.new(0, 12)
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Parent = right
	right.Parent = gui
	local daily, dailyName = Theme.iconButton(right, "📋", "Daily", Theme.purple, function()
		Windows.toggle("Daily")
	end)
	daily.LayoutOrder = 1
	local badge = Theme.bold(daily, { Text = "!", Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0, -12, 0, -10), BackgroundTransparency = 0, BackgroundColor3 = Theme.red, MaxText = 22 })
	Theme.round(badge, 13)
	badge.ZIndex = 3
	local home = Theme.iconButton(right, "🏠", "Home", Theme.green, function()
		Net.event("Travel"):FireServer("home")
	end)
	home.LayoutOrder = 2
	local wild = Theme.iconButton(right, "🌿", "Wild", Color3.fromRGB(240, 150, 50), function()
		Net.event("Travel"):FireServer("wild")
	end)
	wild.LayoutOrder = 3
	local seat, seatName = Theme.iconButton(right, "☁️", "Seat", Theme.pink, function()
		local data = Store.data
		local riding = LOCAL:GetAttribute("RideSeat")
		local on = type(riding) == "string" and riding ~= ""
		local owned = if data then data.seats else {}
		local first = if owned.Cloud then "Cloud" else next(owned)
		Net.event("Seat"):FireServer(if on then "" else (if data and data.seat ~= "" then data.seat else first) or "")
	end)
	seat.LayoutOrder = 4

	-- Bottom right: the night's countdown
	local night = Theme.bold(gui, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -12), Size = UDim2.fromOffset(300, 46), TextXAlignment = Enum.TextXAlignment.Right, MaxText = 40 })

	-- Over the top: the weather
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
	-- A Peaceful private server says so (no bats or traps there: GearService)
	local peaceful = Instance.new("Frame")
	peaceful.Name = "Peaceful"
	peaceful.AnchorPoint = Vector2.new(0.5, 0)
	peaceful.Position = UDim2.new(0.5, 0, 0, 52)
	peaceful.Size = UDim2.fromOffset(300, 30)
	Theme.gradient(peaceful, Theme.green, 0.2, 0.15)
	peaceful.Visible = false
	Theme.round(peaceful, 15)
	Theme.stroke(peaceful, Theme.outline, 2)
	Theme.bold(peaceful, { Text = "🕊️ Peaceful server: no bats or traps", Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Font = Theme.font, MaxText = 20 })
	peaceful.Parent = gui

	-- Top right: the server's players, best earners first
	local board = Instance.new("Frame")
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(1, 0)
	board.Position = UDim2.new(1, -12, 0, 8)
	board.Size = UDim2.fromOffset(300, 30 + BOARD_ROWS * 26)
	board.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	board.BackgroundTransparency = 0.3
	Theme.round(board, 10)
	board.Parent = gui
	local function cell(row: number, column: number, text: string): TextLabel
		local widths = { 0, 0.5, 0.75 }
		return Theme.text(board, {
			Text = text,
			Position = UDim2.new(widths[column], 8, 0, 4 + row * 26),
			Size = UDim2.new(if column == 1 then 0.5 else 0.25, -10, 0, 22),
			TextColor3 = if row == 0 then Color3.fromRGB(190, 190, 205) else Color3.new(1, 1, 1),
			TextXAlignment = if column == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
		})
	end
	cell(0, 1, "People")
	cell(0, 2, "🪙/s")
	cell(0, 3, "⚡")
	local rows: { { TextLabel } } = {}
	for row = 1, BOARD_ROWS do
		rows[row] = { cell(row, 1, ""), cell(row, 2, ""), cell(row, 3, "") }
	end

	local function number(player: Player, name: string): number
		local value = player:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end

	task.spawn(function()
		while true do
			peaceful.Visible = workspace:GetAttribute("Peaceful") == true
			local playerSpeed = number(LOCAL, "Speed")
			speed.Text = "⚡ " .. Format.abbrev(math.floor(playerSpeed))
			coins.Text = "🪙 " .. Format.abbrev(Store.coins())
			local fedUntil = LOCAL:GetAttribute("FedUntil")
			local fed = type(fedUntil) == "number" and fedUntil > workspace:GetServerTimeNow()
			rate.Text = ("+%s / second%s"):format(Format.abbrev(Store.rate()), if fed then " · 😋 fed" else "")
			local boost = number(LOCAL, "FriendBoost")
			friends.Text = ("👥 Friend Boost: +%d%%"):format(boost)
			friends.TextColor3 = if boost > 0 then Color3.fromRGB(110, 255, 110) else Color3.fromRGB(220, 220, 230)
			local today = DailyWindow.state()
			local ready = Daily.done(today) and not today.claimed
			badge.Visible = ready
			dailyName.Text = if ready then "Claim!" else "Daily"
			local riding = LOCAL:GetAttribute("RideSeat")
			seatName.Text = if type(riding) == "string" and riding ~= "" then "Walk" else "Seat"
			-- The night
			local now = workspace:GetServerTimeNow()
			local nightFrom, nightTo = Night.window(now)
			if Night.isNight(now) then
				night.Text = ("🌙 NIGHT ×%d · %s"):format(NightConfig.SPEED, Format.time(math.max(0, math.ceil(nightTo - now))))
				night.TextColor3 = Color3.fromRGB(190, 200, 255)
			else
				night.Text = "🌙 in " .. Format.time(math.max(0, math.ceil(nightFrom - now)))
				night.TextColor3 = Color3.new(1, 1, 1)
			end
			-- The weather
			local weather, ends = Weather.at(math.floor(now))
			local left = Format.time(math.max(0, math.ceil(ends - now)))
			if weather.mutation then
				weatherText.Text = ("%s %s: eggs hatching now are %s+ · %s"):format(weather.icon, weather.name, weather.mutation, left)
				stroke.Color = Mutations.byId[weather.mutation].color
			else
				weatherText.Text = ("%s %s · next weather in %s"):format(weather.icon, weather.name, left)
				stroke.Color = weather.color
			end
			-- The board
			local everyone = Players:GetPlayers()
			table.sort(everyone, function(a, b)
				return number(a, "Rate") > number(b, "Rate")
			end)
			for row = 1, BOARD_ROWS do
				local player = everyone[row]
				local labels = rows[row]
				labels[1].Text = if player then (if player == LOCAL then "⭐ " else "") .. player.DisplayName else ""
				labels[2].Text = if player then Format.abbrev(math.floor(number(player, "Rate"))) else ""
				labels[3].Text = if player then Format.abbrev(math.floor(number(player, "Speed"))) else ""
			end
			board.Size = UDim2.fromOffset(300, 34 + math.min(#everyone, BOARD_ROWS) * 26)
			task.wait(0.5)
		end
	end)
end

return HUD
