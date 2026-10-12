--!strict
-- Builds the world (Logic/Layout, docs/images/map-plan.png): the round square where players arrive, the shops'
-- market stalls in a row on its west side facing the spawn, the big gate into the Wild north of it, and the
-- players' gardens on an arc south of it, each fenced, with its laser gate toward the square, incubators and
-- owner's sign; the roads between them. Everything is simple parts: light, and there before any art loads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared.Config.Island)
local SnapConfig = require(Shared.Config.Snap)
local WildConfig = require(Shared.Config.Wild)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Layout = require(Shared.Logic.Layout)
local Nest = require(Shared.Nest)
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
	p.CanTouch = false -- (nothing in the world listens for touches: no physics work for it)
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

-- A shop's name in big yellow letters with a dark outline, floating over its stall
local function bigName(parent: Instance, text: string, width: number, height: number): TextLabel
	local name = label(parent, text, width, height, Vector3.zero)
	name.Font = Enum.Font.LuckiestGuy
	name.TextColor3 = rgb(255, 221, 64)
	name.TextStrokeColor3 = rgb(20, 18, 30)
	name.TextStrokeTransparency = 0
	return name
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

-- The shops, in the order of their stalls (Layout.shop), with their sign and colors
type ShopSpot = { name: string, ui: string, color: Color3, sign: string?, emoji: string, machine: boolean?, menu: { string } }
local SHOPS: { ShopSpot } = {
	{ name = "Shop", sign = "SHOP", ui = "Shop", emoji = "🛒", color = rgb(92, 200, 120), menu = { "Sell eggs and creatures", "Buy food for the trough" } },
	{ name = "Fuse Machine", machine = true, ui = "Fuse", emoji = "⚙️", color = rgb(60, 130, 240), menu = { ("%d of a kind  →  Mega"):format(SnapConfig.NEED), ("%d Megas  →  Rainbow"):format(SnapConfig.NEED) } },
	{ name = "Trail Shop", sign = "TRAILS", ui = "Trails", emoji = "✨", color = rgb(255, 200, 40), menu = { "Colored trails behind you", "More speed with every step" } },
	{ name = "Mutation Machine", machine = true, ui = "Mutate", emoji = "🧪", color = rgb(90, 230, 110), menu = { "Raise a creature's mutation", "Normal  →  Golden  →  Neon" } },
}

WorldService.SHOPS = SHOPS

-- The shop buildings are drawn Layout.SHOP_SCALE times bigger than their base size: `sp` places a part given in
-- the base size and the frame's space, scaled about the frame's origin
local SCALE = Layout.SHOP_SCALE
local scaleFrame: CFrame = CFrame.new()
local function sp(parent: Instance, props: { [string]: any }): Part
	local rel = scaleFrame:ToObjectSpace(props.CFrame)
	props.CFrame = scaleFrame * (CFrame.new(rel.Position * SCALE) * rel.Rotation)
	props.Size = props.Size * SCALE
	return part(parent, props)
end

