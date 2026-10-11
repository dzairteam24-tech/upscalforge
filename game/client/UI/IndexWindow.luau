--!strict
-- The Index (Logic/Index), as in Steal an Egg: a page for each egg (the list on the left), its creatures in
-- cards colored by rarity (a dark silhouette and ??? until hatched), how many are found, and the page's reward
-- with its CLAIM button once all are in. Under it all, how many creatures are found in total.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local Eggs = require(Shared.Config.Eggs)
local IndexConfig = require(Shared.Config.Index)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Index = require(Shared.Logic.Index)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local IndexWindow = {}

function IndexWindow.mount(gui: Instance)
	local window, content = Theme.window(gui, "📖 Index", Vector2.new(900, 600), Color3.fromRGB(80, 190, 240))
	content.Visible = false -- (its own panels instead)
	local tier = 1

	-- The eggs, down the left
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(14, 66)
	list.Size = UDim2.new(0.24, -14, 1, -126)
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	list.Parent = window

	-- The page
	local page = Instance.new("Frame")
	page.BackgroundTransparency = 1
	page.Position = UDim2.new(0.24, 8, 0, 66)
	page.Size = UDim2.new(0.76, -22, 1, -126)
	page.Parent = window

	-- Found in all
	local totalBar = Theme.card(window, Color3.fromRGB(40, 40, 60), { Position = UDim2.new(0, 14, 1, -52), Size = UDim2.new(1, -28, 0, 40) })
	local totalText = Theme.bold(totalBar, { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), MaxText = 28 })

	local eggButtons: { [number]: TextButton } = {}

	local function rebuild()
		local data = Store.data
		local found: { [string]: boolean } = if data and data.index then data.index else {}
		local claimed: { [string]: boolean } = if data and data.indexClaimed then data.indexClaimed else {}
		-- The list
		for _, egg in Eggs do
			local got, all = Index.progress(found, egg.tier)
			local button = eggButtons[egg.tier]
			if not button then
				local created = Theme.button(list, "", egg.color, function()
					tier = egg.tier
					rebuild()
				end)
				created.Size = UDim2.new(1, -10, 0, 44)
				created.LayoutOrder = egg.tier
				eggButtons[egg.tier] = created
				button = created
			end
			local b = button :: TextButton
			local ready = Index.claimable(found, claimed, egg.tier) ~= nil
			local short = string.gsub(egg.name, " Egg", "")
			b.Text = if Hatch.open(egg.tier) then ("%s%s  %d/%d"):format(if ready then "🎁 " else "", short, got, all) else "🔒 " .. short
			Theme.recolor(b, if egg.tier == tier then egg.color else Theme.lighten(egg.color, 0.1):Lerp(Theme.gray, 0.55))
		end
		local got, all = Index.total(found)
		totalText.Text = ("📖 Unlocked: %d/%d"):format(got, all)

		-- The page
		for _, child in page:GetChildren() do
			child:Destroy()
		end
		local egg = Eggs[tier]
		if not egg then
			return
		end
		if not Hatch.open(tier) then
			Theme.bold(page, { Text = egg.name, Size = UDim2.new(1, 0, 0, 40), TextColor3 = egg.color, MaxText = 34 })
			Theme.bold(page, { Text = "🔒 COMING SOON", Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 140), TextColor3 = Color3.fromRGB(255, 210, 80), MaxText = 60 })
			return
		end
		local pageGot, pageAll = Index.progress(found, tier)
		local columns = if pageAll == 8 or pageAll <= 4 then 4 else 5
		local rows = math.ceil(pageAll / columns)
		Theme.bold(page, { Text = egg.name, Size = UDim2.new(0.66, 0, 0, 34), TextColor3 = egg.color, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 32 })
		-- The creatures
		local grid = Instance.new("Frame")
		grid.BackgroundTransparency = 1
		grid.Position = UDim2.fromOffset(0, 40)
		grid.Size = UDim2.new(0.66, -8, 1, -96)
		local layout = Instance.new("UIGridLayout")
		layout.CellPadding = UDim2.fromOffset(6, 6)
		layout.CellSize = UDim2.new(1 / columns, -6, 1 / rows, -6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		grid.Parent = page
		for i, id in egg.creatures do
			local species = Creatures.byId[id]
			local rarity = if species then species.rarity else "Common"
			local has = found[id] == true
			local card = Theme.card(grid, Theme.RARITY[rarity] or Theme.gray, { LayoutOrder = i })
			local view = Theme.creatureView(card, { s = id })
			view.Size = UDim2.new(1, 0, 0.78, 0)
			view.Position = UDim2.fromScale(0, 0.16)
			if not has then -- (a silhouette)
				view.ImageColor3 = Color3.new(0, 0, 0)
				view.ImageTransparency = 0.25
			end
			Theme.bold(card, { Text = if has then id else "???", Size = UDim2.new(1, -8, 0.2, 0), Position = UDim2.fromOffset(4, 2), MaxText = 22 })
			-- (what finding it gives, or that it's been given)
			local gift = Index.creatureReward(id)
			Theme.bold(card, {
				Text = if has then "✓" else ("🎁 🪙%s ⚡%s"):format(Format.abbrev(gift.coins), Format.abbrev(gift.power)),
				Size = UDim2.new(1, -8, 0.14, 0),
				Position = UDim2.new(0, 4, 0.85, 0),
				TextColor3 = if has then Color3.fromRGB(110, 255, 110) else Color3.fromRGB(255, 230, 120),
				Font = Theme.font,
				MaxText = 16,
			})
		end
		-- How far, and the reward
		local bar = Instance.new("Frame")
		bar.Position = UDim2.new(0, 0, 1, -48)
		bar.Size = UDim2.new(0.66, -8, 0, 40)
		bar.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
		Theme.round(bar, 12)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(if pageAll > 0 then pageGot / pageAll else 0, 1)
		Theme.gradient(fill, Theme.green, 0.25, 0.1)
		Theme.round(fill, 12)
		fill.Parent = bar
		Theme.bold(bar, { Text = ("%d/%d"):format(pageGot, pageAll), Size = UDim2.new(1, 0, 1, -6), Position = UDim2.fromOffset(0, 3), MaxText = 30 })
		bar.Parent = page
		local reward = IndexConfig.REWARDS[tier]
		local box = Theme.card(page, Color3.fromRGB(40, 110, 60), { Position = UDim2.new(0.66, 4, 0, 40), Size = UDim2.new(0.34, -4, 1, -40) })
		Theme.bold(box, { Text = "Page complete:", Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 24 })
		if reward then
			Theme.bold(box, { Text = "🪙 " .. Format.abbrev(reward.coins), Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 48), TextColor3 = Color3.fromRGB(255, 225, 110), MaxText = 34 })
			Theme.bold(box, { Text = "⚡ +" .. Format.abbrev(reward.power), Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 94), TextColor3 = Color3.fromRGB(150, 210, 255), MaxText = 34 })
		end
		local taken = claimed[tostring(tier)] == true
		local ready = Index.claimable(found, claimed, tier) ~= nil
		local claim = Theme.button(box, if taken then "CLAIMED ✓" else "CLAIM!", if ready then Theme.green else Theme.gray, function()
			if ready then
				Net.event("ClaimIndex"):FireServer(tier)
			end
		end)
		claim.AnchorPoint = Vector2.new(0.5, 1)
		claim.Position = UDim2.new(0.5, 0, 1, -12)
		claim.Size = UDim2.new(1, -24, 0, 56)
	end

	Windows.register("Index", window, rebuild)
	Store.Changed:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
end

return IndexWindow
