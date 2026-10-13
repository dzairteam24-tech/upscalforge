--!strict
-- Rebirth: start again from the top for a permanent bonus on everything you sell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local RebirthConfig = require(Shared.Config.Rebirth)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local RebirthWindow = {}

function RebirthWindow.new(screen: ScreenGui)
	local window = Ui.window(screen, "REBIRTH", UDim2.fromOffset(520, 380))
	local body = window.body
	local function line(text: string, y: number, height: number, color: Color3?): TextLabel
		local l = Ui.label(body, text, UDim2.new(1, -20, 0, height), UDim2.fromOffset(10, y), color or Color3.fromRGB(60, 52, 70))
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.TextScaled = false
		l.TextSize = 22
		l.ZIndex = 12
		return l
	end
	local title = line("", 4, 34, Ui.gold)
	title.TextStrokeTransparency = 0
	title.TextSize = 28
	line(("Start again from the top. You lose your coins, shovel, backpack and depth. You keep your catalog, your passes and a permanent bonus: everything you sell is worth +%d%% more, for every rebirth."):format(math.floor(RebirthConfig.BONUS * 100)), 44, 110)
	local need = line("", 160, 60)
	local confirm = false
	local button: TextButton
	button = Ui.button(body, "Rebirth", UDim2.fromOffset(260, 56), UDim2.new(0.5, -130, 1, -76), Ui.gray, function()
		local data = Store.data
		if not data or not data.canRebirth then
			return
		end
		if not confirm then
			confirm = true
			button.Text = "Tap again to confirm"
			task.delay(3, function()
				confirm = false
				if Store.data then
					button.Text = "Rebirth"
				end
			end)
			return
		end
		confirm = false
		button.Text = "Rebirth"
		Net.event("Rebirth"):FireServer()
		window.close()
	end)
	Store.onChanged(function()
		local data = Store.data
		title.Text = ("Rebirth %d  (x%s now)"):format(data.rebirths + 1, tostring(math.floor(data.multiplier * 100 + 0.5) / 100))
		need.Text = if data.canRebirth then ("Ready! It costs %d coins."):format(data.rebirthCost) else (data.rebirthWhy or "")
		button.BackgroundColor3 = if data.canRebirth then Ui.green else Ui.gray
	end)
	return window
end

return RebirthWindow
