--!strict
-- The town's orders board: three orders, what each asks for and pays, how many they have, deliver or swap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crops = require(Shared.Config.Crops)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local OrdersWindow = {}

function OrdersWindow.new(screen: ScreenGui): Ui.Window
	local window = Ui.window(screen, "TOWN ORDERS", Ui.blue, UDim2.fromOffset(600, 380))
	local list = Ui.list(window.body, 10)
	local cards: { { row: Frame, title: TextLabel, desc: TextLabel, swatch: Frame, deliver: TextButton, swap: TextButton } } = {}
	for i = 1, 3 do
		local row = Ui.row(list, "", "", Color3.new(1, 1, 1), 84)
		row.LayoutOrder = i
		local deliver = Ui.button(row, "DELIVER", UDim2.fromOffset(130, 40), UDim2.new(1, -142, 0, 6), Ui.green, function()
			Net.event("Deliver"):FireServer(i)
		end)
		deliver.ZIndex = 13
		local swap = Ui.button(row, "SWAP", UDim2.fromOffset(130, 28), UDim2.new(1, -142, 0, 50), Ui.gray, function()
			Net.event("SwapOrder"):FireServer(i)
		end)
		swap.ZIndex = 13
		cards[i] = { row = row, title = row:FindFirstChild("Title") :: TextLabel, desc = row:FindFirstChild("Desc") :: TextLabel, swatch = row:FindFirstChild("Swatch") :: Frame, deliver = deliver, swap = swap }
	end
	local function render()
		local data = Store.data
		if not data then
			return
		end
		local swapLeft = math.max(0, (data.swapAt or 0) - workspace:GetServerTimeNow())
		for i, card in cards do
			local order = data.orders and data.orders[i]
			card.row.Visible = order ~= nil
			if order then
				local crop = Crops.byKey[order.c]
				local have = data.barn[order.c] or 0
				card.title.Text = ("Bring %d %s"):format(order.n, crop.name)
				card.desc.Text = ("%s coins · %d XP · you have %d%s"):format(Format.short(order.coins), order.xp, have, if crop.level > data.level then " (buy at a stand!)" else "")
				card.swatch.BackgroundColor3 = crop.fruit
				Ui.setEnabled(card.deliver, Ui.green, have >= order.n)
				Ui.setText(card.swap, if swapLeft > 0 then "SWAP " .. Format.clock(swapLeft) else "SWAP")
			end
		end
	end
	Store.onChanged(render)
	task.spawn(function()
		while true do
			task.wait(1)
			if window.isOpen() then
				render()
			end
		end
	end)
	return window
end

return OrdersWindow
