--!strict
-- Map props (art/blender/decor.py, art/models/Decor.glb; Config/PropLooks): textured models placed round
-- each tier's egg in the Egg Garden, the props of that tier's world (its "zones"). The props model is loaded by ArtService into
-- ReplicatedStorage (Config/Art PROPS_ASSET_ID), or imported there by hand: any model with parts named
-- Prop__<Name>. Without it the garden has none. The town's props (Town.glb) are placed by HubBuilder with
-- PropService.spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PropLooks = require(Shared.Config.PropLooks)

local WorldBuilder = require(script.Parent.WorldBuilder)

local PropService = {}

local PER_EGG = 4 -- props round each egg in the garden
local PROP_SCALE = 0.7 -- (smaller than in the old zones: they frame an egg)
local SIZE_JITTER = { 0.85, 1.2 }
local WAIT_FOR_MODEL = 60 -- seconds to wait for the props model to load

type Entry = { look: PropLooks.Look, source: BasePart }

local LOOKS: { [string]: PropLooks.Look } = {}
for _, look in PropLooks do
	LOOKS[look.name] = look
end

-- The newest Prop__<Name> part of each prop anywhere in ReplicatedStorage
local function findSources(): { [string]: BasePart }
	local found: { [string]: BasePart } = {}
	local children = ReplicatedStorage:GetChildren()
	for i = #children, 1, -1 do
		for _, d in children[i]:GetDescendants() do
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

-- A copy of a prop standing on the ground at `at` (turned by its yaw), `scale` times its designed size
local function spawnFrom(source: BasePart, look: PropLooks.Look, at: CFrame, scale: number): BasePart
	-- The import's own size for this prop (Studio may scale or turn it): back to the designed size
	local importScale = source.Size.Magnitude / look.size.Magnitude
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

-- A prop by name (any loaded model's Prop__<Name>) standing at `at`, or nil when it isn't loaded
function PropService.spawn(name: string, at: CFrame, scale: number?): BasePart?
	local look = LOOKS[name]
	local source = findSources()[name]
	if not (look and source) then
		return nil
	end
	return spawnFrom(source, look, at, scale or 1)
end

-- One of the kit's props, the rarer (big) ones picked less often
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

-- A few of a tier's props round its egg in the Egg Garden (behind it and to its sides, off the lawn)
local function place(zoneId: number, kit: { Entry }, parent: Instance)
	local egg = WorldBuilder.eggPositions[zoneId]
	if not egg then
		return
	end
	local rng = Random.new(zoneId * 131)
	local outward = (Vector3.new(egg.X, 0, egg.Z) - WorldBuilder.gardenCenter()) * Vector3.new(1, 0, 1)
	outward = if outward.Magnitude > 1 then outward.Unit else Vector3.new(0, 0, -1)
	local side = Vector3.new(outward.Z, 0, -outward.X)
	local folder = Instance.new("Model")
	folder.Name = "Props_" .. zoneId
	for i = 1, PER_EGG do
		local entry = pick(kit, rng)
		local across = (i - (PER_EGG + 1) / 2) * 7 + rng:NextNumber(-1.5, 1.5)
		local spot = Vector3.new(egg.X, 0, egg.Z) + outward * rng:NextNumber(9, 13) + side * across
		local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		local prop = spawnFrom(entry.source, entry.look, CFrame.new(spot) * yaw, rng:NextNumber(SIZE_JITTER[1], SIZE_JITTER[2]) * PROP_SCALE)
		prop.Parent = folder
	end
	folder.Parent = parent
end

local function decorate(sources: { [string]: BasePart })
	local world = workspace:WaitForChild("World")
	local kits: { [number]: { Entry } } = {}
	for _, look in PropLooks do
		local source = sources[look.name]
		if source then
			for _, zoneId in look.zones do
				kits[zoneId] = kits[zoneId] or {}
				table.insert(kits[zoneId], { look = look, source = source })
			end
		end
	end
	local garden = world:WaitForChild("EggGarden", 30)
	if not garden then
		return
	end
	for zoneId, kit in kits do
		if not garden:FindFirstChild("Props_" .. zoneId) then
			place(zoneId, kit, garden)
		end
	end
	print("[Props] placed in", (function()
		local ids = {}
		for zoneId in kits do
			table.insert(ids, tostring(zoneId))
		end
		table.sort(ids)
		return "zones " .. table.concat(ids, ", ")
	end)())
end

-- Whether a zone prop is loaded (not only the town's)
local function hasZoneProps(): boolean
	for name in findSources() do
		if LOOKS[name] and #LOOKS[name].zones > 0 then
			return true
		end
	end
	return false
end

function PropService.init()
	task.spawn(function()
		local deadline = os.clock() + WAIT_FOR_MODEL
		while not hasZoneProps() and os.clock() < deadline do
			task.wait(1)
		end
		if not hasZoneProps() then
			print("[Props] no props model in ReplicatedStorage (no Prop__ parts): the garden has no props")
			return
		end
		task.wait(1) -- let the rest of the model arrive
		decorate(findSources())
	end)
end

return PropService
