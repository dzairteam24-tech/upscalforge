--!strict
-- The screen: coins, the backpack's fill, how deep you are, the buttons (town, mine, back down, bag, shop), and
-- the little messages for gems found and purchases.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

-- Calls `onBag` and `onShop` for those buttons
function Hud.init(screen: ScreenGui, onBag: () -> (), onShop: () -> ())
	local top = Ui.frame(screen, UDim2.fromOffset(190, 46), UDim2.new(1, -206, 0, 14), Color3.fromRGB(40, 36, 56))
	Ui.stroke(top, Ui.ink, 3)
	local coinsLabel = Ui.label(top, "0", UDim2.new(1, -52, 1, -10), UDim2.fromOffset(46, 5), Ui.gold)
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	local coin = Ui.frame(top, UDim2.fromOffset(28, 28), UDim2.fromOffset(10, 9), Ui.gold)
	Ui.round(coin, 14)
	Ui.stroke(coin, Ui.ink, 2)

	-- the backpack, under the coins
	local bag = Ui.frame(screen, UDim2.fromOffset(190, 34), UDim2.new(1, -206, 0, 66), Color3.fromRGB(40, 36, 56))
	Ui.stroke(bag, Ui.ink, 3)
	local fill = Ui.frame(bag, UDim2.new(0, 0, 1, -8), UDim2.fromOffset(4, 4), Ui.green)
	local bagLabel = Ui.label(bag, "0/20", UDim2.fromScale(1, 0.7), UDim2.fromScale(0, 0.15))
	bagLabel.ZIndex = 3

	-- the depth, at the top in the middle
	local depth = Ui.label(screen, "", UDim2.fromOffset(260, 40), UDim2.new(0.5, -130, 0, 14))

	-- the buttons, down the left side
	local function side(text: string, row: number, color: Color3, fn: () -> ())
		return Ui.button(screen, text, UDim2.fromOffset(150, 46), UDim2.new(0, 14, 0.5, -130 + row * 56), color, fn)
	end
	side("Town", 0, Ui.blue, function()
		Net.event("Teleport"):FireServer("surface")
	end)
	side("My Mine", 1, Ui.green, function()
		Net.event("Teleport"):FireServer("plot")
	end)
	side("Dig Down", 2, Color3.fromRGB(176, 110, 255), function()
		Net.event("Teleport"):FireServer("depth")
	end)
	side("Bag", 3, Color3.fromRGB(230, 150, 50), onBag)
	side("Shop", 4, Ui.gold, onShop)

	Store.onChanged(function()
		local data = Store.data
		coinsLabel.Text = short(data.coins)
		bagLabel.Text = data.used .. "/" .. data.capacity
		local fraction = math.clamp(data.used / math.max(1, data.capacity), 0, 1)
		TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.new(fraction, -8, 1, -8) }):Play()
		fill.BackgroundColor3 = if fraction >= 1 then Ui.red elseif fraction > 0.8 then Ui.gold else Ui.green
	end)

	-- depth follows the player
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
			task.wait(0.2)
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
