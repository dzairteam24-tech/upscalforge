-- Quests (daily + weekly), the Battle Pass, and character style (titles and trails).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BountyConfig = require(Shared.Config.Bounty)
local JourneyConfig = require(Shared.Config.Journey)
local Cosmetics = require(Shared.Config.Cosmetics)
local Products = require(Shared.Config.Products)
local Progression = require(Shared.Config.Progression)
local FirstClearConfig = require(Shared.Config.FirstClear)
local FirstClear = require(Shared.Logic.FirstClear)
local Format = require(Shared.Logic.Format)
local Progress = require(Shared.Logic.Progress)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local AchievementsView = require(script.Parent.AchievementsView)
local AdButton = require(script.Parent.AdButton)
local PetCard = require(script.Parent.PetCard)
local Rewards = require(script.Parent.Rewards)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local QuestsPanel = {}

-- True when any quest or pass level can be claimed (for the menu dot).
function QuestsPanel.hasClaimable(): boolean
	local data = Store.data
	if not data then
		return false
	end
	local live = Store.currency.questProgress
	for _, kind in { "daily", "weekly" } do
		for i, quest in data.quests[kind] do
			local progress = if live and live[kind] and live[kind][i] then live[kind][i] else quest.progress
			if not quest.claimed and progress >= quest.goal then
				return true
			end
		end
	end
	local level = Progress.passLevel(data.pass.xp)
	for l = 1, level do
		if not data.pass.claimedFree[tostring(l)] and Progression.passReward(l, false) then
			return true
		end
	end
	return false
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function progressBar(parent: Instance, fraction: number, position: UDim2, size: UDim2): Frame
	local back = Theme.frame({ Position = position, Size = size, BackgroundColor3 = Color3.fromRGB(20, 24, 38) })
	Theme.corner(back, 6)
	local fill = Theme.frame({ Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1), BackgroundColor3 = Theme.green })
	Theme.corner(fill, 6)
	fill.Parent = back
	back.Parent = parent
	return back
end

function QuestsPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Quests & Pass", function()
		Windows.close("Quests")
	end)

	local tabs = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) })
	tabs.Parent = content
	local tabButtons = {}
	local current = "Quests"
	local TABS = { "Quests", "Pass", "Awards", "Style" }
	for i, name in TABS do
		local b = Theme.button({
			Text = name,
			Size = UDim2.new(1 / #TABS, -6, 1, -4),
			Position = UDim2.new((i - 1) / #TABS, 3, 0, 0),
			BackgroundColor3 = Theme.card,
		})
		b.Parent = tabs
		tabButtons[name] = b
	end

	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(0, 48)
	body.Size = UDim2.new(1, 0, 1, -48)
	body.ScrollBarThickness = 8
	body.AutomaticCanvasSize = Enum.AutomaticSize.XY
	body.CanvasSize = UDim2.new()
	body.Parent = content

	local layout: UIListLayout? = nil
	local function setLayout(horizontal: boolean)
		if layout then
			layout:Destroy()
		end
		layout = Theme.list(body, 8, horizontal)
	end

	local function questRows(kind: string, header: string, order: number): number
		local data = Store.data
		if not data then
			return order
		end
		local title = Theme.label({
			Text = header,
			Font = Theme.titleFont,
			Size = UDim2.new(1, -12, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			MaxTextSize = 20,
		})
		title.Parent = body
		order += 1
		local live = Store.currency.questProgress
		for i, quest in data.quests[kind] do
			local template = Progress.template(quest.id)
			local progress = if live and live[kind] and live[kind][i] then live[kind][i] else quest.progress
			local row = Theme.frame({ Size = UDim2.new(1, -12, 0, 62), BackgroundColor3 = Theme.card, LayoutOrder = order })
			Theme.corner(row, 10)
			local text = Theme.label({
				Text = if template then (template.text:gsub("{goal}", Format.abbrev(quest.goal))) else quest.id,
				Size = UDim2.new(0.66, 0, 0, 24),
				Position = UDim2.fromOffset(10, 6),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 17,
			})
			text.Parent = row
			progressBar(row, progress / math.max(1, quest.goal), UDim2.fromOffset(10, 36), UDim2.new(0.5, 0, 0, 14))
			local count = Theme.label({
				Text = ("%s / %s"):format(Format.abbrev(math.min(progress, quest.goal)), Format.abbrev(quest.goal)),
				Size = UDim2.new(0.14, 0, 0, 16),
				Position = UDim2.new(0.52, 14, 0, 35),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 13,
			})
			count.Parent = row
			local reward = if kind == "daily" then Progression.DAILY_QUEST_REWARD else Progression.WEEKLY_QUEST_REWARD
			local done = progress >= quest.goal
			local b = Theme.button({
				Text = if quest.claimed then "Claimed" elseif done then "Claim" else Rewards.describe(reward, data):gsub("\n", " · "),
				Size = UDim2.new(0.3, 0, 1, -14),
				Position = UDim2.new(0.69, 0, 0, 7),
				BackgroundColor3 = if done and not quest.claimed then Theme.green else Theme.panel,
				MaxTextSize = 15,
			})
			b.Activated:Connect(function()
				if done and not quest.claimed then
					Net.event("ClaimQuest"):FireServer(kind, i)
				end
			end)
			b.Parent = row
			if kind == "daily" and not done and not quest.claimed and AdButton.offer("AdReroll", "QuestSwap") ~= nil then
				text.Size = UDim2.new(0.5, 0, 0, 24)
				local swap = Theme.button({
					Text = AdButton.label("AdReroll", "QuestSwap", "Swap"),
					Size = UDim2.new(0.15, 0, 0, 24),
					Position = UDim2.new(0.52, 0, 0, 6),
					BackgroundColor3 = Theme.purple,
					MaxTextSize = 13,
				})
				swap.Activated:Connect(function()
					AdButton.take("AdReroll", "QuestSwap", i)
				end)
				swap.Parent = row
			end
			row.Parent = body
			order += 1
		end
		return order
	end

	-- Journey: Professor Cubo's current step
	local function journeyRows(order: number): number
		local data = Store.data
		local journey = data and (data :: any).journey
		if not journey then
			return order
		end
		local step = JourneyConfig.steps[journey.step]
		local title = Theme.label({
			Text = if step
				then ("📖 Journey · step %d of %d"):format(journey.step, #JourneyConfig.steps)
				else "📖 Journey complete! You're a Valley Hero.",
			Font = Theme.titleFont,
			Size = UDim2.new(1, -12, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			MaxTextSize = 20,
		})
		title.Parent = body
		order += 1
		if not step then
			return order
		end
		local row = Theme.frame({ Size = UDim2.new(1, -12, 0, 92), BackgroundColor3 = Theme.card, LayoutOrder = order })
		Theme.corner(row, 10)
		Theme.stroke(row, Theme.accent, 2)
		local say = Theme.label({
			Text = ("%s: \"%s\""):format(JourneyConfig.NPC_NAME, step.say),
			Font = Enum.Font.GothamMedium,
			TextColor3 = Theme.muted,
			Size = UDim2.new(1, -20, 0, 30),
			Position = UDim2.fromOffset(10, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			MaxTextSize = 14,
		})
		say.Parent = row
		local text = Theme.label({
			Text = step.text,
			Size = UDim2.new(0.66, 0, 0, 22),
			Position = UDim2.fromOffset(10, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 17,
		})
		text.Parent = row
		local progress = math.min(journey.progress, step.goal)
		progressBar(row, progress / math.max(1, step.goal), UDim2.fromOffset(10, 64), UDim2.new(0.5, 0, 0, 14))
		local count = Theme.label({
			Text = ("%s / %s"):format(Format.abbrev(progress), Format.abbrev(step.goal)),
			Size = UDim2.new(0.14, 0, 0, 16),
			Position = UDim2.new(0.52, 14, 0, 63),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 13,
		})
		count.Parent = row
		local done = journey.progress >= step.goal
		local b = Theme.button({
			Text = if done then "Claim" else (Rewards.describe(step.reward, data :: any):gsub("\n", " · ")),
			Size = UDim2.new(0.3, 0, 0, 46),
			Position = UDim2.new(0.69, 0, 0, 38),
			BackgroundColor3 = if done then Theme.green else Theme.panel,
			MaxTextSize = 15,
		})
		b.Activated:Connect(function()
			if done then
				Net.event("ClaimJourney"):FireServer()
			end
		end)
		b.Parent = row
		row.Parent = body
		return order + 1
	end

	-- Daily Bounty: three creatures to hatch today
	-- First clears: permanent bonuses for the first win against each guardian and the World Boss
	local function clearRows(order: number): number
		local data = Store.data
		local clears = data and (data :: any).clears
		if not clears then
			return order
		end
		local guardians = FirstClear.guardians(clears)
		local label = Theme.label({
			Text = ("⭐ First clears · guardians %d/10 (Coins +%d%% forever) · World Boss %s"):format(
				guardians,
				math.floor(guardians * FirstClearConfig.GUARDIAN_COINS * 100 + 0.5),
				if clears.Boss then ("✓ (Luck +%d%%)"):format(FirstClearConfig.BOSS_LUCK * 100) else "not yet"
			),
			Font = Enum.Font.GothamMedium,
			TextColor3 = Theme.gold,
			Size = UDim2.new(1, -12, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			MaxTextSize = 15,
		})
		label.Parent = body
		return order + 1
	end

	local function bountyRows(order: number): number
		local data = Store.data
		local bounty = data and (data :: any).bounty
		if not bounty or not bounty.targets or #bounty.targets == 0 then
			return order
		end
		local title = Theme.label({
			Text = "🎯 Daily Bounty · hatch these today",
			Font = Theme.titleFont,
			Size = UDim2.new(1, -12, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			MaxTextSize = 20,
		})
		title.Parent = body
		order += 1
		for index, target in bounty.targets do
			local done = bounty.done[index] == true
			local row = Theme.frame({ Size = UDim2.new(1, -12, 0, 62), BackgroundColor3 = Theme.card, LayoutOrder = order })
			Theme.corner(row, 10)
			if not done and target.tier == 3 then
				Theme.stroke(row, Theme.gold, 2)
			end
			local iconHolder = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(4, 3) })
			iconHolder.Parent = row
			PetCard.icon({ s = target.species, v = target.variant, z = "Normal" }, iconHolder)
			local name = if target.variant == "Normal" then target.species else target.variant .. " " .. target.species
			local text = Theme.label({
				Text = ("%s · Hatch a %s"):format(BountyConfig.TIER_NAMES[target.tier], name),
				Size = UDim2.new(0.6, -64, 0, 24),
				Position = UDim2.fromOffset(66, 8),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 17,
			})
			text.Parent = row
			local sub = Theme.label({
				Text = if target.variant == "Normal" then "Any variant counts" else ("%s or rarer counts"):format(target.variant),
				Font = Enum.Font.Gotham,
				TextColor3 = Theme.muted,
				Size = UDim2.new(0.6, -64, 0, 18),
				Position = UDim2.fromOffset(66, 34),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 13,
			})
			sub.Parent = row
			local reward = Theme.label({
				Text = if done then "✅ Done" else (Rewards.describe(BountyConfig.REWARDS[target.tier], data :: any):gsub("\n", " · ")),
				TextColor3 = if done then Theme.green else Theme.text,
				Size = UDim2.new(0.36, 0, 1, -14),
				Position = UDim2.new(0.63, 0, 0, 7),
				MaxTextSize = 15,
			})
			reward.Parent = row
			row.Parent = body
			order += 1
		end
		return order
	end

	local function showQuests()
		setLayout(false)
		local now = os.time()
		local order = journeyRows(1)
		order = clearRows(order)
		order = bountyRows(order)
		order = questRows("daily", ("Daily · new in %s"):format(Format.time(Progress.secondsToNextDay(now))), order)
		questRows("weekly", "Weekly · new every Monday", order)
	end

	local function showPass()
		setLayout(false)
		local data = Store.data
		if not data then
			return
		end
		local pass = data.pass
		local level = Progress.passLevel(pass.xp)
		local header = Theme.frame({ Size = UDim2.new(1, -12, 0, 70), BackgroundColor3 = Theme.card, LayoutOrder = 1 })
		Theme.corner(header, 10)
		local headerText = Theme.label({
			Text = ("Season %d · Level %d/%d · ends in %s"):format(
				pass.season,
				level,
				Progression.PASS_LEVELS,
				Format.time(Progress.seasonSecondsLeft(os.time()))
			),
			Font = Theme.titleFont,
			Size = UDim2.new(0.66, 0, 0, 26),
			Position = UDim2.fromOffset(10, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 18,
		})
		headerText.Parent = header
		local into = pass.xp % Progression.PASS_XP_PER_LEVEL
		progressBar(header, if level >= Progression.PASS_LEVELS then 1 else into / Progression.PASS_XP_PER_LEVEL, UDim2.fromOffset(10, 42), UDim2.new(0.6, 0, 0, 14))
		local product = Products.productByKey.PassPremium
		local premiumButton = Theme.button({
			Text = if pass.premium then "Premium ✓" elseif product and product.id ~= 0 then "Unlock Premium" else "Premium: soon",
			Size = UDim2.new(0.3, 0, 1, -14),
			Position = UDim2.new(0.69, 0, 0, 7),
			BackgroundColor3 = if pass.premium then Theme.panel else Theme.gold,
			MaxTextSize = 17,
		})
		premiumButton.Activated:Connect(function()
			-- Through the server like every product, so its checks (already owned...) run
			if not pass.premium and product and product.id ~= 0 then
				AdButton.buy(product.key)
			end
		end)
		premiumButton.Parent = header
		header.Parent = body

		local note = Theme.label({
			Text = "Earn XP from quests. Premium gives titles and trails only, never power.",
			Font = Enum.Font.Gotham,
			TextColor3 = Theme.muted,
			Size = UDim2.new(1, -12, 0, 22),
			LayoutOrder = 2,
			MaxTextSize = 14,
		})
		note.Parent = body

		local strip = Instance.new("ScrollingFrame")
		strip.BackgroundTransparency = 1
		strip.BorderSizePixel = 0
		strip.Size = UDim2.new(1, -12, 0, 250)
		strip.ScrollBarThickness = 8
		strip.ScrollingDirection = Enum.ScrollingDirection.X
		strip.AutomaticCanvasSize = Enum.AutomaticSize.X
		strip.CanvasSize = UDim2.new()
		strip.LayoutOrder = 3
		Theme.list(strip, 6, true)
		strip.Parent = body

		for l = 1, Progression.PASS_LEVELS do
			local column = Theme.frame({ Size = UDim2.fromOffset(118, 236), BackgroundColor3 = if l <= level then Theme.card else Theme.panel, LayoutOrder = l })
			Theme.corner(column, 10)
			local number = Theme.label({ Text = "Lv " .. l, Font = Theme.titleFont, Size = UDim2.new(1, 0, 0, 24), MaxTextSize = 18 })
			number.Parent = column
			for track, premium in { false, true } do
				local reward = Progression.passReward(l, premium)
				local claimed = if premium then pass.claimedPremium[tostring(l)] else pass.claimedFree[tostring(l)]
				local y = 28 + (track - 1) * 104
				local box = Theme.frame({
					Position = UDim2.fromOffset(4, y),
					Size = UDim2.new(1, -8, 0, 98),
					BackgroundColor3 = if premium then Color3.fromRGB(80, 64, 30) else Color3.fromRGB(34, 60, 80),
				})
				Theme.corner(box, 8)
				box.Parent = column
				if reward then
					local text = Theme.label({
						Text = Rewards.describe(reward, data),
						Font = Enum.Font.Gotham,
						Size = UDim2.new(1, -6, 0, 60),
						Position = UDim2.fromOffset(3, 2),
						MaxTextSize = 13,
					})
					text.Parent = box
					local canClaim = l <= level and not claimed and (not premium or pass.premium)
					local b = Theme.button({
						Text = if claimed then "✓" elseif canClaim then "Claim" else (if premium and not pass.premium then "🔒" else "—"),
						Size = UDim2.new(1, -10, 0, 28),
						Position = UDim2.fromOffset(5, 66),
						BackgroundColor3 = if canClaim then Theme.green else Theme.panel,
						MaxTextSize = 15,
					})
					b.Activated:Connect(function()
						if canClaim then
							Net.event("ClaimPass"):FireServer(l, premium)
						end
					end)
					b.Parent = box
				end
			end
			column.Parent = strip
		end
	end

	local function showStyle()
		setLayout(false)
		local data = Store.data
		if not data then
			return
		end
		local order = 0
		local function section(title: string)
			order += 1
			local label = Theme.label({
				Text = title,
				Font = Theme.titleFont,
				Size = UDim2.new(1, -12, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = order,
				MaxTextSize = 20,
			})
			label.Parent = body
		end
		local function row(text: string, color: Color3, equipped: boolean, onEquip: () -> ())
			order += 1
			local frame = Theme.frame({ Size = UDim2.new(1, -12, 0, 48), BackgroundColor3 = Theme.card, LayoutOrder = order })
			Theme.corner(frame, 10)
			local label = Theme.label({
				Text = text,
				Font = Theme.titleFont,
				TextColor3 = color,
				Size = UDim2.new(0.65, 0, 1, -8),
				Position = UDim2.fromOffset(12, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 20,
			})
			label.Parent = frame
			local b = Theme.button({
				Text = if equipped then "Equipped" else "Equip",
				Size = UDim2.new(0.3, 0, 1, -12),
				Position = UDim2.new(0.68, 0, 0, 6),
				BackgroundColor3 = if equipped then Theme.panel else Theme.green,
			})
			b.Activated:Connect(onEquip)
			b.Parent = frame
			frame.Parent = body
		end
		section("Titles")
		row("None", Theme.muted, data.equippedTitle == nil, function()
			Net.event("EquipCosmetic"):FireServer("title", "")
		end)
		for _, title in Cosmetics.titles do
			if data.titles[title.id] then
				row(title.text, title.color, data.equippedTitle == title.id, function()
					Net.event("EquipCosmetic"):FireServer("title", title.id)
				end)
			end
		end
		section("Rides (+25% speed, all the same)")
		row("None", Theme.muted, data.equippedRide == nil, function()
			Net.event("EquipCosmetic"):FireServer("ride", "")
		end)
		for _, ride in Cosmetics.rides do
			if data.rides and data.rides[ride.id] then
				row(ride.name, ride.glow, data.equippedRide == ride.id, function()
					Net.event("EquipCosmetic"):FireServer("ride", ride.id)
				end)
			end
		end
		section("Trails")
		row("None", Theme.muted, data.equippedTrail == nil, function()
			Net.event("EquipCosmetic"):FireServer("trail", "")
		end)
		for _, trail in Cosmetics.trails do
			if data.trails[trail.id] then
				row(trail.name, trail.colors[1], data.equippedTrail == trail.id, function()
					Net.event("EquipCosmetic"):FireServer("trail", trail.id)
				end)
			end
		end
		-- Looks sold for Robux: owned ones can be equipped, the others show their price
		local function forSale(kind: string, id: string): Products.DevProduct?
			for _, product in Products.devProducts do
				local cosmetic = product.cosmetic
				if cosmetic and cosmetic.kind == kind and cosmetic.id == id then
					return product
				end
			end
			return nil
		end
		local function buyRow(text: string, color: Color3, product: Products.DevProduct)
			order += 1
			local frame = Theme.frame({ Size = UDim2.new(1, -12, 0, 48), BackgroundColor3 = Theme.card, LayoutOrder = order })
			Theme.corner(frame, 10)
			local label = Theme.label({
				Text = text,
				Font = Theme.titleFont,
				TextColor3 = color,
				TextTransparency = 0.35,
				Size = UDim2.new(0.65, 0, 1, -8),
				Position = UDim2.fromOffset(12, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 20,
			})
			label.Parent = frame
			local b = Theme.button({
				Text = if product.id == 0 then "Soon" else "R$ " .. product.price,
				Size = UDim2.new(0.3, 0, 1, -12),
				Position = UDim2.new(0.68, 0, 0, 6),
				BackgroundColor3 = if product.id == 0 then Theme.panel else Theme.gold,
			})
			b.Activated:Connect(function()
				if product.id ~= 0 then
					AdButton.buy(product.key)
				end
			end)
			b.Parent = frame
			frame.Parent = body
		end
		local auras = data.auras or {}
		section("Auras (look only)")
		row("None", Theme.muted, data.equippedAura == nil, function()
			Net.event("EquipCosmetic"):FireServer("aura", "")
		end)
		for _, aura in Cosmetics.auras do
			if auras[aura.id] then
				row(aura.name, aura.colors[1], data.equippedAura == aura.id, function()
					Net.event("EquipCosmetic"):FireServer("aura", aura.id)
				end)
			else
				local product = forSale("aura", aura.id)
				if product then
					buyRow(aura.name, aura.colors[1], product)
				end
			end
		end
		local hatchFx = data.hatchFx or {}
		section("Hatch effects (same odds, just prettier)")
		row("Classic", Theme.muted, data.equippedHatchFx == nil, function()
			Net.event("EquipCosmetic"):FireServer("hatchFx", "")
		end)
		for _, fx in Cosmetics.hatchFx do
			if hatchFx[fx.id] then
				row(fx.name, fx.colors[1], data.equippedHatchFx == fx.id, function()
					Net.event("EquipCosmetic"):FireServer("hatchFx", fx.id)
				end)
			else
				local product = forSale("hatchFx", fx.id)
				if product then
					buyRow(fx.name, fx.colors[1], product)
				end
			end
		end
		order += 1
		local hint = Theme.label({
			Text = "Get more titles, trails and rides from achievements, Rank, the Lucky Spin and the Battle Pass premium track.",
			Font = Enum.Font.Gotham,
			TextColor3 = Theme.muted,
			Size = UDim2.new(1, -12, 0, 24),
			LayoutOrder = order,
			MaxTextSize = 14,
		})
		hint.Parent = body
	end

	local function rebuild()
		clear(body)
		for name, b in tabButtons do
			b.BackgroundColor3 = if name == current then Theme.gold else Theme.card
		end
		if current == "Quests" then
			showQuests()
		elseif current == "Pass" then
			showPass()
		elseif current == "Awards" then
			setLayout(false)
			if Store.data then
				AchievementsView.build(body, Store.data)
			end
		else
			showStyle()
		end
	end

	for name, b in tabButtons do
		b.Activated:Connect(function()
			current = name
			rebuild()
		end)
	end
	Store.DataChanged:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	Windows.register("Quests", window, rebuild)
end

return QuestsPanel
