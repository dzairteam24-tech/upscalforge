-- Coin sources in every zone. Coins inside a source go to whoever collects them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Breakables = require(Shared.Config.Breakables)
local World1 = require(Shared.Config.World1)
local PetModel = require(Shared.PetModel)
local Signal = require(Shared.Signal)

-- A Big or a guardian: a creature you collect from like a source.
export type Special = {
	type: string, -- "Big" | "Guardian"
	pet: { s: string, v: string, z: string },
	expires: number, -- os.clock() when it leaves
	eligible: { [Player]: boolean }, -- guardians: players whose fight counts (tame roll + cooldown)
}

export type Source = {
	name: string,
	part: BasePart,
	zoneId: number,
	kind: Breakables.BreakableKind,
	coinsMax: number,
	coinsLeft: number,
	alive: boolean,
	contributors: { [Player]: number },
	special: Special?,
}

local BreakableService = {}

local sources: { [string]: Source } = {}
local byZone: { [number]: { Source } } = {}
local folder: Folder

-- Fired with the live source table (not a copy) and who collected from it.
BreakableService.Broken = Signal.new() :: Signal.Signal<Source, { [Player]: number }>

local clickHandler: ((Player, BasePart) -> ())? = nil
local specialCount = 0

local unbound: { { detector: ClickDetector, part: BasePart } } = {}

local function bindClick(detector: ClickDetector, part: BasePart)
	detector.MouseClick:Connect(function(player)
		if clickHandler then
			clickHandler(player, part)
		end
	end)
end

-- GameService handles clicks (target + tap damage). Detectors made before this call are bound now.
function BreakableService.setClickHandler(fn: (Player, BasePart) -> ())
	clickHandler = fn
	for _, entry in unbound do
		bindClick(entry.detector, entry.part)
	end
	unbound = {}
end

local function addInfo(p: BasePart, height: number, width: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(width, 34)
	gui.StudsOffset = Vector3.new(0, height / 2 + 1.8, 0)
	gui.MaxDistance = 90
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
end

local function addClick(p: BasePart)
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 120
	click.Parent = p
	if clickHandler then
		bindClick(click, p)
	else
		table.insert(unbound, { detector = click, part = p })
	end
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

-- The breakables' folder. The zones' coin sources are gone (the team earns coins by itself now, GameService),
-- so only specials live here: the World Boss in the Hub.
function BreakableService.build()
	folder = Instance.new("Folder")
	folder.Name = "Breakables"
	for _, zone in World1.zones do
		byZone[zone.id] = {}
	end
	folder.Parent = workspace
end

function BreakableService.get(name: string): Source?
	return sources[name]
end

function BreakableService.inZone(zoneId: number): { Source }
	return byZone[zoneId] or {}
end

-- Alive regular sources (Bigs and guardians are left out so instant-break skills can't one-shot them).
function BreakableService.aliveInZone(zoneId: number): { Source }
	local alive = {}
	for _, source in BreakableService.inZone(zoneId) do
		if source.alive and not source.special then
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

-- Brings a broken source back after `delay` seconds. A newer respawn call (Time Skip) cancels older ones.
local respawnTokens: { [Source]: number } = {}
function BreakableService.respawn(source: Source, delay: number)
	local token = (respawnTokens[source] or 0) + 1
	respawnTokens[source] = token
	task.delay(delay, function()
		if respawnTokens[source] ~= token or source.alive then
			return
		end
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

-- Spawns a Big or a guardian: an invisible click box with the creature model inside.
function BreakableService.spawnSpecial(
	zoneId: number,
	specialType: string,
	pet: { s: string, v: string, z: string },
	position: Vector3,
	coins: number,
	lifetime: number
): Source
	specialCount += 1
	local built = PetModel.build(pet)
	local width = built.radius * 2.4
	local kind: Breakables.BreakableKind = {
		id = specialType,
		coins = coins,
		respawn = 0,
		count = 0,
		size = Vector3.new(width, built.height, width),
		color = Color3.new(1, 1, 1),
		isChest = false,
		isPile = false,
	}
	local name = ("S_%d_%d"):format(zoneId, specialCount)
	local box = Instance.new("Part")
	box.Name = name
	box.Anchored = true
	box.CanCollide = false
	box.Transparency = 1
	box.Size = kind.size
	box.CFrame = CFrame.new(position + Vector3.new(0, built.height / 2, 0))
	box:SetAttribute("Kind", specialType)
	box:SetAttribute("ZoneId", zoneId)
	box:AddTag("Breakable")
	addClick(box)
	addInfo(box, built.height, 170)
	local facing = CFrame.new(box.CFrame.Position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	PetModel.place(built, facing)
	built.model.Parent = box

	local source: Source = {
		name = name,
		part = box,
		zoneId = zoneId,
		kind = kind,
		coinsMax = coins,
		coinsLeft = coins,
		alive = true,
		contributors = {},
		special = { type = specialType, pet = pet, expires = os.clock() + lifetime, eligible = {} },
	}
	sync(source)
	box.Parent = folder
	sources[name] = source
	byZone[zoneId] = byZone[zoneId] or {}
	table.insert(byZone[zoneId], source)
	return source
end

-- Removes a Big or guardian for good.
function BreakableService.despawn(source: Source)
	sources[source.name] = nil
	local list = byZone[source.zoneId]
	local index = list and table.find(list, source)
	if list and index then
		table.remove(list, index)
	end
	source.alive = false
	source.part:Destroy()
end

function BreakableService.specials(): { Source }
	local out = {}
	for _, source in sources do
		if source.special then
			table.insert(out, source)
		end
	end
	return out
end

return BreakableService

