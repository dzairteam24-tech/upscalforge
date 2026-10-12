--!strict
-- The bag, in three tabs. Eggs: each kind the player holds as a card with the egg in 3D, to set down on
-- the grass where they stand (as its tool in the inventory does). Creatures: a card for each, its model in 3D,
-- colored by rarity, with its mutation, what it earns, what it sells for, and a button to put it in the garden
-- or take it back to the inventory, or keep it in the barn (selling is at the Sell Shop in town). Garden: room for more eggs on the grass, creatures in the garden,
-- the storage barn and the pasture.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local IslandConfig = require(Shared.Config.Island)
local Mutations = require(Shared.Config.Mutations)
local SnapConfig = require(Shared.Config.Snap)
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Snap = require(Shared.Logic.Snap)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local BagWindow = {}

local TABS = { "🥚 Eggs", "🐾 Creatures", "🌳 Garden" }

function BagWindow.mount(gui: Instance)
	local window, content = Theme.window(gui, "🎒 Bag", Vector2.new(720, 620), Theme.blue, true)
	local tab = TABS[1]

	local function clear()
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function hint(order: number, text: string)
		Theme.text(content, { Text = text, Size = UDim2.new(1, -8, 0, 22), TextColor3 = Theme.soft, LayoutOrder = order })
	end

	-- A card's bottom button
	local function cardButton(card: Frame, text: string, color: Color3, onClick: () -> ()): TextButton
		local button = Theme.button(card, text, color, onClick)
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.new(0.5, 0, 1, -8)
		button.Size = UDim2.new(1, -16, 0, 34)
		return button
	end

	-- An upgrade row (the Garden tab, and on top of the Eggs tab): an icon, what it is, how far it's grown, and a button to grow it
	local function upgradeRow(order: number, icon: string, title: string, detail: string, price: number?, label: string, remote: string)
		local row = Theme.card(content, Theme.cream, { Size = UDim2.new(1, -8, 0, 78), LayoutOrder = order })
		Theme.text(row, { Text = icon, Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(10, 11) })
		Theme.bold(row, { Text = title, Size = UDim2.new(0.58, -76, 0, 30), Position = UDim2.fromOffset(74, 10), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 26 })
		Theme.text(row, { Text = detail, Size = UDim2.new(0.58, -76, 0, 22), Position = UDim2.fromOffset(74, 44), TextColor3 = Theme.soft, TextXAlignment = Enum.TextXAlignment.Left })
		if price then
			local button = Theme.button(row, ("%s · 🪙 %s"):format(label, Format.abbrev(price)), if Store.coins() >= price then Theme.green else Theme.gray, function()
				Net.event(remote):FireServer()
			end)
			button.Size = UDim2.new(0.4, -12, 0, 52)
			button.Position = UDim2.new(0.6, 0, 0, 13)
		else
			Theme.bold(row, { Text = "MAX", Size = UDim2.new(0.4, -12, 0, 40), Position = UDim2.new(0.6, 0, 0, 19), TextColor3 = Theme.gold })
		end
	end

	local function eggsTab(data: { [string]: any })
		local down = 0
		for key in data.incubating do
			local slot = tonumber(key)
			if slot and slot <= IslandConfig.MACHINE_SLOT then
				down += 1
			end
		end
		-- How many eggs can hatch at once, and the button for one more, right here
		upgradeRow(0, "🥚", ("Hatching %d / %d"):format(down, data.incubators), "Eggs on your grass at once", Earn.nextPrice(IslandConfig.INCUBATOR_PRICES, data.incubators, IslandConfig.INCUBATORS), "+1 egg", "BuyIncubator")
		hint(1, "Eggs in your hotbar can be stolen outside your garden: set them down or store them at home")
		local grid = Theme.grid(content, 2, 4, 196)
		local kinds = 0
		for tier = 11, 1, -1 do
			local egg = Hatch.egg(tier)
			for _, golden in { true, false } do
				local held = if golden then data.golden else data.eggs
				local count = held and held[tostring(tier)] or 0
				if count > 0 and egg then
					kinds += 1
					local color = if golden then Theme.gold else egg.color
					local card = Theme.card(grid, Theme.lighten(color, 0.45), { LayoutOrder = kinds })
					local view = Theme.eggView(card, egg.color, golden)
					view.Size = UDim2.new(1, 0, 0, 96)
					view.Position = UDim2.fromOffset(0, 4)
					Theme.bold(card, { Text = "×" .. count, Size = UDim2.fromOffset(60, 28), Position = UDim2.new(1, -66, 0, 6), TextXAlignment = Enum.TextXAlignment.Right, MaxText = 26 })
					Theme.bold(card, { Text = (if golden then "✨ Golden " else "") .. egg.name, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 100), MaxText = 20 })
					Theme.text(card, { Text = "⏳ " .. Format.time(Hatch.seconds(tier)), Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(6, 124), TextColor3 = Theme.ink })
					local down = Theme.button(card, "Set down", Theme.green, function()
						Net.event("SetEgg"):FireServer(tier, golden)
					end)
					down.AnchorPoint = Vector2.new(0, 1)
					down.Position = UDim2.new(0, 8, 1, -8)
					down.Size = UDim2.new(0.58, -10, 0, 34)
					local keep = Theme.button(card, "📦 Store", Theme.blue, function()
						Net.event("Store"):FireServer(if golden then "golden" else "egg", tier, false)
					end)
					keep.AnchorPoint = Vector2.new(1, 1)
					keep.Position = UDim2.new(1, -8, 1, -8)
					keep.Size = UDim2.new(0.42, -10, 0, 34)
				end
			end
		end
		-- The barn: eggs kept there are safe anywhere (what's in the hotbar can be stolen outside the garden)
		local stored = 0
		local barn = Theme.grid(content, 5, 4, 150)
		for tier = 11, 1, -1 do
			local egg = Hatch.egg(tier)
			for _, golden in { true, false } do
				local held = if golden then data.storedGolden else data.storedEggs
				local count = held and held[tostring(tier)] or 0
				if count > 0 and egg then
					stored += 1
					local card = Theme.card(barn, Theme.lighten(if golden then Theme.gold else egg.color, 0.45), { LayoutOrder = stored })
					local view = Theme.eggView(card, egg.color, golden)
					view.Size = UDim2.new(1, 0, 0, 70)
					view.Position = UDim2.fromOffset(0, 4)
					Theme.bold(card, { Text = "×" .. count, Size = UDim2.fromOffset(60, 26), Position = UDim2.new(1, -66, 0, 6), TextXAlignment = Enum.TextXAlignment.Right, MaxText = 24 })
					Theme.bold(card, { Text = (if golden then "✨ " else "") .. egg.name, Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 76), MaxText = 17 })
					cardButton(card, "Take out", Theme.blue, function()
						Net.event("Withdraw"):FireServer(if golden then "golden" else "egg", tier, false)
					end)
				end
			end
		end
		hint(4, if stored > 0 then "📦 In your barn: safe anywhere. Take eggs out in your garden to hatch them" else "📦 Your barn is empty. Keep eggs there to stop anyone stealing them")
		if kinds == 0 then
			local empty = Theme.card(content, Theme.cream, { Size = UDim2.new(1, -8, 0, 120), LayoutOrder = 3 })
			Theme.text(empty, { Text = "🥚", Size = UDim2.fromOffset(70, 70), Position = UDim2.fromOffset(16, 25) })
			Theme.bold(empty, { Text = "No eggs yet!", Size = UDim2.new(1, -110, 0, 36), Position = UDim2.fromOffset(96, 22), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 30 })
			Theme.text(empty, { Text = "Steal one from the Wild", Size = UDim2.new(1, -110, 0, 40), Position = UDim2.fromOffset(96, 60), TextColor3 = Theme.soft, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
		end
	end

	local function creaturesTab(data: { [string]: any })
		local list = {}
		local count = 0
		for id, creature in data.creatures do
			count += 1
			table.insert(list, { id = id, creature = creature, rate = Earn.rate(creature), placed = table.find(data.placed, id) ~= nil, stored = data.stored[id] == true })
		end
		table.sort(list, function(a, b)
			if a.placed ~= b.placed then
				return a.placed
			end
			return a.rate > b.rate
		end)
		local level = math.clamp(data.storage, 1, #IslandConfig.STORAGE)
		hint(0, ("🌷 In your garden %d / %d  ·  📦 Kept %d / %d"):format(#data.placed, data.pens, count, IslandConfig.STORAGE[level]))
		-- (fusing is at the Fuse Machine in town)
		hint(1, "⚙️ Fuse 3 matching creatures into a stronger one at the Fuse Machine in town")
		if #list == 0 then
			local empty = Theme.card(content, Theme.cream, { Size = UDim2.new(1, -8, 0, 120), LayoutOrder = 2 })
			Theme.text(empty, { Text = "🐣", Size = UDim2.fromOffset(70, 70), Position = UDim2.fromOffset(16, 25) })
			Theme.bold(empty, { Text = "No creatures yet!", Size = UDim2.new(1, -110, 0, 36), Position = UDim2.fromOffset(96, 22), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 30 })
			Theme.text(empty, { Text = "Set an egg down on your grass and wait for it to hatch", Size = UDim2.new(1, -110, 0, 40), Position = UDim2.fromOffset(96, 60), TextColor3 = Theme.soft, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
			return
		end
		local grid = Theme.grid(content, 2, 4, 214)
		for i, entry in list do
			local creature = entry.creature
			local species = Creatures.byId[creature.s]
			local rarity = if species then species.rarity else "Common"
			local mutation = Mutations.byId[creature.m] or Mutations.byId.Normal
			local grade = if creature.g then SnapConfig.byId[creature.g] else nil
			local card = Theme.card(grid, Theme.lighten(Theme.RARITY[rarity] or Theme.gray, 0.35), { LayoutOrder = i })
			local view = Theme.creatureView(card, { s = creature.s, m = creature.m, size = if grade then grade.size else nil })
			view.Size = UDim2.new(1, 0, 0, 100)
			view.Position = UDim2.fromOffset(0, 6)
			-- Its mutation and size on top, and a mark when it's in the garden
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
			if entry.placed then
				local mark = Theme.bold(card, { Text = "🌷", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -32, 0, 4), MaxText = 24 })
				mark.ZIndex = 2
			end
			Theme.bold(card, { Text = species and species.id or creature.s, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 104), MaxText = 22 })
			Theme.bold(card, { Text = rarity, Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(6, 127), TextColor3 = Theme.RARITY[rarity] or Theme.gray, Font = Theme.font, MaxText = 15 })
			Theme.bold(card, { Text = ("🪙 %s/s"):format(Format.abbrev(entry.rate)), Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 144), TextColor3 = Color3.fromRGB(255, 230, 120), MaxText = 18 })
			if entry.stored then
				local mark = Theme.bold(card, { Text = "📦", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -32, 0, 4), MaxText = 24 })
				mark.ZIndex = 2
			end
			local toggle = Theme.button(card, if entry.placed then "Take" else "Place", if entry.placed then Theme.blue else Theme.green, function()
				Net.event(if entry.placed then "TakeCreature" else "PlaceCreature"):FireServer(entry.id)
			end)
			toggle.AnchorPoint = Vector2.new(0, 1)
			toggle.Position = UDim2.new(0, 8, 1, -8)
			toggle.Size = UDim2.new(if entry.placed then 1 else 0.5, if entry.placed then -16 else -10, 0, 34)
			if not entry.placed then
				-- (what's in the hotbar can be stolen outside the garden; in the barn it's safe anywhere)
				local keep = Theme.button(card, if entry.stored then "↩ Out" else "📦 Store", Theme.gray, function()
					Net.event(if entry.stored then "Withdraw" else "Store"):FireServer("creature", entry.id, false)
				end)
				Theme.recolor(keep, if entry.stored then Theme.blue else Theme.gray)
				keep.AnchorPoint = Vector2.new(1, 1)
				keep.Position = UDim2.new(1, -8, 1, -8)
				keep.Size = UDim2.new(0.5, -10, 0, 34)
			end
		end
	end

	local function gardenTab(data: { [string]: any })
		local down = 0
		for key in data.incubating do
			local slot = tonumber(key)
			if slot and slot <= IslandConfig.MACHINE_SLOT then
				down += 1
			end
		end
		upgradeRow(1, "🥚", ("Eggs on the grass %d / %d"):format(down, data.incubators), "How many eggs hatch in your garden at once", Earn.nextPrice(IslandConfig.INCUBATOR_PRICES, data.incubators, IslandConfig.INCUBATORS), "+1", "BuyIncubator")
		upgradeRow(2, "🌷", ("Creatures out %d / %d"):format(#data.placed, data.pens), "Only creatures in the garden earn coins", Earn.nextPrice(IslandConfig.PEN_PRICES, data.pens, IslandConfig.PENS), "+1", "BuyPen")
		local count = 0
		for _ in data.creatures do
			count += 1
		end
		local level = math.clamp(data.storage, 1, #IslandConfig.STORAGE)
		local next = IslandConfig.STORAGE[level + 1]
		upgradeRow(3, "📦", ("Storage %d / %d"):format(count, IslandConfig.STORAGE[level]), "How many creatures you can keep", IslandConfig.STORAGE_PRICES[level], if next then "→ " .. next else "", "BuyStorage")
		local growLevel = math.clamp(data.pasture or 1, 1, #IslandConfig.PASTURE_GROWTH)
		upgradeRow(4, "🌳", ("Pasture %d / %d"):format(growLevel, #IslandConfig.PASTURE_GROWTH), "A bigger pasture, further back", IslandConfig.PASTURE_PRICES[growLevel], "Bigger", "BuyPasture")
	end

	local function rebuild()
		clear()
		local data = Store.data
		if not data then
			return
		end
		if tab == TABS[1] then
			eggsTab(data)
		elseif tab == TABS[2] then
			creaturesTab(data)
		else
			gardenTab(data)
		end
	end
	local select = Theme.tabs(window, TABS, Theme.blue, function(name)
		tab = name
		content.CanvasPosition = Vector2.zero
		rebuild()
	end)
	Windows.register("Bag", window, function()
		select(tab)
	end)
	Store.Changed:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
end

return BagWindow
