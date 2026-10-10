--!strict
-- The gardens on this screen: the eggs in the nests with their timers, the owner's nest prompts (and a
-- thief's, at Raid Time), the laser gates (always open for their owner), the creatures roaming the pastures
-- with their coins popping, the Heist Egg's timer, and what the prompts in the world open.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RaidConfig = require(Shared.Config.Raid)
local Format = require(Shared.Logic.Format)
local Raid = require(Shared.Logic.Raid)
local Hatch = require(Shared.Logic.Hatch)
local Layout = require(Shared.Logic.Layout)
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
		egg.Size = Vector3.new(2.2, 2.2, 2.2)
		egg.Anchored = true
		egg.CanCollide = false
		egg.CanQuery = false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 1.3, 1)
		mesh.Parent = egg
		entry = { egg = egg, text = billboard(pad, 7, 1.6, Vector3.new(0, 4.6, 0)) }
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
		pad_.egg.CFrame = CFrame.new(pad.Position + Vector3.new(0, 1.2 + math.sin(os.clock() * 2 + pad.Position.X) * 0.08, 0)) * CFrame.Angles(0, os.clock() * 0.6, 0)
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

-- A trough: the owner's food and how long the creatures are fed; the owner feeds there, a thief steals food at
-- Raid Time
local troughTexts: { [BasePart]: TextLabel } = {}
local function updateTrough(trough: BasePart)
	local text = troughTexts[trough]
	if not text then
		text = billboard(trough, 7, 1.6, Vector3.new(0, 3.2, 0))
		troughTexts[trough] = text
	end
	local owner = number(trough, "Owner")
	local mine = owner == LOCAL.UserId
	local food = number(trough, "Food")
	local left = number(trough, "FedUntil") - now()
	local fed = if left > 0 then ("😋 ×2 · %s"):format(Format.time(math.ceil(left))) else "😴 Hungry"
	;(text :: TextLabel).Text = if owner == 0 then "" elseif mine then ("%s · 🌾 %d"):format(fed, food) else fed
	local stealable = Raid.at(math.floor(now())) and not mine and owner ~= 0 and food > 0
	local prompt = trough:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = mine or stealable
		prompt.ActionText = if stealable then "Steal food" else "Feed"
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

-- The creatures roam their garden's pasture: each walks to a random spot, rests a moment, and walks on, hopping
-- as it goes; every few seconds the coins it earned pop over its head. (Moved on this screen only.)
local COIN_EVERY = 3
type Roamer = { model: Model, base: CFrame, y: number, at: Vector3, target: Vector3, rest: number, phase: number, nextCoin: number }
local roamers: { [Model]: Roamer } = {}

local function pastureSpot(index: number): Vector3
	local center, size = Layout.pasture(index)
	local spot = Vector3.zero
	repeat -- (not in the pond, the trough or the barn)
		spot = Vector3.new((math.random() - 0.5) * (size.X - 3), 0, (math.random() - 0.5) * (size.Z - 3))
	until not Layout.blocked(spot + Layout.PASTURE.center)
	return center:PointToWorldSpace(spot)
end

local function coinPop(model: Model, amount: number)
	local head = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not head then
		return
	end
	local text = billboard(head, 4, 1, Vector3.new(0, number(model, "Height") + 1, 0))
	local gui = text.Parent :: BillboardGui
	text.Text = "+" .. Format.abbrev(amount)
	text.TextColor3 = Color3.fromRGB(255, 215, 80)
	task.spawn(function()
		for i = 1, 20 do
			gui.StudsOffsetWorldSpace = Vector3.new(0, number(model, "Height") + 1 + i * 0.1, 0)
			text.TextTransparency = math.max(0, (i - 12) / 8)
			text.TextStrokeTransparency = math.max(0.3, (i - 12) / 8)
			task.wait(0.05)
		end
		gui:Destroy()
	end)
end

local function addRoamer(model: Instance)
	if not model:IsA("Model") or roamers[model] then
		return
	end
	local index = number(model, "Island")
	if index == 0 then
		return
	end
	local pivot = model:GetPivot()
	roamers[model] = {
		model = model,
		base = pivot.Rotation,
		y = pivot.Position.Y,
		at = pivot.Position,
		target = pastureSpot(index),
		rest = math.random() * 2,
		phase = math.random() * 10,
		nextCoin = os.clock() + math.random() * COIN_EVERY,
	}
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			roamers[model] = nil
		end
	end)
end

local function roam(dt: number)
	local clock = os.clock()
	for model, r in roamers do
		local flat = Vector3.new(r.target.X, r.y, r.target.Z) - r.at
		local walking = false
		if r.rest > 0 then
			r.rest -= dt
		elseif flat.Magnitude < 0.5 then
			r.rest = 1 + math.random() * 3
			r.target = pastureSpot(number(model, "Island"))
		else
			r.at += flat.Unit * math.min(flat.Magnitude, 4 * dt)
			walking = true
		end
		local hop = if walking then math.abs(math.sin(clock * 9 + r.phase)) * 0.5 else 0
		local facing = if flat.Magnitude > 0.1 then CFrame.Angles(0, math.atan2(-flat.X, -flat.Z), 0) else r.base
		if walking then
			r.base = facing
		end
		model:PivotTo(CFrame.new(r.at + Vector3.new(0, hop, 0)) * r.base)
		if clock >= r.nextCoin then
			r.nextCoin = clock + COIN_EVERY
			coinPop(model, number(model, "Earn") * COIN_EVERY)
		end
	end
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
		local garden = prompt:GetAttribute("Island")
		if type(ui) == "string" and type(garden) == "number" and garden ~= LOCAL:GetAttribute("Island") then
			Notify.show("That's not your garden's", "error")
			return
		end
		local trough = prompt:GetAttribute("Trough")
		if type(trough) == "number" then
			if prompt.ActionText == "Steal food" then
				Net.event("StealFood"):FireServer(trough)
			else
				Net.event("Feed"):FireServer()
			end
			return
		end
		if type(ui) == "string" then
			if ui == "Soon" or not Windows.open(ui) then
				Notify.show("Coming soon! 🛠️", "info")
			end
			return
		end
		local slot = prompt:GetAttribute("Slot")
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
		addRoamer(model)
	end
	CollectionService:GetInstanceAddedSignal("IslandCreature"):Connect(addRoamer)
	RunService.RenderStepped:Connect(roam)
	task.spawn(function()
		while true do
			for _, pad in CollectionService:GetTagged("Incubator") do
				if pad:IsA("BasePart") then
					updatePad(pad)
				end
			end
			for _, trough in CollectionService:GetTagged("Trough") do
				if trough:IsA("BasePart") then
					updateTrough(trough)
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
