-- Builds the Hub, the town where players spawn, as a floating island (art: the Hub concept in docs/map-art.md):
-- a round paved plaza with a cat fountain, six buildings around it facing the middle, the fishing pond and
-- the leaderboards in the south, a stone arch toward Spawn Meadow in the north and the way to the Trading
-- Plaza in the east. Shapes stay big and few so it runs well on phones.
--
-- Positions are from the Hub center; -Z is north (Spawn Meadow), +X is east (Trading Plaza).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FishingConfig = require(Shared.Config.Fishing)
local MapLayout = require(Shared.Logic.MapLayout)
local PetModel = require(Shared.PetModel)

local HubBuilder = {}

-- Sized for a full server: wide plaza and paths, buildings far apart
local PLAZA_RADIUS = 80
local BUILDING_RADIUS = 125
local BUILDING_SCALE = 1.3
HubBuilder.SPAWN_OFFSET = Vector3.new(0, 0, 36)
-- Where the World Boss lands: the north path, between Trading and Fusion
HubBuilder.BOSS_OFFSET = Vector3.new(0, 0, -105)
-- Leaderboards: along the south rim, two on each side of the pond (they face north)
HubBuilder.LEADERBOARD_X = { -150, -110, 110, 150 }
HubBuilder.LEADERBOARD_Z = 178

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder to lie flat (axis up)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local GRASS = rgb(118, 190, 92)
local STONE = rgb(226, 208, 172)
local STONE_DARK = rgb(196, 176, 142)
local ROCK = rgb(132, 130, 138)
local WOOD = rgb(150, 104, 64)
local WATER = rgb(70, 170, 235)

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

-- A flat disc lying on the ground, its top at `top`
local function disc(parent: Instance, name: string, center: Vector3, radius: number, top: number, color: Color3, material: Enum.Material?): Part
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, top - 0.2, center.Z) * FLAT,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

