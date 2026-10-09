-- Builds the world: the Hub (the town), the Egg Garden north of it with every tier's egg, the Trading Plaza
-- east and the Nest field west, where each player's incubators hatch eggs in real time. The zones of
-- Config/World1 are the egg tiers now: unlocking one opens its egg's cage in the garden.
-- Everything is made of simple blocks so the game runs without uploaded assets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World1 = require(Shared.Config.World1)
local PetModel = require(Shared.PetModel)
local MapLayout = require(Shared.Logic.MapLayout)
local Nest = require(Shared.Logic.Nest)
local NestConfig = require(Shared.Config.Nest)
local HubBuilder = require(script.Parent.HubBuilder)

local WorldBuilder = {}

WorldBuilder.eggPositions = {} :: { [number]: Vector3 }

-- Trading Plaza: a platform east of the Hub with booths where players sell creatures for gems.
WorldBuilder.PLAZA_SIDE = Vector3.new(1, 0, 0)
-- The Nest field: the players' islands with their incubators (NestService), west of the Hub
WorldBuilder.NEST_SIDE = Vector3.new(-1, 0, 0)
-- The Egg Garden, north of the Hub
WorldBuilder.GARDEN_SIDE = Vector3.new(0, 0, -1)
WorldBuilder.PLAZA_BOOTHS = 8

