-- Reload window: what you get, what resets, what stays, and a two-tap confirm.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Expedition = require(Shared.Logic.Expedition)
local Format = require(Shared.Logic.Format)
local Reload = require(Shared.Logic.Reload)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local ReloadPanel = {}

local CONFIRM_SECONDS = 4

function ReloadPanel.canReload(): boolean
	local data = Store.data
	return data ~= nil and data.canReload == true
end

local function column(parent: Instance, title: string, color: Color3, x: number): TextLabel
	local box = Theme.frame({
		Position = UDim2.new(x, 4, 0, 70),
		Size = UDim2.new(1 / 3, -8, 1, -150),
		BackgroundColor3 = Theme.panel,
	})
	Theme.corner(box, 12)
	Theme.stroke(box, color, 2)
	box.Parent = parent
	local heading = Theme.label({
		Text = title,
		Font = Theme.titleFont,
		TextColor3 = color,
		Size = UDim2.new(1, -12, 0, 28),
		Position = UDim2.fromOffset(6, 6),
		MaxTextSize = 20,
	})
	heading.Parent = box
	local body = Theme.label({
		Text = "",
		Font = Enum.Font.Gotham,
		Size = UDim2.new(1, -16, 1, -44),
		Position = UDim2.fromOffset(8, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 16,
	})
	body.Parent = box
	return body
end

function ReloadPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Reload", function()
		Windows.close("Reload")
	end)

	local intro = Theme.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 60),
		MaxTextSize = 18,
	})
	intro.Parent = content

	local gain = column(content, "You get", Theme.gold, 0)
	local reset = column(content, "Resets", Theme.red, 1 / 3)
	local keep = column(content, "You keep", Theme.green, 2 / 3)
	reset.Text = "• Coins\n• Gates (back to Zone 1)\n• Zone restore %"
	keep.Text = "• All creatures\n• Items and Boost Cards\n• Upgrades\n• Gems\n• Pass, titles and trails\n• Trips in progress"

	local button = Theme.button({
		Text = "Reload",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(0.5, 0, 0, 56),
		BackgroundColor3 = Theme.purple,
		MaxTextSize = 26,
	})
	button.Parent = content

	local confirmUntil = 0

	local function update()
		local data = Store.data
		if not data then
			return
		end
		local reloads: number = data.reloads or 0
		local ready = data.canReload == true
		intro.Text = if ready
			then ("🔄 Reload %d → %d. The world loads again with new colors, and you come back stronger."):format(reloads, reloads + 1)
			else ("🔒 Unlock %s (Zone %d) to Reload. Reloads so far: %d"):format(
				Reload.requiredZoneName(),
				Constants.RELOAD_REQUIRED_ZONE,
				reloads
			)
		local trips: number = data.nextExpeditionSlots or Expedition.slots(reloads + 1)
		gain.Text = table.concat({
			("• Coins %s → %s forever"):format(Format.mult(data.reloadMult or 1), Format.mult(data.nextReloadMult or 1.5)),
			("• Boost Card slots %d → %d"):format(data.cartridgeSlots or 2, data.nextCartridgeSlots or 3),
			("• Trip slots: %d"):format(trips),
			"• New world colors",
		}, "\n")
		local confirming = os.clock() < confirmUntil
		button.Text = if not ready then "Locked" elseif confirming then "Tap again to Reload!" else "Reload"
		button.BackgroundColor3 = if not ready then Theme.card elseif confirming then Theme.red else Theme.purple
	end

	button.Activated:Connect(function()
		if not ReloadPanel.canReload() then
			return
		end
		if os.clock() < confirmUntil then
			confirmUntil = 0
			Net.event("Reload"):FireServer(true)
			Windows.close("Reload")
		else
			confirmUntil = os.clock() + CONFIRM_SECONDS
			task.delay(CONFIRM_SECONDS, update)
		end
		update()
	end)

	Store.DataChanged:Connect(function()
		if window.Visible then
			update()
		end
	end)
	Windows.register("Reload", window, function()
		confirmUntil = 0
		update()
	end)
end

return ReloadPanel
