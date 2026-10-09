-- Builds the World 1 map from config: zone platforms, bridges with gates, egg stands and the Hub.
-- Everything is made of simple blocks so the game runs without uploaded assets.
-- Each zone is closed by a tall themed wall (Config/MapTheme) and the bridges are walled corridors with a
-- solid gate, so a player sees the zone they're in and has to unlock a gate to find out what's next.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World1 = require(Shared.Config.World1)
local PetModel = require(Shared.PetModel)
local MapLayout = require(Shared.Logic.MapLayout)
local Nest = require(Shared.Logic.Nest)
local NestConfig = require(Shared.Config.Nest)
local MapTheme = require(Shared.Config.MapTheme)
local HubBuilder = require(script.Parent.HubBuilder)

local WorldBuilder = {}

WorldBuilder.eggPositions = {} :: { [number]: Vector3 }

-- Trading Plaza: a platform east of the Hub with booths where players sell creatures for gems.
WorldBuilder.PLAZA_SIDE = Vector3.new(1, 0, 0)
-- The Nest field: the players' islands with their incubators (NestService), west of the Hub
WorldBuilder.NEST_SIDE = Vector3.new(-1, 0, 0)
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

local WALL_H = MapTheme.WALL_HEIGHT
local WALL_T = MapTheme.WALL_THICKNESS

-- A straight piece of wall from the ground up, with a lighter band along its top. `size` is the wall's
-- footprint (X and Z); `name` lets the smoke test find the zone borders. `height` is the wall's (WALL_H).
local function wall(parent: Instance, name: string, position: Vector3, size: Vector3, style: { wall: Enum.Material, wallColor: Color3, capColor: Color3 }, height: number?)
	local h = height or WALL_H
	part({
		Name = name,
		Size = Vector3.new(size.X, h + 4, size.Z),
		Position = Vector3.new(position.X, h / 2 - 2, position.Z),
		Color = style.wallColor,
		Material = style.wall,
	}).Parent = parent
	part({
		Name = "WallCap",
		Size = Vector3.new(size.X + 1, 2, size.Z + 1),
		Position = Vector3.new(position.X, h + 1, position.Z),
		Color = style.capColor,
		CanCollide = false,
	}).Parent = parent
end

-- A square tower, a bit wider and taller than the wall: on the corners and on each side of an entrance.
local function tower(parent: Instance, position: Vector3, style: { wall: Enum.Material, wallColor: Color3, capColor: Color3 })
	local width = WALL_T + 3
	part({
		Name = "Tower",
		Size = Vector3.new(width, WALL_H + 10, width),
		Position = Vector3.new(position.X, (WALL_H + 10) / 2 - 4, position.Z),
		Color = style.wallColor:Lerp(Color3.new(0, 0, 0), 0.12),
		Material = style.wall,
	}).Parent = parent
	part({
		Name = "TowerCap",
		Size = Vector3.new(width + 2, 3, width + 2),
		Position = Vector3.new(position.X, WALL_H + 7.5, position.Z),
		Color = style.capColor,
		CanCollide = false,
	}).Parent = parent
end

local HUB_GRASS = Color3.fromRGB(118, 190, 92)

-- The base just inside each zone's entrance: the stations a player keeps going back to (beside the egg), so
-- they never have to walk back to the town for them
local STATIONS = {
	{ name = "Upgrades", icon = "⬆️", ui = "Shop", color = Color3.fromRGB(255, 196, 64), across = -34 },
	{ name = "Gifts", icon = "🎁", ui = "Daily", color = Color3.fromRGB(240, 96, 120), across = -20 },
	{ name = "Pets", icon = "🐾", ui = "Pets", color = Color3.fromRGB(110, 200, 140), across = 20 },
	{ name = "Teleport", icon = "✨", ui = "Teleport", color = Color3.fromRGB(120, 160, 255), across = 34 },
}
local STATION_INWARD = 14 -- studs in from the entrance edge

local function buildStations(zone: World1.Zone, model: Instance)
	local theme = MapTheme.get(zone.id)
	local folder = Instance.new("Model")
	folder.Name = "Stations"
	local center = MapLayout.center(zone.id)
	for _, station in STATIONS do
		local at = MapLayout.basePoint(zone.id, STATION_INWARD, station.across)
		local facing = CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z)) -- toward the zone
		part({
			Name = "Station",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 9, 9),
			CFrame = CFrame.new(at + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = theme.wallColor,
		}).Parent = folder
		local stand = part({
			Name = station.name,
			Size = Vector3.new(5, 5, 3),
			CFrame = facing * CFrame.new(0, 3.7, 0),
			Color = station.color,
		})
		stand.Parent = folder
		part({
			Name = "Glow",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.6,
			Position = at + Vector3.new(0, 7.6, 0),
			Color = station.color,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}).Parent = folder
		label(stand, station.icon .. " " .. station.name, UDim2.fromScale(9, 2), Vector3.new(0, 7, 0))
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = station.name
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OpenUI", station.ui)
		prompt.Parent = stand
	end
	folder.Parent = model
