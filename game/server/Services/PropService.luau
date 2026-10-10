--!strict
-- Decor (art/models/Decor.glb, Config/PropLooks): each island is framed by the props of one of the worlds the
-- creatures come from (meadow, forest, beach...), along its back and sides, clear of the incubators and the
-- creatures. The props model is loaded by ArtService (Config/Art PROPS_ASSET_ID); without it, no decor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared.Config.Island)
local PropLooks = require(Shared.Config.PropLooks)
local Layout = require(Shared.Logic.Layout)

local WorldService = require(script.Parent.WorldService)

local PropService = {}

-- Each island's world (the "zones" in PropLooks: 1 meadow, 3 forest, 4 beach, 6 desert, 7 snow, 9 ice)
local THEMES = { 1, 3, 4, 6, 7, 9, 8, 10 }
local SPOTS = 9 -- props round each island

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

-- The spots round an island (its frame's space): along the back edge and down both sides
local function spots(): { Vector3 }
	local half = Layout.GARDEN_SIZE / 2 - 4
	local list = {}
	for i = 0, 2 do
		table.insert(list, Vector3.new((i - 1) * 18, 0, half))
	end
	for _, side in { -1, 1 } do
		for i = 0, 2 do
			table.insert(list, Vector3.new(side * half, 0, half - 6 - i * 15))
		end
	end
	return list
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
			local prop = spawnFrom(pick(kit, rng), CFrame.new(frame:PointToWorldSpace(spot)) * yaw, rng:NextNumber(0.55, 0.8))
			prop.Parent = folder
		end
		folder.Parent = island
	end
end

return PropService
