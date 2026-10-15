--!strict
-- The screen: coins and the level (with its XP bar) at the top, the big buttons (SEEDS, BARN, LAND) on the right,
-- the seed bar at the bottom (tap one to plant it), banners for big moments and little messages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crops = require(Shared.Config.Crops)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local Hud = {}

local KIND_COLORS: { [string]: Color3 } = { info = Color3.new(1, 1, 1), good = Ui.green, bad = Ui.red, gold = Ui.yellow }

export type Buttons = { seeds: () -> (), barn: () -> (), land: () -> (), select: (key: string) -> () }
export type Hud = {
	banner: (title: string, sub: string?, color: Color3?) -> (),
	info: (text: string) -> (),
	selected: (key: string) -> (),
}

function Hud.new(screen: ScreenGui, buttons: Buttons): Hud
	-- coins
	local coinBox = Ui.panel(screen, UDim2.fromOffset(180, 54), UDim2.fromOffset(14, 14))
	local coin = Instance.new("Frame")
	coin.Size = UDim2.fromOffset(32, 32)
	coin.Position = UDim2.fromOffset(12, 11)
	coin.BackgroundColor3 = Ui.yellow
	coin.BorderSizePixel = 0
	Ui.round(coin, 16)
	Ui.stroke(coin, Ui.yellow:Lerp(Ui.ink, 0.5), 2.5)
	coin.Parent = coinBox
	local coinsLabel = Ui.label(coinBox, "0", UDim2.new(1, -60, 0, 34), UDim2.fromOffset(52, 10))
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	local coinScale = Instance.new("UIScale")
	coinScale.Parent = coinsLabel

	-- the level and its bar
	local levelBox = Ui.panel(screen, UDim2.fromOffset(250, 54), UDim2.fromOffset(204, 14))
	local badge = Instance.new("Frame")
	badge.Size = UDim2.fromOffset(42, 42)
	badge.Position = UDim2.fromOffset(6, 6)
	badge.BackgroundColor3 = Ui.green
	badge.BorderSizePixel = 0
	Ui.round(badge, 21)
	Ui.stroke(badge, Ui.green:Lerp(Ui.ink, 0.5), 2.5)
	badge.Parent = levelBox
	local levelLabel = Ui.label(badge, "1", UDim2.new(1, -10, 1, -12), UDim2.fromOffset(5, 6))
	Ui.outlined(levelLabel)
	local barBack = Instance.new("Frame")
	barBack.Size = UDim2.new(1, -70, 0, 16)
	barBack.Position = UDim2.fromOffset(58, 28)
	barBack.BackgroundColor3 = Ui.cream
	barBack.BorderSizePixel = 0
	Ui.round(barBack, 8)
	Ui.stroke(barBack, Ui.cream:Lerp(Ui.ink, 0.35), 2)
	barBack.Parent = levelBox
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(0, 1)
	bar.BackgroundColor3 = Ui.green
	bar.BorderSizePixel = 0
	Ui.round(bar, 8)
	bar.Parent = barBack
	local levelText = Ui.label(levelBox, "LEVEL 1", UDim2.new(1, -70, 0, 18), UDim2.fromOffset(58, 7))
	levelText.TextXAlignment = Enum.TextXAlignment.Left

	-- the big buttons, right side (clear of the jump button)
	local seedsButton = Ui.button(screen, "SEEDS", UDim2.fromOffset(150, 56), UDim2.new(1, -164, 0, 14), Ui.green, buttons.seeds)
	local barnButton = Ui.button(screen, "BARN", UDim2.fromOffset(150, 56), UDim2.new(1, -164, 0, 78), Ui.red, buttons.barn)
	local landButton = Ui.button(screen, "LAND", UDim2.fromOffset(150, 56), UDim2.new(1, -164, 0, 142), Ui.orange, buttons.land)
	local landCost = Ui.label(screen, "", UDim2.fromOffset(150, 20), UDim2.new(1, -164, 0, 200))
	Ui.outlined(landCost)
	local barnCount = Instance.new("Frame")
	barnCount.Size = UDim2.fromOffset(34, 26)
	barnCount.Position = UDim2.new(1, -24, 0, -10)
	barnCount.BackgroundColor3 = Ui.yellow
	barnCount.BorderSizePixel = 0
	Ui.round(barnCount, 13)
	Ui.stroke(barnCount, Ui.ink, 2)
	barnCount.Visible = false
	barnCount.Parent = barnButton
	local barnCountLabel = Ui.label(barnCount, "0", UDim2.new(1, -6, 1, -6), UDim2.fromOffset(3, 3))
	local _ = seedsButton

	-- the seed bar at the bottom
	local seedBar = Instance.new("Frame")
	seedBar.BackgroundTransparency = 1
	seedBar.Size = UDim2.new(1, -40, 0, 84)
	seedBar.AnchorPoint = Vector2.new(0.5, 1)
	seedBar.Position = UDim2.new(0.5, 0, 1, -14)
	seedBar.Parent = screen
	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	barLayout.Padding = UDim.new(0, 8)
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = seedBar
	local slots: { [string]: { frame: TextButton, count: TextLabel, stroke: UIStroke } } = {}
	for i, crop in Crops.LIST do
		local slot = Instance.new("TextButton")
		slot.Name = crop.key
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.Size = UDim2.fromOffset(70, 74)
		slot.LayoutOrder = i
		slot.BackgroundColor3 = Ui.paper
		slot.BorderSizePixel = 0
		slot.Visible = false
		Ui.round(slot, 14)
		local stroke = Ui.stroke(slot, Ui.ink, 3)
		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.fromOffset(34, 34)
		swatch.Position = UDim2.new(0.5, -17, 0, 8)
		swatch.BackgroundColor3 = crop.fruit
		swatch.BorderSizePixel = 0
		Ui.round(swatch, 8)
		Ui.stroke(swatch, crop.fruit:Lerp(Ui.ink, 0.5), 2)
		swatch.Parent = slot
		local leaf = Instance.new("Frame")
		leaf.Size = UDim2.fromOffset(14, 8)
		leaf.Position = UDim2.new(0.5, -7, 0, 3)
		leaf.BackgroundColor3 = crop.leaf
		leaf.BorderSizePixel = 0
		Ui.round(leaf, 3)
		leaf.Parent = slot
		local name = Ui.label(slot, crop.name, UDim2.new(1, -6, 0, 14), UDim2.fromOffset(3, 44))
		name.TextScaled = true
		local count = Ui.label(slot, "0", UDim2.fromOffset(30, 18), UDim2.new(1, -32, 0, 2))
		count.TextXAlignment = Enum.TextXAlignment.Right
		slot.Parent = seedBar
		slot.Activated:Connect(function()
			buttons.select(crop.key)
		end)
		slots[crop.key] = { frame = slot, count = count, stroke = stroke }
	end
	local function selected(key: string)
		for k, slot in slots do
			slot.stroke.Color = if k == key then Ui.yellow else Ui.ink
			slot.stroke.Thickness = if k == key then 5 else 3
			slot.frame.Size = if k == key then UDim2.fromOffset(78, 82) else UDim2.fromOffset(70, 74)
		end
	end

	-- a banner in the middle, for big moments
	local banner = Ui.label(screen, "", UDim2.fromOffset(640, 72), UDim2.new(0.5, -320, 0.24, 0))
	Ui.outlined(banner)
	local bannerSub = Ui.label(screen, "", UDim2.fromOffset(560, 30), UDim2.new(0.5, -280, 0.24, 76))
	Ui.outlined(bannerSub)
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	local token = 0
	local function showBanner(title: string, sub: string?, color: Color3?)
		token += 1
		local mine = token
		banner.Text = title
		banner.TextColor3 = color or Color3.new(1, 1, 1)
		banner.TextTransparency = 0
		banner.TextStrokeTransparency = 0
		bannerSub.Text = sub or ""
		bannerSub.TextTransparency = 0
		bannerSub.TextStrokeTransparency = 0
		bannerScale.Scale = 1.5
		TweenService:Create(bannerScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(2.2, function()
			if mine == token then
				TweenService:Create(banner, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				TweenService:Create(bannerSub, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	-- a line just above the seed bar, for what a tap did
	local info = Ui.label(screen, "", UDim2.fromOffset(520, 26), UDim2.new(0.5, -260, 1, -128))
	Ui.outlined(info)
	local infoToken = 0
	local function showInfo(text: string)
		infoToken += 1
		local mine = infoToken
		info.Text = text
		info.TextTransparency = 0
		info.TextStrokeTransparency = 0
		task.delay(1.8, function()
			if mine == infoToken then
				info.TextTransparency = 1
				info.TextStrokeTransparency = 1
			end
		end)
	end

	local lastCoins = -1
	Store.onChanged(function()
		local data = Store.data
		coinsLabel.Text = Format.comma(data.coins)
		if lastCoins >= 0 and data.coins > lastCoins then
			coinScale.Scale = 1.25
			TweenService:Create(coinScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		lastCoins = data.coins
		levelLabel.Text = tostring(data.level)
		levelText.Text = "LEVEL " .. data.level
		TweenService:Create(bar, TweenInfo.new(0.3), { Size = UDim2.fromScale(math.clamp(data.levelShare, 0, 1), 1) }):Play()
		local inBarn = 0
		for _, n in data.barn do
			inBarn += n
		end
		barnCount.Visible = inBarn > 0
		barnCountLabel.Text = if inBarn > 99 then "99+" else tostring(inBarn)
		if data.nextTileCost then
			local ready = data.level >= data.nextTileLevel
			landCost.Text = if ready then ("+1 tile: %s"):format(Format.short(data.nextTileCost)) else ("next at level %d"):format(data.nextTileLevel)
			Ui.setEnabled(landButton, Ui.orange, ready and data.coins >= data.nextTileCost)
		else
			landCost.Text = "all land is yours"
			Ui.setEnabled(landButton, Ui.orange, false)
		end
		for _, crop in Crops.LIST do
			local slot = slots[crop.key]
			local count = data.seeds[crop.key] or 0
			slot.frame.Visible = count > 0
			slot.count.Text = tostring(count)
		end
	end)

	-- little messages, at the top in the middle
	local toasts = Instance.new("Frame")
	toasts.BackgroundTransparency = 1
	toasts.Size = UDim2.fromOffset(460, 160)
	toasts.Position = UDim2.new(0.5, -230, 0, 80)
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = toasts
	toasts.Parent = screen
	Net.event("Notify").OnClientEvent:Connect(function(text: string, kind: string)
		local label = Ui.label(toasts, text, UDim2.fromOffset(440, 28), UDim2.new())
		Ui.outlined(label)
		label.TextColor3 = KIND_COLORS[kind] or Color3.new(1, 1, 1)
		task.delay(3.2, function()
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.45)
			label:Destroy()
		end)
		local children = toasts:GetChildren()
		if #children > 5 then
			children[2]:Destroy() -- (the first child is the layout)
		end
	end)

	return { banner = showBanner, info = showInfo, selected = selected }
end

return Hud
