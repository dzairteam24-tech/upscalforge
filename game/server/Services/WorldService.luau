--!strict
-- Builds the world (Logic/Layout, docs/images/map-plan.png): the round square where players arrive, the shops on
-- an arc north of it, the big gate into the Wild beyond them, and the players' gardens on an arc south of it, each
-- fenced, with its laser gate toward the square, incubators and owner's sign; the roads between them. Everything is simple parts, so it works
-- before the 3D art loads; once the town model (Config/Art TOWN_ASSET_ID) is in, each shop is drawn with its
-- building from art/models/Town.glb.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared.Config.Island)
local WildConfig = require(Shared.Config.Wild)
local TownLooks = require(Shared.Config.TownLooks)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Layout = require(Shared.Logic.Layout)
local Wild = require(Shared.Logic.Wild)

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

-- The shops, in the order of their spots on the arc north of the square (Layout.shop), and the art building
-- each is drawn with
local SHOPS = {
	{ name = "Egg Shop", art = "Shop", ui = "Shop", color = rgb(110, 200, 140) },
	{ name = "Food Shop", art = "Potion", ui = "Food", color = rgb(160, 110, 230) },
	{ name = "Gear Shop", art = "Arcade", ui = "Gear", color = rgb(240, 110, 170) },
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
	-- The square where players arrive (no fountain: room for the Mother Cube and the Heist Egg)
	disc(town, "Plaza", Layout.CENTER + Vector3.new(0, 0.1, 0), Layout.SQUARE_RADIUS, 0.3, PAVING, Enum.Material.Pavement)
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
-- place and size, its front (where the logo is) toward the square, colored from Config/TownLooks.
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
	local function fence(cf: CFrame, length: number, parent: Instance?)
		local into = parent or model
		for _, y in { 1.2, 2.6 } do
			part(into, { Name = "Rail", Size = Vector3.new(length, 0.35, 0.3), CFrame = cf * CFrame.new(0, y, 0), Color = WOOD, CanCollide = false })
		end
		local posts = math.max(1, math.floor(length / 2.2))
		for i = 0, posts do
			local x = -length / 2 + i * length / posts
			part(into, { Name = "Picket", Size = Vector3.new(0.5, 3.4, 0.4), CFrame = cf * CFrame.new(x, 1.7, 0), Color = rgb(250, 240, 222), CanCollide = false })
		end
		part(into, { Name = "Wall", Size = Vector3.new(length, Layout.FENCE_HEIGHT, 0.6), CFrame = cf * CFrame.new(0, Layout.FENCE_HEIGHT / 2, 0), Transparency = 1 })
	end
	for _, side in { -1, 1 } do
		fence(at(side * half, 0, 0) * CFrame.Angles(0, math.rad(90), 0), size)
		local piece = (size - Layout.GATE_WIDTH) / 2
		fence(at(side * (Layout.GATE_WIDTH / 2 + piece / 2), 0, -half), piece)
	end

	-- The laser gate between two posts: shut for everyone but the owner
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
	-- a glass dome (the first one ringed in gold), and a warm lamp each side of the path
	local hc = at(hatchery.center.X, 0, hatchery.center.Z)
	part(model, { Name = "Deck", Size = hatchery.size + Vector3.new(0, 0.6, 0), CFrame = hc * CFrame.new(0, 0.5, 0), Color = WOOD, Material = Enum.Material.WoodPlanks })
	for _, side in { -1, 1 } do
		local post = hc * CFrame.new(side * 4.4, 0, hatchery.size.Z / 2 - 1)
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
		local first = slot == 1 -- (golden: where the starter egg goes)
		local base = CFrame.new(spot)
		part(model, { Name = "NestStand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, nest, nest), CFrame = base * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(206, 196, 184), Material = Enum.Material.Slate })
		part(model, { Name = "NestRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, nest + 0.6, nest + 0.6), CFrame = base * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = if first then GOLD else WOOD_DARK, CanCollide = false })
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
		prompt.ObjectText = "Nest"
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false -- GardenClient turns on the owner's
		prompt:SetAttribute("Island", index)
		prompt:SetAttribute("Slot", slot)
		prompt.Parent = pad
	end

	-- The pasture: a meadow behind a low hedge (open where the path comes in) round a pond, where the creatures roam
	part(model, { Name = "Pasture", Size = pasture.size + Vector3.new(0, 0.3, 0), CFrame = at(pasture.center.X, 0.45, pasture.center.Z), Color = rgb(108, 186, 92), Material = Enum.Material.Grass, CanCollide = false })
	local pond = Layout.POND
	part(model, { Name = "Pond", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, pond.radius * 2, pond.radius * 2), CFrame = at(pond.center.X, 0.7, pond.center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(100, 180, 235), Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false })
	part(model, { Name = "PondEdge", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, pond.radius * 2 + 1.4, pond.radius * 2 + 1.4), CFrame = at(pond.center.X, 0.66, pond.center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(206, 196, 184), Material = Enum.Material.Slate, CanCollide = false })
	local function hedge(cf: CFrame, length: number, parent: Instance?)
		part(parent or model, { Name = "Hedge", Size = Vector3.new(length, 1.6, 1.2), CFrame = cf * CFrame.new(0, 0.8, 0), Color = rgb(80, 150, 70), Material = Enum.Material.Grass, CanCollide = false })
	end
	local px, pz = pasture.center.X, pasture.center.Z
	local hx, hz = pasture.size.X / 2, pasture.size.Z / 2
	-- The garden grows backward (away from the square) with the pasture's level (IslandConfig.PASTURE_GROWTH):
	-- each level's stretch of ground and fence, and the back fence and hedge where that level ends.
	-- IslandService shows the owner's (parts marked Grow = level; Only = shown at that level alone).
	local function stage(name: string, level: number, only: boolean): Model
		local m = Instance.new("Model")
		m.Name = name
		m:SetAttribute("Grow", level)
		m:SetAttribute("Only", only)
		m.Parent = model
		return m
	end
	for level, extra in IslandConfig.PASTURE_GROWTH do
		local back = stage("Back" .. level, level, true)
		fence(at(0, 0, half + extra), size, back)
		hedge(at(px, 0, pz + hz + extra), pasture.size.X, back)
		local before = IslandConfig.PASTURE_GROWTH[level - 1]
		if before then
			local grow = stage("Grow" .. level, level, false)
			local length, middle = extra - before, half + (before + extra) / 2
			part(grow, { Name = "Ground", Size = Vector3.new(size, 0.4, length), CFrame = at(0, 0.2, middle), Color = GRASS, Material = Enum.Material.Grass })
			part(grow, { Name = "Pasture", Size = Vector3.new(pasture.size.X, 0.3, length + 0.1), CFrame = at(px, 0.45, middle), Color = rgb(108, 186, 92), Material = Enum.Material.Grass, CanCollide = false })
			for _, side in { -1, 1 } do
				fence(at(side * half, 0, middle) * CFrame.Angles(0, math.rad(90), 0), length, grow)
				hedge(at(px + side * hx, 0, middle) * CFrame.Angles(0, math.rad(90), 0), length, grow)
			end
		end
		-- (how each part looks when shown)
		local stages: { Instance } = { back }
		local grown = model:FindFirstChild("Grow" .. level)
		if grown then
			table.insert(stages, grown)
		end
		for _, m in stages do
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d:SetAttribute("Look", d.Transparency)
					d:SetAttribute("Solid", d.CanCollide)
				end
			end
		end
	end
	for _, s in { -1, 1 } do
		hedge(at(px + s * hx, 0, pz) * CFrame.Angles(0, math.rad(90), 0), pasture.size.Z)
		-- (the front, toward the hatchery, open where the path comes in)
		local piece = hx - Layout.PATH_WIDTH / 2 - 1
		hedge(at(px + s * (hx - piece / 2), 0, pz - hz), piece)
	end
	-- The trough, where the owner feeds the creatures
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
	feed.Enabled = false -- GardenClient turns on the owner's
	feed:SetAttribute("Trough", index)
	feed.Parent = hay

	-- The treadmill, outside in front of the garden: running on it trains the owner's speed (WildService)
	local mill = at(Layout.TREADMILL.X, 0, Layout.TREADMILL.Z)
	part(model, { Name = "TreadmillBase", Size = Vector3.new(11, 0.8, 5.4), CFrame = mill * CFrame.new(0, 0.8, 0), Color = rgb(70, 74, 86) })
	local belt = part(model, { Name = "Treadmill", Size = Vector3.new(10, 0.3, 4), CFrame = mill * CFrame.new(0, 1.35, 0), Color = rgb(40, 42, 50), Material = Enum.Material.Rubber })
	belt:SetAttribute("Island", index)
	for _, s in { -1, 1 } do
		part(model, { Name = "TreadmillRail", Size = Vector3.new(10, 0.3, 0.3), CFrame = mill * CFrame.new(0, 3.6, s * 2.5), Color = rgb(200, 205, 215), Material = Enum.Material.Metal, CanCollide = false })
		-- (walls at its ends: the runner stays on it)
		part(model, { Name = "TreadmillEnd", Size = Vector3.new(0.4, 6, 5.4), CFrame = mill * CFrame.new(s * 5.2, 4, 0), Transparency = 1 })
	end
	local console = part(model, { Name = "TreadmillConsole", Size = Vector3.new(1, 3.6, 3), CFrame = mill * CFrame.new(-6.2, 2.4, 0), Color = rgb(200, 205, 215), Material = Enum.Material.Metal })
	local consoleText = label(console, "🏃 Treadmill", 16, 2.2, Vector3.new(0, 4.2, 0))
	consoleText.Name = "TreadmillText"
	local upgrade = Instance.new("ProximityPrompt")
	upgrade.ActionText = "Upgrade"
	upgrade.ObjectText = "Treadmill"
	upgrade.MaxActivationDistance = 10
	upgrade.RequiresLineOfSight = false
	upgrade.Enabled = false -- (GardenClient: the owner's only)
	upgrade:SetAttribute("Treadmill", index)
	upgrade.Parent = console
	console:AddTag("TreadmillConsole")
	console:SetAttribute("Island", index)

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

-- A straight stretch of paving from `a` to `b`
local function road(parent: Instance, a: Vector3, b: Vector3, width: number)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	part(parent, {
		Name = "Road",
		Size = Vector3.new(width, 0.3, flat.Magnitude),
		CFrame = Layout.facing((a + b) / 2, (a + b) / 2 + flat) * CFrame.new(0, 0.15, 0),
		Color = PAVING,
		Material = Enum.Material.Pavement,
		CanCollide = false,
	})
end

-- A paved arc round the square, `radius` from it, between two angles (degrees from north), in short pieces
local function arc(parent: Instance, radius: number, from: number, to: number, width: number)
	local pieces = math.max(2, math.ceil(math.abs(to - from) / 6))
	for k = 0, pieces - 1 do
		local a1 = from + (to - from) * k / pieces
		local a2 = from + (to - from) * (k + 1) / pieces
		-- (each piece a little longer, so they meet without gaps)
		local mid, half = (a1 + a2) / 2, (a2 - a1) / 2 * 1.15
		road(parent, Layout.around(radius, mid - half), Layout.around(radius, mid + half), width)
	end
end

-- The ground under it all, the roads (the ring round the square and the shops' paths, the road north to the
-- Wild's gate, the road south and the arc past the gardens' gates), and invisible walls round it (open onto the
-- Wild)
local function buildGrounds(world: Instance)
	local w = Layout.ROAD_WIDTH_TOWN
	local north = -Layout.WILD_GATE_DISTANCE
	local growth = IslandConfig.PASTURE_GROWTH
	local south = Layout.GARDEN_RADIUS + Layout.GARDEN_SIZE / 2 + growth[#growth] + 30
	local half = Layout.GARDEN_RADIUS + 60
	local middle = (north + south) / 2
	part(world, {
		Name = "Ground",
		Size = Vector3.new(half * 2, 4, south - north),
		Position = Vector3.new(Layout.CENTER.X, -2.1, middle),
		Color = rgb(150, 205, 120),
		Material = Enum.Material.Grass,
	})
	local roads = Instance.new("Model")
	roads.Name = "Roads"
	arc(roads, Layout.RING_RADIUS, 0, 360, w * 0.8)
	for _, angle in Layout.SHOP_ANGLES do
		road(roads, Layout.around(Layout.RING_RADIUS, angle), Layout.around(Layout.SHOP_RADIUS - Layout.SHOP_DEPTH / 2 + 4, angle), w * 0.7)
	end
	road(roads, Layout.around(Layout.SQUARE_RADIUS - 2, 0), Layout.wildGate(), w)
	road(roads, Layout.around(Layout.SQUARE_RADIUS - 2, 180), Layout.around(Layout.GARDEN_ROAD_RADIUS, 180), w)
	local last = Layout.gardenAngle(IslandConfig.ISLANDS) + Layout.GARDEN_STEP * 0.7
	arc(roads, Layout.GARDEN_ROAD_RADIUS, 180 - last, 180 + last, w)
	for index = 1, IslandConfig.ISLANDS do
		local angle = 180 - Layout.gardenAngle(index)
		road(roads, Layout.around(Layout.GARDEN_ROAD_RADIUS, angle), Layout.gate(index).Position, Layout.GATE_WIDTH)
	end
	roads.Parent = world
	-- Walls (the north one open in the middle onto the Wild)
	part(world, { Name = "Border", Size = Vector3.new(half * 2, 14, 1), Position = Vector3.new(Layout.CENTER.X, 7, south), Transparency = 1 })
	local piece = (half * 2 - Layout.WILD_WIDTH) / 2
	for _, side in { -1, 1 } do
		part(world, { Name = "Border", Size = Vector3.new(piece, 14, 1), Position = Vector3.new(Layout.CENTER.X + side * (Layout.WILD_WIDTH / 2 + piece / 2), 7, north), Transparency = 1 })
		part(world, { Name = "Border", Size = Vector3.new(1, 14, south - north), Position = Vector3.new(Layout.CENTER.X + side * half, 7, middle), Transparency = 1 })
	end
end

-- The Wild (Config/Wild, Layout.wildGate): a big arch north of the square, then the road on through the biomes,
-- each with its ground, its sign (and the speed needed to outrun its guardians) and its nests, each holding an
-- egg (WildService takes it and puts it back)
local function buildWild(world: Instance)
	local wild = Instance.new("Model")
	wild.Name = "Wild"
	local gate = Layout.wildGate()
	local count = #WildConfig.BIOMES
	local length = count * Layout.BIOME_LENGTH
	local middle = gate + Vector3.new(0, 0, -length / 2)
	part(wild, { Name = "WildGround", Size = Vector3.new(Layout.WILD_WIDTH, 4, length + 8), Position = middle + Vector3.new(0, -2.1, -4), Color = rgb(150, 205, 120), Material = Enum.Material.Grass })
	part(wild, { Name = "WildRoad", Size = Vector3.new(Layout.ROAD_WIDTH, 0.34, length), Position = middle + Vector3.new(0, 0.17, 0), Color = PAVING, Material = Enum.Material.Pavement })
	-- The arch
	for _, side in { -1, 1 } do
		part(wild, { Name = "GateTower", Size = Vector3.new(10, 36, 10), Position = gate + Vector3.new(side * 24, 18, 0), Color = rgb(120, 116, 110), Material = Enum.Material.Slate })
		part(wild, { Name = "GateTowerTop", Size = Vector3.new(12, 3, 12), Position = gate + Vector3.new(side * 24, 37.5, 0), Color = rgb(90, 160, 90) })
	end
	local arch = part(wild, { Name = "Arch", Size = Vector3.new(58, 7, 8), Position = gate + Vector3.new(0, 31, 0), Color = rgb(90, 160, 90) })
	label(arch, "🌿 THE WILD", 40, 7, Vector3.new(0, 9, 0))
	local glow = part(wild, { Name = "GateGlow", Size = Vector3.new(38, 27.5, 0.4), Position = gate + Vector3.new(0, 13.9, 0), Color = rgb(120, 255, 160), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false })
	glow.Transparency = 0.75
	for i, biome in WildConfig.BIOMES do
		local center = Layout.biome(i)
		part(wild, { Name = "BiomeGround", Size = Vector3.new(Layout.WILD_WIDTH, 0.3, Layout.BIOME_LENGTH), Position = center + Vector3.new(0, 0.15, 0), Color = biome.color, Material = Enum.Material.Grass })
		local sign = part(wild, { Name = "BiomeSign", Size = Vector3.new(0.8, 6, 0.8), Position = center + Vector3.new(Layout.ROAD_WIDTH / 2 + 2, 3, Layout.BIOME_LENGTH / 2 - 2), Color = WOOD_DARK })
		label(sign, ("%s · ⚡ %s to escape"):format(biome.name, Format.abbrev(Wild.needs(biome))), 18, 2.6, Vector3.new(0, 5, 0))
		local egg = Hatch.egg(biome.tier)
		for k = 1, WildConfig.NESTS do
			local spot = Layout.wildNest(i, k)
			part(wild, { Name = "WildNestBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 7, 7), CFrame = CFrame.new(spot + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = STRAW, Material = Enum.Material.Fabric })
			part(wild, { Name = "WildNestRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 7.6, 7.6), CFrame = CFrame.new(spot + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = WOOD_DARK, Transparency = 0.2, CanCollide = false })
			local eggPart = part(wild, { Name = "WildEgg", Shape = Enum.PartType.Ball, Size = Vector3.one * 3.2, Position = spot + Vector3.new(0, 2.8, 0), Color = if egg then egg.color else GOLD, CanCollide = false })
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1, 1.3, 1)
			mesh.Parent = eggPart
			eggPart:SetAttribute("Biome", i)
			eggPart:SetAttribute("Nest", k)
			eggPart:AddTag("WildEgg")
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Steal"
			prompt.ObjectText = if egg then egg.name else "Egg"
			prompt.HoldDuration = 0.5
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.Parent = eggPart
		end
	end
	-- Invisible walls round it (open toward the square)
	for _, side in { -1, 1 } do
		part(wild, { Name = "Border", Size = Vector3.new(1, 14, length + 8), Position = middle + Vector3.new(side * Layout.WILD_WIDTH / 2, 7, -4), Transparency = 1 })
	end
	part(wild, { Name = "Border", Size = Vector3.new(Layout.WILD_WIDTH, 14, 1), Position = gate + Vector3.new(0, 7, -length - 8), Transparency = 1 })
	local guardians = Instance.new("Folder")
	guardians.Name = "Guardians"
	guardians.Parent = wild
	wild.Parent = world
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
	buildGrounds(world)
	for index = 1, IslandConfig.ISLANDS do
		buildGarden(world, index)
	end
	buildWild(world)
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
