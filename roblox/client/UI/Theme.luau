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

-- Click sound for every button. Required on first use so Theme stays free of other client modules.
local sounds: any = nil
local function click()
	if not sounds then
		local ok, result = pcall(require, script.Parent.Parent.Controllers.SoundClient)
		sounds = if ok then result else false
	end
	if sounds then
		sounds.play("Click")
	end
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
	b.Activated:Connect(click)
	return b
end

-- A centered window with a title and close button. Returns the window and its content frame.
Theme.WINDOW_MIN_HEIGHT = 440

-- Size in layout units (offsets) of something inside a window that may be scaled down on phones.
function Theme.layoutSize(gui: GuiObject): Vector2
	local scale = 1
	local node: Instance? = gui
	while node do
		local scaler = node:FindFirstChildOfClass("UIScale")
		if scaler then
			scale *= scaler.Scale
		end
		node = node.Parent
	end
	return gui.AbsoluteSize / math.max(0.01, scale)
end

function Theme.window(parent: Instance, title: string, onClose: () -> ()): (Frame, Frame)
	local window = Theme.frame({
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.62, 0.72),
		BackgroundColor3 = Theme.bg,
		Visible = false,
		ZIndex = 5, -- above the HUD and guide banner; notifications and hatches draw above windows
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

	-- Short screens (phones): the window fills most of the screen and its contents scale down a little,
	-- so every layout gets at least WINDOW_MIN_HEIGHT of room to work with.
	local scaler = Instance.new("UIScale")
	scaler.Parent = window
	local function fit()
		local screen = if parent:IsA("GuiBase2d") then (parent :: GuiBase2d).AbsoluteSize else Vector2.zero
		if screen.Y <= 0 then
			local camera = workspace.CurrentCamera
			screen = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		end
		if screen.Y < 560 then
			local s = math.clamp(screen.Y * 0.94 / Theme.WINDOW_MIN_HEIGHT, 0.6, 1)
			scaler.Scale = s
			window.Size = UDim2.fromScale(0.96 / s, 0.94 / s)
			window.Position = UDim2.fromScale(0.5, 0.5)
		else
			scaler.Scale = 1
			window.Size = UDim2.fromScale(0.62, 0.72)
			window.Position = UDim2.fromScale(0.5, 0.52)
		end
	end
	fit()
	if parent:IsA("GuiBase2d") then
		(parent :: GuiBase2d):GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	end
	window.Parent = parent
	return window, content
end

return Theme
