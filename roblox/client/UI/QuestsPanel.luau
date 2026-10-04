-- Quests (daily + weekly), the Battle Pass, and character style (titles and trails).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Products = require(Shared.Config.Products)
local Progression = require(Shared.Config.Progression)
local Format = require(Shared.Logic.Format)
local Progress = require(Shared.Logic.Progress)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local AdButton = require(script.Parent.AdButton)
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
	for i, name in { "Quests", "Pass", "Style" } do
		local b = Theme.button({
			Text = name,
			Size = UDim2.new(1 / 3, -6, 1, -4),
			Position = UDim2.new((i - 1) / 3, 3, 0, 0),
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
			if kind == "daily" and not done and not quest.claimed and AdButton.available("AdReroll") then
				text.Size = UDim2.new(0.5, 0, 0, 24)
				local swap = Theme.button({
					Text = "▶ Swap",
					Size = UDim2.new(0.15, 0, 0, 24),
					Position = UDim2.new(0.52, 0, 0, 6),
					BackgroundColor3 = Theme.purple,
					MaxTextSize = 13,
				})
				swap.Activated:Connect(function()
					AdButton.watch("AdReroll", i)
				end)
				swap.Parent = row
			end
			row.Parent = body
			order += 1
		end
		return order
	end

	local function showQuests()
		setLayout(false)
		local now = os.time()
		local order = questRows("daily", ("Daily · new in %s"):format(Format.time(Progress.secondsToNextDay(now))), 1)
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
			if not pass.premium and product and product.id ~= 0 then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.id)
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
		order += 1
		local hint = Theme.label({
			Text = "Get more titles and trails from the Battle Pass premium track.",
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
