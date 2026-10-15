--!strict
-- The look of the screen: dark glass panels with a thin neon edge, clean bold type, buttons that glow. Small
-- helpers so every window is built the same way.

local TweenService = game:GetService("TweenService")

local Ui = {}

Ui.glass = Color3.fromRGB(12, 14, 26) -- panels (see-through)
Ui.glassAlpha = 0.18
Ui.cardColor = Color3.fromRGB(24, 28, 46)
Ui.edge = Color3.fromRGB(90, 110, 170)
Ui.text = Color3.fromRGB(235, 240, 255)
Ui.dim = Color3.fromRGB(140, 150, 185)
Ui.cyan = Color3.fromRGB(0, 229, 255)
Ui.pink = Color3.fromRGB(255, 64, 200)
Ui.gold = Color3.fromRGB(255, 205, 80)
Ui.green = Color3.fromRGB(70, 240, 150)
Ui.red = Color3.fromRGB(255, 80, 110)
Ui.violet = Color3.fromRGB(160, 110, 255)
Ui.font = Enum.Font.GothamBold
Ui.heavy = Enum.Font.GothamBlack

function Ui.round(object: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = object
end

function Ui.stroke(object: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Ui.edge
	stroke.Thickness = thickness or 1.5
	stroke.Transparency = transparency or 0.2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = object
	return stroke
end

-- A glass panel
function Ui.panel(parent: Instance, size: UDim2, position: UDim2, edge: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Ui.glass
	frame.BackgroundTransparency = Ui.glassAlpha
	frame.BorderSizePixel = 0
	Ui.round(frame, 12)
	Ui.stroke(frame, edge or Ui.edge, 1.5, 0.35)
	frame.Parent = parent
	return frame
end

function Ui.label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3?, font: Enum.Font?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Text = text
	label.Font = font or Ui.font
	label.TextScaled = true
	label.TextColor3 = color or Ui.text
	label.TextStrokeTransparency = 1
	label.Parent = parent
	return label
end

-- A soft shadow behind text that sits on the world (keeps it readable on bright neon)
function Ui.shade(label: TextLabel)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 10)
	label.TextStrokeTransparency = 0.55
end

-- A button: filled with its color, a bright edge, and it presses in
function Ui.button(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.05
	button.AutoButtonColor = false
	button.Text = ""
	Ui.round(button, 10)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 190))
	gradient.Parent = button
	Ui.stroke(button, color:Lerp(Color3.new(1, 1, 1), 0.45), 1.5, 0.1)
	local label = Ui.label(button, text, UDim2.new(1, -16, 1, -12), UDim2.fromOffset(8, 6), Color3.new(1, 1, 1), Ui.heavy)
	label.Name = "Text"
	label.TextStrokeColor3 = color:Lerp(Color3.new(), 0.6)
	label.TextStrokeTransparency = 0.4
	button.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.94 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
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

-- A centered window with a title and a close button; `body` is the area to fill
export type Window = { frame: Frame, body: Frame, open: () -> (), close: () -> (), toggle: () -> (), isOpen: () -> boolean }
function Ui.window(screen: Instance, title: string, accent: Color3, size: UDim2): Window
	local frame = Ui.panel(screen, size, UDim2.fromScale(0.5, 0.5), accent)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 0.08
	frame.Visible = false
	frame.ZIndex = 10
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(size.X.Offset, size.Y.Offset)
	limit.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local head = Ui.label(frame, title, UDim2.new(1, -90, 0, 30), UDim2.fromOffset(20, 14), Ui.text, Ui.heavy)
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.ZIndex = 11
	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, -40, 0, 2)
	line.Position = UDim2.fromOffset(20, 52)
	line.BackgroundColor3 = accent
	line.BorderSizePixel = 0
	line.ZIndex = 11
	line.Parent = frame
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	fade.Parent = line
	local close = function()
		frame.Visible = false
	end
	local x = Ui.button(frame, "X", UDim2.fromOffset(36, 36), UDim2.new(1, -52, 0, 12), Color3.fromRGB(60, 64, 90), close)
	x.ZIndex = 12
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -40, 1, -76)
	body.Position = UDim2.fromOffset(20, 64)
	body.ZIndex = 11
	body.Parent = frame
	local function open()
		frame.Visible = true
		scale.Scale = 0.92
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
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
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Ui.edge
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

-- A row card in a list: a title, a line under it, and room on the right for a button
function Ui.card(parent: Instance, title: string, desc: string, accent: Color3, height: number?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -8, 0, height or 64)
	f.BackgroundColor3 = Ui.cardColor
	f.BackgroundTransparency = 0.1
	f.BorderSizePixel = 0
	f.ZIndex = 12
	Ui.round(f, 10)
	Ui.stroke(f, accent, 1, 0.55)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 4, 1, -20)
	bar.Position = UDim2.fromOffset(8, 10)
	bar.BackgroundColor3 = accent
	bar.BorderSizePixel = 0
	bar.ZIndex = 13
	Ui.round(bar, 2)
	bar.Parent = f
	local t = Ui.label(f, title, UDim2.new(0.62, -24, 0, 24), UDim2.fromOffset(22, 9), Ui.text, Ui.heavy)
	t.Name = "Title"
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.ZIndex = 13
	local d = Ui.label(f, desc, UDim2.new(0.62, -24, 0, 18), UDim2.fromOffset(22, 36), Ui.dim)
	d.Name = "Desc"
	d.TextXAlignment = Enum.TextXAlignment.Left
	d.ZIndex = 13
	f.Parent = parent
	return f
end

return Ui
