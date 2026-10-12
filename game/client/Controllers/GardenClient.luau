--!strict
-- The gardens on this screen: the eggs in the nests with their timers, the owner's nest prompts, the laser
-- gates (open only for their owner), the creatures roaming the pastures with their coins popping, the Heist
-- Egg's timer, the Mother Cube, the treadmills, and what the prompts in the world open.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)
local Creatures = require(Shared.Config.Creatures)
local Hatch = require(Shared.Logic.Hatch)
local Snap = require(Shared.Logic.Snap)
local Night = require(Shared.Logic.Night)
local Layout = require(Shared.Logic.Layout)
local Weather = require(Shared.Logic.Weather)
local Wild = require(Shared.Logic.Wild)
local Net = require(Shared.Net)

local Notify = require(script.Parent.Parent.UI.Notify)
local Reveal = require(script.Parent.Parent.UI.Reveal)
local Theme = require(script.Parent.Parent.UI.Theme)
local Store = require(script.Parent.Parent.Store)
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
	text.Font = Enum.Font.LuckiestGuy
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeColor3 = Color3.fromRGB(28, 24, 40)
	text.TextStrokeTransparency = 0
	text.Parent = gui
	gui.Parent = parent
	return text
end

-- Incubators: the egg in each (bobbing; it wobbles as it gets close, and bounces when it's ready), a bar of how
-- far it's got and what's left, and the owner's prompt
local EGG_SIZE = Layout.NEST_SIZE * 0.45
type Pad = { egg: Part, text: TextLabel, bar: Frame, fill: Frame, progress: number, ready: boolean, has: boolean }
local pads: { [BasePart]: Pad } = {}

local function eggBar(pad: BasePart): (TextLabel, Frame, Frame)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(7, 2.2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	gui.MaxDistance = 90
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 0.55)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.LuckiestGuy
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeColor3 = Color3.fromRGB(28, 24, 40)
	text.TextStrokeTransparency = 0
	text.Parent = gui
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, 0.6)
	bar.Size = UDim2.fromScale(0.8, 0.32)
	bar.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(92, 214, 110)
	corner:Clone().Parent = fill
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	shine.Parent = fill
	fill.Parent = bar
	bar.Parent = gui
	gui.Parent = pad
	return text, bar, fill
end

local function updatePad(pad: BasePart)
	local entry = pads[pad]
	if not entry then
		local egg = Instance.new("Part")
		egg.Name = "IncubatingEgg"
		egg.Shape = Enum.PartType.Ball
		egg.Size = Vector3.one * EGG_SIZE -- the same for every tier: it fits the nest
		egg.Anchored = true
		egg.CanCollide = false
		egg.CanQuery = false
		egg.CanTouch = false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 1.3, 1)
		mesh.Parent = egg
		local text, bar, fill = eggBar(pad)
		entry = { egg = egg, text = text, bar = bar, fill = fill, progress = 0, ready = false, has = false }
		pads[pad] = entry
	end
	local pad_ = entry :: Pad
	local owner = number(pad, "Owner")
	local mine = owner == LOCAL.UserId
	local open = pad:GetAttribute("Open") == true
	local tier, start, duration, price = number(pad, "Tier"), number(pad, "Start"), number(pad, "Duration"), number(pad, "Price")
	pad.Transparency = if open then 0 else 0.6
	local egg = Hatch.egg(tier)
	pad_.has = egg ~= nil
	pad_.egg.Parent = if egg then pad else nil
	pad_.bar.Visible = false
	if egg then
		local golden = pad:GetAttribute("Golden") == true
		local color = if golden then Color3.fromRGB(255, 205, 70) else egg.color
		pad_.egg.Color = color
		pad_.egg.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
		-- (nights grow eggs faster: Logic/Night)
		local left = math.ceil(Night.doneAt(start, duration)) - now()
		pad_.progress = if duration > 0 then math.clamp(Night.growth(start, now()) / duration, 0, 1) else 1
		pad_.ready = left <= 0
		pad_.bar.Visible = owner ~= 0 and not pad_.ready
		pad_.fill.Size = UDim2.fromScale(pad_.progress, 1)
		pad_.fill.BackgroundColor3 = Color3.fromRGB(255, 196, 64):Lerp(Color3.fromRGB(92, 214, 110), pad_.progress)
	end
	local action = ""
	local text = ""
	if owner == 0 then
		text = ""
	elseif not open then
		text = if price > 0 then "🔒 " .. Format.abbrev(price) else ""
		action = if price > 0 then "Unlock" else ""
	elseif not egg then
		text = if mine then (if pad:GetAttribute("Machine") then "＋ Egg ⚡×2" else "＋ Egg") else ""
		action = "Add egg"
	else
		local done = math.ceil(Night.doneAt(start, duration))
		local left = done - now()
		if left <= 0 then
			local weather = Weather.at(done)
			text = if weather.mutation then ("READY! %s"):format(weather.icon) else "READY!"
			action = "Hatch"
		else
			text = Format.time(math.ceil(left))
			action = "Check"
		end
	end
	pad_.text.Text = text
	pad_.text.TextColor3 = if pad_.has and pad_.ready then Color3.fromRGB(150, 255, 140) else Color3.new(1, 1, 1)
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = mine and action ~= ""
		prompt.ActionText = action
	end
