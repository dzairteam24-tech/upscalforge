--!strict
-- The seed shop: every crop, what it takes to grow and what it pays; the locked ones say the level they need.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crops = require(Shared.Config.Crops)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local SeedShop = {}

local function time(seconds: number): string
	if seconds < 60 then
		return seconds .. "s"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. " min"
	end
	return (math.floor(seconds / 360) / 10) .. " h"
end

function SeedShop.new(screen: ScreenGui): Ui.Window
	local window = Ui.window(screen, "SEEDS", Ui.green, UDim2.fromOffset(600, 480))
	local list = Ui.list(window.body)
	local rows: { [string]: { one: TextButton, ten: TextButton, desc: TextLabel, row: Frame } } = {}
	for i, crop in Crops.LIST do
		local row = Ui.row(list, crop.name, "", crop.fruit, 70)
		row.LayoutOrder = i
		local one = Ui.button(row, "1", UDim2.fromOffset(84, 46), UDim2.new(1, -196, 0, 12), Ui.green, function()
			Net.event("BuySeeds"):FireServer(crop.key, 1)
		end)
		one.ZIndex = 13
		local ten = Ui.button(row, "10", UDim2.fromOffset(96, 46), UDim2.new(1, -104, 0, 12), Ui.green, function()
			Net.event("BuySeeds"):FireServer(crop.key, 10)
		end)
		ten.ZIndex = 13
		rows[crop.key] = { one = one, ten = ten, desc = row:FindFirstChild("Desc") :: TextLabel, row = row }
	end
	Store.onChanged(function()
		local data = Store.data
		for _, crop in Crops.LIST do
			local r = rows[crop.key]
			local open = data.level >= crop.level
			if open then
				r.desc.Text = ("grows in %s · sells %d × %s"):format(time(crop.grow), crop.yield, Format.short(crop.sell))
				Ui.setText(r.one, Format.short(crop.seed))
				Ui.setText(r.ten, Format.short(crop.seed * 10))
				Ui.setEnabled(r.one, Ui.green, data.coins >= crop.seed)
				Ui.setEnabled(r.ten, Ui.green, data.coins >= crop.seed * 10)
			else
				r.desc.Text = ("unlocks at level %d"):format(crop.level)
				Ui.setText(r.one, "LV " .. crop.level)
				Ui.setText(r.ten, "LOCKED")
				Ui.setEnabled(r.one, Ui.green, false)
				Ui.setEnabled(r.ten, Ui.green, false)
			end
		end
	end)
	return window
end

return SeedShop
