--!strict
-- The barn: what's been harvested and what it's worth. Sell one kind, or everything at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crops = require(Shared.Config.Crops)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local BarnWindow = {}

function BarnWindow.new(screen: ScreenGui): Ui.Window
	local window = Ui.window(screen, "BARN", Ui.red, UDim2.fromOffset(560, 460))
	local body = window.body
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 1, -70)
	holder.ZIndex = 11
	holder.Parent = body
	local list = Ui.list(holder)
	local empty = Ui.label(holder, "Nothing here yet. Harvest ripe crops to fill your barn!", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 40), Ui.dim)
	empty.ZIndex = 12
	local sellAll = Ui.button(body, "SELL ALL", UDim2.new(1, 0, 0, 58), UDim2.new(0, 0, 1, -60), Ui.yellow, function()
		Net.event("Sell"):FireServer("all")
	end)
	sellAll.ZIndex = 12
	local rows: { [string]: { row: Frame, button: TextButton, desc: TextLabel } } = {}
	for i, crop in Crops.LIST do
		local row = Ui.row(list, crop.name, "", crop.fruit, 66)
		row.LayoutOrder = i
		local button = Ui.button(row, "SELL", UDim2.fromOffset(150, 44), UDim2.new(1, -162, 0, 11), Ui.yellow, function()
			Net.event("Sell"):FireServer(crop.key)
		end)
		button.ZIndex = 13
		rows[crop.key] = { row = row, button = button, desc = row:FindFirstChild("Desc") :: TextLabel }
	end
	Store.onChanged(function()
		local data = Store.data
		local total, any = 0, false
		for _, crop in Crops.LIST do
			local n = data.barn[crop.key] or 0
			local r = rows[crop.key]
			r.row.Visible = n > 0
			if n > 0 then
				any = true
				total += n * crop.sell
				r.desc.Text = ("%d × %s coins"):format(n, Format.short(crop.sell))
				Ui.setText(r.button, "SELL " .. Format.short(n * crop.sell))
			end
		end
		empty.Visible = not any
		Ui.setText(sellAll, if any then "SELL ALL · " .. Format.comma(total) .. " COINS" else "SELL ALL")
		Ui.setEnabled(sellAll, Ui.yellow, any)
	end)
	return window
end

return BarnWindow
