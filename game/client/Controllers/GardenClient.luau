--!strict
-- The gardens on this screen: the eggs in the incubators with their timers, the owner's incubator prompts (and
-- a thief's, at Raid Time), the laser gates (always open for their owner), what each creature earns over its
-- head, the Heist Egg's timer, and what the prompts in the world open.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RaidConfig = require(Shared.Config.Raid)
local Format = require(Shared.Logic.Format)
local Raid = require(Shared.Logic.Raid)
local Hatch = require(Shared.Logic.Hatch)
local Weather = require(Shared.Logic.Weather)
local Net = require(Shared.Net)

local Notify = require(script.Parent.Parent.UI.Notify)
local Windows = require(script.Parent.Parent.UI.Windows)

local GardenClient = {}

local LOCAL = Players.LocalPlayer

local function now(): number
	return workspace:GetServerTimeNow()
end

local function number(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function billboard(parent: Instance, width: number, height: number, offset: Vector3): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(width, height)
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = 90
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Parent = gui
	gui.Parent = parent
	return text
end

-- Incubators
type Pad = { egg: Part, text: TextLabel }
local pads: { [BasePart]: Pad } = {}

local function updatePad(pad: BasePart)
	local entry = pads[pad]
	if not entry then
		local egg = Instance.new("Part")
		egg.Name = "IncubatingEgg"
		egg.Shape = Enum.PartType.Ball
		egg.Size = Vector3.new(3, 3, 3)
		egg.Anchored = true
		egg.CanCollide = false
		egg.CanQuery = false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 1.3, 1)
		mesh.Parent = egg
		entry = { egg = egg, text = billboard(pad, 7, 1.6, Vector3.new(0, 6, 0)) }
		pads[pad] = entry
	end
	local pad_ = entry :: Pad
	local owner = number(pad, "Owner")
	local mine = owner == LOCAL.UserId
	local open = pad:GetAttribute("Open") == true
	local tier, start, duration, price = number(pad, "Tier"), number(pad, "Start"), number(pad, "Duration"), number(pad, "Price")
	pad.Transparency = if open then 0 else 0.6
	local egg = Hatch.egg(tier)
	pad_.egg.Parent = if egg then pad else nil
	if egg then
		pad_.egg.Color = egg.color
		pad_.egg.CFrame = CFrame.new(pad.Position + Vector3.new(0, 2.6 + math.sin(os.clock() * 2 + pad.Position.X) * 0.2, 0))
	end
	local action = ""
	local text = ""
	local raid = Raid.at(math.floor(now()))
	local carried = pad:GetAttribute("Carried") == true
	if carried then
		pad_.egg.Parent = nil
	end
	if carried then
		text = if mine then "🚨 Stolen! Catch them!" else "🏃 Being stolen"
	elseif owner == 0 then
		text = ""
	elseif not open then
		text = if price > 0 then "🔒 " .. Format.abbrev(price) else ""
		action = if price > 0 then "Unlock" else ""
	elseif not egg then
		text = if mine then "＋ Egg" else ""
		action = "Add egg"
	else
		local left = start + duration - now()
		if left <= 0 then
			local weather = Weather.at(start + duration)
			text = if weather.mutation then ("✅ Ready! %s"):format(weather.icon) else "✅ Ready!"
			action = "Hatch"
		else
			text = "⏳ " .. Format.time(math.ceil(left))
			action = "Check"
		end
	end
	-- At Raid Time, someone else's egg can be stolen (not from the safe incubator)
	local stealable = raid and not mine and owner ~= 0 and egg ~= nil and not carried and number(pad, "Slot") ~= RaidConfig.SAFE_SLOT
	if stealable then
		action = "Steal"
	end
	pad_.text.Text = text
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = (mine and action ~= "" and not carried) or stealable
		prompt.ActionText = action
		prompt.HoldDuration = if stealable then 1 else 0
	end
end

