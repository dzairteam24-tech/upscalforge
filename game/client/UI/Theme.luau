--!strict
-- The UI's look: chunky cartoon panels like the big simulator games. Bright gradient buttons with a dark outline,
-- white outlined text, windows with a colored header that pop open, cards with a 3D preview (a creature or an
-- egg in a ViewportFrame) colored by rarity. And the root frame that scales everything to the screen (a phone
-- gets the same layout, smaller).

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetModel = require(Shared.PetModel)

local Effects = require(script.Parent.Parent.Effects)

local Theme = {
	panel = Color3.fromRGB(255, 250, 240),
	ink = Color3.fromRGB(60, 52, 70),
	soft = Color3.fromRGB(130, 120, 140),
	gold = Color3.fromRGB(255, 196, 64),
	green = Color3.fromRGB(92, 214, 110),
	red = Color3.fromRGB(245, 92, 92),
	blue = Color3.fromRGB(80, 160, 255),
	purple = Color3.fromRGB(176, 110, 255),
	pink = Color3.fromRGB(255, 120, 190),
	gray = Color3.fromRGB(150, 150, 165),
	cream = Color3.fromRGB(246, 238, 224),
	outline = Color3.fromRGB(28, 24, 40),
	font = Enum.Font.FredokaOne,
	title = Enum.Font.LuckiestGuy,
}

Theme.RARITY = {
	Common = Color3.fromRGB(170, 176, 190),
	Uncommon = Color3.fromRGB(92, 214, 110),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(176, 110, 255),
	Legendary = Color3.fromRGB(255, 190, 50),
}

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end
Theme.lighten = lighten
Theme.darken = darken

