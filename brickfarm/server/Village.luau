--!strict
-- Builds the world everyone shares, all of bricks: a green baseplate, the market town in the middle (fountain,
-- orders board, signposts), roads out to the farms, trees, and each farm: a big square of land walled by a hedge
-- with a gate facing the town, the grid of tiles, the barn, a house to walk into, the stand where visitors buy,
-- and the name over the gate. A farm's tiles carry what grows on them as attributes (Crop, Planted); each phone
-- builds and animates the crops from those.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FarmConfig = require(Shared.Config.Farm)
local Land = require(Shared.Logic.Land)
local Layout = require(Shared.Logic.Layout)

local Village = {}

local rgb = Color3.fromRGB
Village.GRASS = rgb(75, 151, 75)
Village.SOIL = rgb(124, 92, 70)
Village.FOR_SALE = rgb(110, 175, 95)
local WHITE = rgb(242, 243, 243)
local RED = rgb(196, 40, 28)
local DARK_RED = rgb(123, 46, 47)
local TAN = rgb(215, 197, 154)
local STONE = rgb(163, 162, 165)
local DARK_STONE = rgb(99, 95, 98)
local BLUE = rgb(13, 105, 172)
local BROWN = rgb(105, 64, 40)
local WOOD = rgb(160, 110, 70)
local YELLOW = rgb(245, 205, 48)
local HEDGE = rgb(40, 127, 71)
local ROOF_BLUE = rgb(33, 84, 185)
local CREAM = rgb(253, 234, 141)

-- A plastic brick (studs on top, like the real thing)
local function brick(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, studs: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.Plastic
	p.TopSurface = if studs == false then Enum.SurfaceType.Smooth else Enum.SurfaceType.Studs
	p.BottomSurface = Enum.SurfaceType.Inlet
	p.Parent = parent
	return p
end

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.Parent = gui
	gui.Parent = p
	return t
end

local function prompt(parent: Instance, name: string, action: string, object: string, distance: number?): ProximityPrompt
	local pr = Instance.new("ProximityPrompt")
	pr.Name = name
	pr.ActionText = action
	pr.ObjectText = object
	pr.HoldDuration = 0
	pr.MaxActivationDistance = distance or 12
	pr.RequiresLineOfSight = false
	pr.Parent = parent
	return pr
end

-- A tree: a trunk and three stacked blocks of leaves
local function tree(parent: Instance, at: Vector3, scale: number)
	local model = Instance.new("Model")
	model.Name = "Tree"
	brick(model, "Trunk", Vector3.new(2, 6, 2) * scale, CFrame.new(at + Vector3.new(0, 3 * scale, 0)), BROWN)
	local greens = { rgb(75, 151, 75), rgb(40, 127, 71), rgb(88, 171, 65) }
	for i = 1, 3 do
		local w = (9 - i * 2) * scale
		brick(model, "Leaves", Vector3.new(w, 2.6 * scale, w), CFrame.new(at + Vector3.new(0, (5 + i * 2.6) * scale, 0)), greens[i])
	end
	model.Parent = parent
end

-- A straight run of bricks between two points on the ground (a road, a hedge, a fence rail)
local function run(parent: Instance, name: string, from: Vector3, to: Vector3, width: number, height: number, y: number, color: Color3, studs: boolean?): Part
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	return brick(parent, name, Vector3.new(width, height, length), CFrame.lookAt(mid, to) * CFrame.new(0, y, 0), color, studs)
end

-- The town in the middle: a stone square, the fountain, the orders board, a signpost for each farm
local function town(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Town"
	local floor = brick(model, "Square", Vector3.new(1, FarmConfig.TOWN * 2, FarmConfig.TOWN * 2), CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), STONE, false)
	floor.Shape = Enum.PartType.Cylinder
	for i, r in { 10, 8, 3 } do
		local ring = brick(model, "Fountain", Vector3.new(2 + i, r * 2, r * 2), CFrame.new(0, 1 + i * 1.4, 0) * CFrame.Angles(0, 0, math.pi / 2), if i == 3 then WHITE else DARK_STONE, false)
		ring.Shape = Enum.PartType.Cylinder
	end
	local water = brick(model, "Water", Vector3.new(0.6, 17, 17), CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.pi / 2), BLUE, false)
	water.Shape = Enum.PartType.Cylinder
	water.Material = Enum.Material.Glass
	water.Transparency = 0.25
	-- the orders board
	local at = Layout.board()
	for _, side in { -1, 1 } do
		brick(model, "BoardPost", Vector3.new(1.4, 12, 1.4), at * CFrame.new(side * 9, 6, 0), BROWN)
	end
	local board = brick(model, "OrdersBoard", Vector3.new(18, 9, 1), at * CFrame.new(0, 7.5, 0), WOOD)
	label(board, Enum.NormalId.Back, "ORDERS", WHITE)
	label(board, Enum.NormalId.Front, "ORDERS", WHITE)
	brick(model, "BoardRoof", Vector3.new(21, 1, 3), at * CFrame.new(0, 12.5, 0), DARK_RED)
	prompt(board, "OrdersPrompt", "See the orders", "Orders board", 16)
	-- lamp posts around the square
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local p = Vector3.new(math.cos(a), 0, math.sin(a)) * (FarmConfig.TOWN - 6)
		brick(model, "Lamp", Vector3.new(1, 10, 1), CFrame.new(p + Vector3.new(0, 5, 0)), rgb(27, 42, 53))
		local light = brick(model, "LampTop", Vector3.new(2, 2, 2), CFrame.new(p + Vector3.new(0, 11, 0)), CREAM, false)
		light.Material = Enum.Material.Neon
	end
	model.Parent = parent
