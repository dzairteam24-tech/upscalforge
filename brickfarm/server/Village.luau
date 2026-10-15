--!strict
-- Builds the village everyone shares, all of bricks: a green baseplate, the square in the middle with its
-- fountain, paths out to the farms, trees, and each farm's tiles of land, fence, barn and sign. A farm's tiles
-- carry what grows on them as attributes (Crop, Planted); each phone builds and animates the crops from those.

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
local BLUE = rgb(13, 105, 172)
local BROWN = rgb(105, 64, 40)
local YELLOW = rgb(245, 205, 48)

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

local function square(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Square"
	local floor = brick(model, "Floor", Vector3.new(1, FarmConfig.SQUARE * 2, FarmConfig.SQUARE * 2), CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), STONE, false)
	floor.Shape = Enum.PartType.Cylinder
	-- the fountain: stacked rings of bricks, water in the middle
	for i, r in { 9, 7, 3 } do
		local ring = brick(model, "Fountain", Vector3.new(2 + i, r * 2, r * 2), CFrame.new(0, 1 + i * 1.4, 0) * CFrame.Angles(0, 0, math.pi / 2), if i == 3 then WHITE else rgb(99, 95, 98), false)
		ring.Shape = Enum.PartType.Cylinder
	end
	local water = brick(model, "Water", Vector3.new(0.6, 15, 15), CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.pi / 2), BLUE, false)
	water.Shape = Enum.PartType.Cylinder
	water.Material = Enum.Material.Glass
	water.Transparency = 0.25
	-- the sign
	brick(model, "SignPost", Vector3.new(1.4, 12, 1.4), CFrame.new(0, 6, -FarmConfig.SQUARE + 6), BROWN)
	local board = brick(model, "SignBoard", Vector3.new(22, 6, 1), CFrame.new(0, 13, -FarmConfig.SQUARE + 6), YELLOW)
	label(board, Enum.NormalId.Front, "BRICK FARM", RED)
	label(board, Enum.NormalId.Back, "BRICK FARM", RED)
	model.Parent = parent
end

-- One farm: its tiles, fence, barn and sign
function Village.farm(parent: Instance, index: number): Model
	local model = Instance.new("Model")
	model.Name = "Farm" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("Owner", 0)
	local frame = Layout.farm(index)
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
	-- the fence around the land, open at the front
	local half = FarmConfig.COLUMNS * Layout.STEP / 2 + 3
	local depth = FarmConfig.ROWS * Layout.STEP / 2 + 3
	local function fence(from: Vector3, to: Vector3)
		local length = (to - from).Magnitude
		local mid = (from + to) / 2
		local look = CFrame.lookAt(mid, to)
		brick(model, "Rail", Vector3.new(0.6, 0.6, length), look * CFrame.new(0, 2.2, 0), WHITE)
		brick(model, "Rail", Vector3.new(0.6, 0.6, length), look * CFrame.new(0, 1.0, 0), WHITE)
		local posts = math.floor(length / 6)
		for i = 0, posts do
			brick(model, "Post", Vector3.new(1, 3, 1), CFrame.new(from:Lerp(to, i / posts)) * CFrame.new(0, 1.5, 0), WHITE)
		end
	end
	local function at(x: number, z: number): Vector3
		return (frame * CFrame.new(x, 0, z)).Position
	end
	fence(at(-half, -depth), at(-half, depth))
	fence(at(-half, depth), at(half, depth))
	fence(at(half, depth), at(half, -depth))
	fence(at(-half, -depth), at(-6, -depth))
	fence(at(6, -depth), at(half, -depth))
	-- the barn
	local barnFrame = Layout.barn(index)
	local barn = Instance.new("Model")
	barn.Name = "Barn"
	brick(barn, "Body", Vector3.new(14, 9, 12), barnFrame * CFrame.new(0, 4.5, 0), RED)
	for _, side in { -1, 1 } do
		local roof = brick(barn, "Roof", Vector3.new(15, 1.2, 8.6), barnFrame * CFrame.new(0, 11.3, side * 3.2) * CFrame.Angles(side * math.rad(38), 0, 0), DARK_RED)
		roof.Name = "Roof"
	end
	brick(barn, "Gable", Vector3.new(14, 4, 6), barnFrame * CFrame.new(0, 10.5, 0), RED)
	local door = brick(barn, "Door", Vector3.new(6, 7, 0.4), barnFrame * CFrame.new(0, 3.5, -6.1), WHITE, false)
	brick(barn, "DoorInside", Vector3.new(5, 6, 0.5), barnFrame * CFrame.new(0, 3.2, -6.15), DARK_RED, false)
	local sign = brick(barn, "BarnSign", Vector3.new(8, 2, 0.4), barnFrame * CFrame.new(0, 8, -6.2), WHITE, false)
	label(sign, Enum.NormalId.Front, "BARN", RED)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BarnPrompt"
	prompt.ActionText = "Open the barn"
	prompt.ObjectText = "Barn"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	barn.Parent = model
	-- the sign at the front, with its farmer's name
	local post = at(-half - 4, -depth - 2) -- (beside the entrance, not in the view of the land)
	brick(model, "SignPost", Vector3.new(1, 7, 1), CFrame.new(post + Vector3.new(0, 3.5, 0)), BROWN)
	local board = brick(model, "NameBoard", Vector3.new(12, 3.4, 0.8), CFrame.lookAt(post + Vector3.new(0, 7.5, 0), post + Vector3.new(0, 7.5, 0) - frame.LookVector), YELLOW)
	local nameLabel = label(board, Enum.NormalId.Front, "Free farm", BROWN)
	nameLabel.Name = "Owner"
	-- the path to the square
	local from = at(0, -depth - 1)
	local to = frame.Position + frame.LookVector * (FarmConfig.RING - FarmConfig.SQUARE)
	local length = (to - from).Magnitude
	brick(model, "Path", Vector3.new(8, 0.4, length), CFrame.lookAt((from + to) / 2, to) * CFrame.new(0, 0.2, 0), TAN, false)
	model.Parent = parent
	return model
