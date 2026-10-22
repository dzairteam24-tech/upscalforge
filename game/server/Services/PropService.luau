--!strict
-- Decor (art/models/Decor.glb, Config/PropLooks): each garden has, in its corners, props of one of the worlds the
-- creatures come from (meadow, forest, beach...), and each open biome of the Wild is dressed in its own theme's
-- props. The props model is loaded by ArtService (Config/Art PROPS_ASSET_ID); without it, no decor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared.Config.Island)
local PropLooks = require(Shared.Config.PropLooks)
local WildConfig = require(Shared.Config.Wild)
local Hatch = require(Shared.Logic.Hatch)
local Layout = require(Shared.Logic.Layout)

local WorldService = require(script.Parent.WorldService)

local PropService = {}

-- Each island's world (the "zones" in PropLooks: 1 meadow, 3 forest, 4 beach, 6 desert, 7 snow, 9 ice)
local THEMES = { 1, 3, 4, 6, 7, 9, 8, 10 }
local SPOTS = 4 -- props in each garden
local WILD_SPOTS = 14 -- props in each open biome of the Wild (kept low: no decor lag, as the docs ask)
local WILD_CLEAR = 12 -- studs to keep clear of a nest, a biome's sign and its guardian's home (its middle)

type Entry = { look: PropLooks.Look, source: BasePart }

-- The newest Prop__<Name> part of each prop anywhere in ReplicatedStorage
local function findSources(): { [string]: BasePart }
	local found: { [string]: BasePart } = {}
	for _, child in ReplicatedStorage:GetChildren() do
		for _, d in child:GetDescendants() do
			if d:IsA("BasePart") then
				local name = string.match(d.Name, "^Prop__(%w+)") or (if d.Parent then string.match(d.Parent.Name, "^Prop__(%w+)") else nil)
				if name and not found[name] then
					found[name] = d
				end
			end
		end
	end
	return found
end

-- How tall a part stands with this rotation (its box's extent along the world's Y)
local function standingHeight(rotation: CFrame, size: Vector3): number
	return math.abs(rotation.RightVector.Y) * size.X + math.abs(rotation.UpVector.Y) * size.Y + math.abs(rotation.LookVector.Y) * size.Z
end

-- A copy of a prop standing on the ground at `at`, `scale` times its designed size
local function spawnFrom(entry: Entry, at: CFrame, scale: number): BasePart
	local source, look = entry.source, entry.look
	local importScale = source.Size.Magnitude / look.size.Magnitude -- (Studio may scale or turn the import)
	local prop = source:Clone()
	for _, child in prop:GetChildren() do
		if not (child:IsA("DataModelMesh") or child:IsA("SurfaceAppearance")) then
			child:Destroy()
		end
	end
	prop.Name = look.name
	prop.Size = source.Size / importScale * scale
	prop.Anchored = true
	prop.CanCollide = false
	prop.CanQuery = false
	prop.CanTouch = false
	local rotation = at.Rotation * source.CFrame.Rotation
	prop.CFrame = CFrame.new(at.Position + Vector3.new(0, standingHeight(rotation, prop.Size) / 2, 0)) * rotation
	return prop
end

local function pick(kit: { Entry }, rng: Random): Entry
	local total = 0
	for _, entry in kit do
		total += entry.look.weight
	end
	local roll = rng:NextNumber(0, total)
	for _, entry in kit do
		roll -= entry.look.weight
		if roll <= 0 then
			return entry
		end
	end
	return kit[#kit]
end

-- The spots in a garden (its frame's space): its corners (the barn has one)
local function spots(): { Vector3 }
	local corner = Layout.GARDEN_SIZE / 2 - 2.5
	return {
		Vector3.new(-corner, 0, corner),
		Vector3.new(corner, 0, -corner),
		Vector3.new(-corner, 0, -corner),
	}
end

function PropService.decorate()
	local sources = findSources()
	for index = 1, IslandConfig.ISLANDS do
		local island = WorldService.island(index)
		if not island or island:FindFirstChild("Props") then
			continue
		end
		local theme = THEMES[(index - 1) % #THEMES + 1]
		local kit: { Entry } = {}
		for _, look in PropLooks do
			local source = sources[look.name]
			if source and table.find(look.zones, theme) then
				table.insert(kit, { look = look, source = source })
			end
		end
		if #kit == 0 then
			continue
		end
		local rng = Random.new(index * 131)
		local folder = Instance.new("Model")
		folder.Name = "Props"
		local frame = Layout.garden(index)
		for i, spot in spots() do
			if i > SPOTS then
				break
			end
			local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			local prop = spawnFrom(pick(kit, rng), CFrame.new(frame:PointToWorldSpace(spot)) * yaw, rng:NextNumber(0.4, 0.55))
			prop.Parent = folder
		end
		folder.Parent = island
	end
end

-- Whether a spot in a biome stands clear of the things players run to: its nests, its sign (by the road, at
-- its near end) and its middle, where its guardian sleeps
local function wildClear(i: number, at: Vector3): boolean
	for k = 1, WildConfig.NESTS do
		if (at - Layout.wildNest(i, k)).Magnitude < WILD_CLEAR then
			return false
		end
	end
	local center = Layout.biome(i)
	local sign = center + Vector3.new(Layout.ROAD_WIDTH / 2 + 2, 0, Layout.BIOME_LENGTH / 2 - 2)
	return (at - sign).Magnitude >= WILD_CLEAR and (at - center).Magnitude >= WILD_CLEAR
end

-- The Wild in its finery: every open biome gets its own theme's props (Config/Wild's `theme`, the zones in
-- PropLooks) scattered off its road, so each map reads as its own world the moment a player runs into it.
-- Seeded per biome, so every server dresses them the same. Called again when the props model lands.
function PropService.decorateWild()
	local world = workspace:FindFirstChild("World")
	local wild = world and world:FindFirstChild("Wild")
	if not wild or wild:FindFirstChild("Props") then
		return
	end
	local sources = findSources()
	if next(sources) == nil then
		return -- (no props model yet: ArtService calls this again when it lands)
	end
	local folder = Instance.new("Model")
	folder.Name = "Props"
	for i, biome in WildConfig.BIOMES do
		if not Hatch.open(biome.tier) then
			continue -- (Coming Soon: nothing in it until it opens)
		end
		local kit: { Entry } = {}
		for _, look in PropLooks do
			local source = sources[look.name]
			if source and table.find(look.zones, biome.theme) then
				table.insert(kit, { look = look, source = source })
			end
		end
		if #kit == 0 then
			continue
		end
		local center = Layout.biome(i)
		local rng = Random.new(i * 977 + 13)
		local placed, tries = 0, 0
		while placed < WILD_SPOTS and tries < WILD_SPOTS * 10 do
			tries += 1
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local at = center + Vector3.new(
				side * rng:NextNumber(Layout.ROAD_WIDTH / 2 + 6, Layout.WILD_WIDTH / 2 - 10),
				0,
				rng:NextNumber(-Layout.BIOME_LENGTH / 2 + 10, Layout.BIOME_LENGTH / 2 - 10)
			)
			if not wildClear(i, at) then
				continue
			end
			local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			local prop = spawnFrom(pick(kit, rng), CFrame.new(at) * yaw, rng:NextNumber(0.7, 1))
			prop.Parent = folder
			placed += 1
		end
	end
	if #folder:GetChildren() == 0 then
		folder:Destroy()
		return
	end
	folder.Parent = wild
end

return PropService
