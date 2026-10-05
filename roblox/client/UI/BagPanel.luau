-- Items window with three tabs:
--   Elixirs:    use, merge 3 -> 1, mix two families, active boosts
--   Cards:      Boost Cards (equipped slots + set bonuses), equip and merge
--   Keys:       use keys, merge 2 halves -> 1 key
--   Stickers:   stick one on a creature, merge 3 -> 1 (Normal -> Shiny -> Holo)
--   Gadgets:    one-use tools for the zone you're in

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Format = require(Shared.Logic.Format)
local Gear = require(Shared.Logic.Gear)
local Unlocks = require(Shared.Logic.Unlocks)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Bus = require(script.Parent.Bus)
local PetCard = require(script.Parent.PetCard)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local BagPanel = {}

type Tab = "Elixirs" | "Cartridges" | "Keys" | "Stickers" | "Gadgets"

-- `feature`: the tab shows once that system is open (Config/Unlocks)
local TABS: { { id: Tab, label: string, kinds: { [string]: boolean }, feature: string? } } = {
	{ id = "Elixirs", label = "🧪 Elixirs", kinds = { Elixir = true } },
	{ id = "Cartridges", label = "🃏 Cards", kinds = { Cartridge = true }, feature = "Cartridges" },
	{ id = "Keys", label = "🗝️ Keys", kinds = { Key = true, KeyHalf = true } },
	{ id = "Stickers", label = "⭐ Stickers", kinds = { Sticker = true }, feature = "Stickers" },
	{ id = "Gadgets", label = "💣 Gadgets", kinds = { Gadget = true }, feature = "Gadgets" },
}

local HINTS: { [Tab]: string } = {
	Elixirs = "Elixirs drop from chests, safes, vaults, Bigs and guardians, and come from quests, trips and daily rewards.",
	Cartridges = "Boost Cards give a bonus for as long as they are equipped. They drop from safes, vaults, Bigs, guardians and trips. One card of each kind; merge 3 into a stronger one. Every Reload adds a slot.",
	Keys = "Key halves drop from chests, safes, vaults, Bigs, guardians and trips. Merge 2 halves into a key.",
	Stickers = "Stick one on a creature: it shows on its back. Star boosts that creature, the others help the whole team. Moving a sticker never breaks it.",
	Gadgets = "One use, inside a zone. Gadgets drop from vaults, Bigs, guardians and trips.",
}

local current: Tab = "Elixirs"
local selected: string? = nil
local mixFirst: string? = nil

local function drawElixir(tile: GuiObject, item: Items.Item)
	local bottle = Theme.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.12, 0),
		Size = UDim2.fromScale(0.42, 0.42),
		BackgroundColor3 = item.color,
	})
	Theme.corner(bottle, 14)
	Theme.stroke(bottle, Color3.fromRGB(240, 240, 255), 2)
	bottle.Parent = tile
	local neck = Theme.frame({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.14, 0),
		Size = UDim2.fromScale(0.16, 0.1),
		BackgroundColor3 = Color3.fromRGB(220, 220, 235),
	})
	neck.Parent = tile
end

-- A Boost Card: colored card with a white border, a shine stripe and a star.
local function drawCard(tile: GuiObject, item: Items.Item, scale: number?)
	local s = scale or 1
	local card = Theme.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.06 * s, 0),
		Size = UDim2.fromScale(0.42 * s, 0.5 * s),
		BackgroundColor3 = item.color,
	})
	Theme.corner(card, 6)
	Theme.stroke(card, Color3.new(1, 1, 1), 2)
	card.Parent = tile
	local shine = Theme.frame({
		Position = UDim2.fromScale(0, 0.12),
		Size = UDim2.fromScale(1, 0.14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
	})
	shine.Parent = card
	local star = Theme.label({ Text = "★", Size = UDim2.fromScale(1, 0.55), Position = UDim2.fromScale(0, 0.35), MaxTextSize = 30 })
	star.Parent = card
end

local function drawKey(tile: GuiObject, item: Items.Item)
	local half = item.kind == "KeyHalf"
	local head = Theme.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.32, 0, 0.32, 0),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = item.color,
	})
	Theme.corner(head, 15)
	Theme.stroke(head, Color3.fromRGB(30, 32, 44), 2)
	head.Parent = tile
	local shaft = Theme.frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.32, 10, 0.32, 0),
		Size = UDim2.new(if half then 0.22 else 0.42, 0, 0, 8),
		BackgroundColor3 = item.color,
	})
	shaft.Parent = tile
	if not half then
		for i = 1, 2 do
			local tooth = Theme.frame({
				Position = UDim2.new(0.62 + (i - 1) * 0.1, 0, 0.32, 2),
				Size = UDim2.fromOffset(5, 10),
				BackgroundColor3 = item.color,
			})
			tooth.Parent = tile
		end
	end
