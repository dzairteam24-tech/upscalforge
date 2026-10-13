--!strict
-- "Welcome back": what the drone mined while you were away.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local OfflineConfig = require(Shared.Config.Offline)

local Ui = require(script.Parent.Ui)

local OfflineWindow = {}

function OfflineWindow.new(screen: ScreenGui)
	local window = Ui.window(screen, "WELCOME BACK!", UDim2.fromOffset(480, 280))
	local body = window.body
	local text = Ui.label(body, "", UDim2.new(1, -20, 0, 90), UDim2.fromOffset(10, 6), Color3.fromRGB(60, 52, 70))
	text.TextStrokeTransparency = 1
	text.TextWrapped = true
	text.TextScaled = false
	text.TextSize = 26
	text.ZIndex = 12
	local hint = Ui.label(body, "", UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 100), Color3.fromRGB(110, 100, 125))
	hint.TextStrokeTransparency = 1
	hint.TextWrapped = true
	hint.TextScaled = false
	hint.TextSize = 18
	hint.ZIndex = 12
	Ui.button(body, "Nice!", UDim2.fromOffset(200, 50), UDim2.new(0.5, -100, 1, -66), Ui.green, window.close)
	Net.event("Offline").OnClientEvent:Connect(function(coins: number, seconds: number, capped: boolean)
		local hours = seconds / 3600
		text.Text = ("Your drone mined for %s while you were away:\n+%d coins"):format(if hours >= 1 then string.format("%.1f hours", hours) else string.format("%d minutes", math.floor(seconds / 60)), coins)
		hint.Text = if capped then ("It was full after %d hours. The Long Offline Miner pass makes it work up to %d."):format(OfflineConfig.FREE_HOURS, OfflineConfig.PASS_HOURS) else ""
		window.open()
	end)
	return window
end

return OfflineWindow