end

-- The zone's ground: a square with rounded corners (a cross of two slabs and a disc in each corner)
local function buildGround(zone: World1.Zone, center: Vector3, model: Instance)
	local size, r = MapLayout.PLATFORM, MapLayout.CORNER
	local material = MapTheme.get(zone.id).ground
	local pieces = {
		{ size = Vector3.new(size - 2 * r, 4, size), at = center },
		{ size = Vector3.new(size, 4, size - 2 * r), at = center },
	}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(pieces, { disc = true, at = center + Vector3.new(sx, 0, sz) * (size / 2 - r) })
		end
	end
	for _, piece in pieces do
		local ground = part({
			Name = "Ground",
			Shape = if piece.disc then Enum.PartType.Cylinder else Enum.PartType.Block,
			Size = if piece.disc then Vector3.new(4, 2 * r, 2 * r) else piece.size,
			CFrame = CFrame.new(piece.at + Vector3.new(0, -2, 0)) * (if piece.disc then CFrame.Angles(0, 0, math.rad(90)) else CFrame.identity),
			Color = zone.color,
			Material = material,
		})
		ground:SetAttribute("BaseColor", zone.color)
		ground.Parent = model
	end
end

-- A piece of wall turned to lie along `direction` (for the rounded corners)
local function turnedWall(parent: Instance, at: Vector3, direction: Vector3, length: number, style: { wall: Enum.Material, wallColor: Color3, capColor: Color3 })
	-- (turned about Y so its length, -Z, runs along `direction`)
	local frame = CFrame.new(at.X, 0, at.Z) * CFrame.Angles(0, math.atan2(-direction.X, -direction.Z), 0)
	part({
		Name = "BorderCorner",
		Size = Vector3.new(WALL_T, WALL_H + 4, length),
		CFrame = frame * CFrame.new(0, WALL_H / 2 - 2, 0),
		Color = style.wallColor,
		Material = style.wall,
	}).Parent = parent
	part({
		Name = "WallCap",
		Size = Vector3.new(WALL_T + 1, 2, length + 1),
		CFrame = frame * CFrame.new(0, WALL_H + 1, 0),
		Color = style.capColor,
		CanCollide = false,
	}).Parent = parent
end

-- The low border round a zone, following its rounded corners, with an opening (and towers and an arch)
-- toward each zone it links to
local function buildBorder(zone: World1.Zone, center: Vector3, model: Instance, openSides: { Vector3 })
	local theme = MapTheme.get(zone.id)
	local walls = Instance.new("Model")
	walls.Name = "Walls"
	local half, r, gap = MapLayout.PLATFORM / 2, MapLayout.CORNER, MapLayout.BRIDGE_WIDTH
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local isX = side.X ~= 0
		local open = table.find(openSides, side) ~= nil
		local straight = half - r -- from the middle of the side to where the corner starts
		local segments = if open
			then { { offset = -(straight + gap / 2) / 2, length = straight - gap / 2 }, { offset = (straight + gap / 2) / 2, length = straight - gap / 2 } }
			else { { offset = 0, length = 2 * straight } }
		local line = center + side * (half + WALL_T / 2)
		for _, segment in segments do
			local along = if isX then Vector3.new(0, 0, segment.offset) else Vector3.new(segment.offset, 0, 0)
			wall(walls, "Border", line + along, if isX then Vector3.new(WALL_T, 0, segment.length) else Vector3.new(segment.length, 0, WALL_T), theme)
		end
		if open then
			local across = if isX then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
			local edge = gap / 2 + (WALL_T + 3) / 2
			tower(walls, line + across * edge, theme)
			tower(walls, line - across * edge, theme)
			part({
				Name = "Arch",
				Size = if isX then Vector3.new(WALL_T + 2, 5, gap + 2) else Vector3.new(gap + 2, 5, WALL_T + 2),
				Position = line + Vector3.new(0, WALL_H - 2.5, 0),
				Color = theme.capColor,
				CanCollide = false,
			}).Parent = walls
		end
	end
	-- The corners: a quarter circle each, in short straight pieces
	local steps = 4
	local radius = r + WALL_T / 2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local pivot = center + Vector3.new(sx, 0, sz) * (half - r)
			for i = 1, steps do
				local a = (i - 0.5) / steps * math.pi / 2
				local out = Vector3.new(sx * math.cos(a), 0, sz * math.sin(a))
				local tangent = Vector3.new(-out.Z * sx * sz, 0, out.X * sx * sz)
				turnedWall(walls, pivot + out * radius, tangent, 2 * radius * math.sin(math.pi / 4 / steps) + 1, theme)
			end
		end
	end
	walls.Parent = model
