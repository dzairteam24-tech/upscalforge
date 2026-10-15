--!strict
-- The daily reward: seven days that grow; a missed day just pauses the streak.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DailyConfig = require(Shared.Config.Daily)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local DailyWindow = {}

function DailyWindow.new(screen: ScreenGui): Ui.Window
	local window = Ui.window(screen, "DAILY REWARD", Ui.pink, UDim2.fromOffset(600, 300))
	local body = window.body
	local tiles: { Frame } = {}
	local n = #DailyConfig.REWARDS
	for i, reward in DailyConfig.REWARDS do
		local tile = Ui.panel(body, UDim2.new(1 / n, -8, 0, 120), UDim2.new((i - 1) / n, 4, 0, 4), Ui.pink)
		tile.ZIndex = 12
		local day = Ui.label(tile, "DAY " .. i, UDim2.new(1, -8, 0, 20), UDim2.fromOffset(4, 8), Ui.text, Ui.heavy)
		day.ZIndex = 13
		local coins = Ui.label(tile, "coins", UDim2.new(1, -8, 0, 18), UDim2.fromOffset(4, 52), Ui.gold)
		coins.ZIndex = 13
		if reward.boost then
			local boost = Ui.label(tile, ("+%dm 2x"):format(reward.boost), UDim2.new(1, -8, 0, 16), UDim2.fromOffset(4, 78), Ui.green)
			boost.ZIndex = 13
		end
		tiles[i] = tile
	end
	local claim = Ui.button(body, "CLAIM", UDim2.fromOffset(220, 52), UDim2.new(0.5, -110, 0, 150), Ui.pink, function()
		Net.event("Daily"):FireServer()
	end)
	claim.ZIndex = 12
	Store.onChanged(function()
		local data = Store.data
		for i, tile in tiles do
			local stroke = tile:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Transparency = if i == data.dailyIndex then 0 else 0.7
			stroke.Thickness = if i == data.dailyIndex then 2.5 else 1
		end
		Ui.setText(claim, if data.dailyReady then "CLAIM" else "COME BACK TOMORROW")
		claim.BackgroundColor3 = if data.dailyReady then Ui.pink else Color3.fromRGB(70, 74, 100)
	end)
	return window
end

return DailyWindow
