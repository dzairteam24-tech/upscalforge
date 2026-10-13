--!strict
-- The screen: coins and what they're multiplied by, the backpack's fill, how deep you are, the buttons, and the
-- little messages for gems found and purchases.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gems = require(Shared.Config.Gems)
local MineConfig = require(Shared.Config.Mine)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local Hud = {}

local LOCAL = Players.LocalPlayer

local KIND_COLORS: { [string]: Color3 } = { info = Color3.new(1, 1, 1), good = Ui.green, bad = Ui.red }

local function short(n: number): string
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end
Hud.short = short

local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- `windows`: what each button opens. Returns the daily button (so its red dot can be told about)
function Hud.init(screen: ScreenGui, windows: { bag: () -> (), shop: () -> (), store: () -> (), rebirth: () -> (), daily: () -> () })
	-- coins (top right), what they're multiplied by, the backpack under it
	local top = Ui.frame(screen, UDim2.fromOffset(190, 46), UDim2.new(1, -206, 0, 14), Color3.fromRGB(40, 36, 56))
	Ui.stroke(top, Ui.ink, 3)
	local coinsLabel = Ui.label(top, "0", UDim2.new(1, -52, 1, -10), UDim2.fromOffset(46, 5), Ui.gold)
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	local coin = Ui.frame(top, UDim2.fromOffset(28, 28), UDim2.fromOffset(10, 9), Ui.gold)
	Ui.round(coin, 14)
	Ui.stroke(coin, Ui.ink, 2)

	local bag = Ui.frame(screen, UDim2.fromOffset(190, 34), UDim2.new(1, -206, 0, 66), Color3.fromRGB(40, 36, 56))
	Ui.stroke(bag, Ui.ink, 3)
	local fill = Ui.frame(bag, UDim2.new(0, 0, 1, -8), UDim2.fromOffset(4, 4), Ui.green)
	local bagLabel = Ui.label(bag, "0/12", UDim2.fromScale(1, 0.7), UDim2.fromScale(0, 0.15))
	bagLabel.ZIndex = 3

	local multiplierLabel = Ui.label(screen, "", UDim2.fromOffset(190, 24), UDim2.new(1, -206, 0, 104), Ui.gold)
	multiplierLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- the depth, at the top in the middle
	local depth = Ui.label(screen, "", UDim2.fromOffset(260, 40), UDim2.new(0.5, -130, 0, 14))

	-- the buttons: two columns down the left side
	local function button(text: string, column: number, row: number, color: Color3, fn: () -> ()): TextButton
		return Ui.button(screen, text, UDim2.fromOffset(120, 40), UDim2.fromOffset(14 + column * 128, 64 + row * 46), color, fn)
	end
	button("Town", 0, 0, Ui.blue, function()
		Net.event("Teleport"):FireServer("surface")
	end)
	button("My Mine", 0, 1, Ui.green, function()
		Net.event("Teleport"):FireServer("plot")
	end)
	button("Dig Down", 0, 2, Color3.fromRGB(176, 110, 255), function()
		Net.event("Teleport"):FireServer("depth")
	end)
	button("New Mine", 0, 3, Color3.fromRGB(110, 120, 150), function()
		Net.event("ResetMine"):FireServer()
	end)
	local daily = button("Daily", 0, 4, Color3.fromRGB(230, 90, 150), windows.daily)
	button("Bag", 1, 0, Color3.fromRGB(230, 150, 50), windows.bag)
	button("Shop", 1, 1, Ui.gold, windows.shop)
	button("Store", 1, 2, Color3.fromRGB(60, 190, 130), windows.store)
	local rebirth = button("Rebirth", 1, 3, Color3.fromRGB(200, 70, 70), windows.rebirth)

	local dot = Ui.frame(daily, UDim2.fromOffset(16, 16), UDim2.new(1, -10, 0, -6), Ui.red)
	Ui.round(dot, 8)
	Ui.stroke(dot, Color3.new(1, 1, 1), 2)
	dot.Visible = false
	local rebirthDot = Ui.frame(rebirth, UDim2.fromOffset(16, 16), UDim2.new(1, -10, 0, -6), Ui.green)
	Ui.round(rebirthDot, 8)
	Ui.stroke(rebirthDot, Color3.new(1, 1, 1), 2)
	rebirthDot.Visible = false

	local boostAt = 0 -- os.clock() when the boost ends
	Store.onChanged(function()
		local data = Store.data
		coinsLabel.Text = short(data.coins)
		bagLabel.Text = data.used .. "/" .. data.capacity
		local fraction = math.clamp(data.used / math.max(1, data.capacity), 0, 1)
		TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.new(fraction, -8, 1, -8) }):Play()
		fill.BackgroundColor3 = if fraction >= 1 then Ui.red elseif fraction > 0.8 then Ui.gold else Ui.green
		dot.Visible = data.dailyReady
		rebirthDot.Visible = data.canRebirth
		boostAt = os.clock() + data.boostLeft
		multiplierLabel.Text = if data.multiplier > 1 then ("coins x%s"):format((tostring(math.floor(data.multiplier * 100 + 0.5) / 100))) else ""
	end)

	-- depth follows the player; the boost counts down
	task.spawn(function()
		while true do
			local root = LOCAL.Character and LOCAL.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local y = root.Position.Y
				if y > -1 then
					depth.Text = "Surface"
				else
					depth.Text = "Layer " .. math.floor(-y / MineConfig.CELL) + 1 .. " / " .. MineConfig.MAX_LAYER
				end
			end
			local left = math.max(0, boostAt - os.clock())
			local data = Store.data
			if data and left > 0 then
				multiplierLabel.Text = ("coins x%s  (boost %s)"):format(tostring(math.floor(data.multiplier * 100 + 0.5) / 100), clock(math.floor(left)))
			end
			task.wait(0.5)
		end
	end)

	-- messages, at the bottom
	local toasts = Instance.new("Frame")
	toasts.BackgroundTransparency = 1
	toasts.Size = UDim2.fromOffset(420, 220)
	toasts.Position = UDim2.new(0.5, -210, 1, -250)
	local layout = Instance.new("UIListLayout")
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = toasts
	toasts.Parent = screen
	Net.event("Notify").OnClientEvent:Connect(function(text: string, kind: string)
		local color = KIND_COLORS[kind] or Gems.RARITY_COLORS[kind] or Color3.new(1, 1, 1)
		local label = Ui.label(toasts, text, UDim2.fromOffset(400, 30), UDim2.new(), color)
		task.delay(3.5, function()
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.45)
			label:Destroy()
		end)
		-- (never a long pile)
		local children = toasts:GetChildren()
		if #children > 7 then
			children[2]:Destroy() -- (the first child is the layout)
		end
	end)
end

return Hud
