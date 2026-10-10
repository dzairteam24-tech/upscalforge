--!strict
-- Builds the world (Logic/Layout): the square with its fountain where players arrive, and the street north of it,
-- past the six shops and then the players' gardens, each in two rows facing each other across the street; each
-- garden fenced, with its laser gate, incubators and owner's sign. Everything is simple parts, so it works
-- before the 3D art loads; once the town model (Config/Art TOWN_ASSET_ID) is in, each shop is drawn with its
-- building from art/models/Town.glb.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared.Config.Island)
local RaidConfig = require(Shared.Config.Raid)
local TownLooks = require(Shared.Config.TownLooks)
local Layout = require(Shared.Logic.Layout)

local WorldService = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local GRASS = rgb(123, 201, 111)
local PAVING = rgb(236, 222, 196)

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- A floating label (sized in studs, so it shrinks with distance like a real sign)
local function label(parent: Instance, text: string, width: number, height: number, offset: Vector3): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(width, height)
	gui.StudsOffset = offset
	gui.MaxDistance = 220
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Text"
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0.3
	textLabel.Parent = gui
	gui.Parent = parent
	return textLabel
end

local function disc(parent: Instance, name: string, center: Vector3, radius: number, height: number, color: Color3, material: Enum.Material): Part
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	})
end

---------------------------------------------------------------------------------------------------------------
-- The town

-- The six shops, in order along the street from the square (Layout.shop), and the art building each is drawn with
local SHOPS = {
	{ name = "Egg Shop", art = "Shop", ui = "Shop", color = rgb(110, 200, 140) },
	{ name = "Trading", art = "Trade", ui = "Soon", color = rgb(90, 150, 240) },
	{ name = "Potions", art = "Potion", ui = "Soon", color = rgb(160, 110, 230) },
	{ name = "Lucky Spin", art = "Spin", ui = "Soon", color = rgb(255, 150, 80) },
	{ name = "Trips", art = "Trips", ui = "Soon", color = rgb(80, 190, 220) },
	{ name = "Arcade", art = "Arcade", ui = "Soon", color = rgb(240, 110, 170) },
}
WorldService.SHOPS = SHOPS

local ART_WIDTH = 22 -- the art buildings' width, base included (studs)

type Shop = { model: Model, frame: CFrame, booth: BasePart, art: string }
local shops: { Shop } = {}

local function buildShop(town: Instance, index: number)
	local shop = SHOPS[index]
	local frame = Layout.shop(index)
	local model = Instance.new("Model")
	model.Name = shop.name
	-- A plain booth until the art loads (it stays, invisible, for the prompt and to bump into)
	local booth: BasePart = part(model, {
		Name = "Booth",
		Size = Vector3.new(16, 12, 12),
		CFrame = frame * CFrame.new(0, 6, 4),
		Color = rgb(250, 238, 214),
	})
	part(model, { Name = "Roof", Size = Vector3.new(18, 3, 14), CFrame = frame * CFrame.new(0, 13.5, 4), Color = shop.color })
	label(booth, shop.name, 12, 2.4, Vector3.new(0, 11, 0))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = shop.name
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenUI", shop.ui)
	prompt.Parent = booth
	model.Parent = town
	table.insert(shops, { model = model, frame = frame * CFrame.new(0, 0, 4), booth = booth, art = shop.art })
end

