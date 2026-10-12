--!strict
-- Growing Eggs, as in Steal an Egg: a panel opened by the egg button on the right (HUD), beside it, with every egg hatching in the player's garden (on the
-- grass or in an incubator), each with its bar and the time left (nights count: Logic/Night), and Grow All (the
-- Hatch All Now product, Config/Robux). A ready egg hatches from anywhere with its HATCH! button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Night = require(Shared.Logic.Night)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)

local GrowingEggs = {}

local opened = false -- (the egg button toggles it)
local holderRef: Frame? = nil
local count = 0 -- eggs hatching
local readyCount = 0 -- of them, ready to hatch

-- Opens or closes the panel (the HUD's egg button)
function GrowingEggs.toggle()
	opened = not opened
	if holderRef then
		holderRef.Visible = opened
	end
end

-- How many eggs are hatching, and how many are ready (for the egg button's badge)
function GrowingEggs.counts(): (number, number)
	return count, readyCount
end

local ROW = 58
local MAX_ROWS = 6

type Row = { frame: Frame, fill: Frame, time: TextLabel, hatch: TextButton, start: number, seconds: number }

function GrowingEggs.mount(gui: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "GrowingEggs"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -96, 0.5, 0) -- (beside the right column of buttons, where its egg button is)
	holder.Visible = false
	holderRef = holder
	holder.Size = UDim2.fromOffset(330, 70)
	holder.Parent = gui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
	Theme.round(panel, 12)
	Theme.stroke(panel, Theme.outline, 3)
	panel.Parent = holder
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 48)
	Theme.gradient(header, Color3.fromRGB(210, 170, 120), 0.2, 0.1)
	Theme.round(header, 12)
	header.Parent = panel
	Theme.bold(header, { Text = "Growing Eggs", Size = UDim2.new(0.42, -12, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 28 })
	local growAll = Theme.button(header, "Grow All", Color3.fromRGB(255, 170, 30), function()
		Net.event("BuyRobux"):FireServer("HatchAll")
	end)
	growAll.AnchorPoint = Vector2.new(1, 0.5)
	growAll.Position = UDim2.new(1, -8, 0.5, 0)
	growAll.Size = UDim2.new(0.3, 0, 0, 36)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(8, 56)
	list.Size = UDim2.new(1, -16, 1, -64)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	list.Parent = panel

	local rows: { [string]: Row } = {}
	local shown = ""

	local function rebuild()
		local data = Store.data
		local eggs: { [string]: any } = if data then data.incubating else {}
		local keys = {}
		for key in eggs do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return (tonumber(a) or 0) < (tonumber(b) or 0)
		end)
		local fast = Players.LocalPlayer:GetAttribute("FastHatch") == true
		local signature = table.concat(keys, ",") .. (if fast then "f" else "")
		for _, key in keys do
			signature ..= ":" .. eggs[key].tier .. "@" .. eggs[key].start
		end
		count = #keys
		holder.Visible = opened and #keys > 0
		if signature == shown then
			return
		end
		shown = signature
		for _, row in rows do
			row.frame:Destroy()
		end
		table.clear(rows)
		for i, key in keys do
			if i > MAX_ROWS then
				break
			end
			local egg = eggs[key]
			local info = Hatch.egg(egg.tier)
			local seconds = Hatch.secondsIn(egg.tier, tonumber(key) or 1)
			if fast then
				seconds = math.floor(seconds / 2)
			end
			local frame = Theme.card(list, Color3.fromRGB(70, 70, 90), { Size = UDim2.new(1, 0, 0, ROW), LayoutOrder = i })
			local view = Theme.eggView(frame, if info then info.color else Color3.new(1, 1, 1), egg.m ~= nil)
			view.Size = UDim2.fromOffset(ROW - 6, ROW - 6)
			view.Position = UDim2.fromOffset(3, 3)
			local bar = Instance.new("Frame")
			bar.Position = UDim2.fromOffset(ROW + 4, 12)
			bar.Size = UDim2.new(1, -ROW - 14, 0, ROW - 24)
			bar.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
			Theme.round(bar, 8)
			local fill = Instance.new("Frame")
			Theme.gradient(fill, Theme.green, 0.25, 0.1)
			Theme.round(fill, 8)
			fill.Parent = bar
			local time = Theme.bold(bar, { Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), MaxText = 24 })
			bar.Parent = frame
			local slot = tonumber(key) or 1
			local hatch = Theme.button(frame, "HATCH!", Theme.green, function()
				Net.event("UseIncubator"):FireServer(slot)
			end)
			hatch.Position = bar.Position
			hatch.Size = bar.Size
			hatch.Visible = false
			rows[key] = { frame = frame, fill = fill, time = time, hatch = hatch, start = egg.start, seconds = seconds }
		end
		local count = math.min(#keys, MAX_ROWS)
		holder.Size = UDim2.fromOffset(330, 64 + count * (ROW + 6))
	end

	Store.Changed:Connect(rebuild)
	Players.LocalPlayer:GetAttributeChangedSignal("FastHatch"):Connect(rebuild)
	task.spawn(function()
		while true do
			local now = workspace:GetServerTimeNow()
			local ready = 0
			for _, row in rows do
				local done = math.ceil(Night.doneAt(row.start, row.seconds))
				local left = done - now
				local progress = if row.seconds > 0 then math.clamp(Night.growth(row.start, now) / row.seconds, 0, 1) else 1
				row.fill.Size = UDim2.fromScale(progress, 1)
				row.time.Text = if left <= 0 then "READY!" else Format.time(math.ceil(left))
				row.hatch.Visible = left <= 0
				if left <= 0 then
					ready += 1
				end
			end
			readyCount = ready
			task.wait(0.5)
		end
	end)
	rebuild()
end

return GrowingEggs
