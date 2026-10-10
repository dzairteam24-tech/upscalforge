--!strict
-- The Egg Shop's window: each egg with its price and what's left in stock (Logic/Stock), and when it restocks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Stock = require(Shared.Logic.Stock)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local ShopWindow = {}

function ShopWindow.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "🥚 Egg Shop", Vector2.new(520, 560))
	local restock = Theme.text(content, { Size = UDim2.new(1, 0, 0, 24), TextColor3 = Theme.soft, LayoutOrder = 0 })
	type Row = { stock: TextLabel, buy: TextButton, tier: number, price: number }
	local rows: { Row } = {}
	for _, egg in Eggs do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 64)
		row.BackgroundColor3 = Theme.card
		row.LayoutOrder = egg.tier
		Theme.round(row, 12)
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(40, 50)
		dot.Position = UDim2.fromOffset(10, 7)
		dot.BackgroundColor3 = egg.color
		Theme.round(dot, 20)
		dot.Parent = row
		Theme.text(row, { Text = egg.name, Size = UDim2.new(0.5, -60, 0, 26), Position = UDim2.fromOffset(60, 6), TextXAlignment = Enum.TextXAlignment.Left })
		Theme.text(row, {
			Text = ("🪙 %s · ⏳ %s"):format(Format.abbrev(egg.price), Format.time(Hatch.seconds(egg.tier))),
			Size = UDim2.new(0.5, -60, 0, 22),
			Position = UDim2.fromOffset(60, 34),
			TextColor3 = Theme.soft,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local stock = Theme.text(row, { Size = UDim2.new(0.22, 0, 0, 26), Position = UDim2.new(0.5, 0, 0, 19) })
		local buy = Theme.button(row, "Buy", Theme.green, function()
			Net.event("BuyEgg"):FireServer(egg.tier)
		end)
		buy.Size = UDim2.new(0.24, 0, 0, 40)
		buy.Position = UDim2.new(0.74, 0, 0, 12)
		row.Parent = content
		table.insert(rows, { stock = stock, buy = buy, tier = egg.tier, price = egg.price })
	end

	local function refresh()
		local now = os.time()
		local window_ = Stock.window(now)
		restock.Text = ("Restocks in %s"):format(Format.time(Stock.restockAt(now) - now))
		local data = Store.data
		local bought = if data and data.shop.window == window_ then data.shop.bought else {}
		for _, row in rows do
			local left = math.max(0, Stock.count(window_, row.tier) - (bought[tostring(row.tier)] or 0))
			row.stock.Text = if left > 0 then ("%d in stock"):format(left) else "Sold out"
			row.stock.TextColor3 = if left > 0 then Theme.ink else Theme.red
			row.buy.BackgroundColor3 = if left > 0 and Store.coins() >= row.price then Theme.green else Theme.soft
		end
	end
	Windows.register("Shop", window, refresh)
	task.spawn(function()
		while true do
			if window.Visible then
				refresh()
			end
			task.wait(0.5)
		end
	end)
end

return ShopWindow
