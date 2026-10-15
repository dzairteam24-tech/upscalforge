--!strict
-- A farm stand. Its own farmer sees what's on it (take it back) and their barn (put crops out at a price they
-- choose); a visitor sees what's for sale and buys.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crops = require(Shared.Config.Crops)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)
local Stand = require(Shared.Logic.Stand)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local StandWindow = {}

export type StandWindow = Ui.Window & { show: (index: number, name: string, stock: any, own: boolean) -> () }

function StandWindow.new(screen: ScreenGui): StandWindow
	local window = Ui.window(screen, "FARM STAND", Ui.orange, UDim2.fromOffset(640, 480))
	local list = Ui.list(window.body, 8)
	local current: { index: number, name: string, stock: any, own: boolean }? = nil
	local prices: { [string]: number } = {} -- (the price they're setting for each crop)

	local function clear()
		for _, child in list:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
	end
	local order = 0
	local function heading(text: string)
		order += 1
		local h = Ui.label(list, text, UDim2.new(1, -10, 0, 26), UDim2.new())
		h.TextXAlignment = Enum.TextXAlignment.Left
		h.LayoutOrder = order
		h.ZIndex = 12
	end
	local function row(crop: Crops.Crop, desc: string): Frame
		order += 1
		local r = Ui.row(list, crop.name, desc, crop.fruit, 66)
		r.LayoutOrder = order
		return r
	end

	local function render()
		local view = current
		local data = Store.data
		if not view or not data then
			return
		end
		clear()
		order = 0
		if view.own then
			heading("ON YOUR STAND (visitors buy these, you get the coins)")
			local any = false
			for _, crop in Crops.LIST do
				local lot = view.stock[crop.key]
				if lot then
					any = true
					local r = row(crop, ("%d × %s coins"):format(lot.n, Format.short(lot.p)))
					Ui.button(r, "TAKE BACK", UDim2.fromOffset(150, 42), UDim2.new(1, -162, 0, 12), Ui.gray, function()
						Net.event("StandTake"):FireServer(crop.key)
					end).ZIndex = 13
				end
			end
			if not any then
				heading("   (nothing yet)")
			end
			heading("FROM YOUR BARN")
			for _, crop in Crops.LIST do
				local n = data.barn[crop.key] or 0
				if n > 0 then
					local low, high = Stand.priceRange(crop.key)
					local price = math.clamp(prices[crop.key] or math.floor(crop.sell * 1.3 + 0.5), low, high)
					prices[crop.key] = price
					local r = row(crop, ("%d in barn · barn sells at %s"):format(n, Format.short(crop.sell)))
					local step = math.max(1, math.floor(crop.sell * 0.1 + 0.5))
					local priceLabel = Ui.label(r, Format.short(price), UDim2.fromOffset(70, 30), UDim2.new(1, -300, 0, 18))
					priceLabel.ZIndex = 13
					Ui.button(r, "-", UDim2.fromOffset(36, 36), UDim2.new(1, -340, 0, 15), Ui.gray, function()
						prices[crop.key] = math.max(low, price - step)
						render()
					end).ZIndex = 13
					Ui.button(r, "+", UDim2.fromOffset(36, 36), UDim2.new(1, -230, 0, 15), Ui.gray, function()
						prices[crop.key] = math.min(high, price + step)
						render()
					end).ZIndex = 13
					Ui.button(r, "PUT ALL", UDim2.fromOffset(110, 42), UDim2.new(1, -122, 0, 12), Ui.green, function()
						Net.event("StandPut"):FireServer(crop.key, n, prices[crop.key])
					end).ZIndex = 13
				end
			end
		else
			heading(("%s's stand"):format(view.name))
			local any = false
			for _, crop in Crops.LIST do
				local lot = view.stock[crop.key]
				if lot then
					any = true
					local r = row(crop, ("%d left · %s coins each"):format(lot.n, Format.short(lot.p)))
					local one = Ui.button(r, "BUY 1", UDim2.fromOffset(100, 42), UDim2.new(1, -224, 0, 12), Ui.green, function()
						Net.event("StandBuy"):FireServer(view.index, crop.key, 1)
					end)
					one.ZIndex = 13
					Ui.setEnabled(one, Ui.green, data.coins >= lot.p)
					local all = Ui.button(r, "BUY " .. lot.n, UDim2.fromOffset(110, 42), UDim2.new(1, -116, 0, 12), Ui.green, function()
						Net.event("StandBuy"):FireServer(view.index, crop.key, lot.n)
					end)
					all.ZIndex = 13
					Ui.setEnabled(all, Ui.green, data.coins >= lot.p * lot.n)
				end
			end
			if not any then
				heading("   Nothing for sale right now. Come back later!")
			end
		end
	end
	Store.onChanged(function()
		if window.isOpen() then
			render()
		end
	end)
	local result = window :: any
	result.show = function(index: number, name: string, stock: any, own: boolean)
		current = { index = index, name = name, stock = stock or {}, own = own }
		render()
	end
	return result
end

return StandWindow
