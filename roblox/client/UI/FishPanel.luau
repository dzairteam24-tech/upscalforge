-- Fishing Pond window: cast, wait for the bite, then tap while the marker is in the green for a Perfect.
-- The server times everything (FishingService); this window only shows it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FishingConfig = require(Shared.Config.Fishing)
local Fishing = require(Shared.Logic.Fishing)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local FishPanel = {}

function FishPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Fishing Pond", function()
		Windows.close("Fish")
	end)

	local info = Theme.label({
		Text = "",
		Size = UDim2.new(1, -12, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
	})
	info.Parent = content

	local water = Theme.button({
		Name = "Water",
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, -12, 0, 120),
		BackgroundColor3 = Color3.fromRGB(40, 110, 175),
	})
	water.Parent = content
	local bobber = Theme.label({
		Text = "🎣",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(60, 60),
		MaxTextSize = 48,
	})
	bobber.Parent = water
	local status = Theme.label({
		Text = "",
		Font = Theme.titleFont,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -16, 0, 28),
		TextColor3 = Color3.new(1, 1, 1),
		MaxTextSize = 20,
	})
	status.Parent = water

	-- Timing bar: the marker bounces; tap while it's in the green for a Perfect
	local bar = Theme.frame({
		Position = UDim2.fromOffset(0, 154),
		Size = UDim2.new(1, -12, 0, 22),
		BackgroundColor3 = Theme.card,
		Visible = false,
	})
	Theme.corner(bar, 6)
	bar.Parent = content
	local green = Theme.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(FishingConfig.GREEN, 1),
		BackgroundColor3 = Theme.green,
	})
	green.Parent = bar
	local marker = Theme.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(0, 6, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
	})
	marker.Parent = bar

	local action = Theme.button({
		Text = "Cast",
		Position = UDim2.fromOffset(0, 182),
		Size = UDim2.new(0.6, -12, 0, 44),
		BackgroundColor3 = Theme.green,
		MaxTextSize = 20,
	})
	action.Parent = content
	local autoButton = Theme.button({
		Text = "Auto Fish: OFF",
		Position = UDim2.new(0.6, 0, 0, 182),
		Size = UDim2.new(0.4, -12, 0, 44),
		BackgroundColor3 = Theme.card,
		MaxTextSize = 16,
	})
	autoButton.Parent = content

	local index = Instance.new("ScrollingFrame")
	index.BackgroundTransparency = 1
	index.BorderSizePixel = 0
	index.Position = UDim2.fromOffset(0, 232)
	index.Size = UDim2.new(1, 0, 1, -232)
	index.ScrollBarThickness = 6
	index.AutomaticCanvasSize = Enum.AutomaticSize.Y
	index.CanvasSize = UDim2.new()
	index.Parent = content
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -8, 0, 30)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = index

	local state = "idle" -- idle | waiting | bite
	local biteAt = 0
	local auto = false
	local cells: { [string]: TextLabel } = {}
	for i, fish in FishingConfig.fish do
		local cell = Theme.label({
			Text = "",
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.card,
			LayoutOrder = i,
			MaxTextSize = 14,
		})
		Theme.corner(cell, 6)
		cell.Parent = index
		cells[fish.id] = cell
	end

	local function update()
		local data = Store.data
		local fishing = data and (data :: any).fishing
		local caught = if fishing then fishing.caught else {}
		local kinds = if fishing then Fishing.kinds(fishing) else 0
		info.Text = ("Fish Index %d/%d · caught %d · catch all for the Angler title"):format(
			kinds,
			#FishingConfig.fish,
			if fishing then fishing.total else 0
		)
		for _, fish in FishingConfig.fish do
			local count = caught[fish.id] or 0
			local rarity = FishingConfig.raritiesById[fish.rarity]
			cells[fish.id].Text = if count > 0 then ("%s %s ×%d"):format(fish.icon, fish.name, count) else ("❔ %s fish"):format(fish.rarity)
			cells[fish.id].TextColor3 = if count > 0 then rarity.color else Theme.muted
		end
		if state == "idle" then
			action.Text = if auto then "Auto fishing..." else "Cast"
			action.BackgroundColor3 = if auto then Theme.panel else Theme.green
		elseif state == "waiting" then
			action.Text = "Wait for it..."
			action.BackgroundColor3 = Theme.panel
		else
			action.Text = if auto then "Reeling..." else "REEL!"
			action.BackgroundColor3 = if auto then Theme.panel else Theme.red
		end
		autoButton.Text = if auto then "Auto Fish: ON" else "Auto Fish: OFF"
		autoButton.BackgroundColor3 = if auto then Theme.green else Theme.card
	end

	local function press()
		if auto then
			return
		end
		if state == "idle" then
			Net.event("FishCast"):FireServer()
		elseif state == "waiting" then
			Net.event("FishReel"):FireServer(false) -- too early
		elseif state == "bite" then
			local perfect = Fishing.isPerfect(Fishing.marker(os.clock() - biteAt))
			state = "idle"
			bar.Visible = false
			Net.event("FishReel"):FireServer(perfect)
			update()
		end
	end
	action.Activated:Connect(press)
	water.Activated:Connect(press)
	autoButton.Activated:Connect(function()
		Net.event("FishAuto"):FireServer(not auto)
	end)

	Net.event("FishCast").OnClientEvent:Connect(function()
		state = "waiting"
		status.Text = "Waiting for a bite..."
		bobber.Text = "🎣"
		update()
	end)
	Net.event("FishBite").OnClientEvent:Connect(function(isAuto: boolean)
		state = "bite"
		biteAt = os.clock()
		status.Text = if isAuto then "A bite!" else "BITE! Tap in the green!"
		bobber.Text = "💦"
		bar.Visible = not isAuto
		update()
	end)
	Net.event("FishResult").OnClientEvent:Connect(function(fishId: string?, perfect: boolean, isNew: boolean, text: string)
		state = "idle"
		bar.Visible = false
		local fish = if fishId then FishingConfig.fishById[fishId] else nil
		if fish then
			bobber.Text = fish.icon
			status.Text = ("%s%s%s · %s"):format(if perfect then "PERFECT! " else "", if isNew then "NEW " else "", fish.name, text)
			status.TextColor3 = FishingConfig.raritiesById[fish.rarity].color
		else
			bobber.Text = "🎣"
			status.Text = text
			status.TextColor3 = Color3.new(1, 1, 1)
		end
		update()
	end)
	Net.event("FishAuto").OnClientEvent:Connect(function(on: boolean)
		auto = on
		update()
	end)

	RunService.RenderStepped:Connect(function()
		if state == "bite" and bar.Visible and window.Visible then
			marker.Position = UDim2.fromScale(Fishing.marker(os.clock() - biteAt), 0)
		elseif state == "waiting" and window.Visible then
			bobber.Position = UDim2.fromScale(0.5, 0.45 + math.sin(os.clock() * 3) * 0.04)
		end
	end)

	Store.DataChanged:Connect(function()
		if window.Visible then
			update()
		end
	end)
	Windows.register("Fish", window, function()
		if state == "idle" and status.Text == "" then
			status.Text = "Tap Cast, then tap again when a fish bites"
		end
		update()
	end)
	-- Closing the window turns Auto Fish off (it would keep going unseen otherwise)
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if not window.Visible and auto then
			Net.event("FishAuto"):FireServer(false)
		end
	end)
end

return FishPanel
