-- Teleport window: jump to any unlocked zone with the Teleport game pass.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local World1 = require(Shared.Config.World1)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local TeleportPanel = {}

function TeleportPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Teleport", function()
		Windows.close("Teleport")
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(170, 70)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	scroll.Parent = content

	local function rebuild()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local data = Store.data
		if not data then
			return
		end
		local owned = data.passes ~= nil and data.passes.Teleport == true
		if not owned then
			local pass = Products.passByKey.Teleport
			local buy = Theme.button({
				Text = if pass and pass.id ~= 0 then ("Get Teleport · R$ %d"):format(pass.price) else "Teleport pass: soon",
				BackgroundColor3 = Theme.gold,
				LayoutOrder = 0,
				MaxTextSize = 18,
			})
			buy.Activated:Connect(function()
				if pass and pass.id ~= 0 then
					MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.id)
				end
			end)
			buy.Parent = scroll
		end
		for order, zone in World1.zones do
			local unlocked = Store.isUnlocked(zone.id)
			local b = Theme.button({
				Text = if unlocked then zone.name else "🔒 " .. zone.name,
				BackgroundColor3 = if unlocked and owned then zone.color else Theme.card,
				LayoutOrder = order,
				MaxTextSize = 18,
			})
			b.Activated:Connect(function()
				if unlocked and owned then
					Net.event("Teleport"):FireServer(zone.id)
					Windows.close("Teleport")
				end
			end)
			b.Parent = scroll
		end
	end

	Store.DataChanged:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	Windows.register("Teleport", window, rebuild)
end

return TeleportPanel
