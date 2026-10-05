-- Settings: low-end mode, trade requests, auto equip best. Saved on the server with the player's data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local SettingsPanel = {}

local OPTIONS = {
	{
		key = "lowEnd",
		label = "Low-end mode",
		text = "Hides other players' creatures and coin effects. Use it on older phones.",
	},
	{
		key = "allowTrades",
		label = "Trade requests",
		text = "Let other players send you trade requests.",
	},
	{
		key = "autoEquipBest",
		label = "Auto equip best",
		text = "Put stronger creatures on your team right after hatching.",
	},
	{
		key = "autoDeleteNormal",
		label = "Auto-delete Normal",
		text = "Normal creatures you already have are deleted when hatched. New ones are always kept.",
	},
	{
		key = "autoDeleteGolden",
		label = "Auto-delete Golden",
		text = "Same for Golden creatures you already have.",
	},
	{
		key = "sfx",
		label = "Sound effects",
		text = "Coins, hatching, rewards and buttons.",
	},
	{
		key = "music",
		label = "Music",
		text = "Background music.",
	},
}

function SettingsPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Settings", function()
		Windows.close("Settings")
	end)
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	Theme.list(scroll, 10)
	scroll.Parent = content

	local toggles: { [string]: TextButton } = {}
	for i, option in OPTIONS do
		local row = Theme.frame({ Size = UDim2.new(1, -10, 0, 70), BackgroundColor3 = Theme.card, LayoutOrder = i })
		Theme.corner(row, 12)
		row.Parent = scroll
		local name = Theme.label({
			Text = option.label,
			Font = Theme.titleFont,
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(0.7, -14, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 20,
		})
		name.Parent = row
		local text = Theme.label({
			Text = option.text,
			Font = Enum.Font.Gotham,
			TextColor3 = Theme.muted,
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(0.7, -14, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 14,
		})
		text.Parent = row
		local toggle = Theme.button({
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.new(0.22, 0, 0, 44),
			MaxTextSize = 20,
		})
		toggle.Parent = row
		toggle.Activated:Connect(function()
			local data = Store.data
			if data then
				Net.event("SetSetting"):FireServer(option.key, data.settings[option.key] ~= true)
			end
		end)
		toggles[option.key] = toggle
	end

	local function update()
		local data = Store.data
		if not data then
			return
		end
		for key, toggle in toggles do
			local on = data.settings[key] == true
			toggle.Text = if on then "ON" else "OFF"
			toggle.BackgroundColor3 = if on then Theme.green else Theme.card
		end
	end

	Store.DataChanged:Connect(update)
	Windows.register("Settings", window, update)
end

return SettingsPanel
