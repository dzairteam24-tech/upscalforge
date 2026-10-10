--!strict
-- A new player's first steps: a glowing line from them to what to do next, until they've hatched a few
-- creatures. First their golden nest (the free egg there, IslandService), then the Egg Shop for more eggs.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Store = require(script.Parent.Parent.Store)

local Guide = {}

local LOCAL = Players.LocalPlayer
local DONE_AFTER = 3 -- creatures hatched, then the guide stops
local HIDE_NEAR = 12 -- studs: close enough, the line goes away (the label stays)

local function myNest(slot: number): BasePart?
	for _, pad in CollectionService:GetTagged("Incubator") do
		if pad:IsA("BasePart") and pad:GetAttribute("Owner") == LOCAL.UserId and pad:GetAttribute("Slot") == slot then
			return pad
		end
	end
	return nil
end

local shop: BasePart? = nil
local function eggShop(): BasePart?
	if shop and shop.Parent then
		return shop
	end
	shop = nil
	for _, prompt in workspace:GetDescendants() do
		if prompt:IsA("ProximityPrompt") and prompt:GetAttribute("OpenUI") == "Shop" and prompt.Parent and prompt.Parent:IsA("BasePart") then
			shop = prompt.Parent :: BasePart
			break
		end
	end
	return shop
end

-- Where to go next, and what to tell the player there
local function step(): (BasePart?, string)
	local data = Store.data
	if not data or data.stats.hatched >= DONE_AFTER then
		return nil, ""
	end
	local slot: number? = nil
	for key in data.incubating do
		local n = tonumber(key)
		if n and (not slot or n < slot) then
			slot = n
		end
	end
	if slot then
		return myNest(slot), if data.stats.hatched == 0 then "🐣 Your first egg!" else "🥚 Hatch it here"
	end
	for _, held in { data.eggs, data.golden or {} } do
		for _, count in held do
			if count > 0 then
				return myNest(1), "＋ Put your egg here"
			end
		end
	end
	return eggShop(), "🥚 Buy an egg here"
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
	label.MaxDistance = 400
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.fromRGB(255, 225, 100)
	text.TextStrokeTransparency = 0.2
	text.Parent = label

	task.spawn(function()
		while true do
			local target, words = step()
			local root = LOCAL.Character and LOCAL.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
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
			task.wait(0.25)
		end
	end)
end

return Guide
