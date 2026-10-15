--!strict
-- Trading with another farmer: a question when someone asks, then a window with both sides. Your side: crops
-- from your barn and coins, with + and -. When both press READY it's done; any change takes READY away.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crops = require(Shared.Config.Crops)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local TradeWindow = {}

function TradeWindow.new(screen: ScreenGui): Ui.Window
	local state: any = nil
	-- (closing the window calls the trade off)
	local window = Ui.window(screen, "TRADE", Ui.blue, UDim2.fromOffset(700, 470), function()
		if state then
			Net.event("TradeCancel"):FireServer()
		end
	end)
	local body = window.body
	-- the question
	local ask = Ui.panel(screen, UDim2.fromOffset(420, 120), UDim2.new(0.5, -210, 0.32, 0))
	ask.Visible = false
	ask.ZIndex = 20
	local askText = Ui.label(ask, "", UDim2.new(1, -24, 0, 34), UDim2.fromOffset(12, 10))
	askText.ZIndex = 21
	local askFrom = 0
	Ui.button(ask, "TRADE", UDim2.fromOffset(170, 48), UDim2.fromOffset(20, 56), Ui.green, function()
		ask.Visible = false
		Net.event("TradeAnswer"):FireServer(askFrom, true)
	end).ZIndex = 21
	Ui.button(ask, "NO THANKS", UDim2.fromOffset(170, 48), UDim2.new(1, -190, 0, 56), Ui.gray, function()
		ask.Visible = false
		Net.event("TradeAnswer"):FireServer(askFrom, false)
	end).ZIndex = 21
	Net.event("TradeAsked").OnClientEvent:Connect(function(userId: number, name: string)
		askFrom = userId
		askText.Text = name .. " wants to trade with you"
		ask.Visible = true
		task.delay(25, function()
			if askFrom == userId then
				ask.Visible = false
			end
		end)
	end)

	-- the two sides
	local mineBox = Instance.new("Frame")
	mineBox.BackgroundTransparency = 1
	mineBox.Size = UDim2.new(0.5, -6, 1, -70)
	mineBox.ZIndex = 11
	mineBox.Parent = body
	local theirsBox = Instance.new("Frame")
	theirsBox.BackgroundTransparency = 1
	theirsBox.Size = UDim2.new(0.5, -6, 1, -70)
	theirsBox.Position = UDim2.new(0.5, 6, 0, 0)
	theirsBox.ZIndex = 11
	theirsBox.Parent = body
	local mineList = Ui.list(mineBox, 6)
	local theirsList = Ui.list(theirsBox, 6)
	local ready = Ui.button(body, "READY", UDim2.new(0.5, -6, 0, 54), UDim2.new(0, 0, 1, -58), Ui.green, function() end)
	ready.ZIndex = 12
	local cancel = Ui.button(body, "CANCEL", UDim2.new(0.5, -6, 0, 54), UDim2.new(0.5, 6, 1, -58), Ui.red, function()
		Net.event("TradeCancel"):FireServer()
	end)
	cancel.ZIndex = 12

	local items: { [string]: number } = {}
	local coins = 0
	local function send()
		Net.event("TradeOffer"):FireServer(items, coins)
	end
	ready.Activated:Connect(function()
		if state then
			Net.event("TradeReady"):FireServer(not state.myReady)
		end
	end)

	local function line(parent: Instance, text: string, color: Color3?, height: number?): TextLabel
		local l = Ui.label(parent, text, UDim2.new(1, -8, 0, height or 24), UDim2.new(), color)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.ZIndex = 12
		return l
	end
	local function clear(list: Instance)
		for _, c in list:GetChildren() do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
	end

	local function render()
		local data = Store.data
		if not state or not data then
			return
		end
		clear(mineList)
		clear(theirsList)
		line(mineList, if state.myReady then "YOU GIVE (ready)" else "YOU GIVE", if state.myReady then Ui.green else Ui.text)
		for _, crop in Crops.LIST do
			local have = data.barn[crop.key] or 0
			if have > 0 then
				local r = Instance.new("Frame")
				r.BackgroundTransparency = 1
				r.Size = UDim2.new(1, -8, 0, 40)
				r.ZIndex = 12
				r.Parent = mineList
				local l = Ui.label(r, ("%s  %d/%d"):format(crop.name, items[crop.key] or 0, have), UDim2.new(1, -100, 1, -8), UDim2.fromOffset(0, 4))
				l.TextXAlignment = Enum.TextXAlignment.Left
				l.ZIndex = 13
				Ui.button(r, "-", UDim2.fromOffset(40, 36), UDim2.new(1, -90, 0, 2), Ui.gray, function()
					items[crop.key] = math.max(0, (items[crop.key] or 0) - 1)
					send()
				end).ZIndex = 13
				Ui.button(r, "+", UDim2.fromOffset(40, 36), UDim2.new(1, -44, 0, 2), Ui.green, function()
					items[crop.key] = math.min(have, (items[crop.key] or 0) + 1)
					send()
				end).ZIndex = 13
			end
		end
		local c = Instance.new("Frame")
		c.BackgroundTransparency = 1
		c.Size = UDim2.new(1, -8, 0, 40)
		c.ZIndex = 12
		c.Parent = mineList
		local cl = Ui.label(c, "Coins " .. Format.short(coins), UDim2.new(1, -140, 1, -8), UDim2.fromOffset(0, 4), Ui.orange)
		cl.TextXAlignment = Enum.TextXAlignment.Left
		cl.ZIndex = 13
		for i, step in { -100, -10, 10, 100 } do
			Ui.button(c, (if step > 0 then "+" else "") .. step, UDim2.fromOffset(44, 36), UDim2.new(1, -184 + i * 46, 0, 2), if step > 0 then Ui.green else Ui.gray, function()
				coins = math.clamp(coins + step, 0, data.coins)
				send()
			end).ZIndex = 13
		end
		line(theirsList, if state.theirReady then state.with .. " GIVES (ready)" else state.with .. " GIVES", if state.theirReady then Ui.green else Ui.text)
		local any = false
		for _, crop in Crops.LIST do
			local n = state.theirs.items[crop.key]
			if n and n > 0 then
				any = true
				line(theirsList, ("%d %s"):format(n, crop.name), crop.fruit:Lerp(Ui.ink, 0.3), 30)
			end
		end
		if state.theirs.coins > 0 then
			any = true
			line(theirsList, Format.short(state.theirs.coins) .. " coins", Ui.orange, 30)
		end
		if not any then
			line(theirsList, "(nothing yet)", Ui.dim)
		end
		Ui.setText(ready, if state.myReady then "NOT READY" else "READY")
	end

	Net.event("TradeState").OnClientEvent:Connect(function(newState: any)
		local starting = newState and not state
		state = newState
		if not newState then
			table.clear(items)
			coins = 0
			window.close()
			return
		end
		if starting then
			table.clear(items)
			coins = 0
			window.open()
		end
		render()
	end)
	Store.onChanged(function()
		if state then
			render()
		end
	end)
	return window
end

return TradeWindow