function Theme.round(object: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = object
end

function Theme.stroke(object: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.outline
	stroke.Thickness = thickness or 2.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = object
	return stroke
end

-- A top-to-bottom shine: lighter at the top, darker at the bottom
function Theme.gradient(object: GuiObject, color: Color3, top: number?, bottom: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(lighten(color, top or 0.25), darken(color, bottom or 0.12))
	gradient.Parent = object
	object.BackgroundColor3 = Color3.new(1, 1, 1)
	return gradient
end

function Theme.recolor(object: GuiObject, color: Color3)
	local gradient = object:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(lighten(color, 0.25), darken(color, 0.12))
	else
		object.BackgroundColor3 = color
	end
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

-- White text with a dark outline, the simulator look (titles, numbers, labels on colors)
function Theme.bold(parent: Instance, props: { [string]: any }): TextLabel
	local maxText = props.MaxText or 40
	local copy = table.clone(props)
	copy.MaxText = nil
	local label = Theme.text(parent, copy)
	if props.Font == nil then
		label.Font = Theme.title
	end
	if props.TextColor3 == nil then
		label.TextColor3 = Color3.new(1, 1, 1)
	end
	label.TextStrokeColor3 = Theme.outline
	label.TextStrokeTransparency = 0
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxText
	limit.Parent = label
	return label
end

-- Grows a little under the mouse and squashes when pressed
function Theme.bounce(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local function to(value: number)
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		to(1.05)
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		to(0.92)
	end)
	button.MouseButton1Up:Connect(function()
		to(1.05)
	end)
end

function Theme.button(parent: Instance, text: string, color: Color3, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Font = Theme.title
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeColor3 = Theme.outline
	button.TextStrokeTransparency = 0
	button.TextScaled = true
	button.AutoButtonColor = false
	Theme.gradient(button, color)
	Theme.round(button, 12)
	Theme.stroke(button, Theme.outline, 2.5)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = button
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.Parent = button
	Theme.bounce(button)
	button.Activated:Connect(function()
		Effects.sound("Click")
		onClick()
	end)
	button.Parent = parent
	return button
end

-- A big square HUD button: an icon with its name under it
function Theme.iconButton(parent: Instance, icon: string, label: string, color: Color3, onClick: () -> ()): (TextButton, TextLabel)
	local button = Theme.button(parent, "", color, onClick)
	button.Size = UDim2.fromOffset(74, 74)
	local corner = button:FindFirstChildOfClass("UICorner") :: UICorner
	corner.CornerRadius = UDim.new(0, 18)
	Theme.text(button, { Text = icon, Size = UDim2.new(1, 0, 0.66, 0), Position = UDim2.fromScale(0, -0.04) })
	local name = Theme.bold(button, { Text = label, Size = UDim2.new(1, 10, 0.34, 0), Position = UDim2.new(0, -5, 0.66, 0), MaxText = 18 })
	return button, name
end

-- A rounded card with a soft gradient (a row in a window, or a cell in a grid)
function Theme.card(parent: Instance, color: Color3?, props: { [string]: any }?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	Theme.gradient(frame, color or Theme.cream, 0.35, 0.05)
	Theme.round(frame, 14)
	Theme.stroke(frame, darken(color or Theme.cream, 0.45), 2)
	local set: any = frame
	if props then
		for k, v in props do
			set[k] = v
		end
	end
	frame.Parent = parent
	return frame
end

-- A grid inside a window's content, `columns` across
function Theme.grid(content: Instance, order: number, columns: number, height: number): Frame
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -8, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.LayoutOrder = order
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.CellSize = UDim2.new(1 / columns, -8, 0, height)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	holder.Parent = content
	return holder
end

-- A 3D preview: these parts, slowly turning, in a ViewportFrame
local spinning: { [ViewportFrame]: { model: Model, pivot: CFrame, window: GuiObject? } } = setmetatable({}, { __mode = "k" }) :: any
local function viewport(parent: Instance, model: Model, height: number, radius: number): ViewportFrame
	local view = Instance.new("ViewportFrame")
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(190, 190, 200)
	view.LightColor = Color3.new(1, 1, 1)
	view.LightDirection = Vector3.new(-1, -2, -1.5)
	model.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = math.max(height, radius * 2) * 1.6 + 1
	camera.CFrame = CFrame.lookAt(Vector3.new(0, height * 0.55, distance), Vector3.new(0, height * 0.45, 0))
	camera.Parent = view
	view.CurrentCamera = camera
	view.Parent = parent
	spinning[view] = { model = model, pivot = model:GetPivot() }
	return view
end

function Theme.creatureView(parent: Instance, creature: { s: string, m: string?, size: string? }): ViewportFrame
	local built = PetModel.build({ s = creature.s, v = creature.m or "Normal", z = creature.size or "Normal" })
	PetModel.place(built, CFrame.new(0, built.height / 2, 0) * CFrame.Angles(0, math.rad(200), 0))
	built.model.PrimaryPart = built.body
	return viewport(parent, built.model, built.height, built.radius)
end

function Theme.eggView(parent: Instance, color: Color3, golden: boolean?): ViewportFrame
	local model = Instance.new("Model")
	local egg = Instance.new("Part")
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(2, 2, 2)
	egg.Color = if golden then Color3.fromRGB(255, 205, 70) else color
	egg.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
	egg.CFrame = CFrame.new(0, 1.3, 0)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	egg.Parent = model
	-- (spots)
	for i, at in { Vector3.new(0.55, 1.7, 0.75), Vector3.new(-0.6, 1.1, 0.7), Vector3.new(0.2, 0.75, 0.95) } do
		local spot = Instance.new("Part")
		spot.Shape = Enum.PartType.Ball
		spot.Size = Vector3.one * (0.5 - i * 0.07)
		spot.Color = lighten(egg.Color, 0.55)
		spot.Material = Enum.Material.SmoothPlastic
		spot.CFrame = CFrame.new(at)
		spot.Parent = model
	end
	model.PrimaryPart = egg
	return viewport(parent, model, 2.6, 1)
end

task.spawn(function()
	local angle = 0
	while true do
		local dt = task.wait(1 / 30)
		angle += dt * 0.9
		for view, entry in spinning do
			if not view.Parent then
				spinning[view] = nil
				continue
			end
			-- (only while its window is open: the window is the frame right under Root)
			local window = entry.window
			if not window then
				local at: Instance? = view
				while at and at.Parent and at.Parent.Name ~= "Root" do
					at = at.Parent
				end
				window = if at and at:IsA("GuiObject") then at else nil
				entry.window = window
			end
			if window and window.Visible then
				entry.model:PivotTo(entry.pivot * CFrame.Angles(0, math.sin(angle) * 0.6, 0))
			end
		end
	end
end)

-- A strip of tabs; calls onSelect with the chosen name, and returns a function to select one
function Theme.tabs(parent: Instance, names: { string }, color: Color3, onSelect: (string) -> ()): (string) -> ()
	local bar = Instance.new("Frame")
	bar.Name = "Tabs"
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.fromOffset(14, 62)
	bar.Size = UDim2.new(1, -28, 0, 40)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.Parent = bar
	local buttons: { [string]: TextButton } = {}
	local function select(name: string)
		for other, button in buttons do
			Theme.recolor(button, if other == name then color else Theme.gray)
		end
		onSelect(name)
	end
	for _, name in names do
		local button = Theme.button(bar, name, Theme.gray, function()
			select(name)
		end)
		button.Size = UDim2.new(1 / #names, -8, 1, 0)
		buttons[name] = button
	end
	bar.Parent = parent
	return select
end

-- A window: a colored header with its title, a round close button, and a content area that scrolls. It pops
-- open (Windows.open). `tabs` leaves room under the header for Theme.tabs.
function Theme.window(gui: Instance, title: string, size: Vector2, color: Color3?, tabs: boolean?): (Frame, ScrollingFrame)
	local accent = color or Theme.blue
	local window = Instance.new("Frame")
	window.Name = title
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.52)
	window.Visible = false
	window.ZIndex = 5
	Theme.gradient(window, Theme.panel, 0.4, 0.06)
	Theme.round(window, 20)
	Theme.stroke(window, Theme.outline, 4)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(size.X, size.Y)
	constraint.Parent = window
	window.Size = UDim2.new(0.94, 0, 0.84, 0)
	Instance.new("UIScale").Parent = window -- (the pop: Windows.open)
	-- The header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 54)
	header.BackgroundColor3 = accent
	Theme.round(header, 20)
	header.Parent = window
	local square = Instance.new("Frame") -- (squares the header's bottom corners)
	square.BorderSizePixel = 0
	square.Size = UDim2.new(1, 0, 0, 20)
	square.Position = UDim2.new(0, 0, 1, -20)
	square.BackgroundColor3 = accent
	square.Parent = header
	Theme.bold(window, { Text = title, Size = UDim2.new(1, -90, 0, 40), Position = UDim2.fromOffset(18, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 34 })
	local close = Theme.button(window, "X", Theme.red, function()
		window.Visible = false
	end)
	close.Size = UDim2.fromOffset(48, 48)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -10, 0, 8)
	local round = close:FindFirstChildOfClass("UICorner") :: UICorner
	round.CornerRadius = UDim.new(0.5, 0)
	close.ZIndex = 6
	local top = if tabs then 110 else 64
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(14, top)
	content.Size = UDim2.new(1, -24, 1, -top - 12)
	content.ScrollBarThickness = 8
	content.ScrollBarImageColor3 = darken(accent, 0.2)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = content
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = content
	content.Parent = window
	window.Parent = gui
	return window, content
end

-- The frame everything goes in, scaled to the screen: laid out for about 1280x760 and scaled down on a phone
function Theme.root(gui: ScreenGui): Frame
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function fit()
		local camera = workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else Vector2.new(1280, 760)
		local s = math.clamp(math.min(view.X / 1100, view.Y / 700), 0.55, 1.25)
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	fit()
	task.spawn(function()
		while true do
			task.wait(1)
			fit()
		end
	end)
	root.Parent = gui
	return root
end

return Theme
