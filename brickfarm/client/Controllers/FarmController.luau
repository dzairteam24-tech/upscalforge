--!strict
-- The farms on this phone. Builds every crop of the village from its tile's attributes (what, and when planted),
-- brick by brick (Logic/CropModel), and keeps it alive: it pops up a size each time it grows, sways in the wind,
-- and bobs when it's ready. Tapping (or dragging across) your own tiles plants the chosen seed or harvests what's
-- ready; the harvested bricks fly to you.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CropModel = require(Shared.Logic.CropModel)
local Crops = require(Shared.Config.Crops)
local Format = require(Shared.Logic.Format)
local Growth = require(Shared.Logic.Growth)
local Land = require(Shared.Logic.Land)
local Layout = require(Shared.Logic.Layout)
local Net = require(Shared.Net)

local Effects = require(script.Parent.Effects)
local Store = require(script.Parent.Parent.Store)

local FarmController = {}

local LOCAL = Players.LocalPlayer
local POP_TIME = 0.4
local NEAR = 140 -- studs: crops nearer the camera than this sway

FarmController.selected = "carrot" -- the seed a tap plants
FarmController.onSelected = nil :: ((key: string) -> ())?
FarmController.onTileInfo = nil :: ((text: string, at: Vector3) -> ())?

type View = {
	tile: BasePart,
	crop: string,
	stage: number,
	model: Model,
	parts: { { part: BasePart, at: Vector3, size: Vector3 } },
	popAt: number, -- os.clock() its pop started
	phase: number,
	still: boolean, -- placed at rest (it's far away, nothing to animate)
}

local views: { [BasePart]: View } = {}
local tiles: { BasePart } = {}
local hidden: { [BasePart]: number } = {} -- harvested here, waiting for the server to agree (os.clock())
local folder: Folder? = nil
local pressing = false
local touched: { [BasePart]: boolean } = {} -- the tiles this press has already done

-- an ease that overshoots a little and settles (a pop)
local function backOut(t: number): number
	local c = 1.9
	t -= 1
	return 1 + (c + 1) * t * t * t + c * t * t
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function myFarm(): number?
	local data = Store.data
	return if data then data.farm else nil
end

local function build(tile: BasePart, crop: string, stage: number): View
	local model = Instance.new("Model")
	model.Name = crop
	local parts = {}
	for _, b in CropModel.bricks(crop, stage) do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Plastic
		p.Color = b.color
		p.Size = b.size
		p.TopSurface = if b.size.X >= 0.9 and b.size.Z >= 0.9 then Enum.SurfaceType.Studs else Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if b.round then
			p.Shape = Enum.PartType.Ball
		end
		p.Parent = model
		table.insert(parts, { part = p, at = b.at, size = b.size })
	end
	model.Parent = folder
	return { tile = tile, crop = crop, stage = stage, model = model, parts = parts, popAt = os.clock(), phase = math.random() * 6.28, still = false }
end

-- Puts a crop's bricks where they are this moment: `s` its size (0..1+, for the pop), `lean` how far the wind tips it
local function place(view: View, s: number, lean: number, bob: number)
	local base = view.tile.CFrame * CFrame.new(0, view.tile.Size.Y / 2, 0)
	local tip = base * CFrame.Angles(lean, 0, lean * 0.6)
	for _, item in view.parts do
		local at = item.at * s
		item.part.Size = item.size * math.max(0.05, s)
		item.part.CFrame = tip * CFrame.new(at.X, at.Y + bob, at.Z)
	end
end

local function remove(tile: BasePart)
	local view = views[tile]
	if view then
		view.model:Destroy()
		views[tile] = nil
	end
end

-- Every tile of every farm (farms grow, so this is looked at again each time)
local function scan()
	table.clear(tiles)
	local village = workspace:FindFirstChild("Village")
	if not village then
		return
	end
	for _, farm in village:GetChildren() do
		local tileFolder = farm:FindFirstChild("Tiles")
		if tileFolder then
			for _, tile in tileFolder:GetChildren() do
				if tile:IsA("BasePart") then
					table.insert(tiles, tile)
				end
			end
		end
	end
	-- (crops of tiles that are gone: gone too)
	for tile in views do
		if not tile.Parent then
			remove(tile)
		end
	end
end

-- Every quarter second: each tile's crop is the right one at the right stage
local function refresh()
	scan()
	local t = now()
	for _, tile in tiles do
		local crop = tile:GetAttribute("Crop") :: string?
		local planted = tile:GetAttribute("Planted") :: number?
		if hidden[tile] and (crop == "" or os.clock() - hidden[tile] > 2) then
			hidden[tile] = nil
		end
		if not crop or crop == "" or not Crops.byKey[crop] or hidden[tile] then
			remove(tile)
		else
			local stage = Growth.stage(planted or 0, Crops.byKey[crop].grow, t)
			local view = views[tile]
			if not view or view.crop ~= crop or view.stage ~= stage then
				remove(tile)
				local fresh = build(tile, crop, stage)
				views[tile] = fresh
				place(fresh, 0.05, 0, 0)
				if view then
					Effects.grew(tile.CFrame.Position)
				end
			end
		end
	end
end

-- Every frame: pops and the wind
local function animate()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local clock = os.clock()
	for _, view in views do
		local popping = clock - view.popAt < POP_TIME
		local near = (view.tile.CFrame.Position - eye).Magnitude < NEAR
		if popping or near then
			local s = if popping then backOut((clock - view.popAt) / POP_TIME) else 1
			local ready = view.stage >= 4
			local lean = if view.stage >= 2 then math.sin(clock * 1.7 + view.phase) * (if ready then 0.07 else 0.04) else 0
			local bob = if ready then (math.sin(clock * 3 + view.phase) + 1) * 0.12 else 0
			place(view, s, lean, bob)
			view.still = false
		elseif not view.still then
			place(view, 1, 0, 0)
			view.still = true
		end
	end
end

-- What a tap on one of their tiles does
local function act(tile: BasePart)
	if touched[tile] then
		return
	end
	touched[tile] = true
	local data = Store.data
	local n = tile:GetAttribute("Key") :: string
	if not data then
		return
	end
	local crop = tile:GetAttribute("Crop") :: string
	if crop ~= "" and Crops.byKey[crop] then
		local planted = tile:GetAttribute("Planted") :: number
		local t = now()
		if Growth.ready(planted, Crops.byKey[crop].grow, t) then
			-- harvest: gone here at once (the server agrees in a moment)
			local view = views[tile]
			Effects.harvest(tile, crop, if view then view.model else nil)
			if view then
				views[tile] = nil
			end
			hidden[tile] = os.clock()
			Net.event("Tile"):FireServer(n)
		elseif FarmController.onTileInfo then
			FarmController.onTileInfo(("%s: ready in %s"):format(Crops.byKey[crop].name, Format.clock(Growth.left(planted, Crops.byKey[crop].grow, t))), tile.CFrame.Position)
		end
		return
	end
	local key = FarmController.selected
	if (data.seeds[key] or 0) > 0 then
		Net.event("Tile"):FireServer(n, key)
		Effects.planted(tile.CFrame.Position)
	elseif FarmController.onTileInfo then
		FarmController.onTileInfo("No seeds: buy some in SEEDS", tile.CFrame.Position)
	end
end

-- Buying land: while it's on, every lot they could buy shows as a see-through plate with its price; tapping one
-- buys it
FarmController.landMode = false
local ghosts: Folder? = nil

local function buildGhosts()
	if ghosts then
		ghosts:Destroy()
		ghosts = nil
	end
	local data = Store.data
	local farm = myFarm()
	if not FarmController.landMode or not data or not farm then
		return
	end
	local g = Instance.new("Folder")
	g.Name = "LandForSale"
	local price = Format.short(data.lotCost)
	for _, spot in Land.frontier(data.lots) do
		local plate = Instance.new("Part")
		plate.Name = "Lot"
		plate.Anchored = true
		plate.CanCollide = false
		plate.CastShadow = false
		plate.Size = Vector3.new(Layout.LOT_SIZE - 1, 0.4, Layout.LOT_SIZE - 1)
		plate.CFrame = Layout.lot(farm, spot.cx, spot.cz) * CFrame.new(0, 0.4, 0)
		plate.Color = Color3.fromRGB(255, 200, 40)
		plate.Material = Enum.Material.Plastic
		plate.Transparency = 0.45
		plate:SetAttribute("Cx", spot.cx)
		plate:SetAttribute("Cz", spot.cz)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 8
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Text = "+ " .. price
		label.Parent = gui
		gui.Parent = plate
		plate.Parent = g
	end
	g.Parent = workspace
	ghosts = g
end

function FarmController.setLandMode(on: boolean)
	FarmController.landMode = on
	buildGhosts()
end

-- The tile of their own farm (or, buying land, the lot for sale) under a point of the screen
local function tileUnder(screen: Vector2): BasePart?
	local camera = workspace.CurrentCamera
	local farm = myFarm()
	if not camera or not farm then
		return nil
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local village = workspace:FindFirstChild("Village")
	local farmModel = village and village:FindFirstChild("Farm" .. farm)
	local tileFolder = farmModel and farmModel:FindFirstChild("Tiles")
	if not tileFolder then
		return nil
	end
	params.FilterDescendantsInstances = if ghosts then { tileFolder, ghosts } else { tileFolder }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	return if hit and hit.Instance:IsA("BasePart") then hit.Instance else nil
end

-- Keeps the chosen seed one they have
local function keepSelection()
	local data = Store.data
	if not data then
		return
	end
	if (data.seeds[FarmController.selected] or 0) > 0 then
		return
	end
	for i = #Crops.LIST, 1, -1 do
		local key = Crops.LIST[i].key
		if (data.seeds[key] or 0) > 0 then
			FarmController.select(key)
			return
		end
	end
end

function FarmController.select(key: string)
	FarmController.selected = key
	if FarmController.onSelected then
		FarmController.onSelected(key)
	end
end

function FarmController.init()
	local f = Instance.new("Folder")
	f.Name = "Crops"
	f.Parent = workspace
	folder = f
	workspace:WaitForChild("Village", 30)
	scan()
	Store.onChanged(keepSelection)
	Store.onChanged(function()
		if FarmController.landMode then
			buildGhosts()
		end
	end)
	Net.event("Harvested").OnClientEvent:Connect(function(_n: number, key: string, amount: number, xp: number)
		Effects.gained(key, amount, xp)
	end)
	Net.event("LevelUp").OnClientEvent:Connect(function(level: number, unlocked: { string })
		Effects.levelUp(level, unlocked)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressing = true
			table.clear(touched)
			local tile = tileUnder(Vector2.new(input.Position.X, input.Position.Y))
			if tile and tile:GetAttribute("Cx") ~= nil then
				Net.event("Expand"):FireServer(tile:GetAttribute("Cx"), tile:GetAttribute("Cz"))
				pressing = false
			elseif tile then
				act(tile)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if pressing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local tile = tileUnder(Vector2.new(input.Position.X, input.Position.Y))
			if tile and tile:GetAttribute("Cx") == nil then
				act(tile)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressing = false
			table.clear(touched)
		end
	end)

	task.spawn(function()
		while true do
			refresh()
			task.wait(0.25)
		end
	end)
	RunService.RenderStepped:Connect(animate)
end

-- (for the tests)
FarmController._refresh = refresh
FarmController._animate = animate
FarmController._act = act
FarmController._views = views
FarmController._ghosts = function()
	return ghosts
end

return FarmController