-- A menu board: a dark board in a frame of the shop's color with a title and a line for each thing the shop does
-- (what it sells). `hanging`: hung from the roof over the counter, wide; else a standee on two legs.
local function menuBoard(model: Instance, shop: ShopSpot, size: Vector3, at: Vector3, hanging: boolean)
	local tilt = if hanging then 0 else -8
	local board = sp(model, { Name = "MenuBoard", Size = size, CFrame = scaleFrame * CFrame.new(at) * CFrame.Angles(math.rad(tilt), 0, 0), Color = rgb(34, 30, 48), CanCollide = false })
	sp(model, { Name = "MenuFrame", Size = Vector3.new(size.X + 0.6, size.Y + 0.6, 0.3), CFrame = scaleFrame * CFrame.new(at + Vector3.new(0, 0, 0.12)) * CFrame.Angles(math.rad(tilt), 0, 0), Color = shop.color, CanCollide = false })
	if hanging then
		for _, side in { -1, 1 } do
			sp(model, { Name = "MenuChain", Size = Vector3.new(0.25, 1.8, 0.25), CFrame = scaleFrame * CFrame.new(at + Vector3.new(side * size.X * 0.36, size.Y / 2 + 0.9, 0)), Color = rgb(70, 66, 80), CanCollide = false })
		end
	else
		for _, side in { -1, 1 } do
			sp(model, { Name = "MenuLeg", Size = Vector3.new(0.4, 1.2, 0.4), CFrame = scaleFrame * CFrame.new(at + Vector3.new(side * size.X * 0.36, -size.Y / 2 - 0.4, 0.5)), Color = rgb(120, 82, 52), Material = Enum.Material.WoodPlanks, CanCollide = false })
		end
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 50
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud -- (else PixelsPerStud is ignored and the text is stretched to the part's shape)
	local function label(text: string, x: number, y: number, w: number, h: number, font: Enum.Font, color: Color3, align: Enum.TextXAlignment)
		local t = Instance.new("TextLabel")
		t.Position = UDim2.fromScale(x, y)
		t.Size = UDim2.fromScale(w, h)
		t.BackgroundTransparency = 1
		t.Text = text
		t.TextScaled = true
		t.Font = font
		t.TextColor3 = color
		t.TextXAlignment = align
		t.Parent = gui
	end
	local count = #shop.menu
	if hanging then
		-- (wide: the title on the left, a thin divider in the shop's color, the lines in a column to its right)
		label("MENU", 0.03, 0.12, 0.24, 0.76, Enum.Font.LuckiestGuy, rgb(255, 221, 64), Enum.TextXAlignment.Center)
		local divider = Instance.new("Frame")
		divider.Position = UDim2.fromScale(0.285, 0.14)
		divider.Size = UDim2.fromScale(0.006, 0.72)
		divider.BackgroundColor3 = shop.color
		divider.BorderSizePixel = 0
		divider.Parent = gui
		local rowH = 0.72 / count
		for i, text in shop.menu do
			local y = 0.14 + (i - 1) * rowH
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(0.33, y + rowH / 2)
			dot.Size = UDim2.fromScale(0.5, rowH * 0.22)
			dot.BackgroundColor3 = shop.color
			dot.BorderSizePixel = 0
			local square = Instance.new("UIAspectRatioConstraint")
			square.AspectRatio = 1
			square.DominantAxis = Enum.DominantAxis.Height
			square.Parent = dot
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(0.5, 0)
			round.Parent = dot
			dot.Parent = gui
			label(text, 0.36, y + rowH * 0.15, 0.61, rowH * 0.7, Enum.Font.GothamBold, Color3.new(1, 1, 1), Enum.TextXAlignment.Left)
		end
	else
		label("MENU", 0.04, 0.05, 0.92, 0.27, Enum.Font.LuckiestGuy, rgb(255, 221, 64), Enum.TextXAlignment.Center)
		local rowH = 0.56 / count
		for i, text in shop.menu do
			label(text, 0.07, 0.38 + (i - 1) * rowH + rowH * 0.1, 0.86, rowH * 0.7, Enum.Font.GothamBold, Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
		end
	end
	gui.Parent = board
end

-- A machine in the market row (the Fuse Machine, the Mutation Machine): a big boxy body in its color with a
-- glowing window in front, pipes and a light on top, its name floating over it. Its front holds the prompt.
local function buildMachine(town: Instance, index: number)
	local shop = SHOPS[index]
	local frame = Layout.shop(index)
	scaleFrame = frame
	local model = Instance.new("Model")
	model.Name = shop.name
	local dark = shop.color:Lerp(rgb(30, 30, 40), 0.55)
	sp(model, { Name = "Platform", Size = Vector3.new(Layout.SHOP_WIDTH + 4, 0.8, Layout.SHOP_DEPTH + 6), CFrame = frame * CFrame.new(0, 0.4, (Layout.SHOP_DEPTH - 1) / 2), Color = rgb(96, 100, 116), Material = Enum.Material.DiamondPlate })
	menuBoard(model, shop, Vector3.new(7, 4.4, 0.4), Vector3.new(-8, 4.2, -2.4), false)
	local body = sp(model, { Name = "Body", Size = Vector3.new(13, 9, 8), CFrame = frame * CFrame.new(0, 5.3, 5), Color = dark })
	local window = sp(model, { Name = "Window", Size = Vector3.new(7, 6, 0.4), CFrame = frame * CFrame.new(1.5, 5.6, 0.9), Color = shop.color:Lerp(Color3.new(1, 1, 1), 0.5), Material = Enum.Material.Neon, CanCollide = false })
	local glyph = Instance.new("SurfaceGui")
	glyph.Face = Enum.NormalId.Front
	glyph.PixelsPerStud = 30
	glyph.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud -- (else PixelsPerStud is ignored and the text is stretched to the part's shape)
	local mark = Instance.new("TextLabel")
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.Text = if shop.ui == "Fuse" then "?" else "🔒"
	mark.TextScaled = true
	mark.Font = Enum.Font.LuckiestGuy
	mark.TextColor3 = dark
	mark.Parent = glyph
	glyph.Parent = window
	-- (a lever panel, a pipe arching over, a lamp on top)
	sp(model, { Name = "Panel", Size = Vector3.new(3, 5, 0.5), CFrame = frame * CFrame.new(-4.5, 4.8, 0.85), Color = rgb(70, 75, 90) })
	sp(model, { Name = "Lever", Size = Vector3.new(0.4, 2, 0.4), CFrame = frame * CFrame.new(-4.5, 4.8, 0.4) * CFrame.Angles(math.rad(-25), 0, 0), Color = rgb(230, 70, 70), CanCollide = false })
	for _, x in { -3.5, 3.5 } do
		sp(model, { Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 1.4, 1.4), CFrame = frame * CFrame.new(x, 11.5, 5) * CFrame.Angles(0, 0, math.rad(90)), Color = shop.color, Material = Enum.Material.Neon, CanCollide = false })
	end
	sp(model, { Name = "PipeTop", Size = Vector3.new(8.4, 1.4, 1.4), CFrame = frame * CFrame.new(0, 13.5, 5), Color = rgb(70, 75, 90), CanCollide = false })
	local sign = sp(model, { Name = "MachineSign", Size = Vector3.one, CFrame = frame * CFrame.new(0, 18, 5), Transparency = 1, CanCollide = false, CanQuery = false })
	bigName(sign, shop.emoji .. " " .. string.upper(shop.name), 24 * SCALE, 5 * SCALE)
	local status = label(sign, "", 12 * SCALE, 2.4 * SCALE, Vector3.new(0, -4.4 * SCALE, 0)) -- (each player's own: FuseWindow, MutateWindow)
	status.Name = "Status"
	sign:AddTag(if shop.ui == "Fuse" then "FuseSign" else "MutateSign")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if shop.ui == "Fuse" then "Fuse" else "Open"
	prompt.ObjectText = shop.name
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenUI", shop.ui)
	prompt.Parent = body
	model.Parent = town
end

-- A shop building, just outside the paving's edge, its front toward the lane: a stone platform, a back wall and
-- two side walls with windows, a flat roof with a colored fascia and a scalloped valance, lanterns, a counter
-- with goods on it and shelves behind, flower boxes, a menu board (what it sells) and its name floating high
-- over it in big letters. The counter holds the prompt that opens the shop's window.
local CREAM = rgb(250, 238, 214)
local PLANK = rgb(176, 124, 78)
local DARK_PLANK = rgb(120, 82, 52)
local STONE = rgb(150, 146, 140)

local function goods(model: Instance, shop: ShopSpot, frame: CFrame, width: number, depth: number)
	-- Two shelves on the back wall with little boxes in the shop's colors
	for row, y in { 4.9, 7.3 } do
		sp(model, { Name = "Shelf", Size = Vector3.new(width - 3, 0.35, 1.4), CFrame = frame * CFrame.new(0, y, depth - 1), Color = DARK_PLANK, Material = Enum.Material.WoodPlanks, CanCollide = false })
		for k = 1, 6 do
			local tint = shop.color:Lerp(Color3.new(1, 1, 1), ((k + row) % 3) * 0.25)
			sp(model, { Name = "Goods", Size = Vector3.new(1.3, 1 + ((k + row) % 2) * 0.4, 1), CFrame = frame * CFrame.new(-(width - 3) / 2 + (k - 0.5) * (width - 3) / 6, y + 0.9, depth - 1), Color = tint, CanCollide = false })
		end
	end
	-- On the counter: coins and an apple for the Shop, colored bars for the Trails
	for k = 1, 3 do
		local x = (k - 2) * 3.6
		if shop.ui == "Shop" and k < 3 then
			for h = 0, 2 do
				sp(model, { Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 1.7, 1.7), CFrame = frame * CFrame.new(x, 4.3 + h * 0.36, 0.9) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(255, 205, 60), Material = Enum.Material.Neon, CanCollide = false })
			end
		elseif shop.ui == "Shop" then
			sp(model, { Name = "Apple", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.7, CFrame = frame * CFrame.new(x, 4.8, 0.9), Color = rgb(225, 60, 60), CanCollide = false })
		else
			sp(model, { Name = "Bar", Size = Vector3.new(2.4, 0.5, 1.2), CFrame = frame * CFrame.new(x, 4.4, 0.9), Color = shop.color:Lerp(Color3.new(1, 1, 1), (k - 1) * 0.3), Material = Enum.Material.Neon, CanCollide = false })
		end
	end
end

local function buildShop(town: Instance, index: number)
	local shop = SHOPS[index]
	if shop.machine then
		buildMachine(town, index)
		return
	end
	local frame = Layout.shop(index)
	scaleFrame = frame
	local width, depth = Layout.SHOP_WIDTH, Layout.SHOP_DEPTH
	local model = Instance.new("Model")
	model.Name = shop.name
	local wall = shop.color:Lerp(Color3.new(1, 1, 1), 0.6)
	local dark = shop.color:Lerp(rgb(40, 36, 56), 0.3)
	-- Platform and floor
	sp(model, { Name = "Platform", Size = Vector3.new(width + 4, 0.5, depth + 5), CFrame = frame * CFrame.new(0, 0.25, (depth - 1) / 2), Color = STONE, Material = Enum.Material.Slate })
	sp(model, { Name = "Floor", Size = Vector3.new(width, 0.15, depth), CFrame = frame * CFrame.new(0, 0.58, depth / 2), Color = PLANK, Material = Enum.Material.WoodPlanks, CanCollide = false })
	-- Walls: the back one and the two sides (with a window each), a darker wooden foot all round
	sp(model, { Name = "Back", Size = Vector3.new(width, 9, 0.6), CFrame = frame * CFrame.new(0, 5, depth), Color = wall })
	sp(model, { Name = "BackFoot", Size = Vector3.new(width, 2.2, 0.7), CFrame = frame * CFrame.new(0, 1.6, depth - 0.05), Color = DARK_PLANK, Material = Enum.Material.WoodPlanks, CanCollide = false })
	for _, side in { -1, 1 } do
		local x = side * (width / 2 - 0.3)
		sp(model, { Name = "Side", Size = Vector3.new(0.6, 9, depth), CFrame = frame * CFrame.new(x, 5, depth / 2), Color = wall })
		sp(model, { Name = "SideFoot", Size = Vector3.new(0.7, 2.2, depth), CFrame = frame * CFrame.new(x, 1.6, depth / 2), Color = DARK_PLANK, Material = Enum.Material.WoodPlanks, CanCollide = false })
		sp(model, { Name = "WindowFrame", Size = Vector3.new(0.8, 3.8, 4.6), CFrame = frame * CFrame.new(x, 6, depth / 2), Color = CREAM, CanCollide = false })
		sp(model, { Name = "WindowGlass", Size = Vector3.new(0.4, 3.2, 4), CFrame = frame * CFrame.new(x, 6, depth / 2), Color = rgb(170, 220, 245), Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false })
		-- A front post with a cap, a lantern hanging beside it, and a flower box at its foot
		sp(model, { Name = "Post", Size = Vector3.new(1, 9.6, 1), CFrame = frame * CFrame.new(side * (width / 2 - 0.1), 5.3, -0.4), Color = CREAM })
		sp(model, { Name = "PostCap", Size = Vector3.new(1.4, 0.5, 1.4), CFrame = frame * CFrame.new(side * (width / 2 - 0.1), 10.3, -0.4), Color = DARK_PLANK, CanCollide = false })
		sp(model, { Name = "Lantern", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, CFrame = frame * CFrame.new(side * (width / 2 - 1.4), 8.5, -1.6), Color = rgb(255, 214, 120), Material = Enum.Material.Neon, CanCollide = false })
		sp(model, { Name = "FlowerBox", Size = Vector3.new(2.4, 1, 1.2), CFrame = frame * CFrame.new(side * (width / 2 + 1.6), 1, -1.2), Color = DARK_PLANK, Material = Enum.Material.WoodPlanks, CanCollide = false })
		for k, c in { rgb(90, 190, 90), rgb(255, 150, 190), rgb(90, 190, 90) } do
			sp(model, { Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, CFrame = frame * CFrame.new(side * (width / 2 + 1.6) + (k - 2) * 0.75, 1.8, -1.2), Color = c, CanCollide = false })
		end
	end
	-- The roof, its fascia in the shop's color with a cream line under it, and a scalloped valance
	sp(model, { Name = "Roof", Size = Vector3.new(width + 2.4, 0.7, depth + 4), CFrame = frame * CFrame.new(0, 10.5, (depth - 1) / 2), Color = dark })
	sp(model, { Name = "Fascia", Size = Vector3.new(width + 2.6, 1.4, 0.6), CFrame = frame * CFrame.new(0, 10, -2.6), Color = shop.color, CanCollide = false })
	sp(model, { Name = "FasciaLine", Size = Vector3.new(width + 2.6, 0.3, 0.7), CFrame = frame * CFrame.new(0, 9.2, -2.6), Color = CREAM, CanCollide = false })
	local scallops = 9
	for k = 1, scallops do
		local x = -(width + 2.6) / 2 + (k - 0.5) * (width + 2.6) / scallops
		sp(model, { Name = "Scallop", Shape = Enum.PartType.Ball, Size = Vector3.new((width + 2.6) / scallops * 0.98, 1.3, 0.5), CFrame = frame * CFrame.new(x, 8.7, -2.6), Color = if k % 2 == 1 then shop.color else Color3.new(1, 1, 1), CanCollide = false })
	end
	-- The counter: dark wood with a colored band along its front and a cream top that overhangs
	local counter = sp(model, { Name = "Counter", Size = Vector3.new(width - 2, 3.2, 2.4), CFrame = frame * CFrame.new(0, 2.1, 0.8), Color = PLANK, Material = Enum.Material.WoodPlanks })
	sp(model, { Name = "CounterBand", Size = Vector3.new(width - 2.2, 0.7, 0.2), CFrame = frame * CFrame.new(0, 3, -0.45), Color = shop.color, CanCollide = false })
	sp(model, { Name = "CounterTop", Size = Vector3.new(width - 1.6, 0.4, 3.2), CFrame = frame * CFrame.new(0, 3.9, 0.8), Color = CREAM, CanCollide = false })
	goods(model, shop, frame, width, depth)
	menuBoard(model, shop, Vector3.new(width - 4, 3.2, 0.4), Vector3.new(0, 6.5, -2.2), true)
	-- The name over it in big letters, floating high so it reads from the square
	local sign = sp(model, { Name = "Sign", Size = Vector3.one, CFrame = frame * CFrame.new(0, 17, depth / 2), Transparency = 1, CanCollide = false, CanQuery = false })
	bigName(sign, shop.emoji .. " " .. (shop.sign or shop.name), 22 * SCALE, 6.5 * SCALE)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = shop.name
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenUI", shop.ui)
	prompt.Parent = counter
	model.Parent = town
end

local function buildTown(world: Instance)
	local town = Instance.new("Model")
	town.Name = "Town"
	-- The square where players arrive (no fountain: room for the Mother Cube and the Heist Egg)
	disc(town, "Plaza", Layout.SQUARE_CENTER + Vector3.new(0, 0.1, 0), Layout.SQUARE_RADIUS, 0.3, PAVING, Enum.Material.Pavement)
	local sign = part(town, { Name = "Sign", Size = Vector3.one, Position = Layout.SQUARE_CENTER + Vector3.new(0, 18, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	label(sign, "🥚 Cubeling Nest", 22, 4, Vector3.zero)
	for index = 1, #SHOPS do
		buildShop(town, index)
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = Layout.SPAWN -- (facing the stalls)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = town
	town.Parent = world
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
	local backZ, extra0 = Layout.GARDEN_BACK, Layout.PEN_EXTRA -- (the garden is longer than wide: its pen)
	part(model, { Name = "Ground", Size = Vector3.new(size, 0.4, size + extra0), CFrame = at(0, 0.2, extra0 / 2), Color = GRASS, Material = Enum.Material.Grass })

	-- A low picket fence all round (open at the gate), with an invisible wall behind it nobody can jump
	local function fence(cf: CFrame, length: number, parent: Instance?)
		local into = parent or model
		for _, y in { 1.2, 2.6 } do
			part(into, { Name = "Rail", Size = Vector3.new(length, 0.35, 0.3), CFrame = cf * CFrame.new(0, y, 0), Color = WOOD, CanCollide = false })
		end
		-- (a ranch fence: two rails on a post every 20 studs, not a picket every two: the pickets were most
		-- of the world's parts)
		local posts = math.max(1, math.ceil(length / 20))
		for i = 0, posts do
			local x = -length / 2 + i * length / posts
			part(into, { Name = "Picket", Size = Vector3.new(0.9, 3.6, 0.9), CFrame = cf * CFrame.new(x, 1.7, 0), Color = rgb(250, 240, 222), CanCollide = false })
		end
		part(into, { Name = "Wall", Size = Vector3.new(length, Layout.FENCE_HEIGHT, 0.6), CFrame = cf * CFrame.new(0, Layout.FENCE_HEIGHT / 2, 0), Transparency = 1 })
	end
	for _, side in { -1, 1 } do
		fence(at(side * half, 0, extra0 / 2) * CFrame.Angles(0, math.rad(90), 0), size + extra0)
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

	-- The path from the gate across the yard and the hatching field to the pen's opening
	local field, pasture = Layout.FIELD, Layout.PASTURE
	local pathEnd = pasture.center.Z - pasture.size.Z / 2 + 2
	local pathLength = pathEnd + half
	part(model, { Name = "Path", Size = Vector3.new(Layout.PATH_WIDTH, 0.3, pathLength), CFrame = at(0, 0.85, -half + pathLength / 2), Color = PAVING, Material = Enum.Material.Pavement, CanCollide = false })

	-- The hatching field: the player sets eggs down only here (IslandService makes an invisible pad for each:
	-- GardenClient draws the egg and its timer there); no creature walks in it, so it stays clear
	part(model, { Name = "Field", Size = field.size + Vector3.new(0, 0.3, 0), CFrame = at(field.center.X, 0.45, field.center.Z), Color = rgb(132, 204, 104), Material = Enum.Material.Grass, CanCollide = false })
	local hatchSign = part(model, { Name = "HatcherySign", Size = Vector3.one, CFrame = at(0, 5, field.center.Z - field.size.Z / 2 + 1), Transparency = 1, CanCollide = false, CanQuery = false })
	label(hatchSign, "🥚 Hatching field: set your eggs down here", 16, 2, Vector3.zero)
	local nest = Layout.NEST_SIZE
	-- (the eggs set down on the grass: IslandService puts each one's pad in here)
	local eggs = Instance.new("Folder")
	eggs.Name = "Eggs"
	eggs.Parent = model

	-- The pen: a meadow at the back, behind a wooden fence, where the creatures live and roam
	part(model, { Name = "Pasture", Size = pasture.size + Vector3.new(0, 0.3, 0), CFrame = at(pasture.center.X, 0.5, pasture.center.Z), Color = rgb(108, 186, 92), Material = Enum.Material.Grass, CanCollide = false })
	local function hedge(cf: CFrame, length: number, parent: Instance?)
		part(parent or model, { Name = "Hedge", Size = Vector3.new(length, 1.6, 1.2), CFrame = cf * CFrame.new(0, 0.8, 0), Color = rgb(80, 150, 70), Material = Enum.Material.Grass, CanCollide = false })
	end
	-- (the pen's wooden fence: two rails between white posts)
	local function penFence(cf: CFrame, length: number, parent: Instance?)
		for _, y in { 1.2, 2.6 } do
			part(parent or model, { Name = "PenRail", Size = Vector3.new(length, 0.35, 0.3), CFrame = cf * CFrame.new(0, y, 0), Color = WOOD, CanCollide = false })
		end
		local posts = math.max(1, math.round(length / 8))
		for i = 0, posts do
			part(parent or model, { Name = "PenPost", Size = Vector3.new(0.9, 3.6, 0.9), CFrame = cf * CFrame.new(-length / 2 + i * length / posts, 1.7, 0), Color = rgb(250, 240, 222), CanCollide = false })
		end
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
		local stageBack = stage("Back" .. level, level, true)
		fence(at(0, 0, backZ + extra), size, stageBack)
		local before = IslandConfig.PASTURE_GROWTH[level - 1]
		if before then
			local grow = stage("Grow" .. level, level, false)
			local length, middle = extra - before, backZ + (before + extra) / 2
			part(grow, { Name = "Ground", Size = Vector3.new(size, 0.4, length), CFrame = at(0, 0.2, middle), Color = GRASS, Material = Enum.Material.Grass })
			part(grow, { Name = "Pasture", Size = Vector3.new(pasture.size.X, 0.3, length + 0.1), CFrame = at(px, 0.45, middle), Color = rgb(108, 186, 92), Material = Enum.Material.Grass, CanCollide = false })
			for _, side in { -1, 1 } do
				fence(at(side * half, 0, middle) * CFrame.Angles(0, math.rad(90), 0), length, grow)
			end
		end
		-- (how each part looks when shown)
		local stages: { Instance } = { stageBack }
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
	local fx, fz, fhx, fhz = field.center.X, field.center.Z, field.size.X / 2, field.size.Z / 2
	for _, s in { -1, 1 } do
		-- The pen's front: a wooden fence, open in the middle (its sides and back are the garden's)
		local piece = hx - Layout.PATH_WIDTH / 2 - 1
		penFence(at(px + s * (hx - piece / 2), 0, pz - hz), piece)
		-- The hatching field's front, along the yard (a low hedge, open where the path comes in)
		local front = fhx - Layout.PATH_WIDTH / 2 - 1
		hedge(at(fx + s * (fhx - front / 2), 0, fz - fhz), front)
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
	-- (flat on the ground, so anyone walks straight onto it: no step to climb)
	part(model, { Name = "TreadmillBase", Size = Vector3.new(11, 0.4, 5.4), CFrame = mill * CFrame.new(0, 0.1, 0), Color = rgb(70, 74, 86) })
	local belt = part(model, { Name = "Treadmill", Size = Vector3.new(10, 0.2, 4), CFrame = mill * CFrame.new(0, 0.4, 0), Color = rgb(40, 42, 50), Material = Enum.Material.Rubber })
	belt:AddTag("TreadmillBelt") -- (TreadmillClient moves slats along it)
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

	-- The yard's machines and barn (a model of their own, kept where it is)
	local back = Instance.new("Model")
	back.Name = "Back"
	back:SetAttribute("Shift", 0)
	back.Parent = model

	-- The incubators in the yard, left of the path: machines (bought one by one) where an egg hatches twice as
	-- fast as in a nest: a metal base, a glowing ring and a glass dome
	for k, spot in Layout.MACHINES do
		local slot = IslandConfig.MACHINE_SLOT + k
		local base = at(spot.X, 0, spot.Z)
		part(back, { Name = "MachineBase", Size = Vector3.new(7, 2, 7), CFrame = base * CFrame.new(0, 1, 0), Color = rgb(150, 160, 178), Material = Enum.Material.Metal })
		part(back, { Name = "MachineRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 6.4, 6.4), CFrame = base * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(90, 220, 255), Material = Enum.Material.Neon, CanCollide = false })
		local pad = part(back, {
			Name = "Incubator",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, nest - 1, nest - 1),
			CFrame = base * CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rgb(235, 240, 250),
			Material = Enum.Material.SmoothPlastic,
		})
		pad:SetAttribute("Island", index)
		pad:SetAttribute("Slot", slot)
		pad:SetAttribute("Machine", true)
		pad:AddTag("Incubator")
		part(back, { Name = "Dome", Shape = Enum.PartType.Ball, Size = Vector3.one * (nest + 0.5), CFrame = base * CFrame.new(0, 3.4, 0), Color = rgb(200, 235, 255), Material = Enum.Material.Glass, Transparency = 0.75, CanCollide = false, CanQuery = false })
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Use"
		prompt.ObjectText = ("Incubator ⚡×%d"):format(IslandConfig.MACHINE_SPEED)
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false -- GardenClient turns on the owner's
		prompt:SetAttribute("Island", index)
		prompt:SetAttribute("Slot", slot)
		prompt.Parent = pad
	end

	-- The storage barn in the yard's right corner, by the trough
	local barn = at(Layout.BARN.X, 0, Layout.BARN.Z) * CFrame.Angles(0, math.rad(90), 0) -- (its door toward the path)
	local shed = part(back, { Name = "Barn", Size = Vector3.new(9, 6, 7), CFrame = barn * CFrame.new(0, 3.4, 0), Color = rgb(206, 92, 72) })
	part(back, { Name = "BarnRoof", Size = Vector3.new(10.4, 1.6, 8.4), CFrame = barn * CFrame.new(0, 7.2, 0), Color = rgb(250, 238, 214) })
	part(back, { Name = "BarnDoor", Size = Vector3.new(3.4, 4.4, 0.3), CFrame = barn * CFrame.new(0, 2.6, -3.55), Color = rgb(250, 238, 214) })
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
	label(pastureSign, "🐾 Pen: your creatures live here", 14, 2, Vector3.zero)

	-- The owner's name over the gate
	local board = part(model, { Name = "OwnerSign", Size = Vector3.one, CFrame = Layout.gate(index) * CFrame.new(0, Layout.FENCE_HEIGHT + 2, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	label(board, "Free garden", 16, 3, Vector3.zero)

	-- The owner's avatar and name, high over the garden so it can be seen from far away (IslandService fills it
	-- in and shows it when the garden has an owner)
	local banner = part(model, { Name = "OwnerBanner", Size = Vector3.one, CFrame = Layout.garden(index) * CFrame.new(0, 60, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	local card = Instance.new("BillboardGui")
	card.Name = "Card"
	card.Size = UDim2.fromScale(36, 26)
	card.AlwaysOnTop = true
	card.MaxDistance = 3000
	card.Enabled = false
	local face = Instance.new("ImageLabel")
	face.Name = "Avatar"
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.fromScale(0.5, 0)
	face.Size = UDim2.fromScale(16 / 36, 16 / 26)
	face.BackgroundColor3 = rgb(40, 36, 56)
	face.BorderSizePixel = 0
	local faceRound = Instance.new("UICorner")
	faceRound.CornerRadius = UDim.new(0.5, 0)
	faceRound.Parent = face
	local faceStroke = Instance.new("UIStroke")
	faceStroke.Color = rgb(255, 221, 64)
	faceStroke.Thickness = 5
	faceStroke.Parent = face
	face.Parent = card
	local owner = Instance.new("TextLabel")
	owner.Name = "Owner"
	owner.AnchorPoint = Vector2.new(0.5, 1)
	owner.Position = UDim2.fromScale(0.5, 1)
	owner.Size = UDim2.fromScale(1, 8 / 26)
	owner.BackgroundTransparency = 1
	owner.TextScaled = true
	owner.Font = Enum.Font.LuckiestGuy
	owner.TextColor3 = rgb(255, 221, 64)
	owner.TextStrokeColor3 = rgb(20, 18, 30)
	owner.TextStrokeTransparency = 0
	owner.Text = ""
	owner.Parent = card
	card.Parent = banner

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

-- The ground under it all, the roads (north to the Wild's gate, south and the arc past the gardens' gates), and
-- invisible walls round it (open onto the Wild)
local function buildGrounds(world: Instance)
	local half, north, south = Layout.ground()
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
	local straight, arcs = Layout.roads()
	for _, r in straight do
		road(roads, r.a, r.b, r.width)
	end
	for _, a in arcs do
		arc(roads, a.radius, a.from, a.to, a.width)
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
	-- The paved strip along the gate's line, under the shops (a rectangular plaza as wide as their row)
	part(wild, { Name = "GatePlaza", Size = Vector3.new(Layout.GATE_PLAZA_HALF * 2, 0.3, Layout.GATE_PLAZA_DEPTH), Position = Vector3.new(gate.X, 0.12, gate.Z + Layout.GATE_PLAZA_DEPTH / 2), Color = PAVING, Material = Enum.Material.Pavement, CanCollide = false })
	-- The arch: as wide as the whole entrance of the Wild, a tower at each side, a green beam across and the
	-- name over it in big letters
	local half = Layout.WILD_WIDTH / 2
	for _, side in { -1, 1 } do
		part(wild, { Name = "GateTower", Size = Vector3.new(16, 56, 16), Position = gate + Vector3.new(side * (half - 8), 28, 0), Color = rgb(120, 116, 110), Material = Enum.Material.Slate })
		part(wild, { Name = "GateTowerTop", Size = Vector3.new(19, 4, 19), Position = gate + Vector3.new(side * (half - 8), 58, 0), Color = rgb(90, 160, 90) })
	end
	part(wild, { Name = "Arch", Size = Vector3.new(Layout.WILD_WIDTH, 10, 12), Position = gate + Vector3.new(0, 51, 0), Color = rgb(90, 160, 90) })
	local title = part(wild, { Name = "GateTitle", Size = Vector3.one, Position = gate + Vector3.new(0, 78, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	bigName(title, "🌿 THE WILD", 90, 18)
	local glow = part(wild, { Name = "GateGlow", Size = Vector3.new(Layout.WILD_WIDTH - 32, 46, 0.4), Position = gate + Vector3.new(0, 23, 0), Color = rgb(120, 255, 160), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false })
	glow.Transparency = 0.75
	for i, biome in WildConfig.BIOMES do
		local center = Layout.biome(i)
		part(wild, { Name = "BiomeGround", Size = Vector3.new(Layout.WILD_WIDTH, 0.3, Layout.BIOME_LENGTH), Position = center + Vector3.new(0, 0.15, 0), Color = biome.color, Material = Enum.Material.Grass })
		local sign = part(wild, { Name = "BiomeSign", Size = Vector3.new(0.8, 6, 0.8), Position = center + Vector3.new(Layout.ROAD_WIDTH / 2 + 2, 3, Layout.BIOME_LENGTH / 2 - 2), Color = WOOD_DARK })
		local open = Hatch.open(biome.tier)
		label(sign, if open then ("%s · ⚡ %s to escape"):format(biome.name, Format.abbrev(Wild.needs(biome))) else biome.name .. " · 🔒 Coming Soon", 18, 2.6, Vector3.new(0, 5, 0))
		if not open then
			-- (the first closed biome is walled off, with a big sign; nothing in it until it opens)
			if Hatch.open(biome.tier - 1) then
				local edge = center + Vector3.new(0, 0, Layout.BIOME_LENGTH / 2)
				local wall = part(wild, { Name = "ComingSoon", Size = Vector3.new(Layout.WILD_WIDTH, 16, 2), Position = edge + Vector3.new(0, 8, 0), Color = rgb(60, 60, 80), Transparency = 0.15 })
				local board = Instance.new("SurfaceGui")
				board.Face = Enum.NormalId.Back
				board.PixelsPerStud = 8
				board.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud -- (else PixelsPerStud is ignored and the text is stretched to the part's shape)
				local text = Instance.new("TextLabel")
				text.Size = UDim2.fromScale(1, 1)
				text.BackgroundTransparency = 1
				text.Text = "🔒 COMING SOON"
				text.TextScaled = true
				text.Font = Enum.Font.LuckiestGuy
				text.TextColor3 = rgb(255, 210, 80)
				text.TextStrokeColor3 = rgb(28, 24, 40)
				text.TextStrokeTransparency = 0
				text.Parent = board
				board.Parent = wall
			end
			continue
		end
		local egg = Hatch.egg(biome.tier)
		for k = 1, WildConfig.NESTS do
			local spot = Layout.wildNest(i, k, WildConfig.NESTS)
			-- (a nest in its biome's look: straw, petals, leaves, shells, stones, snow, lava, ice...)
			Nest.build(wild, CFrame.new(spot + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, k, 0), biome.tier, 1.3)
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

return WorldService
