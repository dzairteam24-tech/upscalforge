--!strict
-- The bag: the eggs the player holds (they go into incubators on the island) and their creatures, each with
-- what it earns, to put on the island, take back or sell (or send home, when it's Homesick). And a button to make
-- room for more on the island.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local IslandConfig = require(Shared.Config.Island)
local RaidConfig = require(Shared.Config.Raid)
local Mutations = require(Shared.Config.Mutations)
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Snap = require(Shared.Logic.Snap)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local BagWindow = {}

local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

function BagWindow.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "🎒 Bag", Vector2.new(560, 600))

	local function row(order: number, height: number): Frame
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, -8, 0, height)
		frame.BackgroundColor3 = Theme.card
		frame.LayoutOrder = order
		Theme.round(frame, 12)
		frame.Parent = content
		return frame
	end

	local function rebuild()
		for _, child in content:GetChildren() do
			if child:IsA("Frame") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local data = Store.data
		if not data then
			return
		end
		-- Eggs
		local eggsText = {}
		for tier = 11, 1, -1 do
			local golden = data.golden and data.golden[tostring(tier)] or 0
			local count = data.eggs[tostring(tier)] or 0
			local egg = Hatch.egg(tier)
			if golden > 0 and egg then
				table.insert(eggsText, ("✨ Golden %s ×%d"):format(egg.name, golden))
			end
			if count > 0 and egg then
				table.insert(eggsText, ("%s ×%d"):format(egg.name, count))
			end
		end
		local eggs = row(1, 54)
		Theme.text(eggs, {
			Text = if #eggsText > 0 then "🥚 " .. table.concat(eggsText, "  ·  ") .. "\nWalk to an incubator in your garden to put one in" else "🥚 No eggs: buy some at the Egg Shop in town",
			Size = UDim2.new(1, -16, 1, -8),
			Position = UDim2.fromOffset(8, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		-- Room on the island
		local room = row(2, 48)
		Theme.text(room, { Text = ("🌷 In your garden: %d / %d"):format(#data.placed, data.pens), Size = UDim2.new(0.6, -8, 1, -12), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Left })
		local price = Earn.nextPrice(IslandConfig.PEN_PRICES, data.pens, IslandConfig.PENS)
		if price then
			local more = Theme.button(room, ("+1 room · 🪙 %s"):format(Format.abbrev(price)), Theme.gold, function()
				Net.event("BuyPen"):FireServer()
			end)
			more.Size = UDim2.new(0.38, 0, 1, -12)
			more.Position = UDim2.new(0.6, 0, 0, 6)
		end
		-- The storage barn
		local count = 0
		for _ in data.creatures do
			count += 1
		end
		local barn = row(3, 48)
		local level = math.clamp(data.storage, 1, #IslandConfig.STORAGE)
		Theme.text(barn, { Text = ("📦 Storage: %d / %d"):format(count, IslandConfig.STORAGE[level]), Size = UDim2.new(0.6, -8, 1, -12), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Left })
		local barnPrice = IslandConfig.STORAGE_PRICES[level]
		if barnPrice then
			local bigger = Theme.button(barn, ("→ %d · 🪙 %s"):format(IslandConfig.STORAGE[level + 1], Format.abbrev(barnPrice)), Theme.gold, function()
				Net.event("BuyStorage"):FireServer()
			end)
			bigger.Size = UDim2.new(0.38, 0, 1, -12)
			bigger.Position = UDim2.new(0.6, 0, 0, 6)
		end
		-- Creatures, best first
		local list = {}
		for id, creature in data.creatures do
			table.insert(list, { id = id, creature = creature, rate = Earn.kept(creature), placed = table.find(data.placed, id) ~= nil })
		end
		table.sort(list, function(a, b)
			if a.placed ~= b.placed then
				return a.placed
			end
			return a.rate > b.rate
		end)
		-- Snaps ready: one row for each kind that has enough
		local offered = {}
		for _, entry in list do
			local group, made = Snap.find(data.creatures, data.placed, entry.id)
			local kind = if made then (made.g or "") .. Snap.name(entry.creature) else nil
			if group and made and kind and not offered[kind] then
				offered[kind] = true
				local frame = row(4, 48)
				local snapButton = Theme.button(frame, ("🧊 Snap %d %s → %s (🪙 %s/s)"):format(#group, Snap.name(entry.creature), Snap.name(made), Format.abbrev(Earn.rate(made))), Theme.gold, function()
					Net.event("Snap"):FireServer(entry.id)
				end)
				snapButton.Size = UDim2.new(1, -12, 1, -12)
				snapButton.Position = UDim2.fromOffset(6, 6)
			end
		end
		for i, entry in list do
			local species = Creatures.byId[entry.creature.s]
			local mutation = Mutations.byId[entry.creature.m] or Mutations.byId.Normal
			local frame = row(10 + i, 58)
			local mark = Instance.new("Frame")
			mark.Size = UDim2.fromOffset(8, 42)
			mark.Position = UDim2.fromOffset(8, 8)
			mark.BackgroundColor3 = mutation.color
			Theme.round(mark, 4)
			mark.Parent = frame
			local name = Snap.name(entry.creature)
			Theme.text(frame, { Text = name, Size = UDim2.new(0.42, -24, 0, 26), Position = UDim2.fromOffset(24, 4), TextXAlignment = Enum.TextXAlignment.Left })
			Theme.text(frame, {
				Text = if entry.creature.h
					then ("🏠 Misses %s · 🪙 %s/s"):format(entry.creature.hn or "home", Format.abbrev(entry.rate))
					else ("%s · 🪙 %s/s"):format(if species then species.rarity else "", Format.abbrev(entry.rate)),
				Size = UDim2.new(0.42, -24, 0, 20),
				Position = UDim2.fromOffset(24, 32),
				TextColor3 = if species and RARITY_ORDER[species.rarity] >= 4 then Color3.fromRGB(190, 120, 255) else Theme.soft,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			local toggle = Theme.button(frame, if entry.placed then "Take back" else "To garden", if entry.placed then Theme.blue else Theme.green, function()
				Net.event(if entry.placed then "TakeCreature" else "PlaceCreature"):FireServer(entry.id)
			end)
			toggle.Size = UDim2.new(0.26, 0, 0, 40)
			toggle.Position = UDim2.new(0.44, 0, 0, 9)
			local worth = Earn.sellPrice({ s = entry.creature.s, m = entry.creature.m })
			local sell = if entry.creature.h
				then Theme.button(frame, ("🏠 Home 🪙%s"):format(Format.abbrev(worth * RaidConfig.SEND_HOME_REWARD)), Theme.gold, function()
					Net.event("SendHome"):FireServer(entry.id)
				end)
				else Theme.button(frame, ("Sell 🪙%s"):format(Format.abbrev(worth)), Theme.red, function()
					Net.event("SellCreature"):FireServer(entry.id)
				end)
			sell.Size = UDim2.new(0.27, 0, 0, 40)
			sell.Position = UDim2.new(0.72, 0, 0, 9)
		end
	end
	Windows.register("Bag", window, rebuild)
	Store.Changed:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
end

return BagWindow
