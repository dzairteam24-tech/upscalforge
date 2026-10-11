--!strict
-- Short messages at the top of the screen (the server's Notify, and the client's own).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Theme = require(script.Parent.Theme)

local Notify = {}

local COLORS = { info = Theme.blue, success = Theme.green, error = Theme.red, rare = Theme.purple }

local list: Frame? = nil

function Notify.show(text: string, kind: string?)
	local holder = list
	if not holder then
		return
	end
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 40)
	Theme.gradient(frame, COLORS[kind or "info"] or Theme.blue, 0.25, 0.1)
	Theme.round(frame, 20)
	local stroke = Theme.stroke(frame, Theme.outline, 3)
	local label = Theme.bold(frame, { Text = text, Size = UDim2.new(1, -24, 1, -10), Position = UDim2.fromOffset(12, 5), Font = Theme.font, MaxText = 24 })
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = frame
	frame.Parent = holder
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(if kind == "rare" then 5 else 3, function()
		local fade = TweenInfo.new(0.3)
		TweenService:Create(frame, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.3)
		frame:Destroy()
	end)
end

function Notify.mount(gui: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "Notifications"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 86)
	holder.Size = UDim2.fromOffset(520, 240)
	holder.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = holder
	holder.Parent = gui
	list = holder
	Net.event("Notify").OnClientEvent:Connect(Notify.show)
end

return Notify