-- Text painted on one face of a part
local function paint(target: BasePart, face: Enum.NormalId, text: string, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.35
	label.Text = text
	label.Parent = gui
	gui.Parent = target
end

local function roundTree(parent: Instance, at: Vector3, scale: number, leaf: Color3)
	part(parent, {
		Name = "Decor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5 * scale, 1.6 * scale, 1.6 * scale),
		CFrame = CFrame.new(at + Vector3.new(0, 2.5 * scale, 0)) * FLAT,
		Color = rgb(120, 82, 54),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	part(parent, {
		Name = "Decor",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 7.5 * scale,
		Position = at + Vector3.new(0, 7 * scale, 0),
		Color = leaf,
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
	part(parent, {
		Name = "Decor",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 5 * scale,
		Position = at + Vector3.new(1.6 * scale, 9.5 * scale, 0.8 * scale),
		Color = leaf:Lerp(Color3.new(1, 1, 1), 0.12),
		Material = Enum.Material.Grass,
		CanCollide = false,
	})
end

local function pineTree(parent: Instance, at: Vector3, scale: number)
	part(parent, {
		Name = "Decor",
		Size = Vector3.new(1.4, 3, 1.4) * scale,
		Position = at + Vector3.new(0, 1.5 * scale, 0),
		Color = rgb(120, 82, 54),
		Material = Enum.Material.Wood,
		CanCollide = false,
	})
	for i, width in { 7, 5.2, 3.2 } do
		part(parent, {
			Name = "Decor",
			Size = Vector3.new(width, 3, width) * scale,
			CFrame = CFrame.new(at + Vector3.new(0, (1.5 + i * 2.6) * scale, 0)) * CFrame.Angles(0, math.rad(45 * i), 0),
			Color = rgb(52, 140, 78):Lerp(rgb(80, 170, 90), (i - 1) / 2),
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
end

---------------------------------------------------------------------------------------------------------------
-- The island: grass on top (the zone's Ground), rock cliffs below, a fence on the rim

local function buildIsland(model: Instance, center: Vector3, openings: { Vector3 })
	local half = MapLayout.HUB_SIZE / 2
	-- Cliffs: stacked rock slabs, each smaller than the one above, for a floating island silhouette
	for i, layer in { { size = MapLayout.HUB_SIZE + 2, height = 16 }, { size = MapLayout.HUB_SIZE * 0.85, height = 18 }, { size = MapLayout.HUB_SIZE * 0.62, height = 18 }, { size = MapLayout.HUB_SIZE * 0.36, height = 16 } } do
		local top = -4 - (i - 1) * 13
		part(model, {
			Name = "Cliff",
			Size = Vector3.new(layer.size, layer.height, layer.size),
			CFrame = CFrame.new(center + Vector3.new(0, top - layer.height / 2, 0)) * CFrame.Angles(0, math.rad(i * 7), 0),
			Color = ROCK:Lerp(rgb(96, 94, 104), (i - 1) / 3),
			Material = Enum.Material.Rock,
			CanCollide = i == 1,
		})
	end
	-- Fence along the rim, open where a path leaves the island. An invisible wall ("Border") keeps players on.
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local isX = side.X ~= 0
		local open = false
		for _, o in openings do
			if o == side then
				open = true
			end
		end
		local gap = MapLayout.BRIDGE_WIDTH
		local segments = if open
			then { { offset = -(MapLayout.HUB_SIZE + gap) / 4, length = (MapLayout.HUB_SIZE - gap) / 2 }, { offset = (MapLayout.HUB_SIZE + gap) / 4, length = (MapLayout.HUB_SIZE - gap) / 2 } }
			else { { offset = 0, length = MapLayout.HUB_SIZE } }
		for _, segment in segments do
			local along = if isX then Vector3.new(0, 0, segment.offset) else Vector3.new(segment.offset, 0, 0)
			local line = center + side * (half - 1.5) + along
			local size = if isX then Vector3.new(0.6, 0.6, segment.length) else Vector3.new(segment.length, 0.6, 0.6)
			for _, y in { 1.4, 2.6 } do
				part(model, { Name = "Fence", Size = size, Position = line + Vector3.new(0, y, 0), Color = WOOD, Material = Enum.Material.Wood })
			end
			local posts = math.floor(segment.length / 8)
			for i = 0, posts do
				local t = (i / posts - 0.5) * (segment.length - 1)
				local offset = if isX then Vector3.new(0, 0, t) else Vector3.new(t, 0, 0)
				part(model, { Name = "Fence", Size = Vector3.new(1, 3.4, 1), Position = line + offset + Vector3.new(0, 1.7, 0), Color = WOOD:Lerp(Color3.new(0, 0, 0), 0.15), Material = Enum.Material.Wood })
			end
			part(model, {
				Name = "Border",
				Size = if isX then Vector3.new(1, 10, segment.length) else Vector3.new(segment.length, 10, 1),
				Position = center + side * (half + 0.5) + along + Vector3.new(0, 5, 0),
				Transparency = 1,
			})
		end
	end
end

-- A few small floating islets around the Hub, away from the bridges
local function buildIslets(model: Instance, center: Vector3)
	local islets = {
		{ offset = Vector3.new(-270, 22, -170), size = 26 },
		{ offset = Vector3.new(-296, -6, 46), size = 22 },
		{ offset = Vector3.new(-234, 30, 250), size = 24 },
		{ offset = Vector3.new(50, -4, 286), size = 28 },
		{ offset = Vector3.new(266, 26, 234), size = 22 },
		{ offset = Vector3.new(254, -10, -206), size = 24 },
	}
	for i, islet in islets do
		local top = center + islet.offset
		part(model, { Name = "Islet", Size = Vector3.new(islet.size, 2, islet.size), Position = top - Vector3.new(0, 1, 0), Color = GRASS, Material = Enum.Material.Grass, CanCollide = false })
		part(model, {
			Name = "Islet",
			Size = Vector3.new(islet.size * 0.8, islet.size * 0.6, islet.size * 0.8),
			CFrame = CFrame.new(top - Vector3.new(0, 2 + islet.size * 0.3, 0)) * CFrame.Angles(0, math.rad(i * 23), 0),
			Color = ROCK,
			Material = Enum.Material.Rock,
			CanCollide = false,
		})
		if i % 2 == 1 then
			roundTree(model, top, islet.size / 16, rgb(84, 168, 80))
		else
			pineTree(model, top, islet.size / 14)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- The plaza: paving rings, eight planters and the fountain

local function buildPlaza(model: Instance, center: Vector3)
	disc(model, "Plaza", center, PLAZA_RADIUS, 0.05, STONE, Enum.Material.Pavement)
	disc(model, "Plaza", center, PLAZA_RADIUS - 4, 0.07, STONE_DARK, Enum.Material.Pavement)
	disc(model, "Plaza", center, PLAZA_RADIUS - 5, 0.09, STONE, Enum.Material.Pavement)
	disc(model, "Plaza", center, 26, 0.11, STONE_DARK, Enum.Material.Pavement)

	-- Planters between the eight paths, each with two round bushes
	for i = 0, 7 do
		local angle = math.rad(22.5 + i * 45)
		local at = center + Vector3.new(math.sin(angle) * 52, 0, -math.cos(angle) * 52)
		local frame = CFrame.lookAt(at, center) -- local X runs along the ring
		part(model, { Name = "Planter", Size = Vector3.new(18, 1.2, 8), CFrame = frame + Vector3.new(0, 0.6, 0), Color = STONE_DARK, Material = Enum.Material.Slate })
		part(model, { Name = "Planter", Size = Vector3.new(17, 0.4, 7), CFrame = frame + Vector3.new(0, 1.25, 0), Color = GRASS, Material = Enum.Material.Grass })
		for _, x in { -5, 0.4, 5.4 } do
			part(model, {
				Name = "Bush",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * (if x < 0 then 3.4 else 2.8),
				CFrame = frame * CFrame.new(x, 2.6, 0),
				Color = rgb(70, 160, 76),
				Material = Enum.Material.Grass,
				CanCollide = false,
			})
		end
	end

	-- Fountain, in two tiers: a wide basin with a low marble rim and jets around it, a column holding a
	-- smaller bowl whose water spills all around it, and a plinth for the cat statue (buildStatue)
	local MARBLE = rgb(236, 236, 240)
	local SPRAY = rgb(120, 205, 255)
	local function cylinder(name: string, radius: number, bottom: number, height: number, color: Color3, props: { [string]: any }?)
		local c = part(model, {
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, radius * 2, radius * 2),
			CFrame = CFrame.new(center + Vector3.new(0, bottom + height / 2, 0)) * FLAT,
			Color = color,
			Material = Enum.Material.Marble,
		})
		if props then
			for k, v in props do
				(c :: any)[k] = v
			end
		end
		return c
	end
	-- A raised rim around a circle, made of short straight segments so the water inside shows
	local function rim(radius: number, thickness: number, bottom: number, height: number, segments: number)
		local length = 2 * math.pi * radius / segments * 1.08
		for i = 0, segments - 1 do
			local angle = 2 * math.pi * i / segments
			local at = center + Vector3.new(math.sin(angle) * radius, bottom + height / 2, -math.cos(angle) * radius)
			part(model, {
				Name = "Fountain",
				Size = Vector3.new(length, height, thickness),
				CFrame = CFrame.new(at) * CFrame.Angles(0, -angle, 0), -- long side along the circle
				Color = MARBLE,
				Material = Enum.Material.Marble,
			})
		end
	end
	-- Basin: floor, water, rim
	cylinder("Fountain", 20.4, 0, 0.6, MARBLE)
	cylinder("FountainWater", 20.2, 0.6, 1.0, WATER, { Material = Enum.Material.Glass, Transparency = 0.1 })
	rim(20.9, 1.8, 0, 2.4, 28)
	cylinder("Fountain", 3.2, 0, 6.8, MARBLE) -- column
	-- Upper bowl: floor, water, rim
	cylinder("Fountain", 7.6, 6.2, 0.6, MARBLE)
	cylinder("FountainWater", 7.5, 6.8, 0.8, WATER, { Material = Enum.Material.Glass, Transparency = 0.1 })
	rim(7.9, 1.2, 6.2, 1.9, 16)
	-- The water spilling over the bowl's edge, as a thin see-through curtain down to the basin
	cylinder("FountainWater", 8.6, 1.6, 6.3, SPRAY, { Material = Enum.Material.Glass, Transparency = 0.55, CanCollide = false })
	cylinder("Fountain", 3.4, 6.8, 2.4, MARBLE) -- plinth for the statue
	-- Jets around the basin, arching toward the middle
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		local at = center + Vector3.new(math.sin(angle) * 15.5, 0, -math.cos(angle) * 15.5)
		local lean = CFrame.lookAt(at, center) * CFrame.Angles(math.rad(-28), 0, 0)
		part(model, {
			Name = "FountainWater",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(5.5, 0.7, 0.7),
			CFrame = (lean + Vector3.new(0, 1.6, 0)) * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = SPRAY,
			Material = Enum.Material.Glass,
			Transparency = 0.15,
			CanCollide = false,
		})
	end
end

-- The cat statue on the fountain: a Titan Kitty in marble, keeping its face. Rebuilt when the 3D creature
-- models arrive, so it shows the real model instead of the block version.
local function buildStatue(model: Instance, center: Vector3)
	local old = model:FindFirstChild("Statue")
	if old then
		old:Destroy()
	end
	local built = PetModel.build({ s = "Kitty", v = "Normal", z = "Titan" })
	local face = { eye = true, shine = true, mouth = true, nose = true, blush = true, tongue = true, Eye = true, Shine = true, Mouth = true }
	for _, p in built.parts do
		if not face[p.Name] then
			p.Color = rgb(222, 222, 228)
			p.Material = Enum.Material.Marble
		end
	end
	-- Stand it on the plinth, a little bigger than a Titan
	local base = center + Vector3.new(0, 9.2, 0) -- top of the fountain's plinth
	PetModel.place(built, CFrame.new(base + Vector3.new(0, built.height / 2, 0)) * CFrame.Angles(0, math.rad(180), 0))
	local grow = 1.5
	for _, p in built.parts do
		p.Size *= grow
		p.CFrame = CFrame.new(base + (p.CFrame.Position - base) * grow) * p.CFrame.Rotation
	end
	built.model.Name = "Statue"
	built.model.Parent = model
end

---------------------------------------------------------------------------------------------------------------
-- Buildings. Each faces the plaza (its front is local -Z) and has the ProximityPrompt that opens its window.

type Building = { name: string, ui: string, angle: number, wall: Color3, roof: Color3, extra: (Model, CFrame) -> () }

-- Red and white stripes over the door (an awning), across the front
local function awning(model: Model, frame: CFrame, width: number, y: number, a: Color3, b: Color3)
	local stripes = 6
	for i = 1, stripes do
		part(model, {
			Name = "Awning",
			Size = Vector3.new(width / stripes, 0.4, 3.4),
			CFrame = frame * CFrame.new(-width / 2 + (i - 0.5) * width / stripes, y, -7.4) * CFrame.Angles(math.rad(-22), 0, 0),
			Color = if i % 2 == 1 then a else b,
			CanCollide = false,
		})
	end
end

local function neonTrim(model: Model, frame: CFrame, color: Color3, height: number)
	for _, x in { -8.1, 8.1 } do
		part(model, { Name = "Trim", Size = Vector3.new(0.5, height, 0.5), CFrame = frame * CFrame.new(x, height / 2 + 0.8, -6.1), Color = color, Material = Enum.Material.Neon, CanCollide = false })
	end
	part(model, { Name = "Trim", Size = Vector3.new(16.6, 0.5, 0.5), CFrame = frame * CFrame.new(0, height + 0.8, -6.1), Color = color, Material = Enum.Material.Neon, CanCollide = false })
end

local BUILDINGS: { Building } = {
	{
		name = "Shop",
		ui = "Shop",
		angle = -68,
		wall = rgb(214, 86, 72),
		roof = rgb(170, 52, 48),
		extra = function(model, frame)
			awning(model, frame, 15, 7.4, rgb(230, 60, 55), rgb(250, 245, 240))
			-- A big gift on the roof
			part(model, { Name = "Gift", Size = Vector3.new(6, 5, 6), CFrame = frame * CFrame.new(0, 15.5, 0), Color = rgb(240, 70, 70) })
			part(model, { Name = "Gift", Size = Vector3.new(1.2, 5.1, 6.1), CFrame = frame * CFrame.new(0, 15.5, 0), Color = rgb(255, 210, 70), CanCollide = false })
			part(model, { Name = "Gift", Size = Vector3.new(6.1, 5.1, 1.2), CFrame = frame * CFrame.new(0, 15.5, 0), Color = rgb(255, 210, 70), CanCollide = false })
			for _, x in { -1.3, 1.3 } do
				part(model, { Name = "Gift", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2, CFrame = frame * CFrame.new(x, 18.6, 0), Color = rgb(255, 210, 70), CanCollide = false })
			end
		end,
	},
	{
		name = "Trading",
		ui = "Trade",
		angle = -28,
		wall = rgb(236, 192, 112),
		roof = rgb(178, 118, 64),
		extra = function(model, frame)
			awning(model, frame, 15, 7.4, rgb(70, 130, 220), rgb(250, 245, 240))
			-- A giant gold coin standing on the roof
			local coin = part(model, {
				Name = "Coin",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.2, 7, 7),
				CFrame = frame * CFrame.new(0, 17, 0) * CFrame.Angles(0, math.rad(90), 0),
				Color = rgb(255, 200, 60),
				Material = Enum.Material.Foil,
			})
			paint(coin, Enum.NormalId.Right, "$", rgb(190, 130, 20))
			paint(coin, Enum.NormalId.Left, "$", rgb(190, 130, 20))
		end,
	},
	{
		name = "Fusion",
		ui = "Pets",
		angle = 28,
		wall = rgb(70, 52, 124),
		roof = rgb(46, 34, 86),
		extra = function(model, frame)
			neonTrim(model, frame, rgb(255, 90, 220), 9)
			-- A glass dome with a glowing core, and two pipes
			part(model, { Name = "Dome", Shape = Enum.PartType.Ball, Size = Vector3.one * 9, CFrame = frame * CFrame.new(0, 13.5, 0), Color = rgb(140, 220, 255), Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false })
			part(model, { Name = "Dome", Shape = Enum.PartType.Ball, Size = Vector3.one * 3, CFrame = frame * CFrame.new(0, 13.5, 0), Color = rgb(90, 255, 230), Material = Enum.Material.Neon, CanCollide = false })
			for _, x in { -6.5, 6.5 } do
				part(model, {
					Name = "Pipe",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(7, 1.6, 1.6),
					CFrame = frame * CFrame.new(x, 14, 2) * CFrame.Angles(0, 0, math.rad(90)),
					Color = rgb(150, 90, 220),
					Material = Enum.Material.Metal,
					CanCollide = false,
				})
			end
		end,
	},
	{
		name = "Lucky Spin",
		ui = "Spin",
		angle = 64,
		wall = rgb(236, 84, 120),
		roof = rgb(190, 50, 90),
		extra = function(model, frame)
			-- A giant wheel standing on the roof, facing the plaza: colored spokes on a white disc
			local hub = frame * CFrame.new(0, 19, -1)
			part(model, { Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 13, 13), CFrame = hub * CFrame.Angles(0, math.rad(90), 0), Color = rgb(250, 245, 235), CanCollide = false })
			local colors = { rgb(255, 90, 90), rgb(255, 190, 60), rgb(110, 210, 90), rgb(70, 170, 240), rgb(160, 100, 230), rgb(255, 120, 200) }
			for i, color in colors do
				part(model, {
					Name = "Wheel",
					Size = Vector3.new(2.6, 6, 0.3),
					CFrame = hub * CFrame.Angles(0, 0, math.rad(i * 60)) * CFrame.new(0, 3, -0.5),
					Color = color,
					Material = Enum.Material.Neon,
					CanCollide = false,
				})
			end
			part(model, { Name = "Wheel", Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = hub * CFrame.new(0, 0, -0.8), Color = rgb(255, 210, 70), CanCollide = false })
			part(model, { Name = "Wheel", Size = Vector3.new(1.4, 2, 1), CFrame = hub * CFrame.new(0, 7.2, -0.6), Color = rgb(255, 210, 70), CanCollide = false })
			part(model, { Name = "Wheel", Size = Vector3.new(1.6, 6, 1.6), CFrame = frame * CFrame.new(0, 13.5, 0), Color = rgb(190, 50, 90), CanCollide = false })
		end,
	},
	{
		name = "Trips",
		ui = "Trips",
		angle = -112,
		wall = rgb(196, 140, 84),
		roof = rgb(130, 86, 52),
		extra = function(model, frame)
			-- A hot air balloon tied beside the station
			local at = frame * CFrame.new(-11, 0, 2)
			part(model, { Name = "Balloon", Shape = Enum.PartType.Ball, Size = Vector3.one * 10, CFrame = at * CFrame.new(0, 17, 0), Color = rgb(80, 150, 240), CanCollide = false })
			part(model, { Name = "Balloon", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 10.2, 10.2), CFrame = at * CFrame.new(0, 17, 0) * FLAT, Color = rgb(250, 245, 235), CanCollide = false })
			part(model, { Name = "Balloon", Size = Vector3.new(3.4, 2.6, 3.4), CFrame = at * CFrame.new(0, 9.5, 0), Color = WOOD, Material = Enum.Material.WoodPlanks })
			for _, x in { -1.4, 1.4 } do
				part(model, { Name = "Balloon", Size = Vector3.new(0.2, 4, 0.2), CFrame = at * CFrame.new(x, 12.6, 0), Color = rgb(90, 70, 50), CanCollide = false })
			end
			part(model, { Name = "Balloon", Size = Vector3.new(0.3, 9.5, 0.3), CFrame = at * CFrame.new(0, 4.5, 0), Color = rgb(90, 70, 50), CanCollide = false })
		end,
	},
	{
		name = "Arcade",
		ui = "Stack",
		angle = 120,
		wall = rgb(52, 40, 96),
		roof = rgb(34, 26, 64),
		extra = function(model, frame)
			neonTrim(model, frame, rgb(220, 80, 255), 9)
			-- A big game controller on the roof
			part(model, { Name = "Controller", Size = Vector3.new(8, 3, 3.6), CFrame = frame * CFrame.new(0, 14.5, 0), Color = rgb(110, 190, 255) })
			for _, x in { -4.2, 4.2 } do
				part(model, { Name = "Controller", Shape = Enum.PartType.Ball, Size = Vector3.one * 3.6, CFrame = frame * CFrame.new(x, 14, 0), Color = rgb(110, 190, 255), CanCollide = false })
			end
			for i, color in { rgb(255, 90, 90), rgb(255, 210, 70), rgb(110, 230, 120) } do
				part(model, { Name = "Controller", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, CFrame = frame * CFrame.new(1 + i * 0.9, 15.2, -1.6), Color = color, Material = Enum.Material.Neon, CanCollide = false })
			end
			-- Two arcade cabinets by the door
			for _, x in { -6.2, 6.2 } do
				part(model, { Name = "Cabinet", Size = Vector3.new(2.6, 5, 2.4), CFrame = frame * CFrame.new(x, 2.5, -8), Color = rgb(40, 32, 80) })
				part(model, { Name = "Cabinet", Size = Vector3.new(2, 1.6, 0.2), CFrame = frame * CFrame.new(x, 3.8, -9.25), Color = rgb(90, 220, 255), Material = Enum.Material.Neon, CanCollide = false })
			end
		end,
	},
}

local function buildBuilding(model: Instance, center: Vector3, building: Building)
	local angle = math.rad(building.angle)
	local at = center + Vector3.new(math.sin(angle) * BUILDING_RADIUS, 0, -math.cos(angle) * BUILDING_RADIUS)
	local frame = CFrame.lookAt(at, Vector3.new(center.X, 0, center.Z)) -- -Z (front) faces the plaza
	local house = Instance.new("Model")
	house.Name = building.name

	-- Path from the plaza to the door
	part(house, { Name = "Path", Size = Vector3.new(10, 0.3, 10), CFrame = frame * CFrame.new(0, 0.1, -11), Color = STONE, Material = Enum.Material.Pavement, CanCollide = false })
	part(house, { Name = "Step", Size = Vector3.new(18, 0.8, 14), CFrame = frame * CFrame.new(0, 0.4, 0), Color = STONE_DARK, Material = Enum.Material.Slate })
	local body = part(house, {
		Name = building.name .. "Booth",
		Size = Vector3.new(16, 10, 12),
		CFrame = frame * CFrame.new(0, 5.8, 0),
		Color = building.wall,
		Material = Enum.Material.SmoothPlastic,
	})
	part(house, { Name = "Roof", Size = Vector3.new(18, 2.2, 14), CFrame = frame * CFrame.new(0, 11.9, 0), Color = building.roof })
	part(house, { Name = "Door", Size = Vector3.new(5, 7, 0.4), CFrame = frame * CFrame.new(0, 4.3, -6.1), Color = rgb(255, 236, 170), Material = Enum.Material.Neon, CanCollide = false })
	-- Name board above the door
	local board = part(house, { Name = "Sign", Size = Vector3.new(13, 2.8, 0.6), CFrame = frame * CFrame.new(0, 9.4, -6.4), Color = rgb(110, 70, 44), Material = Enum.Material.Wood, CanCollide = false })
	paint(board, Enum.NormalId.Front, string.upper(building.name))
	building.extra(house, frame)
	-- Everything above is drawn at a base size; grow it around the building's center
	for _, p in house:GetDescendants() do
		if p:IsA("BasePart") then
			local rel = frame:ToObjectSpace(p.CFrame)
			p.Size *= BUILDING_SCALE
			p.CFrame = frame * CFrame.new(rel.Position * BUILDING_SCALE) * (rel - rel.Position)
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = building.name
	prompt.MaxActivationDistance = 20
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenUI", building.ui)
	prompt.Parent = body
	house.Parent = model
end

---------------------------------------------------------------------------------------------------------------
-- Ways out: an arch to Spawn Meadow (north) and to the Trading Plaza (east), and the paths to them

local function arch(model: Instance, at: Vector3, facing: Vector3, text: string, glow: Color3)
	local frame = CFrame.lookAt(at, at + facing) -- -Z looks into the Hub
	for _, x in { -11, 11 } do
		part(model, { Name = "Arch", Size = Vector3.new(4, 18, 4), CFrame = frame * CFrame.new(x, 9, 0), Color = rgb(196, 190, 180), Material = Enum.Material.Cobblestone })
		part(model, { Name = "Arch", Size = Vector3.new(5, 1.4, 5), CFrame = frame * CFrame.new(x, 18.7, 0), Color = rgb(170, 160, 150), Material = Enum.Material.Slate })
		part(model, { Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = frame * CFrame.new(x, 20.2, 0), Color = rgb(255, 220, 140), Material = Enum.Material.Neon, CanCollide = false })
	end
	part(model, { Name = "Arch", Size = Vector3.new(26, 3, 4.4), CFrame = frame * CFrame.new(0, 16.5, 0), Color = rgb(196, 190, 180), Material = Enum.Material.Cobblestone, CanCollide = false })
	local board = part(model, { Name = "Sign", Size = Vector3.new(18, 3.4, 0.6), CFrame = frame * CFrame.new(0, 16.5, -2.5), Color = rgb(110, 70, 44), Material = Enum.Material.Wood, CanCollide = false })
	paint(board, Enum.NormalId.Front, text)
	part(model, { Name = "Portal", Size = Vector3.new(17.6, 14.8, 0.3), CFrame = frame * CFrame.new(0, 7.4, 0), Color = glow, Material = Enum.Material.Neon, Transparency = 0.65, CanCollide = false, CanQuery = false })
end

local function paths(model: Instance, center: Vector3)
	local half = MapLayout.HUB_SIZE / 2
	local length = half - PLAZA_RADIUS + 2
	local mid = PLAZA_RADIUS + length / 2 - 2
	-- North to the arch, east to the Trading Plaza, south to the pond
	part(model, { Name = "Path", Size = Vector3.new(24, 0.3, length), Position = center + Vector3.new(0, 0.1, -mid), Color = STONE, Material = Enum.Material.Pavement, CanCollide = false })
	part(model, { Name = "Path", Size = Vector3.new(length, 0.3, 24), Position = center + Vector3.new(mid, 0.1, 0), Color = STONE, Material = Enum.Material.Pavement, CanCollide = false })
	part(model, { Name = "Path", Size = Vector3.new(14, 0.3, 10), Position = center + Vector3.new(0, 0.1, PLAZA_RADIUS + 3), Color = STONE, Material = Enum.Material.Pavement, CanCollide = false })
	arch(model, center + Vector3.new(0, 0, -half + 3), Vector3.new(0, 0, 1), "1 · SPAWN MEADOW", rgb(110, 220, 255))
	arch(model, center + Vector3.new(half - 3, 0, 0), Vector3.new(-1, 0, 0), "TRADING PLAZA", rgb(255, 210, 110))
end

---------------------------------------------------------------------------------------------------------------
-- Fishing pond (Config/Fishing POND_OFFSET), with a dock, a boat and a waterfall off the south cliff

local function buildPond(model: Instance, center: Vector3)
	local at = center + FishingConfig.POND_OFFSET
	local radius = FishingConfig.POND_RADIUS
	local pond = Instance.new("Model")
	pond.Name = "FishingPond"
	disc(pond, "Rim", at, radius + 2, 0.25, rgb(150, 146, 140), Enum.Material.Slate)
	disc(pond, "Water", at, radius, 0.35, WATER, Enum.Material.Glass).CanCollide = false
	-- Stream from the pond over the cliff, and the waterfall below it
	local edge = MapLayout.HUB_SIZE / 2
	local streamStart = FishingConfig.POND_OFFSET.Z + radius - 1
	part(pond, { Name = "Water", Size = Vector3.new(5, 0.3, edge - streamStart + 0.5), Position = center + Vector3.new(FishingConfig.POND_OFFSET.X, 0.2, (streamStart + edge) / 2), Color = WATER, Material = Enum.Material.Glass, CanCollide = false })
	part(pond, { Name = "Waterfall", Size = Vector3.new(5, 44, 0.8), Position = center + Vector3.new(FishingConfig.POND_OFFSET.X, -22, edge + 0.6), Color = rgb(150, 215, 255), Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false })
	-- Dock and boat
	part(pond, { Name = "Dock", Size = Vector3.new(4, 0.6, radius + 2), Position = at + Vector3.new(-radius * 0.45, 0.7, -radius * 0.3), Color = WOOD, Material = Enum.Material.WoodPlanks })
	part(pond, { Name = "Boat", Size = Vector3.new(2.6, 1.2, 5.4), CFrame = CFrame.new(at + Vector3.new(radius * 0.4, 0.8, 1)) * CFrame.Angles(0, math.rad(25), 0), Color = rgb(170, 110, 60), Material = Enum.Material.WoodPlanks, CanCollide = false })
	local sign = part(pond, { Name = "Sign", Size = Vector3.new(9, 2.6, 0.6), Position = at + Vector3.new(0, 4.4, -radius - 2.5), Color = rgb(110, 70, 44), Material = Enum.Material.Wood })
	paint(sign, Enum.NormalId.Front, "FISHING")
	part(pond, { Name = "Sign", Size = Vector3.new(0.8, 3.2, 0.8), Position = at + Vector3.new(-3, 1.6, -radius - 2.5), Color = WOOD, Material = Enum.Material.Wood })
	part(pond, { Name = "Sign", Size = Vector3.new(0.8, 3.2, 0.8), Position = at + Vector3.new(3, 1.6, -radius - 2.5), Color = WOOD, Material = Enum.Material.Wood })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Fish"
	prompt.ObjectText = "Fishing Pond"
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenUI", "Fish")
	prompt.Parent = sign
	pond.Parent = model
end

---------------------------------------------------------------------------------------------------------------
-- Trees on the rim, leaving the paths, arches, ad boards and leaderboards clear

local function buildTrees(model: Instance, center: Vector3)
	local half = MapLayout.HUB_SIZE / 2
	local rng = Random.new(4242)
	-- Small groves on the lawns between buildings (angles from north, like the buildings)
	for _, grove in { { angle = -48, radius = 168 }, { angle = -90, radius = 160 }, { angle = -146, radius = 150 }, { angle = 46, radius = 168 }, { angle = 148, radius = 160 }, { angle = -10, radius = 168 }, { angle = 10, radius = 168 } } do
		local a = math.rad(grove.angle)
		local at = center + Vector3.new(math.sin(a) * grove.radius, 0, -math.cos(a) * grove.radius)
		roundTree(model, at, 1.3, rgb(84, 168, 80))
		roundTree(model, at + Vector3.new(6, 0, 4), 0.9, rgb(104, 182, 84))
		pineTree(model, at + Vector3.new(-5, 0, 5), 1.1)
	end
	local spots: { Vector3 } = {}
	local step = 16
	for t = -half + 6, half - 6, step do
		table.insert(spots, Vector3.new(t, 0, -half + 6))
		table.insert(spots, Vector3.new(t, 0, half - 6))
		table.insert(spots, Vector3.new(-half + 6, 0, t))
		table.insert(spots, Vector3.new(half - 6, 0, t))
	end
	for i, spot in spots do
		local nearNorth = spot.Z < 0 and math.abs(spot.X) < 22
		local nearEast = spot.X > 0 and math.abs(spot.Z) < 22
		local nearSouth = spot.Z > half - 18 -- leaderboards and the pond
		local nearAdWest = spot.X < -half + 14 and math.abs(spot.Z) < 12
		local nearAdEast = spot.X > half - 14 and math.abs(spot.Z + 40) < 12
		if nearNorth or nearEast or nearSouth or nearAdWest or nearAdEast then
			continue
		end
		local jitter = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		if i % 3 == 0 then
			pineTree(model, center + spot + jitter, rng:NextNumber(1, 1.3))
		else
			roundTree(model, center + spot + jitter, rng:NextNumber(0.9, 1.2), rgb(70, 160, 76):Lerp(rgb(110, 190, 80), rng:NextNumber()))
		end
	end
end

---------------------------------------------------------------------------------------------------------------

-- Builds everything above into `zoneModel` (the Hub's Zone_0 model, which already has its Ground).
-- `openings` are the rim sides where a bridge leaves the island.
function HubBuilder.build(zoneModel: Instance, folder: Instance, openings: { Vector3 })
	local center = MapLayout.center(0)
	local hub = Instance.new("Model")
	hub.Name = "Town"
	buildIsland(zoneModel, center, openings)
	buildIslets(hub, center)
	buildPlaza(hub, center)
	buildStatue(hub, center)
	for _, building in BUILDINGS do
		buildBuilding(hub, center, building)
	end
	paths(hub, center)
	buildPond(hub, center)
	buildTrees(hub, center)

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.Position = center + HubBuilder.SPAWN_OFFSET + Vector3.new(0, 0.2, 0)
	spawn.Color = rgb(255, 255, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.6
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	hub.Parent = folder

	-- The statue is built before the 3D creature models load; rebuild it once they arrive. (The offline
	-- smoke test runs without the task library.)
	if task then
		task.spawn(function()
			local ok, models = pcall(function()
				return ReplicatedStorage:WaitForChild("CreatureModels", 60)
			end)
			if ok and models and hub.Parent then
				buildStatue(hub, center)
			end
		end)
	end
end

return HubBuilder
