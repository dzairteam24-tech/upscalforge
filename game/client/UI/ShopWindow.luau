--!strict
-- The Sell Shop's window, in two tabs. Sell: the player's eggs (one or all of a kind) and creatures out of the
-- garden, each with what it pays. Buy: each egg with its price, what's left in stock (Logic/Stock) and what can
-- hatch from it with each chance, and when it restocks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local Eggs = require(Shared.Config.Eggs)
local Mutations = require(Shared.Config.Mutations)
local ShopConfig = require(Shared.Config.Shop)
local SnapConfig = require(Shared.Config.Snap)
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Stock = require(Shared.Logic.Stock)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local ShopWindow = {}

local TABS = { "💰 Sell", "🥚 Buy Eggs" }

function ShopWindow.mount(gui: Instance)
	local window, content = Theme.window(gui, "💰 Sell Shop", Vector2.new(760, 640), Theme.green, true)
	local tab = TABS[1]

	-- Each tab's views live in their own holder
	local function holder(order: number): Frame
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(1, -8, 0, 0)
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.LayoutOrder = order
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Parent = frame
		frame.Parent = content
		return frame
	end
	local sellView = holder(1)
	local buyView = holder(2)

	-- The Sell tab: rebuilt whenever the player's data changes
	local function sellTab()
		for _, child in sellView:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local data = Store.data
		if not data then
			return
		end
		Theme.text(sellView, { Text = "Sell what you don't need for coins. Creatures living in your garden can't be sold: take them out in your Bag first", Size = UDim2.new(1, -8, 0, 40), TextColor3 = Theme.soft, TextWrapped = true, LayoutOrder = 0 })
		-- Eggs: a row for each kind held, golden ones apart
		local sold = 0
		for _, egg in Eggs do
			for _, golden in { false, true } do
				local count = (if golden then data.golden else data.eggs)[tostring(egg.tier)] or 0
				if count <= 0 then
					continue
				end
				sold += 1
				local each = Earn.eggSellPrice(egg.price, golden)
				local row = Theme.card(sellView, Theme.lighten(egg.color, 0.5), { Size = UDim2.new(1, -8, 0, 84), LayoutOrder = egg.tier * 2 + (if golden then 1 else 0) })
				local view = Theme.eggView(row, egg.color, golden)
				view.Size = UDim2.fromOffset(70, 70)
				view.Position = UDim2.fromOffset(8, 7)
				Theme.bold(row, { Text = ("%s%s ×%d"):format(if golden then "✨ " else "", egg.name, count), Size = UDim2.new(0.4, -80, 0, 30), Position = UDim2.fromOffset(84, 10), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 24 })
				Theme.text(row, { Text = ("🪙 %s each"):format(Format.abbrev(each)), Size = UDim2.new(0.4, -80, 0, 22), Position = UDim2.fromOffset(84, 44), TextColor3 = Theme.ink, TextXAlignment = Enum.TextXAlignment.Left })
				local one = Theme.button(row, ("Sell 1 · 🪙 %s"):format(Format.abbrev(each)), Theme.green, function()
					Net.event("SellEgg"):FireServer(egg.tier, golden, false)
				end)
				one.Size = UDim2.new(0.3, -8, 0, 52)
				one.Position = UDim2.new(0.4, 0, 0, 16)
				local all = Theme.button(row, ("All %d · 🪙 %s"):format(count, Format.abbrev(each * count)), Theme.blue, function()
					Net.event("SellEgg"):FireServer(egg.tier, golden, true)
				end)
				all.Size = UDim2.new(0.3, -8, 0, 52)
				all.Position = UDim2.new(0.7, 0, 0, 16)
			end
		end
		-- Creatures that aren't in the garden, the best first
		local list = {}
		for id, creature in data.creatures do
			if not table.find(data.placed, id) then
				table.insert(list, { id = id, creature = creature, price = Earn.sellPrice(creature) })
			end
		end
		table.sort(list, function(a, b)
			if a.price ~= b.price then
				return a.price > b.price
			end
			return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
		end)
		if #list > 0 then
			local grid = Theme.grid(sellView, 1000, 4, 200)
			for i, entry in list do
				sold += 1
				local creature = entry.creature
				local species = Creatures.byId[creature.s]
				local rarity = if species then species.rarity else "Common"
				local mutation = Mutations.byId[creature.m] or Mutations.byId.Normal
				local grade = if creature.g then SnapConfig.byId[creature.g] else nil
				local card = Theme.card(grid, Theme.lighten(Theme.RARITY[rarity] or Theme.gray, 0.35), { LayoutOrder = i })
				local preview = Theme.creatureView(card, { s = creature.s, m = creature.m, size = if grade then grade.size else nil })
				preview.Size = UDim2.new(1, 0, 0, 100)
				preview.Position = UDim2.fromOffset(0, 6)
				local tags = {}
				if mutation.id ~= "Normal" then
					table.insert(tags, mutation.id)
				end
				if grade then
					table.insert(tags, grade.id)
				end
				if #tags > 0 then
					local tag = Theme.bold(card, { Text = table.concat(tags, " "), Size = UDim2.fromOffset(110, 22), Position = UDim2.fromOffset(6, 6), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if mutation.id ~= "Normal" then mutation.color else Color3.new(1, 1, 1), MaxText = 18 })
					tag.ZIndex = 2
				end
				Theme.bold(card, { Text = species and species.id or creature.s, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 106), MaxText = 22 })
				Theme.bold(card, { Text = rarity, Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(6, 130), TextColor3 = Theme.RARITY[rarity] or Theme.gray, Font = Theme.font, MaxText = 15 })
				local sell = Theme.button(card, ("Sell · 🪙 %s"):format(Format.abbrev(entry.price)), Theme.green, function()
					Net.event("SellCreature"):FireServer(entry.id)
				end)
				sell.AnchorPoint = Vector2.new(0.5, 1)
				sell.Position = UDim2.new(0.5, 0, 1, -8)
				sell.Size = UDim2.new(1, -16, 0, 38)
			end
		end
		if sold == 0 then
			local empty = Theme.card(sellView, Theme.cream, { Size = UDim2.new(1, -8, 0, 110), LayoutOrder = 1 })
			Theme.text(empty, { Text = "💰", Size = UDim2.fromOffset(70, 70), Position = UDim2.fromOffset(16, 20) })
			Theme.bold(empty, { Text = "Nothing to sell yet", Size = UDim2.new(1, -110, 0, 36), Position = UDim2.fromOffset(96, 18), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 30 })
			Theme.text(empty, { Text = "Eggs in your bag and creatures out of the garden show up here", Size = UDim2.new(1, -110, 0, 40), Position = UDim2.fromOffset(96, 56), TextColor3 = Theme.soft, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
		end
	end

	local restock = Theme.bold(buyView, { Size = UDim2.new(1, 0, 0, 28), TextColor3 = Theme.gold, LayoutOrder = 0, MaxText = 24 })
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
	Theme.text(buyView, {
		Text = "✨ Any egg can hatch: " .. table.concat(mutationOdds, " · "),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.soft,
		LayoutOrder = 0,
	})
	type Row = { stock: TextLabel, buy: TextButton, tier: number, price: number }
	local rows: { Row } = {}
	local grid = Theme.grid(buyView, 1, 3, 286)
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
	local select = Theme.tabs(window, TABS, Theme.green, function(name)
		tab = name
		sellView.Visible = name == TABS[1]
		buyView.Visible = name == TABS[2]
		content.CanvasPosition = Vector2.zero
		if name == TABS[1] then
			sellTab()
		else
			refresh()
		end
	end)
	-- (it opens on Sell, or on Buy Eggs when the player has nothing to sell yet)
	local function hasSomethingToSell(): boolean
		local data = Store.data
		if not data then
			return false
		end
		for _, bag in { data.eggs, data.golden } do
			for _, count in bag do
				if count > 0 then
					return true
				end
			end
		end
		for id in data.creatures do
			if not table.find(data.placed, id) then
				return true
			end
		end
		return false
	end
	Windows.register("Shop", window, function()
		select(if hasSomethingToSell() then TABS[1] else TABS[2])
	end)
	Store.Changed:Connect(function()
		if window.Visible and tab == TABS[1] then
			sellTab()
		end
	end)
	task.spawn(function()
		while true do
			if window.Visible and tab == TABS[2] then
				refresh()
			end
			task.wait(0.5)
		end
	end)
end

return ShopWindow