end

local function drawIcon(tile: GuiObject, item: Items.Item)
	local badge = Theme.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.08, 0),
		Size = UDim2.fromScale(0.5, 0.42),
		BackgroundColor3 = item.color,
	})
	Theme.corner(badge, if item.kind == "Sticker" then 8 else 30)
	Theme.stroke(badge, Color3.new(1, 1, 1), if item.kind == "Sticker" then 3 else 1)
	badge.Parent = tile
	local icon = Theme.label({ Text = item.icon or "?", Size = UDim2.fromScale(1, 1), MaxTextSize = 36 })
	icon.Parent = badge
end

local function itemTile(item: Items.Item, count: number?, highlight: boolean): TextButton
	local tile = Instance.new("TextButton")
	tile.Text = ""
	tile.AutoButtonColor = true
	tile.BackgroundColor3 = if highlight then Color3.fromRGB(70, 90, 140) else Theme.card
	tile.BorderSizePixel = 0
	Theme.corner(tile, 10)
	Theme.stroke(tile, item.color, 2)
	if item.kind == "Elixir" then
		drawElixir(tile, item)
	elseif item.kind == "Cartridge" then
		drawCard(tile, item)
	elseif item.kind == "Sticker" or item.kind == "Gadget" then
		drawIcon(tile, item)
	else
		drawKey(tile, item)
	end
	local family = if item.kind == "Cartridge" then Items.cartridgeFamily(item.family) else nil
	local tierText = if item.kind == "KeyHalf"
		then "½"
		elseif family and family.rare then "★"
		elseif item.kind == "Key" or item.kind == "Gadget" then ""
		elseif item.kind == "Sticker" then ({ "", "✦", "✦✦" })[item.tier] or ""
		else Items.ROMAN[item.tier]
	if tierText ~= "" then
		local tier = Theme.label({
			Text = tierText,
			Font = Theme.titleFont,
			Position = UDim2.new(1, -30, 0, 4),
			Size = UDim2.fromOffset(26, 20),
			MaxTextSize = 18,
		})
		tier.Parent = tile
	end
	local name = Theme.label({
		Text = item.name,
		Size = UDim2.new(1, -6, 0.22, 0),
		Position = UDim2.new(0, 3, 0.58, 0),
		MaxTextSize = 13,
	})
	name.Parent = tile
	if count then
		local amount = Theme.label({
			Text = "x" .. count,
			TextColor3 = Theme.gold,
			Size = UDim2.new(1, -6, 0.16, 0),
			Position = UDim2.new(0, 3, 0.8, 0),
			MaxTextSize = 15,
		})
		amount.Parent = tile
	end
	return tile
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function BagPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Items", function()
		Windows.close("Items")
	end)

	-- Tabs
	local tabBar = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) })
	tabBar.Parent = content
	local tabButtons: { [Tab]: TextButton } = {}
	for i, tab in TABS do
		local b = Theme.button({
			Text = tab.label,
			Size = UDim2.new(1 / #TABS, -6, 1, -4),
			Position = UDim2.new((i - 1) / #TABS, 3, 0, 0),
			BackgroundColor3 = Theme.card,
			MaxTextSize = 16,
		})
		b.Parent = tabBar
		tabButtons[tab.id] = b
	end

	-- Header above the grid: boosts, or the Boost Card slots
	local header = Theme.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(0.64, 0, 0, 92),
	})
	header.Parent = content

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(96, 120)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	scroll.Parent = content

	-- Side panel
	local side = Theme.frame({ Position = UDim2.new(0.66, 0, 0, 46), Size = UDim2.new(0.34, 0, 1, -46) })
	Theme.corner(side, 12)
	side.Parent = content
	local title = Theme.label({
		Text = "Pick an item",
		Font = Theme.titleFont,
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.fromOffset(6, 8),
		MaxTextSize = 22,
	})
	title.Parent = side
	local info = Theme.label({
		Text = "",
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.muted,
		Size = UDim2.new(1, -12, 0.42, 0),
		Position = UDim2.fromOffset(6, 42),
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 15,
	})
	info.Parent = side
	local buttons = Theme.frame({
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0.55, 0),
		Size = UDim2.new(1, -16, 0.45, -8),
	})
	Theme.list(buttons, 8)
	buttons.Parent = side
	local useButton = Theme.button({ Text = "Use", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Theme.green, LayoutOrder = 1 })
	local mergeButton = Theme.button({ Text = "Merge", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Theme.purple, LayoutOrder = 2 })
	local mixButton = Theme.button({ Text = "Mix with...", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Theme.accent, LayoutOrder = 3 })
	for _, b in { useButton, mergeButton, mixButton } do
		b.Parent = buttons
	end

	local function boostsText(): string
		local lines = {}
		for stat, boost in Store.currency.boosts do
			table.insert(lines, ("%s x%g (%s)"):format(stat, boost.mult, Format.time(boost.left)))
		end
		return if #lines > 0 then "Active: " .. table.concat(lines, " · ") else "No active boosts"
	end

	local boostsLabel: TextLabel? = nil

	local function buildHeader(data: { [string]: any })
		clear(header)
		boostsLabel = nil
		if current == "Elixirs" then
			local label = Theme.label({
				Text = boostsText(),
				Size = UDim2.new(1, 0, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.green,
				MaxTextSize = 16,
			})
			label.Parent = header
			boostsLabel = label
		elseif current == "Cartridges" then
			local slots: number = data.cartridgeSlots or Gear.BASE_SLOTS
			local row = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 62) })
			Theme.list(row, 6, true)
			row.Parent = header
			for i = 1, Gear.MAX_SLOTS do
				local id = data.cartridges[i]
				local item = if id then Items.byId[id] else nil
				local slot: GuiObject
				if item then
					local b = Instance.new("TextButton")
					b.Text = ""
					b.BackgroundColor3 = Theme.card
					b.BorderSizePixel = 0
					Theme.corner(b, 8)
					Theme.stroke(b, item.color, 2)
					drawCard(b, item, 1.3)
					b.Activated:Connect(function()
						Net.event("UnequipCartridge"):FireServer(id)
					end)
					slot = b
				else
					local open = i <= slots
					local f = Theme.label({
						Text = if open then "+" else "🔒",
						TextColor3 = Theme.muted,
						BackgroundTransparency = 0,
						BackgroundColor3 = if open then Theme.panel else Color3.fromRGB(28, 32, 48),
						MaxTextSize = 22,
					})
					Theme.corner(f, 8)
					slot = f
				end
				slot.Size = UDim2.fromOffset(62, 62)
				slot.LayoutOrder = i
				slot.Parent = row
			end
			local sets = {}
			for _, setId in data.gearSets or {} do
				local set = Items.sets[setId]
				if set then
					table.insert(sets, ("✨ %s set: %s"):format(set.label, set.text))
				end
			end
			local setsLabel = Theme.label({
				Text = if #sets > 0
					then table.concat(sets, " · ")
					else ("Slots %d/%d · Tap a card to take it out · Equip 3 of a set for a bonus"):format(#data.cartridges, slots),
				TextColor3 = if #sets > 0 then Theme.gold else Theme.muted,
				Font = if #sets > 0 then Theme.font else Enum.Font.Gotham,
				Position = UDim2.fromOffset(0, 66),
				Size = UDim2.new(1, 0, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 14,
			})
			setsLabel.Parent = header
		elseif current == "Stickers" then
			local target = if Bus.stickerTarget then data.pets[Bus.stickerTarget] else nil
			local label = Theme.label({
				Text = if target
					then ("Pick a sticker for your %s"):format(PetCard.title(target))
					else "⭐ Normal → ✦ Shiny (+50% effect) → ✦✦ Holo (+100% effect)",
				Font = Enum.Font.Gotham,
				TextColor3 = if target then Theme.gold else Theme.muted,
				Size = UDim2.new(1, 0, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 15,
			})
			label.Parent = header
		elseif current == "Gadgets" then
			local label = Theme.label({
				Text = "💣 Use gadgets inside a zone. Totems help everyone in the zone!",
				Font = Enum.Font.Gotham,
				TextColor3 = Theme.muted,
				Size = UDim2.new(1, 0, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 15,
			})
			label.Parent = header
		else
			local label = Theme.label({
				Text = "🗝️ Zone Key: treasure vault · Golden Key: 3 Golden+ eggs · Titan Key: call a guardian now",
				Font = Enum.Font.Gotham,
				TextColor3 = Theme.muted,
				Size = UDim2.new(1, 0, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 15,
			})
			label.Parent = header
		end
		local headerHeight = if current == "Cartridges" then 92 else 46
		header.Size = UDim2.new(0.64, 0, 0, headerHeight)
		scroll.Position = UDim2.fromOffset(0, 46 + headerHeight)
		scroll.Size = UDim2.new(0.64, 0, 1, -(46 + headerHeight))
	end

	local function tabKinds(): { [string]: boolean }
		for _, tab in TABS do
			if tab.id == current then
				return tab.kinds
			end
		end
		return {}
	end

	local function rebuild()
		clear(scroll)
		local data = Store.data
		if not data then
			return
		end
		-- Only open systems get a tab; the visible tabs share the row
		local shown = {}
		for _, tab in TABS do
			local open = tab.feature == nil or Unlocks.has(data :: any, tab.feature)
			tabButtons[tab.id].Visible = open
			if open then
				table.insert(shown, tab.id)
			elseif current == tab.id then
				current = "Elixirs"
			end
		end
		for i, id in shown do
			local b = tabButtons[id]
			b.Size = UDim2.new(1 / #shown, -6, 1, -4)
			b.Position = UDim2.new((i - 1) / #shown, 3, 0, 0)
			b.BackgroundColor3 = if id == current then Theme.gold else Theme.card
		end
		buildHeader(data)

		local kinds = tabKinds()
		local order = 0
		for _, item in Items.list do
			local count = data.items[item.id] or 0
			if count > 0 and kinds[item.kind] then
				order += 1
				local tile = itemTile(item, count, item.id == selected or item.id == mixFirst)
				tile.LayoutOrder = order
				tile.Activated:Connect(function()
					if mixFirst and mixFirst ~= item.id then
						Net.event("MixItems"):FireServer(mixFirst, item.id)
						mixFirst = nil
					else
						selected = item.id
						mixFirst = nil
					end
					rebuild()
				end)
				tile.Parent = scroll
			end
		end
		if order == 0 then
			local empty = Theme.label({ Text = "Nothing here yet.", Size = UDim2.fromOffset(200, 40), MaxTextSize = 18 })
			empty.Parent = scroll
		end

		local item = if selected then Items.byId[selected] else nil
		local count = if item then data.items[item.id] or 0 else 0
		local show = item ~= nil and count > 0 and kinds[item.kind] == true
		buttons.Visible = show
		if not item or not show then
			title.Text = "Pick an item"
			info.Text = HINTS[current]
			return
		end
		title.Text = item.name
		local lines = { item.description, ("You have %d"):format(count) }
		if item.set and Items.sets[item.set] then
			local set = Items.sets[item.set]
			table.insert(lines, ("%s set: %s"):format(set.label, set.text))
		end
		if mixFirst then
			table.insert(lines, "Now tap another elixir of the same tier to mix.")
		end
		info.Text = table.concat(lines, "\n")

		useButton.Visible = item.kind ~= "KeyHalf"
		local target = if Bus.stickerTarget then data.pets[Bus.stickerTarget] else nil
		useButton.Text = if item.kind == "Cartridge"
			then "Equip"
			elseif item.kind == "Sticker" then (if target then "Stick on " .. PetCard.title(target) else "Stick on a creature")
			else "Use"
		local upgrade = Items.nextTier(item.id)
		mergeButton.Visible = upgrade ~= nil
		if upgrade then
			mergeButton.Text = ("Merge %d → %s"):format(item.mergeCost, Items.byId[upgrade].name)
		end
		mixButton.Visible = item.kind == "Elixir"
		mixButton.Text = if mixFirst then "Cancel mix" else "Mix with..."
	end

	for _, tab in TABS do
		tabButtons[tab.id].Activated:Connect(function()
			current = tab.id
			selected = nil
			mixFirst = nil
			rebuild()
		end)
	end
	useButton.Activated:Connect(function()
		local item = if selected then Items.byId[selected] else nil
		if not item then
			return
		end
		if item.kind == "Cartridge" then
			Net.event("EquipCartridge"):FireServer(item.id)
		elseif item.kind == "Sticker" then
			local data = Store.data
			local target = Bus.stickerTarget
			if target and data and data.pets[target] then
				Bus.stickerTarget = nil
				Net.event("ApplySticker"):FireServer(target, item.id)
				Windows.open("Pets")
			else
				Bus.startPick(("Tap a creature to put the %s on"):format(item.name), function(petId)
					Net.event("ApplySticker"):FireServer(petId, item.id)
				end)
				Windows.open("Pets")
			end
		else
			Net.event("UseItem"):FireServer(item.id)
		end
	end)
	mergeButton.Activated:Connect(function()
		if selected then
			Net.event("MergeItems"):FireServer(selected)
		end
	end)
	mixButton.Activated:Connect(function()
		mixFirst = if mixFirst then nil else selected
		rebuild()
	end)

	Store.DataChanged:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	Store.CurrencyChanged:Connect(function()
		local label = boostsLabel
		if window.Visible and label then
			label.Text = boostsText()
		end
	end)
	Windows.register("Items", window, function()
		local tab = Bus.itemsTab
		if tab then
			Bus.itemsTab = nil
			for _, entry in TABS do
				if entry.id == tab then
					current = entry.id
					selected = nil
					mixFirst = nil
				end
			end
		end
		rebuild()
	end)
end

return BagPanel
