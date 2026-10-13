--!strict
-- The Store: what Robux buys. Only convenience: everything here can also be earned for free with time. The price
-- shown is Roblox's own at the moment of buying; the numbers here are the shop's labels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local PassConfig = require(Shared.Config.Passes)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local StoreWindow = {}

local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function StoreWindow.new(screen: ScreenGui)
	local window = Ui.window(screen, "STORE  (Robux: only convenience)", UDim2.fromOffset(640, 460))
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
	list.Padding = UDim.new(0, 6)
	list.Parent = scroll
	local studio = RunService:IsStudio()

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
			local head = Ui.label(scroll, text, UDim2.new(1, -8, 0, 28), UDim2.new(), Ui.gold)
			head.TextXAlignment = Enum.TextXAlignment.Left
		end
		local function row(name: string, desc: string, id: number, buttonText: string, color: Color3, onClick: (() -> ())?)
			local f = Ui.frame(scroll, UDim2.new(1, -8, 0, 56), UDim2.new(), Color3.fromRGB(240, 232, 218))
			f.ZIndex = 12
			local title = Ui.label(f, name .. (if id == 0 and studio then "  (test: free)" else ""), UDim2.new(0.6, -10, 0, 26), UDim2.fromOffset(12, 3), Color3.fromRGB(60, 52, 70))
			title.TextStrokeTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.ZIndex = 13
			local info = Ui.label(f, desc, UDim2.new(0.6, -10, 0, 20), UDim2.fromOffset(12, 30), Color3.fromRGB(130, 120, 140))
			info.TextStrokeTransparency = 1
			info.TextXAlignment = Enum.TextXAlignment.Left
			info.ZIndex = 13
			local b = Ui.button(f, buttonText, UDim2.fromOffset(160, 38), UDim2.new(1, -170, 0, 9), color, onClick or function() end)
			b.ZIndex = 13
		end
		heading("Passes (yours forever)")
		for _, pass in PassConfig.PASSES do
			if data.passes[pass.key] then
				row(pass.name, pass.desc, pass.id, "Owned", Ui.gray, nil)
			else
				row(pass.name, pass.desc, pass.id, "R$ " .. pass.price, Ui.green, function()
					Net.event("BuyRobux"):FireServer("pass", pass.key)
				end)
			end
		end
		heading("Boosts and packs")
		for _, product in PassConfig.PRODUCTS do
			local active = product.boostMinutes ~= nil and data.boostLeft > 0
			row(product.name, product.desc, product.id, if active then ("Active " .. clock(math.floor(data.boostLeft))) else ("R$ " .. product.price), if active then Ui.gold else Ui.green, function()
				Net.event("BuyRobux"):FireServer("product", product.key)
			end)
		end
	end
	Store.onChanged(render)
	return window
end

return StoreWindow
