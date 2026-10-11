--!strict
-- The Trail Shop's window (Config/Trails), as in Steal an Egg: a card for each trail in its rarity's color, its
-- streak, how many times it multiplies each treadmill step, and its price in coins (Wear / Wearing once owned).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trails = require(Shared.Config.Trails)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local TrailWindow = {}

function TrailWindow.mount(gui: Instance)
	local window, content = Theme.window(gui, "✨ Trail Shop", Vector2.new(820, 600), Theme.purple)

	local function rebuild()
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		Theme.text(content, { Text = "A trail multiplies the speed (⚡) every treadmill step gives you", Size = UDim2.new(1, -8, 0, 24), TextColor3 = Theme.soft, LayoutOrder = 0 })
		local data = Store.data
		local owned = if data and data.trails then data.trails else {}
		local wearing = if data then data.trail else ""
		local grid = Theme.grid(content, 1, 3, 280)
		for i, trail in Trails.LIST do
			local color = trail.colors[1]
			local card = Theme.card(grid, color, { LayoutOrder = i })
			Theme.bold(card, { Text = trail.name, Size = UDim2.new(1, -12, 0, 32), Position = UDim2.fromOffset(6, 6), MaxText = 28 })
			Theme.bold(card, { Text = trail.rarity, Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 38), Font = Theme.font, MaxText = 18 })
			-- (its streak)
			local streak = Instance.new("Frame")
			streak.AnchorPoint = Vector2.new(0.5, 0)
			streak.Position = UDim2.new(0.5, 0, 0, 70)
			streak.Size = UDim2.new(0.8, 0, 0, 70)
			streak.Rotation = -12
			local keys = {}
			for k, c in trail.colors do
				table.insert(keys, ColorSequenceKeypoint.new(if #trail.colors == 1 then 0 else (k - 1) / (#trail.colors - 1), c))
			end
			if #keys == 1 then
				table.insert(keys, ColorSequenceKeypoint.new(1, color))
			end
			local gradient = Instance.new("UIGradient")
			gradient.Color = ColorSequence.new(keys)
			gradient.Transparency = NumberSequence.new(1, 0)
			gradient.Parent = streak
			streak.BackgroundColor3 = Color3.new(1, 1, 1)
			Theme.round(streak, 35)
			streak.Parent = card
			Theme.text(card, { Text = "🏃", Size = UDim2.fromOffset(60, 60), Position = UDim2.new(0.62, 0, 0, 72) })
			local mult = Instance.new("Frame")
			mult.Position = UDim2.new(0, 10, 0, 156)
			mult.Size = UDim2.new(1, -20, 0, 44)
			mult.BackgroundColor3 = Color3.new(0, 0, 0)
			mult.BackgroundTransparency = 0.6
			Theme.round(mult, 10)
			Theme.bold(mult, { Text = ("x%s Speed"):format(tostring(trail.mult)), Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), MaxText = 30 })
			mult.Parent = card
			local has = owned[trail.id] == true
			local worn = wearing == trail.id
			local canPay = data ~= nil and Store.coins() >= trail.price
			local buy = Theme.button(card, if worn then "Wearing ✓" elseif has then "Wear" else "🪙 " .. Format.abbrev(trail.price), if worn then Theme.gray elseif has or canPay then Theme.green else Theme.gray, function()
				if not worn then
					Net.event("BuyTrail"):FireServer(trail.id)
				end
			end)
			buy.AnchorPoint = Vector2.new(0.5, 1)
			buy.Position = UDim2.new(0.5, 0, 1, -10)
			buy.Size = UDim2.new(1, -20, 0, 50)
		end
	end

	Windows.register("Trails", window, rebuild)
	Store.Changed:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
end

return TrailWindow
