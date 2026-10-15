--!strict
-- Upgrades, bought with coins: Orb Power (more speed from every orb), Coin Gain, Magnet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Logic.Economy)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Ui)

local UpgradesWindow = {}

local ACCENTS: { [string]: Color3 } = { orb = Ui.cyan, coin = Ui.gold, magnet = Ui.pink }

function UpgradesWindow.new(screen: ScreenGui): Ui.Window
	local window = Ui.window(screen, "UPGRADES", Ui.cyan, UDim2.fromOffset(560, 330))
	local list = Ui.list(window.body)
	local rows: { [string]: { level: TextLabel, button: TextButton } } = {}
	for i, upgrade in Economy.UPGRADES do
		local accent = ACCENTS[upgrade.key] or Ui.cyan
		local card = Ui.card(list, upgrade.name, upgrade.desc, accent, 70)
		card.LayoutOrder = i
		local level = Ui.label(card, "", UDim2.fromOffset(90, 18), UDim2.new(0.62, -10, 0, 12), accent)
		level.TextXAlignment = Enum.TextXAlignment.Left
		level.ZIndex = 13
		local button = Ui.button(card, "", UDim2.fromOffset(150, 44), UDim2.new(1, -162, 0, 13), Ui.green, function()
			Net.event("Buy"):FireServer(upgrade.key)
		end)
		button.ZIndex = 13
		rows[upgrade.key] = { level = level, button = button }
	end
	Store.onChanged(function()
		local data = Store.data
		for _, upgrade in Economy.UPGRADES do
			local row = rows[upgrade.key]
			local have = data.upgrades[upgrade.key] or 0
			row.level.Text = ("Lv %d/%d"):format(have, upgrade.max)
			if have >= upgrade.max then
				Ui.setText(row.button, "MAX")
				row.button.BackgroundColor3 = Color3.fromRGB(70, 74, 100)
			else
				local cost = Economy.upgradeCost(upgrade, have)
				Ui.setText(row.button, Format.short(cost) .. " coins")
				row.button.BackgroundColor3 = if data.coins >= cost then Ui.green else Color3.fromRGB(70, 74, 100)
			end
		end
	end)
	return window
end

return UpgradesWindow