end

-- A farm's name sign
function Village.setOwner(farm: Model, name: string?)
	local board = farm:FindFirstChild("NameBoard")
	local gui = board and board:FindFirstChildOfClass("SurfaceGui")
	local text = gui and gui:FindFirstChild("Owner") :: TextLabel?
	if text then
		text.Text = if name then name .. "'s Farm" else "Free farm"
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
	effect("Atmosphere", { Density = 0.22, Offset = 0, Color = rgb(199, 225, 255), Decay = rgb(140, 170, 210), Glare = 0, Haze = 0.6 })
end

-- Everything (call once). Returns the farms
function Village.build(parent: Instance): { Model }
	local folder = Instance.new("Folder")
	folder.Name = "Village"
	local ground = brick(folder, "Ground", Vector3.new(800, 2, 800), CFrame.new(0, -1, 0), Village.GRASS)
	ground.Name = "Ground"
	square(folder)
	local farms = {}
	for i = 1, FarmConfig.FARMS do
		farms[i] = Village.farm(folder, i)
	end
	-- trees around the village, never on a farm or a path
	local seed = 7
	local function rand(): number
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	for _ = 1, 70 do
		local a = rand() * math.pi * 2
		local r = FarmConfig.RING + 60 + rand() * 160
		local p = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local clear = true
		for i = 1, FarmConfig.FARMS do
			if (Layout.farm(i).Position - p).Magnitude < 70 then
				clear = false
			end
		end
		if clear then
			tree(folder, p, 0.8 + rand() * 0.7)
		end
	end
	for i = 1, FarmConfig.FARMS do
		-- (one tree between each pair of farms, near the square)
		local a = (i - 0.5) / FarmConfig.FARMS * math.pi * 2
		tree(folder, Vector3.new(math.cos(a) * (FarmConfig.SQUARE + 30), 0, math.sin(a) * (FarmConfig.SQUARE + 30)), 1)
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, FarmConfig.SQUARE - 10)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Parent = folder
	folder.Parent = parent
	Village.lighting()
	return farms
end

return Village