end

-- Every frame: the eggs near the camera bob and turn; close to hatching they wobble, ready they bounce
local function animateEggs()
	local clock = os.clock()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for pad, entry in pads do
		if not entry.has or (pad.Position - eye).Magnitude > 120 then
			continue
		end
		local seed = pad.Position.X + pad.Position.Z
		local lift = EGG_SIZE * 0.6 + math.sin(clock * 2 + seed) * 0.08
		local tilt = CFrame.identity
		if entry.ready then
			lift += math.abs(math.sin(clock * 6 + seed)) * 0.6
			tilt = CFrame.Angles(0, 0, math.sin(clock * 12 + seed) * 0.12)
		elseif entry.progress > 0.75 then
			local strength = (entry.progress - 0.75) / 0.25
			-- (a shake now and then, more often near the end)
			local beat = math.sin(clock * (2 + strength * 3) + seed)
			if beat > 0.7 then
				tilt = CFrame.Angles(math.sin(clock * 30) * 0.12 * strength, 0, math.sin(clock * 26 + 1) * 0.18 * strength)
			end
		end
		local frame = CFrame.new(pad.Position + Vector3.new(0, lift, 0)) * tilt * CFrame.Angles(0, clock * 0.6 + seed, 0)
		entry.egg.CFrame = frame
	end
end

-- A trough: the owner's food and how long the creatures are fed; the owner feeds there
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
	local prompt = trough:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = mine
		prompt.ActionText = "Feed"
	end
end

-- A garden's laser gate: open for its owner (on this screen only: the server keeps it shut for the others)
local function updateGate(gate: BasePart)
	local index = number(gate, "Island")
	local mine = index ~= 0 and index == LOCAL:GetAttribute("Island")
	gate.CanCollide = not mine
	gate.Transparency = if mine then 0.75 else 0.45
end

-- The creatures roam their garden's pasture: each walks to a random spot, rests a moment, and walks on, hopping
-- as it goes; every few seconds the coins it earned pop over its head. (Moved on this screen only.)
local COIN_EVERY = 3
type Roamer = { model: Model, base: CFrame, y: number, at: Vector3, target: Vector3, rest: number, phase: number, nextCoin: number, tag: BillboardGui? }

-- Over each creature, as in Steal an Egg: its rarity (in its color), its name, and its coins a second
local function nameTag(model: Model, body: BasePart): BillboardGui
	local species = Creatures.byId[tostring(model:GetAttribute("Species"))]
	local rarity = if species then species.rarity else "Common"
	local mutation = model:GetAttribute("Mutation")
	local grade = model:GetAttribute("Grade")
	local name = Snap.name({ s = tostring(model:GetAttribute("Species")), m = if type(mutation) == "string" then mutation else "Normal", g = if type(grade) == "string" and grade ~= "" then grade else nil })
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(140, 54)
	gui.StudsOffsetWorldSpace = Vector3.new(0, number(model, "Height") / 2 + 1.6, 0)
	gui.MaxDistance = 45
	gui.LightInfluence = 0
	type Line = { text: string, color: Color3 }
	local lines: { Line } = {
		{ text = rarity, color = Theme.RARITY[rarity] or Color3.new(1, 1, 1) },
		{ text = name, color = Color3.new(1, 1, 1) },
		{ text = "🪙 " .. Format.abbrev(number(model, "Earn")) .. "/s", color = Color3.fromRGB(110, 255, 110) },
	}
	for i, line in lines do
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Position = UDim2.fromScale(0, (i - 1) / 3)
		text.Size = UDim2.fromScale(1, 1 / 3)
		text.Font = Enum.Font.LuckiestGuy
		text.TextScaled = true
		text.Text = line.text
		text.TextColor3 = line.color
		text.TextStrokeColor3 = Color3.fromRGB(28, 24, 40)
		text.TextStrokeTransparency = 0
		text.Parent = gui
	end
	gui.Adornee = body
	gui.Parent = body
	return gui
