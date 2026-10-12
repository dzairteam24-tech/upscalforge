--!strict
-- A new player's first minutes: a glowing line from them to what to do next, a word over it, and one line at the
-- top of the screen saying it, until they've hatched a few creatures. The whole loop, a step at a time: hatch
-- the egg that's ready; carrying an egg from the Wild, run home; holding one, set it down in the hatching field;
-- the first egg still growing, wait by it; else go to the Wild and steal one.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Night = require(Shared.Logic.Night)

local Store = require(script.Parent.Parent.Store)

local Guide = {}

local LOCAL = Players.LocalPlayer
local DONE_AFTER = 3 -- creatures hatched, then the guide stops
local HIDE_NEAR = 12 -- studs: close enough, the line goes away (the word stays)

local function number(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function myIsland(): Instance?
	local index = LOCAL:GetAttribute("Island")
	local world = workspace:FindFirstChild("World")
	return if world and type(index) == "number" then world:FindFirstChild("Island_" .. index) else nil
end

-- A part of the player's garden, by name (the hatching field's sign, the gate)
local function myPart(name: string): BasePart?
	local island = myIsland()
	local found = island and island:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

-- The player's eggs in their garden: the first one ready to hatch, and the first one still growing
local function myEggs(): (BasePart?, BasePart?)
	local ready, growing = nil, nil
	local now = workspace:GetServerTimeNow()
	for _, pad in CollectionService:GetTagged("Incubator") do
		if pad:IsA("BasePart") and pad:GetAttribute("Owner") == LOCAL.UserId and number(pad, "Tier") > 0 then
			if Night.doneAt(number(pad, "Start"), number(pad, "Duration")) <= now then
				ready = ready or pad
			else
				growing = growing or pad
			end
		end
	end
	return ready, growing
end

-- The nearest egg in the Wild's nests
local function nearestWildEgg(from: Vector3): BasePart?
	local best, bestDistance = nil, math.huge
	for _, egg in CollectionService:GetTagged("WildEgg") do
		if egg:IsA("BasePart") and egg.Transparency < 1 then
			local distance = (egg.Position - from).Magnitude
			if distance < bestDistance then
				best, bestDistance = egg, distance
			end
		end
	end
	return best
end

local function holdsEggs(data: any): boolean
	for _, held in { data.eggs, data.golden or {} } do
		for _, count in held do
			if count > 0 then
				return true
			end
		end
	end
	return false
end

-- Where to go next: the target, the word over it, and the line at the top of the screen
local function step(root: BasePart): (BasePart?, string, string)
	local data = Store.data
	local hatched = if data and data.stats then data.stats.hatched else 0
	if not data or hatched >= DONE_AFTER then
		return nil, "", ""
	end
	local ready, growing = myEggs()
	if ready then
		return ready, "🐣 Hatch it!", "Your egg is ready: go and hatch it"
	end
	if LOCAL:GetAttribute("WildEgg") == true then
		return myPart("Gate"), "🏠 Home!", "Run home with the egg: your garden is safe"
	end
	if holdsEggs(data) then
		return myPart("HatcherySign"), "🥚 Here!", "Take your egg from the hotbar and click in your hatching field"
	end
	if growing and hatched == 0 then
		return growing, "🐣 Your first egg!", "Your first egg is hatching: wait for it"
	end
	return nearestWildEgg(root.Position), "🥚 Steal one!", "Go to the Wild and steal an egg: follow the yellow line"
end

function Guide.init()
	local beam = Instance.new("Beam")
	beam.FaceCamera = true
	beam.Width0, beam.Width1 = 0.8, 0.8
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 215, 80))
	beam.Transparency = NumberSequence.new(0.2)
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Static
	beam.TextureLength = 3
	beam.TextureSpeed = 2
	local from = Instance.new("Attachment")
	local to = Instance.new("Attachment")
	to.Position = Vector3.new(0, 3, 0)
	beam.Attachment0, beam.Attachment1 = from, to

	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromScale(9, 2)
	label.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	label.AlwaysOnTop = true
	label.MaxDistance = 600
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.fromRGB(255, 225, 100)
	text.TextStrokeTransparency = 0.2
	text.Parent = label

	-- (the line at the top of the screen, under the weather)
	local screen = Instance.new("ScreenGui")
	screen.Name = "Guide"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 5
	local line = Instance.new("TextLabel")
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0, 52)
	line.Size = UDim2.new(0.6, 0, 0, 30)
	line.BackgroundTransparency = 1
	line.TextScaled = true
	line.Font = Enum.Font.FredokaOne
	line.TextColor3 = Color3.fromRGB(255, 225, 100)
	line.TextStrokeColor3 = Color3.fromRGB(28, 24, 40)
	line.TextStrokeTransparency = 0
	line.Parent = screen
	screen.Parent = LOCAL:WaitForChild("PlayerGui")

	task.spawn(function()
		while true do
			local root = LOCAL.Character and LOCAL.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local target, words, says = nil, "", ""
			if root then
				target, words, says = step(root)
			end
			if target and root then
				from.Parent = root
				to.Parent = target
				label.Parent = target
				label.Adornee = target
				text.Text = words
				beam.Parent = if (root.Position - target.Position).Magnitude > HIDE_NEAR then root else nil
			else
				beam.Parent, label.Parent, from.Parent, to.Parent = nil, nil, nil, nil
			end
			line.Text = says
			line.Visible = says ~= ""
			task.wait(0.25)
		end
	end)
end

return Guide
