-- Items window: elixirs with counts, use / merge / mix, and the active boosts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local BagPanel = {}

local selected: string? = nil
local mixFirst: string? = nil

local ROMAN = { "I", "II", "III", "IV", "V" }

local function itemTile(item: Items.Item, count: number, highlight: boolean): TextButton
	local tile = Instance.new("TextButton")
	tile.Text = ""
	tile.AutoButtonColor = true
	tile.BackgroundColor3 = if highlight then Color3.fromRGB(70, 90, 140) else Theme.card
	tile.BorderSizePixel = 0
	Theme.corner(tile, 10)
	Theme.stroke(tile, item.color, 2)
	-- Bottle drawn with frames
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
	local tier = Theme.label({
		Text = ROMAN[item.tier],
		Font = Theme.titleFont,
		Position = UDim2.new(0.5, -14, 0.2, 0),
		Size = UDim2.fromOffset(28, 22),
		MaxTextSize = 18,
	})
	tier.Parent = tile
	local name = Theme.label({
		Text = item.name,
		Size = UDim2.new(1, -6, 0.22, 0),
		Position = UDim2.new(0, 3, 0.58, 0),
		MaxTextSize = 13,
	})
	name.Parent = tile
	local amount = Theme.label({
		Text = "x" .. count,
		TextColor3 = Theme.gold,
		Size = UDim2.new(1, -6, 0.16, 0),
		Position = UDim2.new(0, 3, 0.8, 0),
		MaxTextSize = 15,
	})
	amount.Parent = tile
	return tile
end

function BagPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Items", function()
		Windows.close("Items")
	end)

	local boostsLabel = Theme.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.green,
		MaxTextSize = 16,
	})
	boostsLabel.Parent = content

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 46)
	scroll.Size = UDim2.new(0.64, 0, 1, -46)
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(96, 120)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	scroll.Parent = content

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
		Text = "Elixirs drop from chests, safes, vaults, Bigs and guardians, and come from quests and daily rewards.",
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.muted,
		Size = UDim2.new(1, -12, 0.4, 0),
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
	local mergeButton = Theme.button({ Text = "Merge 3 → 1", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Theme.purple, LayoutOrder = 2 })
	local mixButton = Theme.button({ Text = "Mix with...", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Theme.accent, LayoutOrder = 3 })
	for _, b in { useButton, mergeButton, mixButton } do
		b.Parent = buttons
	end

	local function updateBoosts()
		local lines = {}
		for stat, boost in Store.currency.boosts do
			table.insert(lines, ("%s x%g (%s)"):format(stat, boost.mult, Format.time(boost.left)))
		end
		boostsLabel.Text = if #lines > 0 then "Active: " .. table.concat(lines, " · ") else "No active boosts"
	end

	local function rebuild()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiButton") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local data = Store.data
		if not data then
			return
		end
		local order = 0
		for _, item in Items.list do
			local count = data.items[item.id] or 0
			if count > 0 then
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
			local empty = Theme.label({ Text = "No items yet.", Size = UDim2.fromOffset(200, 40), MaxTextSize = 18 })
			empty.Parent = scroll
		end
		local item = if selected then Items.byId[selected] else nil
		local count = if item then data.items[item.id] or 0 else 0
		buttons.Visible = item ~= nil and count > 0
		if item and count > 0 then
			title.Text = item.name
			local lines = { item.description, ("You have %d"):format(count) }
			if mixFirst then
				table.insert(lines, "Now tap another elixir of the same tier to mix.")
			end
			info.Text = table.concat(lines, "\n")
			mergeButton.Visible = Items.nextTier(item.id) ~= nil
			mixButton.Text = if mixFirst then "Cancel mix" else "Mix with..."
		else
			title.Text = "Pick an item"
		end
	end

	useButton.Activated:Connect(function()
		if selected then
			Net.event("UseItem"):FireServer(selected)
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
		if window.Visible then
			updateBoosts()
		end
	end)
	Windows.register("Items", window, function()
		rebuild()
		updateBoosts()
	end)
end

return BagPanel
