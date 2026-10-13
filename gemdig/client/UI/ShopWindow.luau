--!strict
-- The shop: the shovels and backpacks, in order. You buy the next one of each.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Config.Gear)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local ShopWindow = {}

function ShopWindow.new(screen: ScreenGui)
	local window = Ui.window(screen, "SHOP", UDim2.fromOffset(620, 430))
	local body = window.body
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 11
	scroll.Parent = body
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
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
		local function section(title: string, kind: string, items: { any }, owned: number, describe: (any) -> string)
			local head = Ui.label(scroll, title, UDim2.new(1, -8, 0, 28), UDim2.new(), Ui.gold)
			head.TextXAlignment = Enum.TextXAlignment.Left
			for i, item in items do
				local row = Ui.frame(scroll, UDim2.new(1, -8, 0, 50), UDim2.new(), Color3.fromRGB(240, 232, 218))
				row.ZIndex = 12
				local name = Ui.label(row, item.name, UDim2.new(0.5, -10, 0, 26), UDim2.fromOffset(12, 3), Color3.fromRGB(60, 52, 70))
				name.TextStrokeTransparency = 1
				name.TextXAlignment = Enum.TextXAlignment.Left
				name.ZIndex = 13
				local info = Ui.label(row, describe(item), UDim2.new(0.5, -10, 0, 18), UDim2.fromOffset(12, 28), Color3.fromRGB(130, 120, 140))
				info.TextStrokeTransparency = 1
				info.TextXAlignment = Enum.TextXAlignment.Left
				info.ZIndex = 13
				local button
				if i <= owned then
					button = Ui.button(row, if i == owned then "In use" else "Owned", UDim2.fromOffset(150, 36), UDim2.new(1, -160, 0, 7), Ui.gray, function() end)
				elseif i == owned + 1 then
					local afford = data.coins >= item.price
					button = Ui.button(row, "Buy  " .. item.price, UDim2.fromOffset(150, 36), UDim2.new(1, -160, 0, 7), if afford then Ui.green else Ui.red, function()
						Net.event("Buy"):FireServer(kind, i)
					end)
				else
					button = Ui.button(row, "Locked", UDim2.fromOffset(150, 36), UDim2.new(1, -160, 0, 7), Color3.fromRGB(110, 106, 124), function() end)
				end
				button.ZIndex = 13
			end
		end
		section("Shovels", "shovel", Gear.SHOVELS, data.shovel, function(s)
			return ("Power %d  -  swing every %.2fs"):format(s.power, s.cooldown)
		end)
		section("Backpacks", "pack", Gear.PACKS, data.pack, function(p)
			return p.slots .. " gem slots"
		end)
	end
	Store.onChanged(render)
	return window
end

return ShopWindow
