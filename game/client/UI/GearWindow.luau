--!strict
-- The Gear Shop's window (Config/Gear): the player's bat, the next one and its price, and how the bat works.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearConfig = require(Shared.Config.Gear)
local Format = require(Shared.Logic.Format)
local Gear = require(Shared.Logic.Gear)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local GearWindow = {}

function GearWindow.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "🏏 Gear Shop", Vector2.new(520, 360))
	Theme.text(content, {
		Text = ("Hit a player carrying an egg to knock it out of their hands: %d hits with the same bat, fewer with a better one"):format(GearConfig.HITS),
		Size = UDim2.new(1, 0, 0, 40),
		TextColor3 = Theme.soft,
		TextWrapped = true,
		LayoutOrder = 0,
	})
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 84)
	row.BackgroundColor3 = Theme.card
	row.LayoutOrder = 1
	Theme.round(row, 12)
	local current = Theme.text(row, { Size = UDim2.new(0.6, -16, 0, 30), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left })
	local nextText = Theme.text(row, { Size = UDim2.new(0.6, -16, 0, 26), Position = UDim2.fromOffset(12, 44), TextColor3 = Theme.soft, TextXAlignment = Enum.TextXAlignment.Left })
	local buy = Theme.button(row, "", Theme.green, function()
		Net.event("UpgradeBat"):FireServer()
	end)
	buy.Size = UDim2.new(0.36, 0, 0, 52)
	buy.Position = UDim2.new(0.62, 0, 0, 16)
	row.Parent = content

	local function refresh()
		local data = Store.data
		local level = if data then data.bat or 1 else 1
		current.Text = "🏏 " .. Gear.bat(level).name
		local price = Gear.upgradePrice(level)
		nextText.Text = if price then "Next: " .. Gear.bat(level + 1).name else "The best bat!"
		buy.Text = if price then "🪙 " .. Format.abbrev(price) else "Max"
		buy.BackgroundColor3 = if price and Store.coins() >= price then Theme.green else Theme.soft
	end
	Windows.register("Gear", window, refresh)
	task.spawn(function()
		while true do
			if window.Visible then
				refresh()
			end
			task.wait(0.5)
		end
	end)
end

return GearWindow
