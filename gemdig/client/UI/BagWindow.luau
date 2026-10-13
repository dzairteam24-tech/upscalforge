--!strict
-- The bag: every gem you carry, grouped, and the catalog of the kinds you've found.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gem = require(Shared.Logic.Gem)
local Gems = require(Shared.Config.Gems)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local BagWindow = {}

function BagWindow.new(screen: ScreenGui)
	local window = Ui.window(screen, "BAG", UDim2.fromOffset(520, 440))
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 11
	scroll.Parent = window.body
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 5)
	list.Parent = scroll

	local function render()
		local data = Store.data
		if not data then
			return
		end
		for _, child in scroll:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		local function heading(text: string)
			local label = Ui.label(scroll, text, UDim2.new(1, -8, 0, 26), UDim2.new(), Ui.gold)
			label.TextXAlignment = Enum.TextXAlignment.Left
		end
		local function row(color: Color3, title: string, right: string)
			local f = Ui.frame(scroll, UDim2.new(1, -8, 0, 36), UDim2.new(), Color3.fromRGB(240, 232, 218))
			f.ZIndex = 12
			local swatch = Ui.frame(f, UDim2.fromOffset(22, 22), UDim2.fromOffset(8, 7), color)
			swatch.Rotation = 45
			swatch.ZIndex = 13
			Ui.stroke(swatch, Ui.ink, 2)
			local name = Ui.label(f, title, UDim2.new(0.62, -40, 0, 24), UDim2.fromOffset(40, 6), Color3.fromRGB(60, 52, 70))
			name.TextStrokeTransparency = 1
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.ZIndex = 13
			local value = Ui.label(f, right, UDim2.new(0.38, -10, 0, 22), UDim2.new(0.62, 0, 0, 7), Ui.gold)
			value.TextXAlignment = Enum.TextXAlignment.Right
			value.ZIndex = 13
		end
		heading(("Backpack  %d / %d"):format(data.used, data.capacity))
		if #data.groups == 0 then
			local empty = Ui.label(scroll, "Empty: go and dig!", UDim2.new(1, -8, 0, 30), UDim2.new(), Color3.fromRGB(130, 120, 140))
			empty.TextStrokeTransparency = 1
		end
		for _, group in data.groups do
			local item = Gem.parseKey(group.key)
			local kind = Gems.byId[item.g]
			row(if kind then kind.color else Ui.gray, Gem.name(item) .. "  x" .. group.count, tostring(group.value * group.count))
		end
		local found = 0
		for _, gem in Gems.LIST do
			if data.found[gem.id] then
				found += 1
			end
		end
		heading(("Catalog  %d / %d"):format(found, #Gems.LIST))
		for _, gem in Gems.LIST do
			if data.found[gem.id] then
				row(gem.color, gem.id, gem.rarity)
			else
				row(Color3.fromRGB(90, 90, 100), "???", gem.rarity)
			end
		end
	end
	Store.onChanged(render)
	return window
end

return BagWindow
