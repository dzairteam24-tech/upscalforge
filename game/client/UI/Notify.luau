--!strict
-- Short messages at the top of the screen (the server's Notify, and the client's own).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Theme = require(script.Parent.Theme)

local Notify = {}

local COLORS = { info = Theme.blue, success = Theme.green, error = Theme.red, rare = Color3.fromRGB(190, 120, 255) }

local list: Frame? = nil

function Notify.show(text: string, kind: string?)
	local holder = list
	if not holder then
		return
	end
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 34)
	frame.BackgroundColor3 = COLORS[kind or "info"] or Theme.blue
	Theme.round(frame, 10)
	Theme.text(frame, { Text = text, Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), TextColor3 = Color3.new(1, 1, 1) })
	frame.Parent = holder
	task.delay(if kind == "rare" then 5 else 3, function()
		TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.wait(0.3)
		frame:Destroy()
	end)
end

function Notify.mount(gui: ScreenGui)
	local holder = Instance.new("Frame")
	holder.Name = "Notifications"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 46)
	holder.Size = UDim2.fromOffset(420, 200)
	holder.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = holder
	holder.Parent = gui
	list = holder
	Net.event("Notify").OnClientEvent:Connect(Notify.show)
end

return Notify