end

local function buildZone(zone: World1.Zone, folder: Folder)
	local center = MapLayout.center(zone.id)
	local model = Instance.new("Model")
	model.Name = "Zone_" .. zone.id
	model:SetAttribute("ZoneId", zone.id)

	-- Border so players can't fall off, with an opening wherever a bridge connects
	local half = MapLayout.PLATFORM / 2
	local openSides: { Vector3 } = {}
	for _, other in zone.links do
		local delta = MapLayout.center(other) - center
		if math.abs(delta.X) > math.abs(delta.Z) then
			table.insert(openSides, Vector3.new(math.sign(delta.X), 0, 0))
		else
			table.insert(openSides, Vector3.new(0, 0, math.sign(delta.Z)))
		end
	end
	if zone.id == 0 then
		-- The Hub is a floating island town instead of a walled zone
		local ground = part({
			Name = "Ground",
			Size = Vector3.new(MapLayout.HUB_SIZE, 4, MapLayout.HUB_SIZE),
			Position = center + Vector3.new(0, -2, 0),
			Material = MapTheme.get(zone.id).ground,
		})
		ground.Parent = model
		table.insert(openSides, WorldBuilder.PLAZA_SIDE)
		table.insert(openSides, WorldBuilder.NEST_SIDE)
		ground.Color = HUB_GRASS
		ground:SetAttribute("BaseColor", HUB_GRASS)
		HubBuilder.build(model, folder, openSides)
		model.Parent = folder
		return
	end
	buildGround(zone, center, model)
	buildBorder(zone, center, model, openSides)
	buildStations(zone, model)

	-- A few block "trees" and rocks for decoration, placed on a ring so they don't block sources (nor the
	-- base: the egg and the stations)
	local rng = Random.new(zone.id * 97)
	local entrance = MapLayout.entrance(zone.id)
	for i = 1, 18 do
		local angle = (i / 18) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local radius = half - 8
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		if direction:Dot(entrance) > 0.4 then
			continue
		end
		local pos = center + direction * radius
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
	label(sign, zone.name, UDim2.fromScale(18, 3.6), Vector3.zero)
	sign.Parent = model

	-- Egg stand
	if zone.eggPrice > 0 then
		local eggPos = MapLayout.eggPosition(zone.id)
		local egg = buildEgg(model, eggPos, zone.color, 8, zone.name .. " Egg", false)
		egg:SetAttribute("ZoneId", zone.id)
		egg:AddTag("EggStand")
		WorldBuilder.eggPositions[zone.id] = egg.Position
	end

	-- The Legendary Egg stands next to the last zone's egg
	local legendary = World1.eggs[World1.LEGENDARY_EGG]
	if legendary and legendary.zone == zone.id then
		local eggPos = MapLayout.basePoint(zone.id, 30, 17) -- beside the zone's egg
		local egg = buildEgg(model, eggPos, Color3.fromRGB(255, 200, 70), 9, legendary.name, true)
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
		egg:SetAttribute("ZoneId", zone.id)
		egg:SetAttribute("EggId", legendary.id)
		egg:AddTag("EggStand")
		WorldBuilder.eggPositions[legendary.id] = egg.Position
	end

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

