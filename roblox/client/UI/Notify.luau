-- Short messages at the top of the screen.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Notify = {}

local holder: Frame

local COLORS = {
	info = Theme.panel,
	success = Color3.fromRGB(46, 125, 80),
	error = Color3.fromRGB(150, 50, 50),
	rare = Color3.fromRGB(120, 70, 190),
}

function Notify.mount(gui: ScreenGui)
	holder = Theme.frame({
		Name = "Notifications",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.new(0.5, 0, 0.4, 0),
	})
	local layout = Theme.list(holder, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	holder.Parent = gui
end

function Notify.show(text: string, kind: string?, seconds: number?)
	if not holder then
		return
	end
	local toast = Theme.frame({
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = COLORS[kind or "info"] or Theme.panel,
		BackgroundTransparency = 0.05,
	})
	Theme.corner(toast, 10)
	Theme.stroke(toast)
	local label = Theme.label({
		Text = text,
		Size = UDim2.new(1, -16, 1, -6),
		Position = UDim2.fromOffset(8, 3),
		MaxTextSize = 20,
	})
	label.Parent = toast
	toast.Parent = holder
	task.delay(seconds or 3, function()
		local tween = TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		tween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
	local children = holder:GetChildren()
	local toasts = 0
	for _, child in children do
		if child:IsA("Frame") then
			toasts += 1
		end
	end
	if toasts > 5 then
		for _, child in children do
			if child:IsA("Frame") then
				child:Destroy()
				break
			end
		end
	end
end

return Notify
