--!strict
-- The daily reward: seven days in a cycle, each better than the last. A missed day waits; nothing is lost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DailyConfig = require(Shared.Config.Daily)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local DailyWindow = {}

function DailyWindow.new(screen: ScreenGui)
	local window = Ui.window(screen, "DAILY REWARD", UDim2.fromOffset(620, 300))
	local body = window.body
	local cells = {}
	local count = #DailyConfig.REWARDS
	for i, reward in DailyConfig.REWARDS do
		local cell = Ui.frame(body, UDim2.new(1 / count, -6, 0, 120), UDim2.new((i - 1) / count, 3, 0, 6), Color3.fromRGB(240, 232, 218))
		cell.ZIndex = 12
		local day = Ui.label(cell, "Day " .. i, UDim2.new(1, -8, 0, 24), UDim2.fromOffset(4, 6), Color3.fromRGB(60, 52, 70))
		day.TextStrokeTransparency = 1
		day.ZIndex = 13
		local text = ("%d min of coins"):format(reward.income) .. (if reward.boost then ("\n+%d min boost"):format(reward.boost) else "")
		local what = Ui.label(cell, text, UDim2.new(1, -8, 0, 70), UDim2.fromOffset(4, 36), Color3.fromRGB(110, 100, 125))
		what.TextStrokeTransparency = 1
		what.TextScaled = false
		what.TextSize = 15
		what.TextWrapped = true
		what.ZIndex = 13
		cells[i] = cell
	end
	local button = Ui.button(body, "Claim", UDim2.fromOffset(240, 56), UDim2.new(0.5, -120, 1, -76), Ui.gray, function()
		local data = Store.data
		if data and data.dailyReady then
			Net.event("Daily"):FireServer()
		end
	end)
	Store.onChanged(function()
		local data = Store.data
		for i, cell in cells do
			cell.BackgroundColor3 = if i == data.dailyIndex then Ui.gold elseif i < data.dailyIndex then Color3.fromRGB(190, 220, 190) else Color3.fromRGB(240, 232, 218)
		end
		button.Text = if data.dailyReady then "Claim" else "Come back tomorrow"
		button.BackgroundColor3 = if data.dailyReady then Ui.green else Ui.gray
	end)
	return window
end

return DailyWindow
