--!strict
-- The Nest on the client (NestService): draws the eggs in the incubators with their timers, turns on the
-- prompts of the player's own island, and shows the weather (Logic/Nest) at the top of the screen.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Variants = require(Shared.Config.Variants)
local World1 = require(Shared.Config.World1)
local Format = require(Shared.Logic.Format)
local Nest = require(Shared.Logic.Nest)
local Net = require(Shared.Net)

local NestClient = {}

local LOCAL = Players.LocalPlayer

type Drawn = { egg: Part, gui: BillboardGui, text: TextLabel }
local drawn: { [BasePart]: Drawn } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function draw(pad: BasePart): Drawn
	local existing = drawn[pad]
	if existing then
		return existing
	end
	local egg = Instance.new("Part")
	egg.Name = "NestEgg"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(4, 4, 4)
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanQuery = false
	egg.CanTouch = false
	egg.Material = Enum.Material.SmoothPlastic
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(8, 1.8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7.5, 0)
	gui.MaxDistance = 80
	gui.Adornee = pad
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Parent = gui
	gui.Parent = pad
	local entry = { egg = egg, gui = gui, text = text }
	drawn[pad] = entry
	return entry
end

local function update(pad: BasePart)
	local entry = draw(pad)
	local mine = pad:GetAttribute("Owner") == LOCAL.UserId
	local owner = pad:GetAttribute("Owner")
	local owned = type(owner) == "number" and owner ~= 0
	local open = pad:GetAttribute("Open") == true
	local function number(name: string): number
		local value = pad:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end
	local zone, start, duration, price = number("Zone"), number("Start"), number("Duration"), number("Price")
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")

	pad.Transparency = if open then 0 else 0.6
	local hasEgg = zone > 0
	entry.egg.Parent = if hasEgg then pad else nil
	if hasEgg then
		local zoneConfig = World1.zonesById[zone]
		entry.egg.Color = if zoneConfig then zoneConfig.color else Color3.new(1, 1, 1)
		local bob = math.sin(os.clock() * 2 + pad.Position.X) * 0.25
		entry.egg.CFrame = CFrame.new(pad.Position + Vector3.new(0, 3.4 + bob, 0))
	end

	local action = ""
	if not owned then
		entry.text.Text = ""
	elseif not open then
		entry.text.Text = if price > 0 then "🔒 " .. Format.abbrev(price) else ""
		action = if price > 0 then "Unlock" else ""
	elseif not hasEgg then
		entry.text.Text = if mine then "＋ Egg" else ""
		action = "Add egg"
	else
		local left = start + duration - now()
		if left <= 0 then
			local weather = Nest.weatherAt(start + duration)
			entry.text.Text = if weather.minVariant then ("✅ Ready! %s"):format(weather.icon) else "✅ Ready!"
			action = "Hatch"
		else
			entry.text.Text = "⏳ " .. Format.time(math.ceil(left))
			action = "Check"
		end
	end
	entry.gui.Enabled = entry.text.Text ~= ""
	if prompt then
		prompt.Enabled = mine and action ~= ""
		prompt.ActionText = action
	end
end

-- The Heist Egg (HeistService): its timer, and no "Steal" prompt for the one carrying it
local heistGuis: { [BasePart]: TextLabel } = {}
local function updateHeist()
	for _, egg in CollectionService:GetTagged("HeistEgg") do
		if not egg:IsA("BasePart") then
			continue
		end
		local text = heistGuis[egg]
		if not text then
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromScale(12, 2.4)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
			gui.AlwaysOnTop = true
			gui.MaxDistance = 400
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.TextColor3 = Color3.fromRGB(255, 220, 90)
			label.TextStrokeTransparency = 0.2
			label.Parent = gui
			gui.Parent = egg
			heistGuis[egg] = label
			text = label
			egg.AncestryChanged:Connect(function()
				if not egg.Parent then
					heistGuis[egg] = nil
				end
			end)
		end
		local ends = egg:GetAttribute("Ends")
		local left = if type(ends) == "number" then math.max(0, math.ceil(ends - now())) else 0
		local mine = egg:GetAttribute("Carrier") == LOCAL.UserId
		;(text :: TextLabel).Text = if mine then ("🥚 Run to your Nest! %s"):format(Format.time(left)) else ("🥚 HEIST EGG · %s"):format(Format.time(left))
		local prompt = egg:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = not mine
		end
	end
end

-- The weather banner
local function mountWeather(gui: ScreenGui): (TextLabel, Frame)
	local frame = Instance.new("Frame")
	frame.Name = "Weather"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 6)
	frame.Size = UDim2.fromOffset(360, 30)
	frame.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
	frame.BackgroundTransparency = 0.25
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = frame
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -16, 1, 0)
	text.Position = UDim2.fromOffset(8, 0)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Parent = frame
	frame.Parent = gui
	return text, frame
end

function NestClient.init(gui: ScreenGui)
	local weatherText, weatherFrame = mountWeather(gui)
	local stroke = weatherFrame:FindFirstChildOfClass("UIStroke") :: UIStroke

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local plot, slot = prompt:GetAttribute("NestPlot"), prompt:GetAttribute("NestSlot")
		if type(plot) == "number" and type(slot) == "number" then
			Net.event("NestUse"):FireServer(plot, slot)
		end
	end)
	CollectionService:GetInstanceRemovedSignal("NestPad"):Connect(function(pad)
		local entry = drawn[pad :: BasePart]
		if entry then
			entry.egg:Destroy()
			drawn[pad :: BasePart] = nil
		end
	end)

	task.spawn(function()
		while true do
			updateHeist()
			for _, pad in CollectionService:GetTagged("NestPad") do
				if pad:IsA("BasePart") then
					update(pad)
				end
			end
			local weather, ends = Nest.weatherAt(math.floor(now()))
			local left = Format.time(math.max(0, math.ceil(ends - now())))
			if weather.minVariant then
				local variant = Variants.byId[weather.minVariant]
				weatherText.Text = ("%s %s: nest eggs hatch %s+ · %s"):format(weather.icon, weather.name, weather.minVariant, left)
				stroke.Color = if variant then variant.color else weather.color
			else
				weatherText.Text = ("%s %s · next weather in %s"):format(weather.icon, weather.name, left)
				stroke.Color = weather.color
			end
			task.wait(0.1)
		end
	end)
end

return NestClient
