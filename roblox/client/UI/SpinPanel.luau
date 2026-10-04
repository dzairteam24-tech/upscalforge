-- Lucky Spin window: a reel of prizes slides and stops on what the server rolled. Chances are listed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WheelConfig = require(Shared.Config.Wheel)
local Format = require(Shared.Logic.Format)
local Progress = require(Shared.Logic.Progress)
local Wheel = require(Shared.Logic.Wheel)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local AdButton = require(script.Parent.AdButton)
local Notify = require(script.Parent.Notify)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local SpinPanel = {}

local CELL = 120
local GAP = 8
local REEL_LENGTH = 60 -- cells in the strip; the winner is placed near the end
local WIN_AT = 52

function SpinPanel.freeReady(): boolean
	local data = Store.data
	return data ~= nil and data.wheel ~= nil and Wheel.freeReady(data.wheel.lastFree, Progress.day(workspace:GetServerTimeNow()))
end

local function cell(index: number): Frame
	local slice = WheelConfig.slices[index]
	local frame = Theme.frame({ Size = UDim2.fromOffset(CELL, CELL), BackgroundColor3 = Theme.card })
	Theme.corner(frame, 12)
	Theme.stroke(frame, slice.color, 3)
	local label = Theme.label({
		Text = slice.label,
		Font = Theme.titleFont,
		TextColor3 = slice.color,
		Size = UDim2.new(1, -12, 0.7, 0),
		Position = UDim2.fromOffset(6, 6),
		MaxTextSize = 22,
	})
	label.Parent = frame
	local chance = Theme.label({
		Text = Format.chance(Wheel.chance(index)),
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.muted,
		Size = UDim2.new(1, -12, 0.22, 0),
		Position = UDim2.new(0, 6, 0.74, 0),
		MaxTextSize = 14,
	})
	chance.Parent = frame
	return frame
end

function SpinPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Lucky Spin", function()
		Windows.close("Spin")
	end)

	-- Reel
	local reelWindow = Theme.frame({
		Size = UDim2.new(1, 0, 0, CELL + 24),
		BackgroundColor3 = Color3.fromRGB(20, 24, 38),
		ClipsDescendants = true,
	})
	Theme.corner(reelWindow, 14)
	reelWindow.Parent = content
	local strip = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset((CELL + GAP) * REEL_LENGTH, CELL) })
	strip.Parent = reelWindow
	local marker = Theme.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = Theme.gold,
		ZIndex = 5,
	})
	marker.Parent = reelWindow

	local function fill(winner: number?)
		for _, child in strip:GetChildren() do
			child:Destroy()
		end
		for i = 1, REEL_LENGTH do
			local index = if i == WIN_AT and winner then winner else Wheel.spin(math.random)
			local c = cell(index)
			c.Position = UDim2.fromOffset((i - 1) * (CELL + GAP), 12)
			c.Parent = strip
		end
	end

	-- Lines up cell `i` under the marker.
	local function offsetFor(i: number): number
		local width = reelWindow.AbsoluteSize.X
		return width / 2 - ((i - 1) * (CELL + GAP) + CELL / 2)
	end

	-- Chances
	local odds = Theme.label({
		Text = "",
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.muted,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, CELL + 32),
		TextWrapped = true,
		MaxTextSize = 14,
	})
	odds.Parent = content
	local lines = {}
	for index, slice in WheelConfig.slices do
		table.insert(lines, ("%s %s"):format(slice.label, Format.chance(Wheel.chance(index))))
	end
	odds.Text = table.concat(lines, " · ")

	local result = Theme.label({
		Text = "",
		Font = Theme.titleFont,
		TextColor3 = Theme.gold,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, CELL + 80),
		MaxTextSize = 22,
	})
	result.Parent = content

	-- Buttons
	local row = Theme.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, 54),
	})
	row.Parent = content
	local freeButton = Theme.button({ Size = UDim2.new(1 / 3, -8, 1, 0), Position = UDim2.new(0, 4, 0, 0), BackgroundColor3 = Theme.green })
	local ticketButton = Theme.button({ Size = UDim2.new(1 / 3, -8, 1, 0), Position = UDim2.new(1 / 3, 4, 0, 0), BackgroundColor3 = Theme.gold })
	local adButton = Theme.button({ Size = UDim2.new(1 / 3, -8, 1, 0), Position = UDim2.new(2 / 3, 4, 0, 0), BackgroundColor3 = Theme.purple })
	for _, b in { freeButton, ticketButton, adButton } do
		b.Parent = row
	end

	local spinning = false

	local function update()
		local data = Store.data
		if not data then
			return
		end
		local free = SpinPanel.freeReady()
		freeButton.Text = if free then "Free spin!" else "Free: tomorrow"
		freeButton.BackgroundColor3 = if free then Theme.green else Theme.card
		local tickets: number = data.tickets or 0
		ticketButton.Text = ("🎟️ %d · Spin for %d"):format(tickets, WheelConfig.TICKET_COST)
		ticketButton.BackgroundColor3 = if tickets >= WheelConfig.TICKET_COST then Theme.gold else Theme.card
		local left = AdButton.left("AdSpin")
		adButton.Text = if left and left <= 0 then "▶ Back tomorrow" else ("▶ Watch & spin (%d)"):format(left or 0)
		adButton.BackgroundColor3 = if AdButton.available("AdSpin") then Theme.purple else Theme.card
	end

	freeButton.Activated:Connect(function()
		if not spinning and SpinPanel.freeReady() then
			Net.event("SpinWheel"):FireServer("free")
		end
	end)
	ticketButton.Activated:Connect(function()
		local data = Store.data
		if not spinning and data and (data.tickets or 0) >= WheelConfig.TICKET_COST then
			Net.event("SpinWheel"):FireServer("ticket")
		end
	end)
	adButton.Activated:Connect(function()
		if not spinning and AdButton.available("AdSpin") then
			AdButton.watch("AdSpin")
		end
	end)

	Net.event("WheelResult").OnClientEvent:Connect(function(index: number, summary: string)
		Windows.open("Spin")
		spinning = true
		result.Text = ""
		fill(index)
		strip.Position = UDim2.fromOffset(offsetFor(3), 12)
		local tween = TweenService:Create(
			strip,
			TweenInfo.new(4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(offsetFor(WIN_AT) + math.random(-CELL // 3, CELL // 3), 12) }
		)
		tween:Play()
		tween.Completed:Wait()
		spinning = false
		local slice = WheelConfig.slices[index]
		result.Text = ("%s! %s"):format(slice.label, (summary:gsub("\n", ", ")))
		Notify.show("Lucky Spin: " .. summary, if slice.id == "Jackpot" then "rare" else "success", 4)
		update()
	end)

	Store.DataChanged:Connect(function()
		if window.Visible then
			update()
		end
	end)
	Windows.register("Spin", window, function()
		if not spinning then
			fill(nil)
			strip.Position = UDim2.fromOffset(offsetFor(3), 12)
		end
		update()
	end)
end

return SpinPanel
