--!strict
-- The screen: the speed number (big, in the middle at the top) and how close it is to what the next wall needs,
-- how far along the stage they are, coins, the buttons, the big banners (STAGE 3, CHECKPOINT, SMASH!) and the
-- little messages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseConfig = require(Shared.Config.Course)
local Economy = require(Shared.Logic.Economy)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local Hud = {}

local KIND_COLORS: { [string]: Color3 } = { info = Ui.text, good = Ui.green, bad = Ui.red, gold = Ui.gold }

export type Buttons = { upgrades: () -> (), store: () -> (), rebirth: () -> (), daily: () -> (), restart: () -> () }
export type Hud = {
	banner: (title: string, sub: string?, color: Color3?) -> (),
	progress: (stage: number, share: number, checkpoint: number) -> (),
	wallNear: (needs: number, stat: number) -> (),
	buttons: { [string]: TextButton },
}

function Hud.new(screen: ScreenGui, open: Buttons): Hud
	-- the speed
	local speedBox = Ui.panel(screen, UDim2.fromOffset(300, 92), UDim2.new(0.5, -150, 0, 10), Ui.cyan)
	Ui.label(speedBox, "SPEED", UDim2.fromOffset(120, 14), UDim2.new(0.5, -60, 0, 8), Ui.dim, Ui.heavy)
	local speedValue = Ui.label(speedBox, "10", UDim2.new(1, -24, 0, 38), UDim2.fromOffset(12, 22), Ui.text, Ui.heavy)
	Ui.shade(speedValue)
	local speedScale = Instance.new("UIScale")
	speedScale.Parent = speedValue
	-- what the wall needs
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -24, 0, 10)
	bar.Position = UDim2.fromOffset(12, 66)
	bar.BackgroundColor3 = Color3.fromRGB(40, 44, 70)
	bar.BorderSizePixel = 0
	Ui.round(bar, 5)
	bar.Parent = speedBox
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Ui.cyan
	fill.BorderSizePixel = 0
	Ui.round(fill, 5)
	fill.Parent = bar
	local wallLabel = Ui.label(screen, "", UDim2.fromOffset(300, 18), UDim2.new(0.5, -150, 0, 106), Ui.dim, Ui.heavy)
	Ui.shade(wallLabel)

	-- how far along the stage, with its checkpoints
	local track = Instance.new("Frame")
	track.Size = UDim2.new(0.5, 0, 0, 4)
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 132)
	track.BackgroundColor3 = Color3.fromRGB(60, 66, 100)
	track.BackgroundTransparency = 0.3
	track.BorderSizePixel = 0
	track.Parent = screen
	local trackFill = Instance.new("Frame")
	trackFill.Size = UDim2.fromScale(0, 1)
	trackFill.BackgroundColor3 = Ui.cyan
	trackFill.BorderSizePixel = 0
	trackFill.Parent = track
	local ticks: { Frame } = {}
	for i = 1, 2 do
		local tick = Instance.new("Frame")
		tick.Size = UDim2.fromOffset(10, 10)
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.new(i / 3, 0, 0.5, 0)
		tick.BackgroundColor3 = Color3.fromRGB(60, 66, 100)
		tick.Rotation = 45
		tick.BorderSizePixel = 0
		tick.Parent = track
		ticks[i] = tick
	end
	local stageLabel = Ui.label(screen, "STAGE 1", UDim2.fromOffset(200, 16), UDim2.new(0.5, -100, 0, 140), Ui.text, Ui.heavy)
	Ui.shade(stageLabel)

	-- coins (top left)
	local coinBox = Ui.panel(screen, UDim2.fromOffset(190, 50), UDim2.fromOffset(14, 14), Ui.gold)
	local coin = Instance.new("Frame")
	coin.Size = UDim2.fromOffset(22, 22)
	coin.Position = UDim2.fromOffset(14, 14)
	coin.BackgroundColor3 = Ui.gold
	coin.Rotation = 45
	coin.BorderSizePixel = 0
	Ui.round(coin, 4)
	coin.Parent = coinBox
	local coinsValue = Ui.label(coinBox, "0", UDim2.new(1, -60, 0, 28), UDim2.fromOffset(48, 11), Ui.gold, Ui.heavy)
	coinsValue.TextXAlignment = Enum.TextXAlignment.Left
	local multiplier = Ui.label(screen, "", UDim2.fromOffset(190, 16), UDim2.fromOffset(14, 68), Ui.gold)
	multiplier.TextXAlignment = Enum.TextXAlignment.Left
	Ui.shade(multiplier)

	-- the buttons (down the left, clear of the thumbstick and the jump button)
	local buttons: { [string]: TextButton } = {}
	local function button(key: string, text: string, row: number, color: Color3, fn: () -> ()): TextButton
		local b = Ui.button(screen, text, UDim2.fromOffset(150, 44), UDim2.fromOffset(14, 96 + row * 52), color, fn)
		buttons[key] = b
		return b
	end
	button("upgrades", "UPGRADES", 0, Color3.fromRGB(0, 150, 190), open.upgrades)
	button("store", "STORE", 1, Color3.fromRGB(200, 140, 30), open.store)
	local daily = button("daily", "DAILY", 2, Color3.fromRGB(200, 40, 140), open.daily)
	local rebirth = button("rebirth", "REBIRTH", 3, Color3.fromRGB(120, 70, 220), open.rebirth)
	button("restart", "RESTART", 4, Color3.fromRGB(60, 64, 90), open.restart)
	local function dot(parent: GuiObject, color: Color3): Frame
		local d = Instance.new("Frame")
		d.Size = UDim2.fromOffset(14, 14)
		d.Position = UDim2.new(1, -8, 0, -5)
		d.BackgroundColor3 = color
		d.BorderSizePixel = 0
		Ui.round(d, 7)
		Ui.stroke(d, Color3.new(1, 1, 1), 2, 0)
		d.Visible = false
		d.Parent = parent
		return d
	end
	local dailyDot = dot(daily, Ui.red)
	local rebirthDot = dot(rebirth, Ui.green)
	local upgradeDot = dot(buttons.upgrades, Ui.green)

	-- the big banner in the middle
	local banner = Ui.label(screen, "", UDim2.fromOffset(700, 70), UDim2.new(0.5, -350, 0.3, 0), Ui.text, Ui.heavy)
	Ui.shade(banner)
	local bannerSub = Ui.label(screen, "", UDim2.fromOffset(500, 26), UDim2.new(0.5, -250, 0.3, 74), Ui.dim, Ui.heavy)
	Ui.shade(bannerSub)
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	local bannerToken = 0
	local function showBanner(title: string, sub: string?, color: Color3?)
		bannerToken += 1
		local token = bannerToken
		banner.Text = title
		banner.TextColor3 = color or Ui.text
		banner.TextTransparency = 0
		banner.TextStrokeTransparency = 0.55
		bannerSub.Text = sub or ""
		bannerSub.TextTransparency = 0
		bannerScale.Scale = 1.4
		TweenService:Create(bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(1.4, function()
			if token == bannerToken then
				TweenService:Create(banner, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				TweenService:Create(bannerSub, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			end
		end)
	end

	local lastStat = 0
	Store.onChanged(function()
		local data = Store.data
		speedValue.Text = Format.comma(data.stat)
		if data.stat > lastStat then
			speedScale.Scale = 1.12
			TweenService:Create(speedScale, TweenInfo.new(0.2), { Scale = 1 }):Play()
		end
		lastStat = data.stat
		if data.needs then
			local share = math.clamp(data.stat / data.needs, 0, 1)
			TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(share, 1) }):Play()
			local ready = data.stat >= data.needs
			fill.BackgroundColor3 = if ready then Ui.green else Ui.cyan
			wallLabel.Text = if ready then ("READY TO SMASH WALL %d"):format(data.stage) else ("WALL %d NEEDS %s"):format(data.stage, Format.short(data.needs))
			wallLabel.TextColor3 = if ready then Ui.green else Ui.dim
		else
			fill.Size = UDim2.fromScale(1, 1)
			fill.BackgroundColor3 = Ui.gold
			wallLabel.Text = "COURSE BEATEN · REBIRTH FOR MORE"
			wallLabel.TextColor3 = Ui.gold
		end
		coinsValue.Text = Format.short(data.coins)
		multiplier.Text = if data.multiplier > 1 then ("COINS x%s%s"):format(tostring(math.floor(data.multiplier * 100 + 0.5) / 100), if data.boostLeft > 0 then "  ·  BOOST " .. Format.clock(data.boostLeft) else "") else ""
		dailyDot.Visible = data.dailyReady
		rebirthDot.Visible = data.canRebirth
		rebirth.Visible = data.rebirths > 0 or data.stage > CourseConfig.STAGES
		-- something they can afford in Upgrades
		local afford = false
		for _, u in Economy.UPGRADES do
			local level = data.upgrades[u.key] or 0
			if level < u.max and data.coins >= Economy.upgradeCost(u, level) then
				afford = true
			end
		end
		upgradeDot.Visible = afford
	end)

	-- the messages, low in the middle
	local toasts = Instance.new("Frame")
	toasts.BackgroundTransparency = 1
	toasts.Size = UDim2.fromOffset(460, 200)
	toasts.Position = UDim2.new(0.5, -230, 1, -230)
	local layout = Instance.new("UIListLayout")
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = toasts
	toasts.Parent = screen
	Net.event("Notify").OnClientEvent:Connect(function(text: string, kind: string)
		local label = Ui.label(toasts, text, UDim2.fromOffset(440, 24), UDim2.new(), KIND_COLORS[kind] or Ui.text, Ui.heavy)
		Ui.shade(label)
		task.delay(3.5, function()
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.45)
			label:Destroy()
		end)
		local children = toasts:GetChildren()
		if #children > 6 then
			children[2]:Destroy() -- (the first child is the layout)
		end
	end)

	return {
		banner = showBanner,
		progress = function(stage: number, share: number, checkpoint: number)
			local theme = CourseConfig.THEMES[(stage - 1) % #CourseConfig.THEMES + 1]
			trackFill.Size = UDim2.fromScale(share, 1)
			trackFill.BackgroundColor3 = theme.accent
			for i, tick in ticks do
				tick.BackgroundColor3 = if checkpoint >= i then theme.accent2 else Color3.fromRGB(60, 66, 100)
			end
			stageLabel.Text = ("STAGE %d · %s"):format(stage, string.upper(theme.name))
		end,
		wallNear = function(needs: number, stat: number)
			showBanner("NOT FAST ENOUGH", ("THIS WALL NEEDS %s SPEED · YOU HAVE %s"):format(Format.short(needs), Format.short(stat)), Ui.red)
		end,
		buttons = buttons,
	}
end

return Hud
