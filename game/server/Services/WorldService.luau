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
	{ name = "Food Shop", art = "Potion", ui = "Food", color = rgb(160, 110, 230) },
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

local WOOD = rgb(176, 124, 78)
local WOOD_DARK = rgb(140, 96, 58)
local STRAW = rgb(236, 202, 120)
local GOLD = rgb(255, 196, 64)

local function buildGarden(world: Instance, index: number)
	local frame = Layout.garden(index)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local model = Instance.new("Model")
	model.Name = "Island_" .. index
	model:SetAttribute("Island", index)
	local size = Layout.GARDEN_SIZE
	local half = size / 2
	part(model, { Name = "Ground", Size = Vector3.new(size, 0.4, size), CFrame = at(0, 0.2, 0), Color = GRASS, Material = Enum.Material.Grass })

	-- A low picket fence all round (open at the gate), with an invisible wall behind it nobody can jump
	local function fence(cf: CFrame, length: number)
		for _, y in { 1.2, 2.6 } do
			part(model, { Name = "Rail", Size = Vector3.new(length, 0.35, 0.3), CFrame = cf * CFrame.new(0, y, 0), Color = WOOD, CanCollide = false })
		end
		local posts = math.max(1, math.floor(length / 2.2))
		for i = 0, posts do
			local x = -length / 2 + i * length / posts
			part(model, { Name = "Picket", Size = Vector3.new(0.5, 3.4, 0.4), CFrame = cf * CFrame.new(x, 1.7, 0), Color = rgb(250, 240, 222), CanCollide = false })
		end
		part(model, { Name = "Wall", Size = Vector3.new(length, Layout.FENCE_HEIGHT, 0.6), CFrame = cf * CFrame.new(0, Layout.FENCE_HEIGHT / 2, 0), Transparency = 1 })
	end
	fence(at(0, 0, half), size)
	for _, side in { -1, 1 } do
		fence(at(side * half, 0, 0) * CFrame.Angles(0, math.rad(90), 0), size)
		local piece = (size - Layout.GATE_WIDTH) / 2
		fence(at(side * (Layout.GATE_WIDTH / 2 + piece / 2), 0, -half), piece)
	end

	-- The laser gate between two posts: shut for everyone but the owner, open for all at Raid Time
	for _, side in { -1, 1 } do
		part(model, { Name = "GatePost", Size = Vector3.new(1.4, 7, 1.4), CFrame = at(side * (Layout.GATE_WIDTH / 2 + 0.2), 3.5, -half), Color = WOOD_DARK })
		part(model, { Name = "GateLight", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = at(side * (Layout.GATE_WIDTH / 2 + 0.2), 7.4, -half), Color = LASER, Material = Enum.Material.Neon, CanCollide = false })
	end
	local gate = part(model, {
		Name = "Gate",
		Size = Vector3.new(Layout.GATE_WIDTH, Layout.FENCE_HEIGHT, 0.4),
		CFrame = Layout.gate(index) * CFrame.new(0, Layout.FENCE_HEIGHT / 2, 0),
		Color = LASER,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
	})
	gate:SetAttribute("Island", index)
	gate:AddTag("Gate")

	-- The path from the gate over the hatchery into the pasture
	local hatchery, pasture = Layout.HATCHERY, Layout.PASTURE
	local pathEnd = pasture.center.Z - pasture.size.Z / 2 + 2
	local pathLength = pathEnd + half
	part(model, { Name = "Path", Size = Vector3.new(Layout.PATH_WIDTH, 0.3, pathLength), CFrame = at(0, 0.85, -half + pathLength / 2), Color = PAVING, Material = Enum.Material.Pavement, CanCollide = false })

	-- The hatchery: a wooden deck across the front, the nests either side of the path, each on a stone stand under
	-- a glass dome (the safe one ringed in gold), and a warm lamp on each side
	local hc = at(hatchery.center.X, 0, hatchery.center.Z)
	part(model, { Name = "Deck", Size = hatchery.size + Vector3.new(0, 0.6, 0), CFrame = hc * CFrame.new(0, 0.5, 0), Color = WOOD, Material = Enum.Material.WoodPlanks })
	for _, side in { -1, 1 } do
		local post = hc * CFrame.new(side * 14.25, 0, 0)
		part(model, { Name = "LampPost", Size = Vector3.new(0.8, 6, 0.8), CFrame = post * CFrame.new(0, 3.8, 0), Color = WOOD_DARK })
		local lamp = part(model, { Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = post * CFrame.new(0, 7.2, 0), Color = rgb(255, 170, 80), Material = Enum.Material.Neon, CanCollide = false })
		local warmth = Instance.new("PointLight")
		warmth.Color = rgb(255, 180, 100)
		warmth.Range = 14
		warmth.Brightness = 1.2
		warmth.Parent = lamp
	end
	local hatchSign = part(model, { Name = "HatcherySign", Size = Vector3.one, CFrame = hc * CFrame.new(0, 7, hatchery.size.Z / 2), Transparency = 1, CanCollide = false, CanQuery = false })
	label(hatchSign, "🥚 Hatchery", 10, 2, Vector3.zero)
	local nest = Layout.NEST_SIZE
	for slot = 1, IslandConfig.INCUBATORS + #IslandConfig.INCUBATOR_PRICES do
		local spot = Layout.incubator(index, slot)
		local safe = slot == RaidConfig.SAFE_SLOT
		local base = CFrame.new(spot)
		part(model, { Name = "NestStand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, nest, nest), CFrame = base * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(206, 196, 184), Material = Enum.Material.Slate })
		part(model, { Name = "NestRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, nest + 0.6, nest + 0.6), CFrame = base * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = if safe then GOLD else WOOD_DARK, CanCollide = false })
		local pad = part(model, {
			Name = "Incubator",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, nest - 1, nest - 1),
			CFrame = base * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = STRAW,
			Material = Enum.Material.Fabric,
		})
		pad:SetAttribute("Island", index)
		pad:SetAttribute("Slot", slot)
		pad:AddTag("Incubator")
		local dome = part(model, { Name = "Dome", Shape = Enum.PartType.Ball, Size = Vector3.one * (nest - 1), CFrame = base * CFrame.new(0, 3.6, 0), Color = rgb(220, 240, 255), Material = Enum.Material.Glass, Transparency = 0.7, CanCollide = false, CanQuery = false })
		dome:SetAttribute("Slot", slot)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Use"
		prompt.ObjectText = if safe then "Safe nest" else "Nest"
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false -- GardenClient turns on the owner's (and a thief's, at Raid Time)
		prompt:SetAttribute("Island", index)
		prompt:SetAttribute("Slot", slot)
		prompt.Parent = pad
	end

	-- The pasture: a meadow behind a low hedge (open where the path comes in) round a pond, where the creatures roam
	part(model, { Name = "Pasture", Size = pasture.size + Vector3.new(0, 0.3, 0), CFrame = at(pasture.center.X, 0.45, pasture.center.Z), Color = rgb(108, 186, 92), Material = Enum.Material.Grass, CanCollide = false })
	local pond = Layout.POND
	part(model, { Name = "Pond", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, pond.radius * 2, pond.radius * 2), CFrame = at(pond.center.X, 0.7, pond.center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(100, 180, 235), Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false })
	part(model, { Name = "PondEdge", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, pond.radius * 2 + 1.4, pond.radius * 2 + 1.4), CFrame = at(pond.center.X, 0.66, pond.center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(206, 196, 184), Material = Enum.Material.Slate, CanCollide = false })
	local function hedge(cf: CFrame, length: number)
		part(model, { Name = "Hedge", Size = Vector3.new(length, 1.6, 1.2), CFrame = cf * CFrame.new(0, 0.8, 0), Color = rgb(80, 150, 70), Material = Enum.Material.Grass, CanCollide = false })
	end
	local px, pz = pasture.center.X, pasture.center.Z
	local hx, hz = pasture.size.X / 2, pasture.size.Z / 2
	hedge(at(px, 0, pz + hz), pasture.size.X)
	for _, s in { -1, 1 } do
		hedge(at(px + s * hx, 0, pz) * CFrame.Angles(0, math.rad(90), 0), pasture.size.Z)
		-- (the front, toward the hatchery, open where the path comes in)
		local piece = hx - Layout.PATH_WIDTH / 2 - 1
		hedge(at(px + s * (hx - piece / 2), 0, pz - hz), piece)
	end
	-- The trough, where the owner feeds the creatures (and a thief can steal food at Raid Time)
	local trough = at(Layout.TROUGH.X, 0, Layout.TROUGH.Z)
	part(model, { Name = "TroughBox", Size = Vector3.new(6, 1.6, 2.6), CFrame = trough * CFrame.new(0, 1.4, 0), Color = WOOD, Material = Enum.Material.WoodPlanks })
	for _, s in { -1, 1 } do
		part(model, { Name = "TroughLeg", Size = Vector3.new(0.6, 1, 2.6), CFrame = trough * CFrame.new(s * 2.5, 0.6, 0), Color = WOOD_DARK })
	end
	local hay = part(model, { Name = "Trough", Size = Vector3.new(5.2, 0.4, 1.8), CFrame = trough * CFrame.new(0, 2.25, 0), Color = STRAW, Material = Enum.Material.Fabric, CanCollide = false })
	hay:SetAttribute("Island", index)
	hay:AddTag("Trough")
	local feed = Instance.new("ProximityPrompt")
	feed.ActionText = "Feed"
	feed.ObjectText = "Trough"
	feed.MaxActivationDistance = 8
	feed.RequiresLineOfSight = false
	feed.Enabled = false -- GardenClient turns on the owner's (and a thief's, at Raid Time)
	feed:SetAttribute("Trough", index)
	feed.Parent = hay

	-- The storage barn in the pasture's back corner: where the creatures not in the pasture are kept
	local barn = at(Layout.BARN.X, 0, Layout.BARN.Z) * CFrame.Angles(0, math.rad(45), 0) -- (its door toward the pasture)
	local shed = part(model, { Name = "Barn", Size = Vector3.new(9, 6, 7), CFrame = barn * CFrame.new(0, 3.4, 0), Color = rgb(206, 92, 72) })
	part(model, { Name = "BarnRoof", Size = Vector3.new(10.4, 1.6, 8.4), CFrame = barn * CFrame.new(0, 7.2, 0), Color = rgb(250, 238, 214) })
	part(model, { Name = "BarnDoor", Size = Vector3.new(3.4, 4.4, 0.3), CFrame = barn * CFrame.new(0, 2.6, -3.55), Color = rgb(250, 238, 214) })
	label(shed, "📦 Storage", 10, 2, Vector3.new(0, 6.5, 0))
	local open = Instance.new("ProximityPrompt")
	open.ActionText = "Open"
	open.ObjectText = "Storage"
	open.MaxActivationDistance = 10
	open.RequiresLineOfSight = false
	open:SetAttribute("OpenUI", "Bag")
	open:SetAttribute("Island", index)
	open.Parent = shed

	local pastureSign = part(model, { Name = "PastureSign", Size = Vector3.one, CFrame = at(px, 5, pz - hz + 1), Transparency = 1, CanCollide = false, CanQuery = false })
	label(pastureSign, "🌷 Pasture", 10, 2, Vector3.zero)

	-- The owner's name over the gate
	local board = part(model, { Name = "OwnerSign", Size = Vector3.one, CFrame = Layout.gate(index) * CFrame.new(0, Layout.FENCE_HEIGHT + 2, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	label(board, "Free garden", 16, 3, Vector3.zero)

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
