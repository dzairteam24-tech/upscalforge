-- Builds the World 1 map from config: zone platforms, bridges with gates, egg stands and the Hub.
-- Everything is made of simple blocks so the game runs without uploaded assets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World1 = require(Shared.Config.World1)
local MapLayout = require(Shared.Logic.MapLayout)

local WorldBuilder = {}

WorldBuilder.eggPositions = {} :: { [number]: Vector3 }

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

local function label(parent: Instance, text: string, size: UDim2, offset: Vector3, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = 250
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

local function buildZone(zone: World1.Zone, folder: Folder)
	local center = MapLayout.center(zone.id)
	local model = Instance.new("Model")
	model.Name = "Zone_" .. zone.id
	model:SetAttribute("ZoneId", zone.id)

	local ground = part({
		Name = "Ground",
		Size = Vector3.new(MapLayout.PLATFORM, 4, MapLayout.PLATFORM),
		Position = center + Vector3.new(0, -2, 0),
		Color = zone.color,
		Material = Enum.Material.Grass,
	})
	ground:SetAttribute("BaseColor", zone.color)
	ground.Parent = model

	-- Border so players can't fall off
	local half = MapLayout.PLATFORM / 2
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local isX = side.X ~= 0
		local wall = part({
			Name = "Border",
			Size = if isX then Vector3.new(1, 8, MapLayout.PLATFORM) else Vector3.new(MapLayout.PLATFORM, 8, 1),
			Position = center + side * (half + 0.5) + Vector3.new(0, 4, 0),
			Transparency = 1,
		})
		wall.Parent = model
	end

	-- A few block "trees" and rocks for decoration, placed on a ring so they don't block sources
	local rng = Random.new(zone.id * 97)
	for i = 1, 10 do
		local angle = (i / 10) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local radius = half - 8
		local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local trunk = part({
			Name = "Decor",
			Size = Vector3.new(2, 6, 2),
			Position = pos + Vector3.new(0, 3, 0),
			Color = Color3.fromRGB(120, 85, 60),
		})
		local leaves = part({
			Name = "Decor",
			Size = Vector3.new(7, 6, 7),
			Position = pos + Vector3.new(0, 8, 0),
			Color = zone.color:Lerp(Color3.new(0, 0, 0), 0.25),
		})
		leaves:SetAttribute("BaseColor", leaves.Color)
		trunk.Parent = model
		leaves.Parent = model
	end

	-- Zone name sign
	local sign = part({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		Position = center + Vector3.new(0, 26, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	label(sign, zone.name, UDim2.fromOffset(400, 80), Vector3.zero)
	sign.Parent = model

	-- Egg stand
	if zone.eggPrice > 0 then
		local eggPos = MapLayout.eggPosition(zone.id)
		local pedestal = part({
			Name = "EggPedestal",
			Size = Vector3.new(10, 2, 10),
			Position = eggPos + Vector3.new(0, 1, 0),
			Color = Color3.fromRGB(70, 75, 95),
		})
		pedestal.Parent = model
		local egg = part({
			Name = "Egg",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(6, 6, 6),
			Position = eggPos + Vector3.new(0, 5, 0),
			Color = zone.color,
			Material = Enum.Material.SmoothPlastic,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 1.3, 1)
		mesh.Parent = egg
		egg:SetAttribute("ZoneId", zone.id)
		egg:AddTag("EggStand")
		label(egg, zone.name .. " Egg", UDim2.fromOffset(240, 50), Vector3.new(0, 6, 0))
		egg.Parent = model
		WorldBuilder.eggPositions[zone.id] = egg.Position
	end

	model.Parent = folder
end

local function buildBridge(a: number, b: number, folder: Folder)
	local ca, cb = MapLayout.center(a), MapLayout.center(b)
	local mid = (ca + cb) / 2
	local delta = cb - ca
	local isX = math.abs(delta.X) > math.abs(delta.Z)
	local length = (if isX then math.abs(delta.X) else math.abs(delta.Z)) - MapLayout.PLATFORM
	local bridge = part({
		Name = ("Bridge_%d_%d"):format(a, b),
		Size = if isX
			then Vector3.new(length, 4, MapLayout.BRIDGE_WIDTH)
			else Vector3.new(MapLayout.BRIDGE_WIDTH, 4, length),
		Position = mid + Vector3.new(0, -2, 0),
		Color = Color3.fromRGB(150, 120, 90),
		Material = Enum.Material.WoodPlanks,
	})
	bridge.Parent = folder

	-- Rails
	for _, sideSign in { -1, 1 } do
		local offset = if isX
			then Vector3.new(0, 2, sideSign * (MapLayout.BRIDGE_WIDTH / 2 + 0.5))
			else Vector3.new(sideSign * (MapLayout.BRIDGE_WIDTH / 2 + 0.5), 2, 0)
		local rail = part({
			Name = "Rail",
			Size = if isX then Vector3.new(length, 4, 1) else Vector3.new(1, 4, length),
			Position = mid + offset,
			Color = Color3.fromRGB(110, 85, 60),
		})
		rail.Parent = folder
	end

	-- Gate in the middle. Clients turn off its collision locally once both sides are unlocked.
	local gate = part({
		Name = ("Gate_%d_%d"):format(a, b),
		Size = if isX
			then Vector3.new(2, 16, MapLayout.BRIDGE_WIDTH)
			else Vector3.new(MapLayout.BRIDGE_WIDTH, 16, 2),
		Position = mid + Vector3.new(0, 8, 0),
		Color = Color3.fromRGB(90, 200, 255),
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
	})
	gate:SetAttribute("ZoneA", a)
	gate:SetAttribute("ZoneB", b)
	gate:AddTag("Gate")
	label(gate, "", UDim2.fromOffset(260, 90), Vector3.new(0, 10, 0))
	gate.Parent = folder
end

local function buildHub(folder: Folder)
	local center = MapLayout.center(0)
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = center + Vector3.new(0, 0.5, 20)
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.5
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	local booths = {
		{ name = "Shop", color = Color3.fromRGB(245, 197, 66), offset = Vector3.new(-35, 0, -10), ui = "Shop" },
		{ name = "Trading", color = Color3.fromRGB(91, 184, 245), offset = Vector3.new(35, 0, -10), ui = "Trade" },
		{ name = "Fusion", color = Color3.fromRGB(185, 166, 245), offset = Vector3.new(0, 0, -35), ui = "Pets" },
		{ name = "Lucky Spin", color = Color3.fromRGB(255, 120, 200), offset = Vector3.new(-35, 0, 24), ui = "Spin" },
		{ name = "Trips", color = Color3.fromRGB(91, 160, 110), offset = Vector3.new(35, 0, 24), ui = "Trips" },
	}
	for _, booth in booths do
		local base = part({
			Name = booth.name .. "Booth",
			Size = Vector3.new(14, 8, 8),
			Position = center + booth.offset + Vector3.new(0, 4, 0),
			Color = booth.color,
		})
		local roof = part({
			Name = "Roof",
			Size = Vector3.new(16, 2, 10),
			Position = center + booth.offset + Vector3.new(0, 11, 0),
			Color = booth.color:Lerp(Color3.new(1, 1, 1), 0.4),
		})
		label(roof, booth.name, UDim2.fromOffset(240, 60), Vector3.new(0, 3, 0))
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = booth.name
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OpenUI", booth.ui)
		prompt.Parent = base
		base.Parent = folder
		roof.Parent = folder
	end
end

function WorldBuilder.build()
	local existing = workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "World"

	for _, zone in World1.zones do
		buildZone(zone, folder)
	end
	local done: { [string]: boolean } = {}
	for _, zone in World1.zones do
		for _, other in zone.links do
			local a, b = math.min(zone.id, other), math.max(zone.id, other)
			local id = a .. "_" .. b
			if not done[id] then
				done[id] = true
				buildBridge(a, b, folder)
			end
		end
	end
	buildHub(folder)

	folder.Parent = workspace
	return folder
end

return WorldBuilder
