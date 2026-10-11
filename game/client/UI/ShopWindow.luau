--!strict
-- The Egg Shop's window: each egg with its price, what's left in stock (Logic/Stock) and what can hatch from it
-- with each chance, and when it restocks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local Eggs = require(Shared.Config.Eggs)
local Mutations = require(Shared.Config.Mutations)
local ShopConfig = require(Shared.Config.Shop)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Stock = require(Shared.Logic.Stock)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local ShopWindow = {}

function ShopWindow.mount(gui: Instance)
	local window, content = Theme.window(gui, "🥚 Egg Shop", Vector2.new(760, 640), Theme.green)
	local restock = Theme.bold(content, { Size = UDim2.new(1, 0, 0, 28), TextColor3 = Theme.gold, LayoutOrder = 0, MaxText = 24 })
	-- The chances, out in the open
	local function percent(chance: number): string
		local value = chance * 100
		return if value >= 1 then ("%d%%"):format(math.floor(value + 0.5)) else ("%s%%"):format(tostring(math.floor(value * 100 + 0.5) / 100))
	end
	local mutationOdds = {}
	for _, mutation in Mutations.list do
		if mutation.chance > 0 then
			table.insert(mutationOdds, ("%s %s"):format(mutation.id, percent(mutation.chance)))
		end
	end
	Theme.text(content, {
		Text = "✨ Any egg can hatch: " .. table.concat(mutationOdds, " · "),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.soft,
		LayoutOrder = 0,
	})
	type Row = { stock: TextLabel, buy: TextButton, tier: number, price: number }
	local rows: { Row } = {}
	local grid = Theme.grid(content, 1, 3, 286)
	for _, egg in Eggs do
		local card = Theme.card(grid, Theme.lighten(egg.color, 0.5), { LayoutOrder = egg.tier })
		local view = Theme.eggView(card, egg.color)
		view.Size = UDim2.new(1, 0, 0, 92)
		view.Position = UDim2.fromOffset(0, 4)
		local stock = Theme.bold(card, { Size = UDim2.fromOffset(110, 22), Position = UDim2.fromOffset(6, 6), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.font, MaxText = 18 })
		stock.ZIndex = 2
		Theme.bold(card, { Text = egg.name, Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 96), MaxText = 24 })
		Theme.text(card, { Text = "⏳ " .. Format.time(Hatch.seconds(egg.tier)), Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(6, 122), TextColor3 = Theme.ink })
		-- What can hatch, each in its rarity's color
		local odds = Instance.new("Frame")
		odds.BackgroundTransparency = 1
		odds.Position = UDim2.fromOffset(8, 144)
		odds.Size = UDim2.new(1, -16, 0, 90)
		local oddsLayout = Instance.new("UIGridLayout")
		oddsLayout.CellSize = UDim2.new(if #egg.creatures > 4 then 0.5 else 1, -2, 0, if #egg.creatures > 4 then 17 else 21)
		oddsLayout.CellPadding = UDim2.fromOffset(2, 1)
		oddsLayout.Parent = odds
		for i, id in egg.creatures do
			local species = Creatures.byId[id]
			local rarity = if species then species.rarity else "Common"
			Theme.bold(odds, { Text = ("%s %s"):format(id, percent(egg.chances[i])), Size = UDim2.fromScale(1, 1), TextColor3 = Theme.RARITY[rarity] or Theme.gray, Font = Theme.font, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = i, MaxText = 16 })
		end
		odds.Parent = card
		local buy = Theme.button(card, ("🪙 %s"):format(Format.abbrev(egg.price)), Theme.green, function()
			Net.event("BuyEgg"):FireServer(egg.tier)
		end)
		buy.AnchorPoint = Vector2.new(0.5, 1)
		buy.Position = UDim2.new(0.5, 0, 1, -8)
		buy.Size = UDim2.new(1, -16, 0, 40)
		table.insert(rows, { stock = stock, buy = buy, tier = egg.tier, price = egg.price })
	end

	local function refresh()
		local now = os.time()
		local window_ = Stock.window(now)
		restock.Text = ("🔄 Restocks in %s"):format(Format.time(Stock.restockAt(now) - now))
		local data = Store.data
		local bought = if data and data.shop.window == window_ then data.shop.bought else {}
		for _, row in rows do
			if not Hatch.open(row.tier) then
				row.stock.Text = "🔒 SOON"
				row.stock.TextColor3 = Color3.fromRGB(255, 210, 80)
				row.buy.Text = "Coming Soon"
				Theme.recolor(row.buy, Theme.gray)
				continue
			end
			if not ShopConfig.STOCK[row.tier] then
				row.stock.Text = "🌿 Wild only"
				row.stock.TextColor3 = Color3.new(1, 1, 1)
				row.buy.Text = "🌿 Steal it!"
				Theme.recolor(row.buy, Theme.gray)
				continue
			end
			local left = math.max(0, Stock.count(window_, row.tier) - (bought[tostring(row.tier)] or 0))
			row.stock.Text = if left > 0 then ("x%d in stock"):format(left) else "SOLD OUT"
			row.stock.TextColor3 = if left > 0 then Color3.new(1, 1, 1) else Theme.red
			Theme.recolor(row.buy, if left > 0 and Store.coins() >= row.price then Theme.green else Theme.gray)
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
