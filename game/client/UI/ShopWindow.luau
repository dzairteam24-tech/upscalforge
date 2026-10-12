--!strict
-- The Shop's window, in two tabs. Sell: the player's eggs (one or all of a kind) and creatures out of the garden,
-- each with what it pays. Food: food for the trough (FoodWindow).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local Hatch = require(Shared.Logic.Hatch)
local Mutations = require(Shared.Config.Mutations)
local SnapConfig = require(Shared.Config.Snap)
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local FoodWindow = require(script.Parent.FoodWindow)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local ShopWindow = {}

local TABS = { "💰 Sell", "🍎 Food" }

function ShopWindow.mount(gui: Instance)
	local window, content = Theme.window(gui, "🛒 Shop", Vector2.new(760, 640), Theme.green, true)

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
	local foodView = holder(2)
	local refreshFood = FoodWindow.build(foodView)

	-- Rebuilt whenever the player's data changes
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
		for _, golden in { false, true } do
			local held = if golden then data.golden else data.eggs
			for _, key in Hatch.sortedKeys(held) do
				local tier, size = Hatch.parse(key)
				local egg = if tier then Hatch.egg(tier) else nil
				local count = held[key] or 0
				if count <= 0 or not egg or not tier then
					continue
				end
				sold += 1
				local each = math.floor(Earn.eggSellPrice(egg.price, golden) * Hatch.size(size).mult)
				local row = Theme.card(sellView, Theme.lighten(egg.color, 0.5), { Size = UDim2.new(1, -8, 0, 84), LayoutOrder = sold })
				local view = Theme.eggView(row, egg.color, golden)
				view.Size = UDim2.fromOffset(70, 70)
				view.Position = UDim2.fromOffset(8, 7)
				Theme.bold(row, { Text = ("%s ×%d"):format(Hatch.name(tier, size, golden), count), Size = UDim2.new(0.4, -80, 0, 30), Position = UDim2.fromOffset(84, 10), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 24 })
				Theme.text(row, { Text = ("🪙 %s each"):format(Format.abbrev(each)), Size = UDim2.new(0.4, -80, 0, 22), Position = UDim2.fromOffset(84, 44), TextColor3 = Theme.ink, TextXAlignment = Enum.TextXAlignment.Left })
				local one = Theme.button(row, ("Sell 1 · 🪙 %s"):format(Format.abbrev(each)), Theme.green, function()
					Net.event("SellEgg"):FireServer(key, golden, false)
				end)
				one.Size = UDim2.new(0.3, -8, 0, 52)
				one.Position = UDim2.new(0.4, 0, 0, 16)
				local all = Theme.button(row, ("All %d · 🪙 %s"):format(count, Format.abbrev(each * count)), Theme.blue, function()
					Net.event("SellEgg"):FireServer(key, golden, true)
				end)
				all.Size = UDim2.new(0.3, -8, 0, 52)
				all.Position = UDim2.new(0.7, 0, 0, 16)
			end
		end
		-- Creatures that aren't in the garden, the best first
		local list = {}
		for id, creature in data.creatures do
			if not table.find(data.placed, id) and not data.stored[id] then
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

	local tab = TABS[1]
	local select = Theme.tabs(window, TABS, Theme.green, function(name)
		tab = name
		sellView.Visible = name == TABS[1]
		foodView.Visible = name == TABS[2]
		content.CanvasPosition = Vector2.zero
		if name == TABS[1] then
			sellTab()
		else
			refreshFood()
		end
	end)
	Windows.register("Shop", window, function()
		select(tab)
	end)
	Store.Changed:Connect(function()
		if window.Visible then
			if tab == TABS[1] then
				sellTab()
			else
				refreshFood()
			end
		end
	end)
end

return ShopWindow
