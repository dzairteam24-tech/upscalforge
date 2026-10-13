--!strict
-- Small helpers for building the screen: chunky rounded panels, outlined text, buttons, windows.

local Ui = {}

Ui.ink = Color3.fromRGB(28, 24, 40)
Ui.panel = Color3.fromRGB(255, 250, 240)
Ui.text = Color3.fromRGB(60, 52, 70)
Ui.gold = Color3.fromRGB(255, 196, 64)
Ui.green = Color3.fromRGB(92, 214, 110)
Ui.red = Color3.fromRGB(245, 92, 92)
Ui.blue = Color3.fromRGB(80, 160, 255)
Ui.gray = Color3.fromRGB(150, 150, 165)
Ui.font = Enum.Font.FredokaOne

function Ui.round(object: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = object
end

function Ui.stroke(object: Instance, color: Color3?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Ui.ink
	stroke.Thickness = thickness or 2.5
	stroke.Parent = object
end

function Ui.frame(parent: Instance, size: UDim2, position: UDim2, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	Ui.round(frame)
	frame.Parent = parent
	return frame
end

-- Outlined white text
function Ui.label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Text = text
	label.Font = Ui.font
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Ui.ink
	label.TextStrokeTransparency = 0
	label.Parent = parent
	return label
end

function Ui.button(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.AutoButtonColor = true
	button.Text = text
	button.Font = Ui.font
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeColor3 = Ui.ink
	button.TextStrokeTransparency = 0
	Ui.round(button)
	Ui.stroke(button)
	button.Parent = parent
	button.Activated:Connect(onClick)
	return button
end

-- A centered window with a title and a close button; `body` is the area to fill
function Ui.window(screen: Instance, title: string, size: UDim2): { frame: Frame, body: Frame, open: () -> (), close: () -> (), toggle: () -> () }
	local frame = Ui.frame(screen, size, UDim2.fromScale(0.5, 0.5), Ui.panel)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = false
	frame.ZIndex = 10
	Ui.stroke(frame, Ui.ink, 4)
	local header = Ui.frame(frame, UDim2.new(1, 0, 0, 52), UDim2.fromOffset(0, 0), Ui.gold)
	header.ZIndex = 11
	Ui.label(header, title, UDim2.new(1, -110, 1, -12), UDim2.fromOffset(16, 6)).TextXAlignment = Enum.TextXAlignment.Left
	local window
	local close = function()
		frame.Visible = false
	end
	local x = Ui.button(header, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 6), Ui.red, close)
	x.ZIndex = 12
	local body = Ui.frame(frame, UDim2.new(1, -24, 1, -68), UDim2.fromOffset(12, 60), Color3.fromRGB(255, 255, 255))
	body.BackgroundTransparency = 1
	body.ZIndex = 11
	window = {
		frame = frame,
		body = body,
		open = function()
			frame.Visible = true
		end,
		close = close,
		toggle = function()
			frame.Visible = not frame.Visible
		end,
	}
	return window
end

return Ui
