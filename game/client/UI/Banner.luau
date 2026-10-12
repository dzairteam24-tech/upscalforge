--!strict
-- The big moments, in big letters across the middle of the screen (the server's Banner: "🏃 RUN!", "😮‍💨 ESCAPED!",
-- "🏠 HOME SAFE!", "🐾 CAUGHT!"); and while a guardian chases the player (their Chased attribute, WildService),
-- the screen's edges pulse red to a heartbeat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Effects = require(script.Parent.Parent.Effects)

local Banner = {}

local holder: Frame? = nil
local current: TextLabel? = nil

function Banner.show(text: string, color: Color3?)
	local root = holder
	if not root then
		return
	end
	if current then
		current:Destroy()
	end
	local label = Instance.new("TextLabel")
	label.Name = "Banner"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3)
	label.Size = UDim2.new(0.9, 0, 0, 84)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.fromRGB(28, 24, 40)
	label.TextStrokeTransparency = 0
	label.ZIndex = 30
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	label.Parent = root
	current = label
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Effects.sound("Rare")
	task.delay(1.4, function()
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.35)
		label:Destroy()
		if current == label then
			current = nil
		end
	end)
end

-- The red edges of a chase: one fading strip along each side of the screen
local function chaseEdges(root: Frame): { Frame }
	local edges: { Frame } = {}
	local RED = Color3.fromRGB(230, 40, 40)
	for _, side in { { 0, 90 }, { 1, 270 }, { 2, 0 }, { 3, 180 } } do
		local edge = Instance.new("Frame")
		edge.Name = "ChaseEdge"
		edge.BorderSizePixel = 0
		edge.BackgroundColor3 = RED
		edge.BackgroundTransparency = 1
		edge.ZIndex = 25
		local vertical = side[1] < 2
		edge.Size = if vertical then UDim2.fromScale(1, 0.16) else UDim2.fromScale(0.12, 1)
		edge.Position = if side[1] == 0 then UDim2.fromScale(0, 0) elseif side[1] == 1 then UDim2.fromScale(0, 0.84) elseif side[1] == 2 then UDim2.fromScale(0, 0) else UDim2.fromScale(0.88, 0)
		local fade = Instance.new("UIGradient")
		fade.Rotation = side[2]
		fade.Transparency = NumberSequence.new(0, 1) -- (solid at the screen's edge, gone inward)
		fade.Parent = edge
		edge.Parent = root
		table.insert(edges, edge)
	end
	return edges
end

function Banner.mount(gui: Instance)
	local root = Instance.new("Frame")
	root.Name = "Banners"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	holder = root
	Net.event("Banner").OnClientEvent:Connect(function(text: string, color: Color3?)
		if type(text) == "string" then
			Banner.show(text, if typeof(color) == "Color3" then color else nil)
		end
	end)
	-- The chase: the edges pulse, a heartbeat every beat
	local edges = chaseEdges(root)
	local player = Players.LocalPlayer
	local nextBeat = 0
	RunService.RenderStepped:Connect(function()
		local chased = player:GetAttribute("Chased") == true
		local pulse = if chased then 0.45 + 0.35 * math.abs(math.sin(os.clock() * 5)) else 1
		for _, edge in edges do
			edge.BackgroundTransparency = pulse
		end
		if chased and os.clock() >= nextBeat then
			nextBeat = os.clock() + 0.6
			Effects.sound("Heart")
		end
	end)
end

return Banner
