--!strict
-- Today's tasks (Config/Daily, Logic/Daily) with how far the player got, and the button to claim the egg once
-- they're all done.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DailyConfig = require(Shared.Config.Daily)
local Daily = require(Shared.Logic.Daily)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local DailyWindow = {}

-- Today's state for the player (a fresh one when their saved one is from another day)
function DailyWindow.state(): Daily.State
	local day = Daily.day(math.floor(workspace:GetServerTimeNow()))
	local saved = Store.data and Store.data.daily
	if saved and saved.day == day then
		return saved
	end
	return { day = day, progress = {}, claimed = false }
end

function DailyWindow.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "📋 Daily Tasks", Vector2.new(480, 380))
	local header = Theme.text(content, { Size = UDim2.new(1, 0, 0, 24), TextColor3 = Theme.soft, LayoutOrder = 0 })
	type Row = { text: TextLabel, mark: TextLabel }
	local rows: { Row } = {}
	for i = 1, DailyConfig.PER_DAY do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 54)
		row.BackgroundColor3 = Theme.card
		row.LayoutOrder = i
		Theme.round(row, 12)
		local text = Theme.text(row, { Size = UDim2.new(0.75, -12, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left })
		local mark = Theme.text(row, { Size = UDim2.new(0.25, -12, 1, -12), Position = UDim2.new(0.75, 0, 0, 6) })
		row.Parent = content
		table.insert(rows, { text = text, mark = mark })
	end
	local claim = Theme.button(content, "", Theme.gold, function()
		Net.event("ClaimDaily"):FireServer()
	end)
	claim.Size = UDim2.new(1, -8, 0, 52)
	claim.LayoutOrder = 10

	local function refresh()
		local state = DailyWindow.state()
		local now = workspace:GetServerTimeNow()
		header.Text = ("New tasks in %s"):format(Format.time(math.ceil((state.day + 1) * 86400 - now)))
		for i, id in Daily.tasks(state.day) do
			local task = DailyConfig.byId[id]
			local row = rows[i]
			if task and row then
				local got = math.min(state.progress[id] or 0, task.goal)
				row.text.Text = task.text:format(task.goal)
				row.mark.Text = if got >= task.goal then "✅" else ("%d / %d"):format(got, task.goal)
				row.mark.TextColor3 = if got >= task.goal then Theme.green else Theme.soft
			end
		end
		local ready = Daily.done(state) and not state.claimed
		claim.Text = if state.claimed then "✅ Claimed! Come back tomorrow" elseif ready then "🎁 Claim your free egg!" else "🎁 Finish all 3 for a free egg"
		claim.BackgroundColor3 = if ready then Theme.gold else Theme.soft
	end
	Windows.register("Daily", window, refresh)
	task.spawn(function()
		while true do
			if window.Visible then
				refresh()
			end
			task.wait(0.5)
		end
	end)
end

return DailyWindow