end
local roamers: { [Model]: Roamer } = {}

local function pastureSpot(index: number): Vector3
	local world = workspace:FindFirstChild("World")
	local island = world and world:FindFirstChild("Island_" .. index)
	local level = if island then island:GetAttribute("Pasture") else nil
	local inside = Layout.pastureArea(if type(level) == "number" then level else 1)
	local center, size = Layout.pasture(index, if type(level) == "number" then level else 1)
	local spot = Vector3.zero
	repeat -- (not in the pond, the trough or the barn)
		spot = Vector3.new((math.random() - 0.5) * (size.X - 3), 0, (math.random() - 0.5) * (size.Z - 3))
	until not Layout.blocked(spot + inside, if type(level) == "number" then level else 1)
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
	-- Where it starts: the spot the server put it on. (Not its pivot: the model can arrive before its parts, and
	-- its pivot is then nowhere near the garden, so it would appear far away and walk home.)
	local spot = model:GetAttribute("Spot")
	local start = if typeof(spot) == "Vector3" then spot + Vector3.new(0, number(model, "Height") / 2, 0) else model:GetPivot().Position
	local pivot = if model.PrimaryPart then model:GetPivot() else CFrame.new(start)
	roamers[model] = {
		model = model,
		base = pivot.Rotation,
		y = start.Y,
		at = start,
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

local ANIMATE_RANGE = 160 -- studs from the camera: creatures further away hold still
local function roam(dt: number)
	local clock = os.clock()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for model, r in roamers do
		-- (not until its body is in: moving it by its pivot before that would send its parts astray)
		local body = model.PrimaryPart
		if not body or (r.at - eye).Magnitude > ANIMATE_RANGE then
			continue
		end
		if not r.tag then
			r.tag = nameTag(model, body)
		end
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
		if model:GetAttribute("Grade") == "Rainbow" then
			local glow = model:FindFirstChild("RainbowGlow") :: Highlight?
			if not glow then
				local created = Instance.new("Highlight")
				created.Name = "RainbowGlow"
				created.FillTransparency = 0.6
				created.DepthMode = Enum.HighlightDepthMode.Occluded
				created.Parent = model
				glow = created
			end
			local color = Color3.fromHSV((clock * 0.25 + r.phase) % 1, 0.8, 1)
			;(glow :: Highlight).FillColor = color
			;(glow :: Highlight).OutlineColor = color
		end
		if clock >= r.nextCoin then
			r.nextCoin = clock + COIN_EVERY
			-- (coins only pop where they can be seen)
			if (r.at - eye).Magnitude < 90 then
				coinPop(model, number(model, "Earn") * COIN_EVERY)
			end
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

-- The Mother Cube: a face, a gentle bob and spin, and how full it is
type Mother = { text: TextLabel, base: Vector3, face: TextLabel }
local mothers: { [BasePart]: Mother } = {}
local function updateMother(cube: BasePart)
	local entry = mothers[cube]
	if not entry then
		local text = billboard(cube, 16, 4, Vector3.new(0, cube.Size.Y / 2 + 4, 0))
		local gui = text.Parent :: BillboardGui
		gui.AlwaysOnTop = true
		gui.MaxDistance = 600
		text.TextColor3 = Color3.fromRGB(255, 220, 120)
		local faces = Instance.new("SurfaceGui")
		faces.Face = Enum.NormalId.Front
		faces.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud -- (the text keeps its shape on the cube's face)
		faces.PixelsPerStud = 20
		faces.Parent = cube
		local face = Instance.new("TextLabel")
		face.Size = UDim2.fromScale(1, 1)
		face.BackgroundTransparency = 1
		face.TextScaled = true
		face.Font = Enum.Font.FredokaOne
		face.TextColor3 = Color3.fromRGB(70, 45, 30)
		face.Parent = faces
		local created = { text = text, base = cube.Position, face = face }
		mothers[cube] = created
		entry = created
		cube.AncestryChanged:Connect(function()
			if not cube.Parent then
				mothers[cube] = nil
			end
		end)
	end
	local m = entry :: Mother
	local full = cube:GetAttribute("Full") == true
	local points, goal = number(cube, "Points"), math.max(1, number(cube, "Goal"))
	local left = math.max(0, math.ceil(number(cube, "Ends") - now()))
	local clock = os.clock()
	-- Hungry, it bobs and looks around; full, it bounces for joy
	local bob = if full then math.abs(math.sin(clock * 6)) * 2 else math.sin(clock * 2) * 0.8
	cube.CFrame = CFrame.new(m.base + Vector3.new(0, bob, 0)) * CFrame.Angles(0, math.sin(clock * 0.7) * 0.6, 0)
	m.face.Text = if full then "^ ‿ ^" elseif points / goal > 0.6 then "• ᴗ •" else "• o •"
	local bar = string.rep("█", math.floor(math.min(points / goal, 1) * 10)) .. string.rep("░", 10 - math.floor(math.min(points / goal, 1) * 10))
	m.text.Text = if full then "👑 MOTHER CUBE\n💛 FULL! Check your bag" else ("👑 MOTHER CUBE · %s\n🍽️ %s %d/%d"):format(Format.time(left), bar, points, goal)
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
			Net.event("Feed"):FireServer()
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
			Net.event("UseIncubator"):FireServer(slot)
		end
	end)
	-- "+2 ⚡" over the player at each step on the treadmill
	Net.event("SpeedUp").OnClientEvent:Connect(function(gain: number)
		local head = LOCAL.Character and LOCAL.Character:FindFirstChild("Head") :: BasePart?
		if not head then
			return
		end
		local text = billboard(head, 4, 1.4, Vector3.new(0, 2.5, 0))
		local gui = text.Parent :: BillboardGui
		gui.AlwaysOnTop = true
		text.Text = "+" .. Format.abbrev(gain) .. " ⚡"
		text.TextColor3 = Color3.fromRGB(90, 220, 255)
		task.spawn(function()
			for i = 1, 20 do
				gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5 + i * 0.12, 0)
				text.TextTransparency = math.max(0, (i - 10) / 10)
				task.wait(0.05)
			end
			gui:Destroy()
		end)
	end)
	Net.event("Hatched").OnClientEvent:Connect(function(_id, species, mutation, grade)
		Reveal.show(species, mutation, grade)
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
	RunService.RenderStepped:Connect(animateEggs)
	RunService.RenderStepped:Connect(function()
		for _, cube in CollectionService:GetTagged("MotherCube") do
			if cube:IsA("BasePart") then
				updateMother(cube)
			end
		end
	end)
	task.spawn(function()
		while true do
			-- (the nests far from the camera wait: nobody sees their timers from there)
			local camera = workspace.CurrentCamera
			local eye = if camera then camera.CFrame.Position else Vector3.zero
			for _, pad in CollectionService:GetTagged("Incubator") do
				if pad:IsA("BasePart") and (not pads[pad] or (pad.Position - eye).Magnitude < 150) then
					updatePad(pad)
				end
			end
			for _, trough in CollectionService:GetTagged("Trough") do
				if trough:IsA("BasePart") then
					updateTrough(trough)
				end
			end
			-- The treadmills' consoles: the owner sees their level and the upgrade
			for _, console in CollectionService:GetTagged("TreadmillConsole") do
				local prompt = console:FindFirstChildOfClass("ProximityPrompt")
				local text = console:FindFirstChild("TreadmillText", true)
				local mine = console:GetAttribute("Island") == LOCAL:GetAttribute("Island")
				local data = Store.data
				local level = if mine and data then data.treadmill or 1 else 0
				if text and text:IsA("TextLabel") then
					text.Text = if level > 0 then ("🏃 +%s ⚡ / second"):format(Format.abbrev(Wild.gain(level))) else "🏃 Treadmill"
				end
				if prompt then
					local price = if level > 0 then Wild.upgradePrice(level) else nil
					prompt.Enabled = price ~= nil
					prompt.ObjectText = if price then ("Treadmill: +%s → +%s ⚡"):format(Format.abbrev(Wild.gain(level)), Format.abbrev(Wild.gain(level + 1))) else "Treadmill"
					prompt.ActionText = if price then ("Upgrade · 🪙 %s"):format(Format.abbrev(price)) else "Max"
				end
			end
			for _, gate in CollectionService:GetTagged("Gate") do
				if gate:IsA("BasePart") then
					updateGate(gate)
				end
			end
			-- A Wild egg can be grabbed once it's dropped
			for _, carried in CollectionService:GetTagged("WildCarry") do
				local prompt = carried:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					-- (only a dropped one: anyone can grab it)
					prompt.Enabled = carried:GetAttribute("Carrier") == 0
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
