--!strict
-- The Food Shop's window: each food with how long it feeds the creatures and its price (Logic/Food: a share of
-- what the boost earns the player's garden), and how much the player holds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoodConfig = require(Shared.Config.Food)
local Earn = require(Shared.Logic.Earn)
local Food = require(Shared.Logic.Food)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local FoodWindow = {}

function FoodWindow.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "🌾 Food Shop", Vector2.new(520, 380))
	Theme.text(content, {
		Text = ("Put food in your trough: your creatures earn ×%d while they're fed"):format(FoodConfig.BOOST),
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = Theme.soft,
		LayoutOrder = 0,
	})
	type Row = { held: TextLabel, buy: TextButton, food: FoodConfig.Food }
	local rows: { Row } = {}
	for i, food in FoodConfig.LIST do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 64)
		row.BackgroundColor3 = Theme.card
		row.LayoutOrder = i
		Theme.round(row, 12)
		Theme.text(row, { Text = food.icon, Size = UDim2.fromOffset(44, 50), Position = UDim2.fromOffset(8, 7) })
		Theme.text(row, { Text = food.name, Size = UDim2.new(0.5, -60, 0, 26), Position = UDim2.fromOffset(60, 6), TextXAlignment = Enum.TextXAlignment.Left })
		Theme.text(row, {
			Text = ("×%d for %s"):format(FoodConfig.BOOST, Format.time(food.minutes * 60)),
			Size = UDim2.new(0.5, -60, 0, 22),
			Position = UDim2.fromOffset(60, 34),
			TextColor3 = Theme.soft,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local held = Theme.text(row, { Size = UDim2.new(0.18, 0, 0, 26), Position = UDim2.new(0.5, 0, 0, 19) })
		local buy = Theme.button(row, "", Theme.green, function()
			Net.event("BuyFood"):FireServer(food.id)
		end)
		buy.Size = UDim2.new(0.3, 0, 0, 40)
		buy.Position = UDim2.new(0.68, 0, 0, 12)
		row.Parent = content
		table.insert(rows, { held = held, buy = buy, food = food })
	end

	local function refresh()
		local data = Store.data
		local rate = if data then Earn.islandRate(data.creatures, data.placed) else 0
		for _, row in rows do
			local price = Food.price(row.food, rate)
			row.held.Text = ("×%d"):format(if data then data.food[row.food.id] or 0 else 0)
			row.buy.Text = "🪙 " .. Format.abbrev(price)
			row.buy.BackgroundColor3 = if Store.coins() >= price then Theme.green else Theme.soft
		end
	end
	Windows.register("Food", window, refresh)
	Store.Changed:Connect(function()
		if window.Visible then
			refresh()
		end
	end)
end

return FoodWindow
