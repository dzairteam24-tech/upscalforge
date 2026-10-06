-- Shop window: coin upgrades, free video rewards, the gem shop and Robux products.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local Upgrades = require(Shared.Config.Upgrades)
local Items = require(Shared.Config.Items)
local GemShopConfig = require(Shared.Config.GemShop)
local Format = require(Shared.Logic.Format)
local GemShop = require(Shared.Logic.GemShop)
local Progress = require(Shared.Logic.Progress)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local AdButton = require(script.Parent.AdButton)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local ShopPanel = {}

function ShopPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Shop", function()
		Windows.close("Shop")
	end)

	local tabs = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) })
	tabs.Parent = content
	local function tab(text: string, index: number): TextButton
		local b = Theme.button({
			Text = text,
			Size = UDim2.new(1 / 4, -6, 1, -4),
			Position = UDim2.new((index - 1) / 4, 3, 0, 0),
			BackgroundColor3 = Theme.card,
			MaxTextSize = 20,
		})
		b.Parent = tabs
		return b
	end
	local upgradesTab = tab("🪙 Upgrades", 1)
	local gemsTab = tab("💎 Gems", 2)
	local freeTab = tab("▶ Free", 3)
	local robuxTab = tab("⭐ Robux", 4)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 48)
	scroll.Size = UDim2.new(1, 0, 1, -48)
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	Theme.list(scroll, 8)
	scroll.Parent = content

	local current = "Upgrades"

	local function row(order: number, title: string, subtitle: string, buttonText: string, enabled: boolean, onBuy: () -> ())
		local frame = Theme.frame({ Size = UDim2.new(1, -12, 0, 64), BackgroundColor3 = Theme.card, LayoutOrder = order })
		Theme.corner(frame, 10)
		local t = Theme.label({
			Text = title,
			Font = Theme.titleFont,
			Size = UDim2.new(0.68, 0, 0.5, 0),
			Position = UDim2.fromOffset(12, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 20,
		})
		t.Parent = frame
		local st = Theme.label({
			Text = subtitle,
			Font = Enum.Font.Gotham,
			TextColor3 = Theme.muted,
			Size = UDim2.new(0.68, 0, 0.4, 0),
			Position = UDim2.new(0, 12, 0.52, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 15,
		})
		st.Parent = frame
		local b = Theme.button({
			Text = buttonText,
			Size = UDim2.new(0.28, 0, 1, -16),
			Position = UDim2.new(0.7, 0, 0, 8),
			BackgroundColor3 = if enabled then Theme.green else Theme.card,
			MaxTextSize = 18,
		})
		b.Active = enabled
		b.AutoButtonColor = enabled
		b.Activated:Connect(function()
			if enabled then
				onBuy()
			end
		end)
		b.Parent = frame
		frame.Parent = scroll
	end

	local function rebuild()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		upgradesTab.BackgroundColor3 = if current == "Upgrades" then Theme.gold else Theme.card
		freeTab.BackgroundColor3 = if current == "Free" then Theme.gold else Theme.card
		robuxTab.BackgroundColor3 = if current == "Robux" then Theme.gold else Theme.card
		gemsTab.BackgroundColor3 = if current == "Gems" then Theme.gold else Theme.card
		local data = Store.data
		if not data then
			return
		end
		if current == "Upgrades" then
			for order, upgrade in Upgrades.list do
				local level = data.upgrades[upgrade.id] or 0
				local cost = Upgrades.nextCost(upgrade.id, level)
				local max = Upgrades.maxLevel(upgrade.id)
				local needs = upgrade.requires and (data.upgrades[upgrade.requires] or 0) < 1
				local subtitle = ("%s · Level %d/%d"):format(upgrade.description, level, max)
				if needs and upgrade.requires then
					subtitle = "Needs " .. Upgrades.byId[upgrade.requires].name
				end
				row(order, upgrade.name, subtitle, if cost then "🪙 " .. Format.abbrev(cost) else "MAX", cost ~= nil and not needs, function()
					Net.event("BuyUpgrade"):FireServer(upgrade.id)
				end)
			end
		elseif current == "Gems" then
			local today = Progress.day(workspace:GetServerTimeNow())
			local gems: number = data.gems or 0
			local state = data.gemShop or { day = -1, deals = {}, storage = 0 }
			local holder = {
				gems = gems,
				gemShop = { day = state.day, deals = if state.day == today then state.deals else {}, storage = state.storage },
				stats = data.stats,
				unlockedZones = data.unlockedZones,
			}
			local order = 0
			local function header(text: string)
				order += 1
				local label = Theme.label({
					Text = text,
					Font = Theme.titleFont,
					Size = UDim2.new(1, -12, 0, 28),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = order,
					MaxTextSize = 20,
				})
				label.Parent = scroll
			end
			local function offerRow(id: string, asDeal: boolean)
				local offer = GemShopConfig.byId[id]
				local price = GemShop.price(holder, id, asDeal)
				local ok = GemShop.canBuy(holder, id, asDeal, today)
				local title, subtitle
				if offer.itemId then
					local item = Items.byId[offer.itemId]
					title = (item.icon or "") .. " " .. item.name
					subtitle = item.description
				else
					title = "📦 Storage +" .. GemShopConfig.STORAGE_STEP
					subtitle = ("More creature storage, forever (%d/%d)"):format(holder.gemShop.storage, GemShopConfig.STORAGE_MAX)
				end
				if asDeal then
					title = ("🔥 -%d%% %s"):format(math.floor(GemShopConfig.DEAL_DISCOUNT * 100), title)
				end
				local bought = asDeal and holder.gemShop.deals[id] == true
				local maxed = offer.upgrade == "Storage" and holder.gemShop.storage >= GemShopConfig.STORAGE_MAX
				order += 1
				row(order, title, subtitle, if bought then "Bought ✓" elseif maxed then "MAX" else "💎 " .. Format.abbrev(price), ok, function()
					Net.event("BuyGemItem"):FireServer(id, asDeal)
				end)
			end

			header(("💎 %s gems · daily deals reset in %s"):format(Format.abbrev(gems), Format.time(Progress.secondsToNextDay(os.time()))))
			for _, id in GemShop.deals(today) do
				local offer = GemShopConfig.byId[id]
				if offer.feature == nil or table.find(GemShop.visible(holder), offer) then
					offerRow(id, true)
				end
			end
			header("Everything")
			for _, offer in GemShop.visible(holder) do
				offerRow(offer.id, false)
			end
		elseif current == "Free" then
			local supported = AdButton.supported()
			local note = Theme.label({
				Text = if supported
					then ("Watch a short video to get a reward. Boost time stacks up to %d hours."):format(Items.BOOST_CAP_SECONDS // 3600)
					else "Videos aren't available for your account (Roblox shows them to players 13+ in some countries). Daily rewards, gifts, quests and the Lucky Spin are always free!",
				Font = Enum.Font.Gotham,
				TextColor3 = Theme.muted,
				Size = UDim2.new(1, -12, 0, if supported then 30 else 48),
				LayoutOrder = 0,
				MaxTextSize = 15,
			})
			note.Parent = scroll
			if supported then
				for order, reward in Products.adRewards do
					if not reward.inShop then
						continue
					end
					local product = Products.productByKey[reward.key]
					local configured = product ~= nil and product.id ~= 0
					local wait = AdButton.cooldown(reward.key)
					local subtitle = if reward.cooldown then "Free · once an hour" else "Free · watch a video"
					local action = if not configured then "Soon" elseif wait > 0 then Format.time(wait) else "▶ Watch"
					row(order, reward.label, subtitle, action, configured and wait <= 0, function()
						AdButton.watch(reward.key)
					end)
				end
			end
		else
			local order = 0
			local function section(text: string)
				order += 1
				local label = Theme.label({
					Text = text,
					Font = Theme.titleFont,
					Size = UDim2.new(1, -12, 0, 28),
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = order,
					MaxTextSize = 20,
				})
				label.Parent = scroll
			end
			local function robux(price: number): string
				return "R$ " .. price
			end
			order += 1
			local note = Theme.label({
				Text = "Eggs, luck, creatures and coins are never sold. Robux buys time, comfort and looks.",
				Font = Enum.Font.Gotham,
				TextColor3 = Theme.muted,
				Size = UDim2.new(1, -12, 0, 30),
				LayoutOrder = order,
				MaxTextSize = 15,
			})
			note.Parent = scroll

			-- Game passes
			section("🎫 Game Passes (forever)")
			for _, pass in Products.gamePasses do
				order += 1
				local owned = data.passes ~= nil and data.passes[pass.key] == true
				row(order, pass.name, pass.description, if owned then "Owned" elseif pass.id == 0 then "Soon" else robux(pass.price), not owned and pass.id ~= 0, function()
					MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.id)
				end)
			end

			-- Boosts, then looks (auras and hatch effects are kept forever)
			local function productRows(wantCosmetic: boolean)
				for _, product in Products.devProducts do
					local cosmetic = product.cosmetic
					if not product.inShop or (cosmetic ~= nil) ~= wantCosmetic then
						continue
					end
					order += 1
					local owned = (product.key == "SupporterTitle" and data.titles.Supporter)
						or (cosmetic ~= nil and cosmetic.kind == "aura" and (data.auras or {})[cosmetic.id] == true)
						or (cosmetic ~= nil and cosmetic.kind == "hatchFx" and (data.hatchFx or {})[cosmetic.id] == true)
					row(order, product.name, product.description, if owned then "Owned" elseif product.id == 0 then "Soon" else robux(product.price), not owned and product.id ~= 0, function()
						AdButton.buy(product.key)
					end)
				end
			end
			section("🚀 Boosts and titles")
			productRows(false)
			local pass = Products.productByKey.PassPremium
			if pass then
				order += 1
				local owned = data.pass.premium
				row(order, pass.name, pass.description, if owned then "Owned" elseif pass.id == 0 then "Soon" else robux(pass.price), not owned and pass.id ~= 0, function()
					AdButton.buy(pass.key)
				end)
			end

			section("✨ Auras and hatch effects (yours forever)")
			productRows(true)

			-- Roblox Premium
			section("⭐ Roblox Premium")
			order += 1
			local premium = data.premium == true
			row(order, "Premium perks", ("Coins +%d%% while you're a Roblox Premium member"):format(math.floor((Products.PREMIUM_COINS - 1) * 100 + 0.5)), if premium then "Active ✓" else "Get Premium", not premium, function()
				MarketplaceService:PromptPremiumPurchase(Players.LocalPlayer)
			end)
		end
	end

	upgradesTab.Activated:Connect(function()
		current = "Upgrades"
		rebuild()
	end)
	robuxTab.Activated:Connect(function()
		current = "Robux"
		rebuild()
	end)
	gemsTab.Activated:Connect(function()
		current = "Gems"
		rebuild()
	end)
	freeTab.Activated:Connect(function()
		current = "Free"
		rebuild()
	end)
	Store.DataChanged:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	Windows.register("Shop", window, rebuild)
end

return ShopPanel
