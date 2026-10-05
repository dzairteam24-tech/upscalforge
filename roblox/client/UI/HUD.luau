-- Always-on screen: coins, gems, team power, zone progress, combo, boosts and the menu buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World1 = require(Shared.Config.World1)
local Format = require(Shared.Logic.Format)
local Unlocks = require(Shared.Logic.Unlocks)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local DailyPanel = require(script.Parent.DailyPanel)
local QuestsPanel = require(script.Parent.QuestsPanel)
local ReloadPanel = require(script.Parent.ReloadPanel)
local SpinPanel = require(script.Parent.SpinPanel)
local TripsPanel = require(script.Parent.TripsPanel)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local HUD = {}

local function pill(parent: Instance, icon: string, color: Color3, order: number): TextLabel
	local frame = Theme.frame({
		Size = UDim2.fromOffset(170, 40),
		BackgroundColor3 = Theme.bg,
		BackgroundTransparency = 0.15,
		LayoutOrder = order,
	})
	Theme.corner(frame, 20)
	Theme.stroke(frame, color, 2)
	local iconLabel = Theme.label({
		Text = icon,
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(4, 3),
		MaxTextSize = 24,
	})
	iconLabel.Parent = frame
	local value = Theme.label({
		Text = "0",
		Font = Theme.titleFont,
		TextColor3 = color,
		Size = UDim2.new(1, -46, 1, -8),
		Position = UDim2.fromOffset(40, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
	})
	value.Parent = frame
	frame.Parent = parent
	return value
end

function HUD.mount(gui: ScreenGui)
	-- Top-left currencies
	local top = Theme.frame({
		Name = "Currencies",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(180, 140),
	})
	Theme.list(top, 6)
	local coins = pill(top, "🪙", Theme.gold, 1)
	local gems = pill(top, "💎", Color3.fromRGB(120, 220, 255), 2)
	local power = pill(top, "⚡", Color3.fromRGB(255, 140, 90), 3)
	top.Parent = gui

	local settingsButton = Theme.button({
		Name = "Settings",
		Text = "⚙️",
		Position = UDim2.fromOffset(190, 12),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Theme.card,
		MaxTextSize = 22,
	})
	settingsButton.Parent = gui
	settingsButton.Activated:Connect(function()
		Windows.toggle("Settings")
	end)

	-- Playtime gift: counts down, then glows until opened
	local giftButton = Theme.button({
		Name = "Gift",
		Text = "🎁",
		Position = UDim2.fromOffset(236, 12),
		Size = UDim2.fromOffset(112, 40),
		BackgroundColor3 = Theme.card,
		MaxTextSize = 20,
	})
	giftButton.Parent = gui
	giftButton.Activated:Connect(function()
		if Store.giftSecondsLeft() == 0 then
			Net.event("ClaimGift"):FireServer()
		end
	end)
	local function updateGift()
		local left = Store.giftSecondsLeft()
		giftButton.Visible = left ~= nil
		if left == nil then
			return
		end
		if left <= 0 then
			giftButton.Text = "🎁 Open!"
			giftButton.BackgroundColor3 = if os.clock() % 1 < 0.5 then Theme.gold else Theme.green
		else
			local s = math.ceil(left)
			giftButton.Text = ("🎁 %d:%02d"):format(s // 60, s % 60)
			giftButton.BackgroundColor3 = Theme.card
		end
	end
	local spinButton = Theme.button({
		Name = "Spin",
		Text = "🎰",
		Position = UDim2.fromOffset(354, 12),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Color3.fromRGB(255, 120, 200),
		MaxTextSize = 22,
	})
	spinButton.Parent = gui
	spinButton.Activated:Connect(function()
		Windows.toggle("Spin")
	end)
	local spinDot = Theme.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Theme.red,
		Visible = false,
	})
	Theme.corner(spinDot, 7)
	spinDot.Parent = spinButton
	local teleportButton = Theme.button({
		Name = "Teleport",
		Text = "🌀",
		Position = UDim2.fromOffset(400, 12),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Color3.fromRGB(110, 90, 200),
		MaxTextSize = 22,
	})
	teleportButton.Parent = gui
	teleportButton.Activated:Connect(function()
		Windows.toggle("Teleport")
	end)
	task.spawn(function()
		while true do
			updateGift()
			-- Leave room when the gift button is gone
			local x = if giftButton.Visible then 354 else 236
			spinButton.Position = UDim2.fromOffset(x, 12)
			teleportButton.Position = UDim2.fromOffset(x + 46, 12)
			local data = Store.data
			spinButton.Visible = data ~= nil and Unlocks.has(data :: any, "Spin")
			spinDot.Visible = SpinPanel.freeReady()
			teleportButton.Position = UDim2.fromOffset(if spinButton.Visible then x + 46 else x, 12)
			task.wait(0.5)
		end
	end)

	-- Zone name + restore bar (top center)
	local zoneFrame = Theme.frame({
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(280, 52),
		BackgroundColor3 = Theme.bg,
		BackgroundTransparency = 0.15,
	})
	Theme.corner(zoneFrame, 12)
	Theme.stroke(zoneFrame)
	local zoneName = Theme.label({
		Text = "",
		Font = Theme.titleFont,
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.fromOffset(8, 3),
		MaxTextSize = 22,
	})
	zoneName.Parent = zoneFrame
	local barBack = Theme.frame({
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.fromOffset(8, 31),
		BackgroundColor3 = Color3.fromRGB(20, 24, 38),
	})
	Theme.corner(barBack, 7)
	local barFill = Theme.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.green })
	Theme.corner(barFill, 7)
	barFill.Parent = barBack
	local barText = Theme.label({ Text = "", Size = UDim2.fromScale(1, 1), MaxTextSize = 12 })
	barText.Parent = barBack
	barBack.Parent = zoneFrame
	zoneFrame.Parent = gui

	-- Combo + boosts (right side)
	local comboLabel = Theme.label({
		Name = "Combo",
		Text = "",
		Font = Theme.titleFont,
		TextColor3 = Color3.fromRGB(255, 120, 60),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(220, 40),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 34,
	})
	comboLabel.Parent = gui
	local boostLabel = Theme.label({
		Name = "Boosts",
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 56),
		Size = UDim2.fromOffset(240, 90),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 16,
	})
	boostLabel.Parent = gui

	-- Rift banner (under the zone)
	local riftLabel = Theme.label({
		Name = "Rift",
		Text = "",
		Font = Theme.titleFont,
		TextColor3 = Color3.fromRGB(200, 160, 255),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(360, 24),
		MaxTextSize = 18,
	})
	riftLabel.Parent = gui

	-- Menu buttons (left middle), three short columns so it fits on phones
	local menu = Theme.frame({
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.58, 0),
		Size = UDim2.fromOffset(210, 174),
	})
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(66, 54)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = menu
	local function menuButton(text: string, color: Color3, order: number): TextButton
		local b = Theme.button({
			Text = text,
			BackgroundColor3 = color,
			LayoutOrder = order,
			MaxTextSize = 15,
		})
		b.Parent = menu
		return b
	end
	local function dot(button: TextButton): Frame
		local d = Theme.frame({
			Name = "Dot",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Theme.red,
			Visible = false,
		})
		Theme.corner(d, 8)
		d.Parent = button
		return d
	end
	menuButton("🐾\nPets", Theme.accent, 1).Activated:Connect(function()
		Windows.toggle("Pets")
	end)
	menuButton("🧪\nItems", Color3.fromRGB(80, 170, 120), 2).Activated:Connect(function()
		Windows.toggle("Items")
	end)
	local questsButton = menuButton("📜\nQuests", Color3.fromRGB(240, 138, 45), 3)
	questsButton.Activated:Connect(function()
		Windows.toggle("Quests")
	end)
	local dailyButton = menuButton("🎁\nDaily", Theme.red, 4)
	dailyButton.Activated:Connect(function()
		Windows.toggle("Daily")
	end)
	menuButton("🛒\nShop", Theme.gold, 5).Activated:Connect(function()
		Windows.toggle("Shop")
	end)
	menuButton("🔁\nTrade", Theme.purple, 6).Activated:Connect(function()
		Windows.toggle("Trade")
	end)
	local tripsButton = menuButton("🧭\nTrips", Color3.fromRGB(91, 160, 110), 7)
	tripsButton.Activated:Connect(function()
		Windows.toggle("Trips")
	end)
	local reloadButton = menuButton("🔄\nReload", Color3.fromRGB(110, 90, 200), 8)
	reloadButton.Activated:Connect(function()
		Windows.toggle("Reload")
	end)
	local autoButton = menuButton("🤖\nAuto", Theme.card, 9)
	autoButton.Activated:Connect(function()
		Net.event("ToggleAuto"):FireServer(not Store.currency.auto)
	end)
	local questsDot = dot(questsButton)
	local dailyDot = dot(dailyButton)
	local tripsDot = dot(tripsButton)
	local reloadDot = dot(reloadButton)
	menu.Parent = gui

	local function update()
		local c = Store.currency
		coins.Text = Format.abbrev(c.coins)
		gems.Text = Format.abbrev(c.gems)
		power.Text = Format.abbrev(c.power) .. "/s"
		local zone = if c.zoneId then World1.zonesById[c.zoneId] else nil
		zoneFrame.Visible = zone ~= nil
		if zone then
			zoneName.Text = zone.name
			local isPlayZone = zone.restoreGoal > 0
			barBack.Visible = isPlayZone
			barFill.Size = UDim2.fromScale(c.zoneProgress, 1)
			barText.Text = if c.zoneProgress >= 1 then "Restored!" else ("Restored %d%%"):format(math.floor(c.zoneProgress * 100))
		end
		comboLabel.Text = if c.combo >= 2 then ("COMBO x%d  (%gx)"):format(c.combo, c.comboMult) else ""
		local lines = {}
		for stat, boost in c.boosts do
			table.insert(lines, ("%s x%g · %ds"):format(stat, boost.mult, math.ceil(boost.left)))
		end
		boostLabel.Text = table.concat(lines, "\n")
		autoButton.BackgroundColor3 = if c.auto then Theme.green else Theme.card
		local rift = if c.rift then World1.zonesById[c.rift] else nil
		riftLabel.Text = if rift then "🟪 Pixel Rift today: " .. rift.name else ""
		questsDot.Visible = QuestsPanel.hasClaimable()
		dailyDot.Visible = DailyPanel.claimable() ~= nil
		local data = Store.data
		tripsButton.Visible = data ~= nil and Unlocks.has(data :: any, "Trips")
		tripsDot.Visible = TripsPanel.hasReady()
		reloadDot.Visible = ReloadPanel.canReload()
	end
	Store.CurrencyChanged:Connect(update)
	update()
end

return HUD
