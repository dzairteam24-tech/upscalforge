-- Daily reward: 7-day cycle, today's reward highlighted, claim button and time to the next one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared.Config.Progression)
local Format = require(Shared.Logic.Format)
local Progress = require(Shared.Logic.Progress)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local AdButton = require(script.Parent.AdButton)
local Rewards = require(script.Parent.Rewards)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local DailyPanel = {}

-- Day (1..7) the player can claim now, or nil.
function DailyPanel.claimable(): number?
	local data = Store.data
	if not data then
		return nil
	end
	return Progress.dailyNext(data.daily, Progress.day(os.time()))
end

function DailyPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Daily Reward", function()
		Windows.close("Daily")
	end)

	local row = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.62, 0) })
	local layout = Theme.list(row, 8, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.Parent = content

	local status = Theme.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0.66, 0),
		MaxTextSize = 20,
	})
	status.Parent = content
	local claim = Theme.button({
		Text = "Claim",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.78, 0),
		Size = UDim2.new(0.4, 0, 0.16, 0),
		BackgroundColor3 = Theme.green,
	})
	claim.Parent = content
	claim.Activated:Connect(function()
		Net.event("ClaimDaily"):FireServer()
	end)
	local save = Theme.button({
		Text = "▶ Save streak",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.72, 0, 0.78, 0),
		Size = UDim2.new(0.4, 0, 0.16, 0),
		BackgroundColor3 = Theme.purple,
		Visible = false,
	})
	save.Parent = content
	save.Activated:Connect(function()
		AdButton.take("AdStreak", "StreakSave")
	end)

	local function rebuild()
		for _, child in row:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local data = Store.data
		local today = DailyPanel.claimable()
		local streak = if data then data.daily.streak else 0
		local current = today or ((streak - 1) % #Progression.DAILY) + 1
		for day, reward in Progression.DAILY do
			local isToday = day == current
			local card = Theme.frame({
				Size = UDim2.new(1 / 7, -8, 1, 0),
				BackgroundColor3 = if isToday then Color3.fromRGB(70, 90, 140) else Theme.card,
				LayoutOrder = day,
			})
			Theme.corner(card, 10)
			Theme.stroke(card, if isToday then Theme.gold else Theme.muted, if isToday then 3 else 1)
			local dayLabel = Theme.label({
				Text = "Day " .. day,
				Font = Theme.titleFont,
				Size = UDim2.new(1, -6, 0, 26),
				Position = UDim2.fromOffset(3, 4),
				MaxTextSize = 20,
			})
			dayLabel.Parent = card
			local text = Theme.label({
				Text = Rewards.describe(reward, data),
				Font = Enum.Font.Gotham,
				Size = UDim2.new(1, -8, 1, -38),
				Position = UDim2.fromOffset(4, 34),
				TextYAlignment = Enum.TextYAlignment.Top,
				MaxTextSize = 14,
			})
			text.Parent = card
			card.Parent = row
		end
		local savable = data ~= nil
			and Progress.streakSavable(data.daily, Progress.day(os.time()))
			and AdButton.offer("AdStreak", "StreakSave") ~= nil
		save.Visible = savable
		claim.Position = UDim2.new(if savable then 0.28 else 0.5, 0, 0.78, 0)
		if savable then
			save.Text = AdButton.label("AdStreak", "StreakSave", ("Keep my %d-day streak"):format(streak))
		end
		if today then
			status.Text = if savable
				then ("You missed a day! Keep your streak, or start again from Day 1.")
				else ("Day %d is ready! Streak: %d"):format(today, streak)
			claim.Visible = true
		else
			status.Text = ("Next reward in %s · Streak: %d days"):format(Format.time(Progress.secondsToNextDay(os.time())), streak)
			claim.Visible = false
		end
	end

	Store.DataChanged:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	Windows.register("Daily", window, rebuild)
end

return DailyPanel
