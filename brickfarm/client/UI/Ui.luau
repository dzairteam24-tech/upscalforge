--!strict
-- The look of the screen: bright toy-like panels (white, thick soft outline, rounded), chunky friendly type,
-- colorful buttons that press in. Small helpers so every window is built the same way.

local TweenService = game:GetService("TweenService")

local Ui = {}

Ui.paper = Color3.fromRGB(255, 252, 244)
Ui.cream = Color3.fromRGB(246, 238, 222)
Ui.ink = Color3.fromRGB(58, 48, 66)
Ui.text = Color3.fromRGB(58, 48, 66)
Ui.dim = Color3.fromRGB(140, 128, 140)
Ui.green = Color3.fromRGB(88, 196, 80)
Ui.red = Color3.fromRGB(232, 72, 64)
Ui.blue = Color3.fromRGB(64, 156, 240)
Ui.yellow = Color3.fromRGB(255, 200, 40)
Ui.orange = Color3.fromRGB(255, 146, 44)
Ui.brown = Color3.fromRGB(150, 98, 60)
Ui.gray = Color3.fromRGB(176, 170, 180)
Ui.font = Enum.Font.FredokaOne

function Ui.round(object: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 14)
	corner.Parent = object
end

function Ui.stroke(object: Instance, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Ui.ink
	stroke.Thickness = thickness or 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = object
	return stroke
end

-- A white panel with a soft dark outline
function Ui.panel(parent: Instance, size: UDim2, position: UDim2, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color or Ui.paper
	frame.BorderSizePixel = 0
	Ui.round(frame, 16)
	Ui.stroke(frame, Ui.ink, 3)
	frame.Parent = parent
	return frame
end

function Ui.label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Text = text
	label.Font = Ui.font
	label.TextScaled = true
	label.TextColor3 = color or Ui.text
	label.TextStrokeTransparency = 1
	label.Parent = parent
	return label
end

-- White text with a dark outline, for over the world
function Ui.outlined(label: TextLabel)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Ui.ink
	label.TextStrokeTransparency = 0
end

-- A colorful button that presses in
function Ui.button(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.AutoButtonColor = false
	button.Text = ""
	Ui.round(button, 14)
	Ui.stroke(button, color:Lerp(Ui.ink, 0.55), 3)
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215))
	shine.Parent = button
	local label = Ui.label(button, text, UDim2.new(1, -14, 1, -12), UDim2.fromOffset(7, 6))
	label.Name = "Text"
	Ui.outlined(label)
	label.TextStrokeColor3 = color:Lerp(Ui.ink, 0.6)
	button.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	button.Activated:Connect(onClick)
	return button
end

function Ui.setText(button: TextButton, text: string)
	local label = button:FindFirstChild("Text") :: TextLabel?
	if label then
		label.Text = text
	end
end

-- A greyed button can't be used
function Ui.setEnabled(button: TextButton, color: Color3, enabled: boolean)
	button.BackgroundColor3 = if enabled then color else Ui.gray
	button.Active = enabled
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = (if enabled then color else Ui.gray):Lerp(Ui.ink, 0.55)
	end
end

-- A centered window with a colored title bar and a close button; `body` is the area to fill
export type Window = { frame: Frame, body: Frame, open: () -> (), close: () -> (), toggle: () -> (), isOpen: () -> boolean }
function Ui.window(screen: Instance, title: string, color: Color3, size: UDim2): Window
	local frame = Ui.panel(screen, size, UDim2.fromScale(0.5, 0.5))
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = false
	frame.ZIndex = 10
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 56)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.ZIndex = 11
	Ui.round(bar, 16)
	bar.Parent = frame
	-- (square off the bar's bottom corners)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 0, 16)
	fill.Position = UDim2.new(0, 0, 1, -16)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.ZIndex = 11
	fill.Parent = bar
	local head = Ui.label(bar, title, UDim2.new(1, -90, 0, 36), UDim2.fromOffset(18, 10))
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.ZIndex = 12
	Ui.outlined(head)
	local close = function()
		frame.Visible = false
	end
	local x = Ui.button(bar, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -50, 0, 8), Ui.red, close)
	x.ZIndex = 13
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -32, 1, -80)
	body.Position = UDim2.fromOffset(16, 66)
	body.ZIndex = 11
	body.Parent = frame
	local function open()
		frame.Visible = true
		scale.Scale = 0.85
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	return {
		frame = frame,
		body = body,
		open = open,
		close = close,
		toggle = function()
			if frame.Visible then
				close()
			else
				open()
			end
		end,
		isOpen = function()
			return frame.Visible
		end,
	}
end

-- A scrolling list inside a window's body
function Ui.list(parent: Instance, padding: number?): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Ui.dim
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 11
	scroll.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	return scroll
end

-- A row in a list: a colored square (the crop's color), a title and a line under it; room on the right
function Ui.row(parent: Instance, title: string, desc: string, swatch: Color3, height: number?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -10, 0, height or 66)
	f.BackgroundColor3 = Ui.cream
	f.BorderSizePixel = 0
	f.ZIndex = 12
	Ui.round(f, 12)
	Ui.stroke(f, Ui.cream:Lerp(Ui.ink, 0.25), 2)
	local s = Instance.new("Frame")
	s.Name = "Swatch"
	s.Size = UDim2.fromOffset(42, 42)
	s.Position = UDim2.new(0, 12, 0.5, -21)
	s.BackgroundColor3 = swatch
	s.BorderSizePixel = 0
	s.ZIndex = 13
	Ui.round(s, 8)
	Ui.stroke(s, swatch:Lerp(Ui.ink, 0.5), 2)
	s.Parent = f
	local t = Ui.label(f, title, UDim2.new(0.55, -70, 0, 26), UDim2.fromOffset(66, 8))
	t.Name = "Title"
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.ZIndex = 13
	local d = Ui.label(f, desc, UDim2.new(0.55, -70, 0, 20), UDim2.fromOffset(66, 36), Ui.dim)
	d.Name = "Desc"
	d.TextXAlignment = Enum.TextXAlignment.Left
	d.ZIndex = 13
	f.Parent = parent
	return f
end

return Ui
