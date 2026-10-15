--!strict
-- The Store: what Robux buys. Only convenience: everything here can also be had for free by running. The price
-- shown is Roblox's own at the moment of buying; the numbers here are the shop's labels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)
local PassConfig = require(Shared.Config.Passes)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local StoreWindow = {}

function StoreWindow.new(screen: ScreenGui): Ui.Window
	local window = Ui.window(screen, "STORE", Ui.gold, UDim2.fromOffset(600, 470))
	local list = Ui.list(window.body)
	local studio = RunService:IsStudio()
	local passButtons: { [string]: TextButton } = {}
	local boostButton: TextButton? = nil
	local order = 0
	local function heading(text: string)
		order += 1
		local h = Ui.label(list, text, UDim2.new(1, -8, 0, 22), UDim2.new(), Ui.gold, Ui.heavy)
		h.TextXAlignment = Enum.TextXAlignment.Left
		h.LayoutOrder = order
		h.ZIndex = 12
	end
	local function row(name: string, desc: string, id: number, price: number, onClick: () -> ()): TextButton
		order += 1
		local card = Ui.card(list, name .. (if id == 0 and studio then "  (test: free)" else ""), desc, Ui.gold, 64)
		card.LayoutOrder = order
		local button = Ui.button(card, "R$ " .. price, UDim2.fromOffset(130, 42), UDim2.new(1, -142, 0, 11), Ui.green, onClick)
		button.ZIndex = 13
		return button
	end
	heading("PASSES  ·  yours forever")
	for _, pass in PassConfig.PASSES do
		passButtons[pass.key] = row(pass.name, pass.desc, pass.id, pass.price, function()
			Net.event("BuyRobux"):FireServer("pass", pass.key)
		end)
	end
	heading("BOOSTS")
	for _, product in PassConfig.PRODUCTS do
		local button = row(product.name, product.desc, product.id, product.price, function()
			Net.event("BuyRobux"):FireServer("product", product.key)
		end)
		if product.boostMinutes then
			boostButton = button
		end
	end
	local function refresh()
		local data = Store.data
		if not data then
			return
		end
		for _, pass in PassConfig.PASSES do
			local b = passButtons[pass.key]
			if data.passes[pass.key] then
				Ui.setText(b, "OWNED")
				b.BackgroundColor3 = Color3.fromRGB(70, 74, 100)
				b.Active = false
			end
		end
		if boostButton then
			for _, product in PassConfig.PRODUCTS do
				if product.boostMinutes then
					Ui.setText(boostButton, if data.boostLeft > 0 then Format.clock(data.boostLeft) .. " left" else "R$ " .. product.price)
				end
			end
		end
	end
	Store.onChanged(refresh)
	return window
end

return StoreWindow
