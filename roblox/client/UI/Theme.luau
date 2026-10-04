-- Colors and small helpers for building UI in code.

local Theme = {
	bg = Color3.fromRGB(27, 34, 54),
	panel = Color3.fromRGB(36, 44, 68),
	card = Color3.fromRGB(48, 58, 88),
	text = Color3.fromRGB(238, 241, 247),
	muted = Color3.fromRGB(169, 179, 201),
	accent = Color3.fromRGB(91, 184, 245),
	gold = Color3.fromRGB(245, 197, 66),
	green = Color3.fromRGB(80, 200, 120),
	red = Color3.fromRGB(229, 83, 75),
	purple = Color3.fromRGB(142, 91, 217),
	titleFont = Enum.Font.FredokaOne,
	font = Enum.Font.GothamBold,
}

function Theme.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

function Theme.stroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(15, 18, 30)
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

function Theme.padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

function Theme.list(parent: Instance, padding: number, horizontal: boolean?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, padding)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Parent = parent
	return l
end

function Theme.frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Theme.panel
	for k, v in props do
		(f :: any)[k] = v
	end
	return f
end

function Theme.label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Theme.text
	l.Font = Theme.font
	l.TextScaled = true
	l.TextWrapped = true
	for k, v in props do
		if k ~= "MaxTextSize" then
			(l :: any)[k] = v
		end
	end
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = props.MaxTextSize or 28
	limit.Parent = l
	return l
end

function Theme.button(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = Theme.accent
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Theme.titleFont
	b.TextScaled = true
	b.BorderSizePixel = 0
	for k, v in props do
		if k ~= "MaxTextSize" then
			(b :: any)[k] = v
		end
	end
	Theme.corner(b, 10)
	Theme.stroke(b, Color3.fromRGB(15, 18, 30), 2)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = props.MaxTextSize or 24
	limit.Parent = b
	return b
end

-- A centered window with a title and close button. Returns the window and its content frame.
function Theme.window(parent: Instance, title: string, onClose: () -> ()): (Frame, Frame)
	local window = Theme.frame({
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.62, 0.72),
		BackgroundColor3 = Theme.bg,
		Visible = false,
	})
	Theme.corner(window, 16)
	Theme.stroke(window, Color3.fromRGB(10, 12, 22), 3)
	local ratio = Instance.new("UISizeConstraint")
	ratio.MinSize = Vector2.new(320, 260)
	ratio.MaxSize = Vector2.new(900, 620)
	ratio.Parent = window

	local header = Theme.label({
		Text = title,
		Font = Theme.titleFont,
		Size = UDim2.new(1, -70, 0, 44),
		Position = UDim2.fromOffset(16, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 32,
	})
	header.Parent = window

	local close = Theme.button({
		Text = "X",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -50, 0, 8),
		BackgroundColor3 = Theme.red,
	})
	close.Parent = window
	close.Activated:Connect(onClose)

	local content = Theme.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -24, 1, -68),
	})
	content.Parent = window
	window.Parent = parent
	return window, content
end

return Theme