local function buildTown(world: Instance)
	local town = Instance.new("Model")
	town.Name = "Town"
	-- The square where players arrive, with the fountain
	disc(town, "Plaza", Layout.CENTER + Vector3.new(0, 0.1, 0), Layout.SQUARE_RADIUS, 0.3, PAVING, Enum.Material.Pavement)
	disc(town, "Fountain", Layout.CENTER + Vector3.new(0, 0.8, 0), 7, 1.6, rgb(240, 240, 250), Enum.Material.Marble)
	local water = disc(town, "Water", Layout.CENTER + Vector3.new(0, 1.2, 0), 6.2, 1.2, rgb(90, 180, 240), Enum.Material.Glass)
	water.Transparency = 0.2
	disc(town, "Fountain", Layout.CENTER + Vector3.new(0, 3, 0), 1.6, 4, rgb(240, 240, 250), Enum.Material.Marble)
	local sign = part(town, { Name = "Sign", Size = Vector3.one, Position = Layout.CENTER + Vector3.new(0, 18, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	label(sign, "🥚 Cubeling Nest", 22, 4, Vector3.zero)
	for index = 1, #SHOPS do
		buildShop(town, index)
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.Position = Layout.CENTER + Vector3.new(0, 0.2, 16)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = town
	town.Parent = world
end

-- A part's box along the world's axes (half sizes)
local function extents(p: BasePart): Vector3
	local r, u, l, h = p.CFrame.RightVector, p.CFrame.UpVector, p.CFrame.LookVector, p.Size / 2
	return Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	)
end

-- Draws a shop with its art building from the town model (parts Building<Name>__<role>): in the booth's
-- place and size, its front (where the logo is) toward the fountain, colored from Config/TownLooks.
local function dressShop(root: Instance, shop: Shop): boolean
	local pattern = "^Building" .. shop.art .. "__(.+)$"
	local pieces: { { part: BasePart, role: string } } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local function roleOf(name: string): string?
				return string.match((string.gsub(name, "%.%d+$", "")), pattern)
			end
			local role = roleOf(d.Name) or (if d.Parent then roleOf(d.Parent.Name) else nil)
			if role then
				table.insert(pieces, { part = d, role = role })
			end
		end
	end
	if #pieces == 0 then
		return false
	end
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	local logo, logos = Vector3.zero, 0
	for _, piece in pieces do
		local e = extents(piece.part)
		lo = lo:Min(piece.part.Position - e)
		hi = hi:Max(piece.part.Position + e)
		if string.sub(piece.role, 1, 5) == "logo_" then
			logo += piece.part.Position
			logos += 1
		end
	end
	local middle = (lo + hi) / 2
	local base = Vector3.new(middle.X, lo.Y, middle.Z)
	local front = if logos > 0 then (logo / logos - middle) * Vector3.new(1, 0, 1) else Vector3.new(0, 0, -1)
	if front.Magnitude < 1e-3 then
		front = Vector3.new(0, 0, -1)
	end
	local turn = Layout.facing(Vector3.zero, front.Unit):Inverse() -- the import's front to -Z
	local scale = ART_WIDTH / math.max(hi.X - lo.X, hi.Z - lo.Z)
	local looks = (TownLooks :: any)[shop.art] or {}
	local art = Instance.new("Model")
	art.Name = "Art"
	for _, piece in pieces do
		local p = piece.part:Clone()
		for _, child in p:GetChildren() do
			if not child:IsA("DataModelMesh") then
				child:Destroy()
			end
		end
		local color = looks[piece.role]
		if color then
			p.Color = color
			if p:IsA("MeshPart") then
				p.TextureID = ""
			end
		end
		p.Material = Enum.Material.SmoothPlastic
		p.Size = piece.part.Size * scale
		p.CFrame = shop.frame * CFrame.new(turn:VectorToWorldSpace(piece.part.Position - base) * scale) * turn * piece.part.CFrame.Rotation
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Parent = art
	end
	for _, d in shop.model:GetChildren() do
		if d:IsA("BasePart") and d ~= shop.booth then
			d:Destroy()
		end
	end
	shop.booth.Transparency = 1
	art.Parent = shop.model
	return true
end

---------------------------------------------------------------------------------------------------------------
-- The islands

local LASER = rgb(255, 70, 90)

local function buildGarden(world: Instance, index: number)
	local frame = Layout.garden(index)
	local model = Instance.new("Model")
	model.Name = "Island_" .. index
	model:SetAttribute("Island", index)
	local size = Layout.GARDEN_SIZE
	local half = size / 2
	part(model, { Name = "Ground", Size = Vector3.new(size, 0.4, size), CFrame = frame * CFrame.new(0, 0.2, 0), Color = GRASS, Material = Enum.Material.Grass })
	-- The fence: the back and both sides, and the front either side of the gate
	local h = Layout.FENCE_HEIGHT
	local function fence(at: CFrame, length: number)
		part(model, { Name = "Fence", Size = Vector3.new(length, h, 1.2), CFrame = at * CFrame.new(0, h / 2, 0), Color = rgb(250, 240, 222) })
		part(model, { Name = "FenceCap", Size = Vector3.new(length + 0.4, 0.8, 1.8), CFrame = at * CFrame.new(0, h + 0.4, 0), Color = rgb(255, 205, 90), CanCollide = false })
	end
	fence(frame * CFrame.new(0, 0, half), size)
	for _, side in { -1, 1 } do
		fence(frame * CFrame.new(side * half, 0, 0) * CFrame.Angles(0, math.rad(90), 0), size)
		local piece = (size - Layout.GATE_WIDTH) / 2
		fence(frame * CFrame.new(side * (Layout.GATE_WIDTH / 2 + piece / 2), 0, -half), piece)
	end
	-- The laser gate: shut for everyone but the owner, open for all at Raid Time (RaidService, GardenClient)
	local gate = part(model, {
		Name = "Gate",
		Size = Vector3.new(Layout.GATE_WIDTH, h, 0.6),
		CFrame = Layout.gate(index) * CFrame.new(0, h / 2, 0),
		Color = LASER,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
	})
	gate:SetAttribute("Island", index)
	gate:AddTag("Gate")
	-- The owner's sign over the gate
	local board = part(model, { Name = "OwnerSign", Size = Vector3.one, CFrame = Layout.gate(index) * CFrame.new(0, h + 5, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	label(board, "Free garden", 16, 3, Vector3.zero)
	-- The incubators
	for slot = 1, IslandConfig.INCUBATORS + #IslandConfig.INCUBATOR_PRICES do
		local at = Layout.incubator(index, slot)
		local pad = part(model, {
			Name = "Incubator",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 5.5, 5.5),
			CFrame = CFrame.new(at + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = if slot == RaidConfig.SAFE_SLOT then rgb(255, 225, 140) else rgb(250, 244, 232),
		})
		pad:SetAttribute("Island", index)
		pad:SetAttribute("Slot", slot)
		pad:AddTag("Incubator")
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Use"
		prompt.ObjectText = if slot == RaidConfig.SAFE_SLOT then "Safe incubator" else "Incubator"
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false -- GardenClient turns on the owner's (and a thief's, at Raid Time)
		prompt:SetAttribute("Island", index)
		prompt:SetAttribute("Slot", slot)
		prompt.Parent = pad
	end
	local creatures = Instance.new("Model")
	creatures.Name = "Creatures"
	creatures.Parent = model
	model.Parent = world
end

-- The ground under the square, the street, the shops and the gardens, the street's paving, and invisible walls round it all
local function buildStreet(world: Instance)
	local start, length = Layout.street()
	local width = Layout.STREET_WIDTH + 2 * math.max(Layout.GARDEN_SIZE, Layout.SHOP_DEPTH) + 24
	local south = Layout.CENTER.Z + Layout.SQUARE_RADIUS + 6
	local north = start.Z - length - 4
	local middle = (south + north) / 2
	part(world, {
		Name = "Ground",
		Size = Vector3.new(width, 4, south - north),
		Position = Vector3.new(start.X, -2.1, middle),
		Color = rgb(150, 205, 120),
		Material = Enum.Material.Grass,
	})
	part(world, {
		Name = "Street",
		Size = Vector3.new(Layout.STREET_WIDTH, 0.3, length),
		Position = start + Vector3.new(0, 0.15, -length / 2),
		Color = PAVING,
		Material = Enum.Material.Pavement,
	})
	for _, z in { south, north } do
		part(world, { Name = "Border", Size = Vector3.new(width, 14, 1), Position = Vector3.new(start.X, 7, z), Transparency = 1 })
	end
	for _, side in { -1, 1 } do
		part(world, { Name = "Border", Size = Vector3.new(1, 14, south - north), Position = Vector3.new(start.X + side * width / 2, 7, middle), Transparency = 1 })
	end
end

function WorldService.island(index: number): Instance?
	local world = workspace:FindFirstChild("World")
	return world and world:FindFirstChild("Island_" .. index)
end

function WorldService.build(): Folder
	local existing = workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	table.clear(shops)
	local world = Instance.new("Folder")
	world.Name = "World"
	buildTown(world)
	buildStreet(world)
	for index = 1, IslandConfig.ISLANDS do
		buildGarden(world, index)
	end
	world.Parent = workspace
	return world
end

-- Once the town model is in ReplicatedStorage (ArtService), the shops get their art buildings
function WorldService.dressTown(root: Instance)
	local dressed = 0
	for _, shop in shops do
		if not shop.model:FindFirstChild("Art") and dressShop(root, shop) then
			dressed += 1
		end
	end
	print(("[World] %d shops drawn with the town model"):format(dressed))
end

return WorldService