local function buildBridge(a: number, b: number, folder: Folder)
	local ca, cb = MapLayout.center(a), MapLayout.center(b)
	-- Middle of the gap between the two platforms (they can differ in size)
	local dir = (cb - ca).Unit
	local mid = ((ca + dir * MapLayout.size(a) / 2) + (cb - dir * MapLayout.size(b) / 2)) / 2
	local delta = cb - ca
	local isX = math.abs(delta.X) > math.abs(delta.Z)
	local length = (if isX then math.abs(delta.X) else math.abs(delta.Z)) - (MapLayout.size(a) + MapLayout.size(b)) / 2
	local bridge = part({
		Name = ("Bridge_%d_%d"):format(a, b),
		Size = if isX
			then Vector3.new(length, 4, MapLayout.BRIDGE_WIDTH)
			else Vector3.new(MapLayout.BRIDGE_WIDTH, 4, length),
		Position = mid + Vector3.new(0, -2, 0),
		Color = if a == 0 then Color3.fromRGB(150, 110, 70) else Color3.fromRGB(150, 140, 125),
		Material = if a == 0 then Enum.Material.WoodPlanks else Enum.Material.Cobblestone,
	})
	bridge.Parent = folder

	-- The bridge out of the Hub stays an open wooden bridge (the Hub is a floating island) and its gate
	-- never closes (the first zone is free), so it gets rails and no gate frame.
	if a == 0 then
		for _, sideSign in { -1, 1 } do
			local offset = if isX
				then Vector3.new(0, 1.5, sideSign * (MapLayout.BRIDGE_WIDTH / 2 + 0.5))
				else Vector3.new(sideSign * (MapLayout.BRIDGE_WIDTH / 2 + 0.5), 1.5, 0)
			part({
				Name = "Rail",
				Size = if isX then Vector3.new(length, 3, 1) else Vector3.new(1, 3, length),
				Position = mid + offset,
				Color = Color3.fromRGB(120, 84, 52),
				Material = Enum.Material.Wood,
			}).Parent = folder
		end
	end

	-- Corridor walls, so from a bridge you only see the gate ahead and the zone behind
	local style = MapTheme.CORRIDOR
	local walledSides: { number } = if a == 0 then {} else { -1, 1 }
	for _, sideSign in walledSides do
		local offset = if isX
			then Vector3.new(0, 0, sideSign * (MapLayout.BRIDGE_WIDTH / 2 + WALL_T / 2))
			else Vector3.new(sideSign * (MapLayout.BRIDGE_WIDTH / 2 + WALL_T / 2), 0, 0)
		wall(folder, "CorridorWall", mid + offset, if isX then Vector3.new(length, 0, WALL_T) else Vector3.new(WALL_T, 0, length), style)
	end

	-- Gate in the middle: a solid door in an iron frame, colored like the zone behind it. Clients hide the
	-- door and turn off its collision locally once both sides are unlocked; the frame stays.
	local behind = World1.zonesById[b]
	local doorHeight = WALL_H - 2 -- (too tall to jump over)
	local across = if isX then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	local iron = Color3.fromRGB(58, 60, 68)
	for _, sideSign in walledSides do
		part({
			Name = "GatePost",
			Size = Vector3.new(WALL_T + 2, WALL_H + 8, WALL_T + 2),
			Position = mid + across * sideSign * (MapLayout.BRIDGE_WIDTH / 2 + WALL_T / 2) + Vector3.new(0, (WALL_H + 8) / 2 - 2, 0),
			Color = iron,
			Material = Enum.Material.Metal,
		}).Parent = folder
	end
	part({
		Name = "GateLintel",
		Transparency = if a == 0 then 1 else 0,
		Size = if isX then Vector3.new(WALL_T + 2, 6, MapLayout.BRIDGE_WIDTH + 2) else Vector3.new(MapLayout.BRIDGE_WIDTH + 2, 6, WALL_T + 2),
		Position = mid + Vector3.new(0, doorHeight + 3, 0),
		Color = behind.color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}).Parent = folder
	local gate = part({
		Name = ("Gate_%d_%d"):format(a, b),
		Size = if isX
			then Vector3.new(2, doorHeight, MapLayout.BRIDGE_WIDTH)
			else Vector3.new(MapLayout.BRIDGE_WIDTH, doorHeight, 2),
		Position = mid + Vector3.new(0, doorHeight / 2, 0),
		Color = behind.color:Lerp(Color3.new(0, 0, 0), 0.35),
		Material = Enum.Material.Metal,
	})
	gate:SetAttribute("ZoneA", a)
	gate:SetAttribute("ZoneB", b)
	gate:AddTag("Gate")
	-- The lock, the zone and the price are painted on both faces of the door (WorldClient fills them in)
	local faces: { Enum.NormalId } = if isX then { Enum.NormalId.Left, Enum.NormalId.Right } else { Enum.NormalId.Front, Enum.NormalId.Back }
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.AnchorPoint = Vector2.new(0.5, 0.5)
		text.Position = UDim2.fromScale(0.5, 0.45)
		text.Size = UDim2.fromScale(0.85, 0.4)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.2
		text.Text = ""
		text.Parent = gui
		gui.Parent = gate
	end
	gate.Parent = folder
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
	buildProfessor(folder)
	buildPlaza(folder)
	buildNestField(folder)

	folder.Parent = workspace
	return folder
end

return WorldBuilder
