--!strict
-- Rebirth: once the whole course is beaten, start it again from stage 1 (speed, coins and upgrades go) for a
-- lasting bonus on every orb and coin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Logic.Economy)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local RebirthWindow = {}

function RebirthWindow.new(screen: ScreenGui): Ui.Window
	local window = Ui.window(screen, "REBIRTH", Ui.violet, UDim2.fromOffset(480, 320))
	local body = window.body
	local now = Ui.label(body, "", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 4), Ui.text, Ui.heavy)
	now.ZIndex = 12
	local info = Ui.label(body, "Start the course again from stage 1. Your speed, coins and upgrades reset, but every orb and coin is worth more, for good.", UDim2.new(1, 0, 0, 64), UDim2.fromOffset(0, 44), Ui.dim)
	info.TextWrapped = true
	info.ZIndex = 12
	local why = Ui.label(body, "", UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 118), Ui.red)
	why.ZIndex = 12
	local button = Ui.button(body, "REBIRTH", UDim2.fromOffset(240, 54), UDim2.new(0.5, -120, 0, 156), Ui.violet, function()
		Net.event("Rebirth"):FireServer()
	end)
	button.ZIndex = 12
	Store.onChanged(function()
		local data = Store.data
		local bonus = math.floor((data.rebirths + 1) * Economy.REBIRTH_BONUS * 100 + 0.5)
		now.Text = ("Rebirth %d  →  +%d%% orbs & coins"):format(data.rebirths + 1, bonus)
		why.Text = if data.canRebirth then "" else (data.rebirthWhy or "")
		Ui.setText(button, ("REBIRTH  ·  %s coins"):format(Format.short(data.rebirthCost)))
		button.BackgroundColor3 = if data.canRebirth then Ui.violet else Color3.fromRGB(70, 74, 100)
	end)
	return window
end

return RebirthWindow