local buildEgg: (parent: Instance, position: Vector3, color: Color3, size: number, title: string, golden: boolean) -> BasePart

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- size is in studs (UDim2.fromScale), so a sign far away looks small, like a real sign. In pixels every
-- sign showed at full size up to MaxDistance and the names of every zone piled up on the screen.
local function label(parent: Instance, text: string, size: UDim2, offset: Vector3, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = 180
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextColor3 = color or Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0.3
	textLabel.Name = "Text"
	textLabel.Parent = gui
	gui.Parent = parent
end

local HUB_GRASS = Color3.fromRGB(118, 190, 92)

-- The Hub: the floating island town (HubBuilder), open toward the Egg Garden, the plaza and the Nest
local function buildHub(folder: Folder)
	local center = MapLayout.center(0)
	local model = Instance.new("Model")
	model.Name = "Zone_0"
	model:SetAttribute("ZoneId", 0)
	local ground = part({
		Name = "Ground",
		Size = Vector3.new(MapLayout.HUB_SIZE, 4, MapLayout.HUB_SIZE),
		Position = center + Vector3.new(0, -2, 0),
		Color = HUB_GRASS,
		Material = Enum.Material.Grass,
	})
	ground:SetAttribute("BaseColor", HUB_GRASS)
	ground.Parent = model
	HubBuilder.build(model, folder, { WorldBuilder.GARDEN_SIDE, WorldBuilder.PLAZA_SIDE, WorldBuilder.NEST_SIDE })
	model.Parent = folder
end

-- A big egg (about twice the player's height) on a pedestal with a glowing ring, inside an "EggModel"
-- with its spots so the client can turn and bob it as one piece (WorldClient).
function buildEgg(parent: Instance, position: Vector3, color: Color3, size: number, title: string, golden: boolean): BasePart
	local pedestal = part({
		Name = "EggPedestal",
		Size = Vector3.new(size + 5, 2, size + 5),
		Position = position + Vector3.new(0, 1, 0),
		Color = Color3.fromRGB(70, 75, 95),
		Material = Enum.Material.Slate,
	})
	pedestal.Parent = parent
	local ring = part({
		Name = "EggRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, size + 3, size + 3),
		CFrame = CFrame.new(position + Vector3.new(0, 2.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color:Lerp(Color3.new(1, 1, 1), 0.3),
		Material = Enum.Material.Neon,
	})
	ring.Parent = parent
	local eggModel = Instance.new("Model")
	eggModel.Name = "EggModel"
	local height = size * 1.3
	local center = position + Vector3.new(0, 2.6 + height / 2, 0)
	local egg = part({
		Name = "Egg",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size,
		Position = center,
		Color = color,
		Material = if golden then Enum.Material.Foil else Enum.Material.SmoothPlastic,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	egg.Parent = eggModel
	-- Spots on the shell
	local spotColor = color:Lerp(Color3.new(1, 1, 1), 0.55)
	for i = 1, 7 do
		local y = math.sin(i * 1.7) * height * 0.32
		local r = size / 2 * math.sqrt(math.max(0.15, 1 - (y / (height / 2)) ^ 2)) - size * 0.03
		local a = i * 2.1
		local spot = part({
			Name = "Spot",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size * (0.16 + (i % 3) * 0.05),
			Position = center + Vector3.new(math.cos(a) * r, y, math.sin(a) * r),
			Color = spotColor,
			CanCollide = false,
		})
		spot.Parent = eggModel
	end
	eggModel.PrimaryPart = egg
	eggModel.Parent = parent
	label(egg, title, UDim2.fromScale(9, 1.9), Vector3.new(0, height / 2 + 2.5, 0))
	return egg
end

---------------------------------------------------------------------------------------------------------------
-- The Egg Garden, north of the Hub: every egg in one place, from the first to the Legendary, on an arc round
-- a lawn. A locked egg stands in a cage ("Gate", drawn by WorldClient) that opens when its tier is unlocked.

local GARDEN_SIZE = Vector3.new(240, 0, 120)
local GARDEN_CORNER = 30

function WorldBuilder.gardenCenter(): Vector3
	return MapLayout.center(0) + WorldBuilder.GARDEN_SIDE * (MapLayout.HUB_SIZE / 2 + MapLayout.HUB_BRIDGE + GARDEN_SIZE.Z / 2)
end

-- Where a tier's egg stands (its zone id), on the arc; the Legendary Egg in the middle
function WorldBuilder.gardenEgg(zoneId: number): Vector3
	local center = WorldBuilder.gardenCenter()
	local tiers = 0
	for _, zone in World1.zones do
		if zone.eggPrice > 0 then
			tiers += 1
		end
	end
	local a = math.rad(-72 + (zoneId - 1) * 144 / math.max(1, tiers - 1))
	-- (north is -Z: the arc bows away from the bridge)
	return center + Vector3.new(math.sin(a) * 100, 0, 28 - math.cos(a) * 72)
end

local function buildGardenGround(model: Instance, center: Vector3)
	local sx, sz, r = GARDEN_SIZE.X, GARDEN_SIZE.Z, GARDEN_CORNER
	local color = Color3.fromRGB(123, 201, 111)
	local pieces = {
		{ size = Vector3.new(sx - 2 * r, 4, sz), at = center },
		{ size = Vector3.new(sx, 4, sz - 2 * r), at = center },
	}
	for _, ax in { -1, 1 } do
		for _, az in { -1, 1 } do
			table.insert(pieces, { disc = true, at = center + Vector3.new(ax * (sx / 2 - r), 0, az * (sz / 2 - r)) })
		end
	end
	for _, piece in pieces do
		local ground = part({
			Name = "Ground",
			Shape = if piece.disc then Enum.PartType.Cylinder else Enum.PartType.Block,
			Size = if piece.disc then Vector3.new(4, 2 * r, 2 * r) else piece.size,
			CFrame = CFrame.new(piece.at + Vector3.new(0, -2, 0)) * (if piece.disc then CFrame.Angles(0, 0, math.rad(90)) else CFrame.identity),
			Color = color,
			Material = Enum.Material.Grass,
		})
		ground:SetAttribute("BaseColor", color)
		ground.Parent = model
	end
	-- A paved path from the bridge to the Legendary Egg
	part({
		Name = "Path",
		Size = Vector3.new(MapLayout.BRIDGE_WIDTH - 6, 0.3, sz / 2),
		Position = center + Vector3.new(0, 0.15, sz / 4),
		Color = Color3.fromRGB(226, 208, 172),
		Material = Enum.Material.Pavement,
		CanCollide = false,
	}).Parent = model
	-- Invisible walls round the edge (open toward the bridge)
	local half = Vector3.new(sx / 2, 0, sz / 2)
	part({ Name = "Border", Size = Vector3.new(sx, 12, 1), Position = center + Vector3.new(0, 6, -half.Z - 0.5), Transparency = 1 }).Parent = model
	for _, ax in { -1, 1 } do
		part({ Name = "Border", Size = Vector3.new(1, 12, sz), Position = center + Vector3.new(ax * (half.X + 0.5), 6, 0), Transparency = 1 }).Parent = model
		local length = (sx - MapLayout.BRIDGE_WIDTH) / 2
		part({ Name = "Border", Size = Vector3.new(length, 12, 1), Position = center + Vector3.new(ax * (MapLayout.BRIDGE_WIDTH / 2 + length / 2), 6, half.Z + 0.5), Transparency = 1 }).Parent = model
	end
end

-- The cage round a locked egg: a door (a "Gate" between the tier before and this one) on each side
local function buildCage(model: Instance, zoneId: number, at: Vector3)
	local zone = World1.zonesById[zoneId]
	local cage = part({
		Name = ("Gate_%d_%d"):format(zoneId - 1, zoneId),
		Size = Vector3.new(15, 17, 15),
		Position = at + Vector3.new(0, 8.5, 0),
		Color = zone.color:Lerp(Color3.new(0, 0, 0), 0.35),
		Material = Enum.Material.Glass,
	})
	cage:SetAttribute("ZoneA", zoneId - 1)
	cage:SetAttribute("ZoneB", zoneId)
	cage:AddTag("Gate")
	-- The lock, the tier and the price on each face (WorldClient fills them in)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(0.9, 0.5)
		text.AnchorPoint = Vector2.new(0.5, 0.5)
		text.Position = UDim2.fromScale(0.5, 0.45)
		text.BackgroundTransparency = 1
		text.TextScaled = true
		text.Font = Enum.Font.FredokaOne
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.2
		text.Parent = gui
		gui.Parent = cage
	end
	cage.Parent = model
end

local function buildEggGarden(folder: Folder)
	local center = WorldBuilder.gardenCenter()
	local model = Instance.new("Model")
	model.Name = "EggGarden"
	buildGardenGround(model, center)
	local sign = part({ Name = "Sign", Size = Vector3.one, Position = center + Vector3.new(0, 26, 10), Transparency = 1, CanCollide = false, CanQuery = false })
	label(sign, "🥚 Egg Garden", UDim2.fromScale(18, 3.6), Vector3.zero)
	sign.Parent = model
	for _, zone in World1.zones do
		if zone.eggPrice <= 0 then
			continue
		end
		local at = WorldBuilder.gardenEgg(zone.id)
		local egg = buildEgg(model, at, zone.color, 8, zone.name .. " Egg", false)
		egg:SetAttribute("ZoneId", zone.id)
		egg:AddTag("EggStand")
		WorldBuilder.eggPositions[zone.id] = egg.Position
		if zone.gateCost > 0 then
			buildCage(model, zone.id, at)
		end
	end
	-- The Legendary Egg in the middle, caged until its tier is unlocked
	local legendary = World1.eggs[World1.LEGENDARY_EGG]
	if legendary then
		local at = center + Vector3.new(0, 0, -6)
		local egg = buildEgg(model, at, Color3.fromRGB(255, 200, 70), 9, legendary.name, true)
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140), Color3.fromRGB(200, 140, 255))
		sparkles.LightEmission = 0.8
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Lifetime = NumberRange.new(1, 1.8)
		sparkles.Speed = NumberRange.new(1, 2.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Rate = 20
		sparkles.Parent = egg
		egg:SetAttribute("ZoneId", legendary.zone)
		egg:SetAttribute("EggId", legendary.id)
		egg:AddTag("EggStand")
		WorldBuilder.eggPositions[legendary.id] = egg.Position
		buildCage(model, legendary.zone, at)
	end
	model.Parent = folder
end

-- The wooden bridge from the Hub to the Egg Garden
local function buildGardenBridge(folder: Folder)
	local hubEdge = MapLayout.center(0) + WorldBuilder.GARDEN_SIDE * (MapLayout.HUB_SIZE / 2)
	local gardenEdge = WorldBuilder.gardenCenter() - WorldBuilder.GARDEN_SIDE * (GARDEN_SIZE.Z / 2)
	local mid = (hubEdge + gardenEdge) / 2
	local length = (hubEdge - gardenEdge).Magnitude
	part({
		Name = "Bridge_0_1",
		Size = Vector3.new(MapLayout.BRIDGE_WIDTH, 4, length),
		Position = mid + Vector3.new(0, -2, 0),
		Color = Color3.fromRGB(150, 110, 70),
		Material = Enum.Material.WoodPlanks,
	}).Parent = folder
	for _, sideSign in { -1, 1 } do
		part({
			Name = "Rail",
			Size = Vector3.new(1, 3, length),
			Position = mid + Vector3.new(sideSign * (MapLayout.BRIDGE_WIDTH / 2 + 0.5), 1.5, 0),
			Color = Color3.fromRGB(120, 84, 52),
			Material = Enum.Material.Wood,
		}).Parent = folder
	end
end


-- Professor Cubo: the Journey's NPC near the spawn. Talking to him opens the Quests window.
local function buildProfessor(folder: Folder)
	local center = MapLayout.center(0) + Vector3.new(58, 0, 118)
	local built = PetModel.build({ s = "Cubby", v = "Normal", z = "Big" })
	local facing = CFrame.lookAt(center + Vector3.new(0, built.height / 2, 0), center + Vector3.new(-16, built.height / 2, -20))
	PetModel.place(built, facing)
	built.model.Name = "ProfessorCubo"
	-- Round glasses
	for _, side in { -1, 1 } do
		local lens = part({
			Name = "Glasses",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, 1.1, 1.1),
			CFrame = facing * CFrame.new(side * 0.85, 0.35, -built.radius * 0.66) * CFrame.Angles(0, math.rad(90), 0),
			Color = Color3.fromRGB(40, 40, 50),
			Transparency = 0.4,
			CanCollide = false,
		})
		lens.Parent = built.model
	end
	local base = part({
		Name = "ProfessorBase",
		Size = Vector3.new(8, 0.6, 8),
		Position = center + Vector3.new(0, 0.3, 0),
		Color = Color3.fromRGB(120, 90, 200),
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
	})
	base.Parent = built.model
	label(base, "📖 Professor Cubo", UDim2.fromScale(9, 1.9), Vector3.new(0, built.height + 3, 0))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = "Professor Cubo"
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenUI", "Quests")
	prompt.Parent = base
	built.model.Parent = folder
end

---------------------------------------------------------------------------------------------------------------
-- The Nest field (Config/Nest): eight islands in two rows along a path, each with eight incubator pads.
-- NestService gives each player one and fills the pads (attributes); NestClient draws the eggs and timers.

local NEST_PLOT = 56 -- an island's width
local NEST_GAP = 8
local NEST_PATH = 20 -- the path between the two rows

function WorldBuilder.nestCenter(): Vector3
	local width = 2 * NEST_PLOT + NEST_PATH + 16
	return MapLayout.center(0) + WorldBuilder.NEST_SIDE * (MapLayout.HUB_SIZE / 2 + 30 + width / 2)
end

-- Where an island is (1..PLOTS) and which way its front (toward the path) faces
function WorldBuilder.nestPlot(index: number): (Vector3, Vector3)
	local center = WorldBuilder.nestCenter()
	local side = if index % 2 == 1 then -1 else 1 -- odd ones in the row west of the path, even ones east
	local row = (index - 1) // 2
	local rows = math.ceil(NestConfig.PLOTS / 2)
	local z = (row - (rows - 1) / 2) * (NEST_PLOT + NEST_GAP)
	local out = Vector3.new(side, 0, 0)
	return center + out * (NEST_PATH / 2 + NEST_PLOT / 2) + Vector3.new(0, 0, z), -out
end

-- The incubator pads' spots on an island: two rows of four, in front of the owner's sign
function WorldBuilder.nestPad(index: number, slot: number): Vector3
	local plot, front = WorldBuilder.nestPlot(index)
	local right = Vector3.new(front.Z, 0, -front.X)
	local column = (slot - 1) % 4
	local row = (slot - 1) // 4
	return plot + front * (8 - row * 14) + right * ((column - 1.5) * 12)
end

local function buildNestField(folder: Folder)
	local center = WorldBuilder.nestCenter()
	local rows = math.ceil(NestConfig.PLOTS / 2)
	local depth = rows * NEST_PLOT + (rows - 1) * NEST_GAP + 16
	local width = 2 * NEST_PLOT + NEST_PATH + 16
	local model = Instance.new("Model")
	model.Name = "NestField"
	-- The bridge from the Hub, the path down the middle and the open sky round the islands
	local hubEdge = MapLayout.center(0).X - MapLayout.HUB_SIZE / 2
	local fieldEdge = center.X + width / 2
	part({
		Name = "NestBridge",
		Size = Vector3.new(hubEdge - fieldEdge, 4, MapLayout.BRIDGE_WIDTH),
		Position = Vector3.new((hubEdge + fieldEdge) / 2, -2, center.Z),
		Color = Color3.fromRGB(150, 110, 70),
		Material = Enum.Material.WoodPlanks,
	}).Parent = model
	part({
		Name = "Ground",
		Size = Vector3.new(NEST_PATH + 8, 4, depth),
		Position = center + Vector3.new(0, -2, 0),
		Color = Color3.fromRGB(226, 208, 172),
		Material = Enum.Material.Pavement,
	}).Parent = model
	part({
		Name = "Ground",
		Size = Vector3.new(width, 4, MapLayout.BRIDGE_WIDTH),
		Position = center + Vector3.new(0, -2, 0),
		Color = Color3.fromRGB(226, 208, 172),
		Material = Enum.Material.Pavement,
	}).Parent = model
	local sign = part({ Name = "Sign", Size = Vector3.one, Position = center + Vector3.new(width / 2 - 4, 16, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	label(sign, "🥚 The Nest", UDim2.fromScale(16, 3.4), Vector3.zero)
	sign.Parent = model
	-- Invisible walls round the field's outer edge
	for _, s in { -1, 1 } do
		part({ Name = "Border", Size = Vector3.new(width, 12, 1), Position = center + Vector3.new(0, 6, s * (depth / 2 + 0.5)), Transparency = 1 }).Parent = model
	end
	part({ Name = "Border", Size = Vector3.new(1, 12, depth), Position = center + Vector3.new(-width / 2 - 0.5, 6, 0), Transparency = 1 }).Parent = model
	for _, s in { -1, 1 } do
		-- (the Hub side, open where the bridge comes in)
		local length = (depth - MapLayout.BRIDGE_WIDTH) / 2
		part({ Name = "Border", Size = Vector3.new(1, 12, length), Position = center + Vector3.new(width / 2 + 0.5, 6, s * (MapLayout.BRIDGE_WIDTH / 2 + length / 2)), Transparency = 1 }).Parent = model
	end

	for index = 1, NestConfig.PLOTS do
		local plotCenter, front = WorldBuilder.nestPlot(index)
		local plot = Instance.new("Model")
		plot.Name = "NestPlot_" .. index
		plot:SetAttribute("Plot", index)
		part({
			Name = "Ground",
			Size = Vector3.new(NEST_PLOT, 4, NEST_PLOT),
			Position = plotCenter + Vector3.new(0, -2, 0),
			Color = Color3.fromRGB(118, 190, 92),
			Material = Enum.Material.Grass,
		}).Parent = plot
		-- The owner's sign at the back
		local board = part({
			Name = "OwnerSign",
			Size = Vector3.new(1, 1, 1),
			Position = plotCenter - front * (NEST_PLOT / 2 - 6) + Vector3.new(0, 10, 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		label(board, "Free island", UDim2.fromScale(14, 2.6), Vector3.zero)
		board.Parent = plot
		for slot = 1, Nest.maxSlots() do
			local at = WorldBuilder.nestPad(index, slot)
			local pad = part({
				Name = "Incubator",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.4, 8, 8),
				CFrame = CFrame.new(at + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(240, 232, 214),
			})
			pad:SetAttribute("Plot", index)
			pad:SetAttribute("Slot", slot)
			pad:AddTag("NestPad")
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Use"
			prompt.ObjectText = "Incubator"
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Enabled = false -- NestClient turns on the owner's
			prompt:SetAttribute("NestPlot", index)
			prompt:SetAttribute("NestSlot", slot)
			prompt.Parent = pad
			pad.Parent = plot
		end
		plot.Parent = model
	end
	model.Parent = folder
end

local PLAZA_SIZE = 90

function WorldBuilder.plazaCenter(): Vector3
	return MapLayout.center(0) + WorldBuilder.PLAZA_SIDE * (MapLayout.HUB_SIZE / 2 + 40 + PLAZA_SIZE / 2)
end

local function buildPlaza(folder: Folder)
	local hub = MapLayout.center(0)
	local center = WorldBuilder.plazaCenter()
	local model = Instance.new("Model")
	model.Name = "TradingPlaza"

	local ground = part({
		Name = "Ground",
		Size = Vector3.new(PLAZA_SIZE, 4, PLAZA_SIZE),
		Position = center + Vector3.new(0, -2, 0),
		Color = Color3.fromRGB(205, 190, 160),
		Material = Enum.Material.Cobblestone,
	})
	ground.Parent = model

	-- Bridge from the Hub's east edge to the plaza's west edge
	local fromX = hub.X + MapLayout.HUB_SIZE / 2
	local toX = center.X - PLAZA_SIZE / 2
	local bridge = part({
		Name = "PlazaBridge",
		Size = Vector3.new(toX - fromX, 4, MapLayout.BRIDGE_WIDTH),
		Position = Vector3.new((fromX + toX) / 2, -2, center.Z),
		Color = Color3.fromRGB(150, 120, 90),
		Material = Enum.Material.WoodPlanks,
	})
	bridge.Parent = model
	for _, sideSign in { -1, 1 } do
		local rail = part({
			Name = "Rail",
			Size = Vector3.new(toX - fromX, 4, 1),
			Position = Vector3.new((fromX + toX) / 2, 2, center.Z + sideSign * (MapLayout.BRIDGE_WIDTH / 2 + 0.5)),
			Color = Color3.fromRGB(110, 85, 60),
		})
		rail.Parent = model
	end

	-- Invisible walls, open toward the bridge
	local half = PLAZA_SIZE / 2
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local isX = side.X ~= 0
		local wall = part({
			Name = "Border",
			Size = if isX then Vector3.new(1, 8, PLAZA_SIZE) else Vector3.new(PLAZA_SIZE, 8, 1),
			Position = center + side * (half + 0.5) + Vector3.new(0, 4, 0),
			Transparency = 1,
		})
		wall.Parent = model
	end
	for _, sign in { -1, 1 } do
		local length = (PLAZA_SIZE - MapLayout.BRIDGE_WIDTH) / 2
		local wall = part({
			Name = "Border",
			Size = Vector3.new(1, 8, length),
			Position = center + Vector3.new(-half - 0.5, 4, sign * (MapLayout.BRIDGE_WIDTH / 2 + length / 2)),
			Transparency = 1,
		})
		wall.Parent = model
	end

	local sign = part({
		Name = "PlazaSign",
		Size = Vector3.new(1, 1, 1),
		Position = center + Vector3.new(0, 14, 0),
		Transparency = 1,
		CanCollide = false,
	})
	label(sign, "🏪 Trading Plaza", UDim2.fromScale(13, 2.5), Vector3.new(0, 0, 0), Color3.fromRGB(255, 225, 120))
	sign.Parent = model

	-- Booths on a ring, facing the middle
	for i = 1, WorldBuilder.PLAZA_BOOTHS do
		local angle = (i - 0.5) / WorldBuilder.PLAZA_BOOTHS * math.pi * 2
		local pos = center + Vector3.new(math.cos(angle) * 30, 0, math.sin(angle) * 30)
		local facing = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
		local hue = (i - 1) / WorldBuilder.PLAZA_BOOTHS
		local booth = part({
			Name = "Booth_" .. i,
			Size = Vector3.new(10, 4, 5),
			CFrame = facing * CFrame.new(0, 2, 0),
			Color = Color3.fromHSV(hue, 0.45, 0.95),
		})
		booth:SetAttribute("BoothId", i)
		booth:AddTag("Booth")
		local roof = part({
			Name = "BoothRoof",
			Size = Vector3.new(12, 1, 7),
			CFrame = facing * CFrame.new(0, 9, 0),
			Color = Color3.fromHSV(hue, 0.6, 0.8),
		})
		roof.Parent = model
		for _, x in { -5.5, 5.5 } do
			local pole = part({
				Name = "BoothPole",
				Size = Vector3.new(0.6, 5, 0.6),
				CFrame = facing * CFrame.new(x, 6, 0),
				Color = Color3.fromRGB(240, 240, 240),
			})
			pole.Parent = model
		end
		label(booth, "Free booth", UDim2.fromScale(8, 2), Vector3.new(0, 9, 0))
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Booth"
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("BoothId", i)
		prompt.Parent = booth
		booth.Parent = model
	end

	model.Parent = folder
end

function WorldBuilder.build()
	local existing = workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "World"

	buildHub(folder)
	buildGardenBridge(folder)
	buildEggGarden(folder)
	buildProfessor(folder)
	buildPlaza(folder)
	buildNestField(folder)

	folder.Parent = workspace
	return folder
end

return WorldBuilder