end

-- One farm: its walled land, tiles, barn, house, stand, the name over its gate, and the road to town
function Village.farm(parent: Instance, index: number): Model
	local model = Instance.new("Model")
	model.Name = "Farm" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("Owner", 0)
	local frame = Layout.farm(index)
	local half = FarmConfig.ENCLOSURE / 2
	local function at(x: number, z: number): Vector3
		return (frame * CFrame.new(x, 0, z)).Position
	end

	-- the land inside the hedge is a lighter green (so the farm reads as its own place)
	brick(model, "Yard", Vector3.new(FarmConfig.ENCLOSURE, 0.2, FarmConfig.ENCLOSURE), frame * CFrame.new(0, 0.1, 0), rgb(98, 166, 80), false)
	-- the hedge, with the gate
	local h = FarmConfig.WALL
	local gap = FarmConfig.GATE / 2
	run(model, "Hedge", at(-half, -half), at(-half, half), 4, h, h / 2, HEDGE)
	run(model, "Hedge", at(-half, half), at(half, half), 4, h, h / 2, HEDGE)
	run(model, "Hedge", at(half, half), at(half, -half), 4, h, h / 2, HEDGE)
	run(model, "Hedge", at(-half, -half), at(-gap, -half), 4, h, h / 2, HEDGE)
	run(model, "Hedge", at(gap, -half), at(half, -half), 4, h, h / 2, HEDGE)
	-- the gate: two posts and an arch with the farmer's name
	local gate = Layout.gate(index)
	for _, side in { -1, 1 } do
		brick(model, "GatePost", Vector3.new(3, h + 6, 3), gate * CFrame.new(side * (gap + 1.5), (h + 6) / 2, 0), WOOD)
	end
	local arch = brick(model, "NameBoard", Vector3.new(FarmConfig.GATE + 6, 4, 1.2), gate * CFrame.new(0, h + 4, 0), YELLOW)
	local nameLabel = label(arch, Enum.NormalId.Front, "Free farm", BROWN)
	nameLabel.Name = "Owner"
	local inside = label(arch, Enum.NormalId.Back, "Free farm", BROWN)
	inside.Name = "OwnerInside"
	-- (and high over the gate, seen from far away, so farms are easy to find)
	local far = Instance.new("BillboardGui")
	far.Name = "FarName"
	far.Size = UDim2.fromOffset(260, 50)
	far.StudsOffset = Vector3.new(0, 14, 0)
	far.MaxDistance = 1500
	far.LightInfluence = 0
	local farText = Instance.new("TextLabel")
	farText.BackgroundTransparency = 1
	farText.Size = UDim2.fromScale(1, 1)
	farText.Font = Enum.Font.FredokaOne
	farText.TextScaled = true
	farText.TextColor3 = WHITE
	farText.TextStrokeColor3 = BROWN
	farText.TextStrokeTransparency = 0
	farText.Text = "Free farm"
	farText.Parent = far
	far.Parent = arch

	-- the tiles, and a low white fence around them
	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = model
	for n = 1, Land.MAX do
		local tile = brick(tiles, "Tile" .. n, Vector3.new(FarmConfig.TILE, 1, FarmConfig.TILE), Layout.tile(index, n) * CFrame.new(0, 0.5, 0), Village.FOR_SALE)
		tile:SetAttribute("Farm", index)
		tile:SetAttribute("Index", n)
		tile:SetAttribute("Owned", false)
		tile:SetAttribute("Crop", "")
		tile:SetAttribute("Planted", 0)
	end
	local fx = FarmConfig.COLUMNS * Layout.STEP / 2 + 3
	local fz = FarmConfig.ROWS * Layout.STEP / 2 + 3
	local function fence(from: Vector3, to: Vector3)
		run(model, "Rail", from, to, 0.6, 0.6, 2.2, WHITE)
		run(model, "Rail", from, to, 0.6, 0.6, 1.0, WHITE)
		local posts = math.max(1, math.floor((to - from).Magnitude / 6))
		for i = 0, posts do
			brick(model, "Post", Vector3.new(1, 3, 1), CFrame.new(from:Lerp(to, i / posts)) * CFrame.new(0, 1.5, 0), WHITE)
		end
	end
	fence(at(-fx, -fz), at(-fx, fz))
	fence(at(-fx, fz), at(fx, fz))
	fence(at(fx, fz), at(fx, -fz))
	fence(at(-fx, -fz), at(-6, -fz))
	fence(at(6, -fz), at(fx, -fz))

	-- the barn
	local barnFrame = Layout.barn(index)
	local barn = Instance.new("Model")
	barn.Name = "Barn"
	brick(barn, "Body", Vector3.new(14, 9, 12), barnFrame * CFrame.new(0, 4.5, 0), RED)
	for _, side in { -1, 1 } do
		brick(barn, "Roof", Vector3.new(15, 1.2, 8.6), barnFrame * CFrame.new(0, 11.3, side * 3.2) * CFrame.Angles(side * math.rad(38), 0, 0), DARK_RED)
	end
	brick(barn, "Gable", Vector3.new(14, 4, 6), barnFrame * CFrame.new(0, 10.5, 0), RED)
	local door = brick(barn, "Door", Vector3.new(6, 7, 0.4), barnFrame * CFrame.new(0, 3.5, -6.1), WHITE, false)
	brick(barn, "DoorInside", Vector3.new(5, 6, 0.5), barnFrame * CFrame.new(0, 3.2, -6.15), DARK_RED, false)
	local sign = brick(barn, "BarnSign", Vector3.new(8, 2, 0.4), barnFrame * CFrame.new(0, 8, -6.2), WHITE, false)
	label(sign, Enum.NormalId.Front, "BARN", RED)
	prompt(door, "BarnPrompt", "Open the barn", "Barn", 14)
	barn.Parent = model

	-- the house: four walls with a doorway, windows, a roof, and a room inside (table, bed, rug) to walk into
	local hf = Layout.house(index)
	local house = Instance.new("Model")
	house.Name = "House"
	local W, D, H = 18, 16, 10
	brick(house, "Floor", Vector3.new(W, 0.6, D), hf * CFrame.new(0, 0.3, 0), rgb(204, 142, 105), false)
	brick(house, "WallBack", Vector3.new(W, H, 1), hf * CFrame.new(0, H / 2, D / 2), CREAM)
	brick(house, "WallLeft", Vector3.new(1, H, D), hf * CFrame.new(-W / 2, H / 2, 0), CREAM)
	brick(house, "WallRight", Vector3.new(1, H, D), hf * CFrame.new(W / 2, H / 2, 0), CREAM)
	-- the front, with a doorway in the middle and a window either side
	brick(house, "FrontLeft", Vector3.new(6, H, 1), hf * CFrame.new(-6, H / 2, -D / 2), CREAM)
	brick(house, "FrontRight", Vector3.new(6, H, 1), hf * CFrame.new(6, H / 2, -D / 2), CREAM)
	brick(house, "FrontTop", Vector3.new(6, 3, 1), hf * CFrame.new(0, H - 1.5, -D / 2), CREAM)
	for _, side in { -1, 1 } do
		local window = brick(house, "Window", Vector3.new(3, 3, 1.1), hf * CFrame.new(side * 6, 5.5, -D / 2), rgb(159, 195, 233), false)
		window.Material = Enum.Material.Glass
		window.Transparency = 0.4
	end
	for _, side in { -1, 1 } do
		brick(house, "Roof", Vector3.new(W + 2, 1.2, D / 2 + 3), hf * CFrame.new(0, H + 2.4, side * (D / 4 + 0.6)) * CFrame.Angles(side * math.rad(-32), 0, 0), ROOF_BLUE)
	end
	brick(house, "Gable", Vector3.new(W, 3.5, D - 4), hf * CFrame.new(0, H + 1.6, 0), CREAM)
	brick(house, "Chimney", Vector3.new(2, 5, 2), hf * CFrame.new(5, H + 4, 3), RED)
	-- inside
	brick(house, "Rug", Vector3.new(8, 0.15, 6), hf * CFrame.new(0, 0.66, 0), rgb(196, 40, 28), false)
	brick(house, "Table", Vector3.new(4, 0.5, 3), hf * CFrame.new(-4, 3, 3), WOOD)
	for _, leg in { { -1.6, -1.2 }, { 1.6, -1.2 }, { -1.6, 1.2 }, { 1.6, 1.2 } } do
		brick(house, "Leg", Vector3.new(0.4, 2.4, 0.4), hf * CFrame.new(-4 + leg[1], 1.6, 3 + leg[2]), BROWN)
	end
	brick(house, "Bed", Vector3.new(4, 1.6, 7), hf * CFrame.new(6, 1.4, 3.5), WHITE)
	brick(house, "Blanket", Vector3.new(4.1, 0.4, 4.5), hf * CFrame.new(6, 2.3, 2.2), BLUE)
	brick(house, "Pillow", Vector3.new(3, 0.8, 1.5), hf * CFrame.new(6, 2.6, 6), WHITE)
	local lamp = brick(house, "Lamp", Vector3.new(1.2, 1.2, 1.2), hf * CFrame.new(0, H - 1, 0), CREAM, false)
	lamp.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Color = rgb(255, 230, 180)
	light.Parent = lamp
	house.Parent = model

	-- the stand: a counter under a striped awning, a sign and the prompt to buy (or, for its farmer, to stock it)
	local sf = Layout.stand(index)
	local stand = Instance.new("Model")
	stand.Name = "Stand"
	local counter = brick(stand, "Counter", Vector3.new(10, 3.4, 3), sf * CFrame.new(0, 1.7, 0), WOOD)
	for _, side in { -1, 1 } do
		brick(stand, "StandPost", Vector3.new(0.8, 8, 0.8), sf * CFrame.new(side * 4.6, 4, 1), BROWN)
	end
	for i = 0, 4 do
		brick(stand, "Awning", Vector3.new(2, 0.6, 5), sf * CFrame.new(-4 + i * 2, 8.3, -0.5) * CFrame.Angles(math.rad(-12), 0, 0), if i % 2 == 0 then RED else WHITE)
	end
	local standSign = brick(stand, "StandSign", Vector3.new(8, 1.8, 0.4), sf * CFrame.new(0, 6.6, -0.2), WHITE, false)
	label(standSign, Enum.NormalId.Front, "FARM STAND", RED)
	prompt(counter, "StandPrompt", "Shop", "Farm stand", 12)
	-- (crates on the counter show what's for sale: the phones fill them)
	stand.Parent = model

	-- the road to town, from the gate
	local from = gate.Position
	local to = frame.Position + frame.LookVector * (FarmConfig.RING - FarmConfig.TOWN + 2)
	run(model, "Road", from, to, 14, 0.4, 0.2, TAN, false)
	run(model, "RoadIn", from, at(0, -FarmConfig.ROWS * Layout.STEP / 2 - 4), 10, 0.4, 0.3, TAN, false)
	model.Parent = parent
	return model
end

-- A farm's name over its gate (and on the town's signpost for it)
function Village.setOwner(farm: Model, name: string?)
	local board = farm:FindFirstChild("NameBoard")
	if board then
		for _, gui in board:GetChildren() do
			if gui:IsA("SurfaceGui") or gui:IsA("BillboardGui") then
				local text = gui:FindFirstChildOfClass("TextLabel")
				if text then
					text.Text = if name then name .. "'s Farm" else "Free farm"
				end
			end
		end
	end