-- A garden's laser gate: always open for its owner (on this screen only: the server keeps it shut for the
-- others until Raid Time)
local function updateGate(gate: BasePart)
	local index = number(gate, "Island")
	local mine = index ~= 0 and index == LOCAL:GetAttribute("Island")
	local isOpen = gate:GetAttribute("Open") == true
	gate.CanCollide = not (isOpen or mine)
	gate.Transparency = if isOpen then 0.9 elseif mine then 0.75 else 0.45
end

-- What each creature on an island earns, over its head
local creatureTags: { [Instance]: boolean } = {}
local function tagCreature(model: Instance)
	if creatureTags[model] or not model:IsA("Model") then
		return
	end
	creatureTags[model] = true
	local earn = number(model, "Earn")
	local head = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if head then
		local text = billboard(head, 5, 1.1, Vector3.new(0, 3.2, 0))
		text.Text = "🪙 " .. Format.abbrev(earn) .. "/s"
		text.TextColor3 = Color3.fromRGB(255, 225, 120)
	end
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			creatureTags[model] = nil
		end
	end)
end

-- The Heist Egg's timer, and no "Steal" prompt for the one carrying it
local heistTexts: { [BasePart]: TextLabel } = {}
local function updateHeist(egg: BasePart)
	local text = heistTexts[egg]
	if not text then
		local created = billboard(egg, 12, 2.4, Vector3.new(0, 4.5, 0))
		local gui = created.Parent :: BillboardGui
		gui.AlwaysOnTop = true
		gui.MaxDistance = 500
		created.TextColor3 = Color3.fromRGB(255, 220, 90)
		heistTexts[egg] = created
		text = created
		egg.AncestryChanged:Connect(function()
			if not egg.Parent then
				heistTexts[egg] = nil
			end
		end)
	end
	local left = math.max(0, math.ceil(number(egg, "Ends") - now()))
	local mine = number(egg, "Carrier") == LOCAL.UserId
	;(text :: TextLabel).Text = if mine then ("🥚 Run home! %s"):format(Format.time(left)) else ("🥚 HEIST EGG · %s"):format(Format.time(left))
	local prompt = egg:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = not mine
	end
end

function GardenClient.init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local ui = prompt:GetAttribute("OpenUI")
		if type(ui) == "string" then
			if ui == "Soon" or not Windows.open(ui) then
				Notify.show("Coming soon! 🛠️", "info")
			end
			return
		end
		local slot = prompt:GetAttribute("Slot")
		local garden = prompt:GetAttribute("Island")
		if type(slot) == "number" then
			if prompt.ActionText == "Steal" then
				Net.event("StealEgg"):FireServer(garden, slot)
			else
				Net.event("UseIncubator"):FireServer(slot)
			end
		end
	end)
	Net.event("Hatched").OnClientEvent:Connect(function(_id, species, mutation)
		Notify.show(("🐣 You hatched a %s%s!"):format(if mutation ~= "Normal" then mutation .. " " else "", species), if mutation ~= "Normal" then "rare" else "success")
	end)
	CollectionService:GetInstanceRemovedSignal("Incubator"):Connect(function(pad)
		local entry = pads[pad :: BasePart]
		if entry then
			entry.egg:Destroy()
			pads[pad :: BasePart] = nil
		end
	end)
	for _, model in CollectionService:GetTagged("IslandCreature") do
		tagCreature(model)
	end
	CollectionService:GetInstanceAddedSignal("IslandCreature"):Connect(tagCreature)
	task.spawn(function()
		while true do
			for _, pad in CollectionService:GetTagged("Incubator") do
				if pad:IsA("BasePart") then
					updatePad(pad)
				end
			end
			for _, gate in CollectionService:GetTagged("Gate") do
				if gate:IsA("BasePart") then
					updateGate(gate)
				end
			end
			for _, egg in CollectionService:GetTagged("HeistEgg") do
				if egg:IsA("BasePart") then
					updateHeist(egg)
				end
			end
			task.wait(0.1)
		end
	end)
end

return GardenClient
