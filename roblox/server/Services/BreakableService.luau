-- Coin sources in every zone. Coins inside a source go to whoever collects them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Breakables = require(Shared.Config.Breakables)
local World1 = require(Shared.Config.World1)
local MapLayout = require(Shared.Logic.MapLayout)
local Signal = require(Shared.Signal)

export type Source = {
	name: string,
	part: BasePart,
	zoneId: number,
	kind: Breakables.BreakableKind,
	coinsMax: number,
	coinsLeft: number,
	alive: boolean,
	contributors: { [Player]: number },
}

local BreakableService = {}

local sources: { [string]: Source } = {}
local byZone: { [number]: { Source } } = {}
local folder: Folder

-- Fired with the live source table (not a copy) and who collected from it.
BreakableService.Broken = Signal.new() :: Signal.Signal<Source, { [Player]: number }>

local function buildPart(kind: Breakables.BreakableKind, position: Vector3, name: string): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = kind.size
	p.Color = kind.color
	p.Material = if kind.id == "Pile" then Enum.Material.Foil else Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = CFrame.new(position + Vector3.new(0, kind.size.Y / 2, 0))
	p:SetAttribute("Kind", kind.id)
	p:AddTag("Breakable")

	if kind.isChest then
		local trim = Instance.new("Part")
		trim.Name = "Trim"
		trim.Anchored = true
		trim.CanCollide = false
		trim.CanQuery = false
		trim.Size = Vector3.new(kind.size.X + 0.2, kind.size.Y * 0.15, kind.size.Z + 0.2)
		trim.CFrame = p.CFrame
		trim.Color = Color3.fromRGB(245, 197, 66)
		trim.Material = Enum.Material.Foil
		trim.Parent = p
	end

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 120
	click.Parent = p

	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(110, 34)
	gui.StudsOffset = Vector3.new(0, kind.size.Y / 2 + 1.8, 0)
	gui.MaxDistance = 70
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(1, 0.32)
	bar.Position = UDim2.fromScale(0, 0.68)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(245, 197, 66)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local text = Instance.new("TextLabel")
	text.Name = "Coins"
	text.Size = UDim2.fromScale(1, 0.66)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Parent = gui
	gui.Parent = p
	return p
end

local function setVisible(source: Source, visible: boolean)
	local p = source.part
	p.Transparency = if visible then 0 else 1
	p.CanCollide = visible
	p.CanQuery = visible
	for _, child in p:GetChildren() do
		if child:IsA("BasePart") then
			child.Transparency = if visible then 0 else 1
		elseif child:IsA("BillboardGui") then
			child.Enabled = visible
		elseif child:IsA("ClickDetector") then
			child.MaxActivationDistance = if visible then 120 else 0
		end
	end
end

local function sync(source: Source)
	source.part:SetAttribute("CoinsLeft", source.coinsLeft)
	source.part:SetAttribute("CoinsMax", source.coinsMax)
	source.part:SetAttribute("Alive", source.alive)
end

function BreakableService.build()
	folder = Instance.new("Folder")
	folder.Name = "Breakables"
	for _, zone in World1.zones do
		if zone.id == 0 then
			continue
		end
		byZone[zone.id] = {}
		local total = 0
		for _, kind in Breakables.list do
			total += kind.count
		end
		local spots = MapLayout.sourceSpots(zone.id, total, zone.id * 7919 + 13)
		local index = 0
		for _, kind in Breakables.list do
			for _ = 1, kind.count do
				index += 1
				local spot = spots[index]
				if not spot then
					break
				end
				local name = ("B_%d_%d"):format(zone.id, index)
				local coins = kind.coins * zone.scale
				local source: Source = {
					name = name,
					part = buildPart(kind, spot, name),
					zoneId = zone.id,
					kind = kind,
					coinsMax = coins,
					coinsLeft = coins,
					alive = true,
					contributors = {},
				}
				source.part:SetAttribute("ZoneId", zone.id)
				sync(source)
				source.part.Parent = folder
				sources[name] = source
				table.insert(byZone[zone.id], source)
			end
		end
	end
	folder.Parent = workspace
end

function BreakableService.get(name: string): Source?
	return sources[name]
end

function BreakableService.inZone(zoneId: number): { Source }
	return byZone[zoneId] or {}
end

function BreakableService.aliveInZone(zoneId: number): { Source }
	local alive = {}
	for _, source in BreakableService.inZone(zoneId) do
		if source.alive then
			table.insert(alive, source)
		end
	end
	return alive
end

-- Takes up to `amount` coins out of the source for `player`. Returns the raw coins taken and whether it broke.
function BreakableService.collect(source: Source, player: Player, amount: number): (number, boolean)
	if not source.alive or amount <= 0 then
		return 0, false
	end
	local taken = math.min(amount, source.coinsLeft)
	source.coinsLeft -= taken
	source.contributors[player] = (source.contributors[player] or 0) + taken
	local broke = source.coinsLeft <= 1e-9
	if broke then
		source.alive = false
		source.coinsLeft = 0
		setVisible(source, false)
		local contributors = source.contributors
		source.contributors = {}
		BreakableService.Broken:Fire(source, contributors)
	end
	sync(source)
	return taken, broke
end

-- Brings a broken source back after `delay` seconds.
function BreakableService.respawn(source: Source, delay: number)
	task.delay(delay, function()
		source.coinsLeft = source.coinsMax
		source.alive = true
		setVisible(source, true)
		sync(source)
	end)
end

-- Closest alive source in a zone, or nil.
function BreakableService.nearest(zoneId: number, position: Vector3, range: number): Source?
	local best: Source? = nil
	local bestDistance = range
	for _, source in BreakableService.inZone(zoneId) do
		if source.alive then
			local distance = (source.part.Position - position).Magnitude
			if distance < bestDistance then
				best = source
				bestDistance = distance
			end
		end
	end
	return best
end

return BreakableService