end

-- A sunny day
function Village.lighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.4
	Lighting.Ambient = rgb(110, 110, 120)
	Lighting.OutdoorAmbient = rgb(150, 150, 160)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	local function effect(className: string, props: { [string]: any })
		local e: any = Lighting:FindFirstChildOfClass(className) or Instance.new(className)
		for k, v in props do
			e[k] = v
		end
		e.Parent = Lighting
	end
	effect("ColorCorrectionEffect", { Saturation = 0.12, Contrast = 0.05, Brightness = 0.02 })
	effect("BloomEffect", { Intensity = 0.4, Size = 24, Threshold = 1.4 })
	effect("Atmosphere", { Density = 0.25, Offset = 0, Color = rgb(199, 225, 255), Decay = rgb(140, 170, 210), Glare = 0, Haze = 0.8 })
end

-- Everything (call once). Returns the farms
function Village.build(parent: Instance): { Model }
	local folder = Instance.new("Folder")
	folder.Name = "Village"
	local size = (FarmConfig.RING + FarmConfig.ENCLOSURE) * 2 + 300
	brick(folder, "Ground", Vector3.new(size, 2, size), CFrame.new(0, -1, 0), Village.GRASS)
	town(folder)
	local farms = {}
	for i = 1, FarmConfig.FARMS do
		farms[i] = Village.farm(folder, i)
	end
	-- trees: never on a farm, a road or the square
	local seed = 7
	local function rand(): number
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	local function clear(p: Vector3): boolean
		if p.Magnitude < FarmConfig.TOWN + 14 then
			return false
		end
		for i = 1, FarmConfig.FARMS do
			local local_ = Layout.farm(i):PointToObjectSpace(p)
			local half = FarmConfig.ENCLOSURE / 2 + 12
			if math.abs(local_.X) < half and math.abs(local_.Z) < half then
				return false
			end
			-- (the road: in front of the gate, out to the town)
			if math.abs(local_.X) < 16 and local_.Z < 0 then
				return false
			end
		end
		return true
	end
	local planted = 0
	for _ = 1, 600 do
		if planted >= 140 then
			break
		end
		local a = rand() * math.pi * 2
		local r = FarmConfig.TOWN + 20 + rand() * (FarmConfig.RING + FarmConfig.ENCLOSURE)
		local p = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if clear(p) then
			tree(folder, p, 0.8 + rand() * 0.9)
			planted += 1
		end
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, FarmConfig.TOWN - 12)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Parent = folder
	folder.Parent = parent
	Village.lighting()
	return farms
end

return Village
