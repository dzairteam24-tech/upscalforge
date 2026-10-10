--!strict
-- The UI's look: soft pastel panels with gold touches, and small helpers to build them.

local Theme = {
	panel = Color3.fromRGB(255, 250, 240),
	ink = Color3.fromRGB(60, 52, 70),
	soft = Color3.fromRGB(130, 120, 140),
	gold = Color3.fromRGB(255, 196, 64),
	green = Color3.fromRGB(110, 200, 140),
	red = Color3.fromRGB(240, 110, 110),
	blue = Color3.fromRGB(110, 160, 245),
	card = Color3.fromRGB(246, 238, 224),
	font = Enum.Font.FredokaOne,
}

function Theme.round(object: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = object
end

function Theme.stroke(object: GuiObject, color: Color3?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.gold
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = object
end

function Theme.text(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.font
	label.TextColor3 = Theme.ink
	label.TextScaled = true
	for k, v in props do
		(label :: any)[k] = v
	end
	label.Parent = parent
	return label
end

function Theme.button(parent: Instance, text: string, color: Color3, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = color
	button.Font = Theme.font
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextScaled = true
	button.AutoButtonColor = true
	Theme.round(button, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = button
	button.Activated:Connect(onClick)
	button.Parent = parent
	return button
end

-- A centered window with a title and a close button; returns the window and its content area
function Theme.window(gui: ScreenGui, title: string, size: Vector2): (Frame, ScrollingFrame)
	local window = Instance.new("Frame")
	window.Name = title
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.52)
	window.Size = UDim2.fromOffset(size.X, size.Y)
	window.BackgroundColor3 = Theme.panel
	window.Visible = false
	Theme.round(window, 18)
	Theme.stroke(window, Theme.gold, 3)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(size.X, size.Y)
	constraint.Parent = window
	window.Size = UDim2.new(0.92, 0, 0.8, 0)
	Theme.text(window, { Text = title, Size = UDim2.new(1, -80, 0, 34), Position = UDim2.fromOffset(16, 10), TextXAlignment = Enum.TextXAlignment.Left })
	local close = Theme.button(window, "✕", Theme.red, function()
		window.Visible = false
	end)
	close.Size = UDim2.fromOffset(36, 36)
	close.Position = UDim2.new(1, -46, 0, 10)
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(12, 54)
	content.Size = UDim2.new(1, -24, 1, -66)
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content
	content.Parent = window
	window.Parent = gui
	return window, content
end

return Theme
