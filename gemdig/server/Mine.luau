--!strict
-- One player's mine: a shaft of cubes under their plot, built a few layers at a time around where they are (so
-- a deep mine never has thousands of parts). Digging is decided here, on the server: the cooldown, the reach, how
-- hard a cube is, what falls out of it, whether it fits the backpack. Cubes already dug stay dug.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Backpack = require(Shared.Logic.Backpack)
local Gear = require(Shared.Config.Gear)
local Gem = require(Shared.Logic.Gem)
local Gems = require(Shared.Config.Gems)
local Layout = require(Shared.Logic.Layout)
local MineConfig = require(Shared.Config.Mine)
local MineGen = require(Shared.Logic.MineGen)

local CELL, WIDTH = MineConfig.CELL, MineConfig.WIDTH
local SHAFT = CELL * WIDTH
local WALL = 2 -- bedrock walls round the shaft, this thick

local Mine = {}
Mine.__index = Mine

export type Outcome = { ok: boolean, reason: string?, broke: boolean?, item: Gem.Item?, items: { Gem.Item }?, geode: boolean?, needs: number?, position: Vector3?, color: Color3?, hpFraction: number? }

export type Mine = typeof(setmetatable(
	{} :: {
		index: number,
		seed: number,
		owner: number,
		folder: Instance,
		blocks: { [number]: Part },
		hp: { [number]: number },
		loot: { [number]: { Gem.Item } },
		shaft: number,
		dug: { [number]: boolean },
		built: { [number]: Instance },
		lastDug: { x: number, l: number, z: number }?,
		lastSwing: number,
	},
	Mine
))

local function key(x: number, l: number, z: number): number
	return l * 64 + x * 8 + z
end

local MID = (WIDTH + 1) // 2

-- The cleared shaft down the middle (the elevator): these cubes start already dug
local function shaftCells(checkpoint: number): { [number]: boolean }
	local dug: { [number]: boolean } = {}
	for l = 1, checkpoint do
		dug[key(MID, l, MID)] = true
	end
	return dug
end

function Mine.new(index: number, seed: number, owner: number, parent: Instance, checkpoint: number?): Mine
	local folder = Instance.new("Folder")
	folder.Name = "Mine_" .. owner
	folder.Parent = parent
	local shaft = checkpoint or 0
	return setmetatable({
		index = index,
		seed = seed,
		owner = owner,
		folder = folder,
		blocks = {},
		hp = {},
		loot = {},
		dug = shaftCells(shaft),
		shaft = shaft,
		built = {},
		lastDug = nil,
		lastSwing = -math.huge,
	}, Mine)
end

local function part(size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = CFrame.new(position)
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	p.Material = material
	return p
end

-- Little glowing crystals poking out of a cube that holds a gem
local function flecks(block: Part, position: Vector3, color: Color3)
	local out = CELL / 2
	for _, offset in { Vector3.new(0, out, 0), Vector3.new(out, 0, 0), Vector3.new(-out, 0, 0), Vector3.new(0, 0, out), Vector3.new(0, 0, -out) } do
		local f = Instance.new("Part")
		f.Name = "Fleck"
		f.Size = Vector3.one * 1.3
		f.CFrame = CFrame.new(position + offset * 0.98) * CFrame.Angles(0.6, 0.7, 0.4)
		f.Anchored = true
		f.CanCollide = false
		f.CanQuery = false
		f.CanTouch = false
		f.Material = Enum.Material.Neon
		f.Color = color
		f.CastShadow = false
		f.Parent = block
	end
end

-- A geode: a big glowing purple cluster on every face, and sparkles
local function geodeFlecks(block: Part, position: Vector3)
	local out = CELL / 2
	for _, offset in { Vector3.new(0, out, 0), Vector3.new(out, 0, 0), Vector3.new(-out, 0, 0), Vector3.new(0, 0, out), Vector3.new(0, 0, -out) } do
		local f = Instance.new("Part")
		f.Name = "Fleck"
		f.Size = Vector3.one * 2.2
		f.CFrame = CFrame.new(position + offset * 0.97) * CFrame.Angles(0.8, 0.3, 0.6)
		f.Anchored = true
		f.CanCollide = false
		f.CanQuery = false
		f.CanTouch = false
		f.Material = Enum.Material.Neon
		f.Color = Color3.fromRGB(200, 90, 255)
		f.CastShadow = false
		f.Parent = block
	end
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(220, 140, 255)
	sparkles.Parent = block
end

function Mine.build(self: Mine, layer: number)
	if self.built[layer] then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "L" .. layer
	self.built[layer] = folder
	local center = Layout.plotCenter(self.index)
	if layer > MineConfig.MAX_LAYER then
		-- the floor under the deepest layer: it can't be dug
		local floor = part(Vector3.new(SHAFT, CELL, SHAFT), Layout.cellCenter(self.index, (WIDTH + 1) / 2, layer, (WIDTH + 1) / 2), Color3.fromRGB(25, 25, 32), Enum.Material.Basalt)
		floor.Name = "Bedrock"
		floor.Parent = folder
		folder.Parent = self.folder
		return
	end
	local zone = MineGen.zone(layer)
	for x = 1, WIDTH do
		for z = 1, WIDTH do
			local k = key(x, layer, z)
			if not self.dug[k] then
				local position = Layout.cellCenter(self.index, x, layer, z)
				local shade = MineGen.shade(self.seed, x, layer, z)
				local color = zone.color:Lerp(shade < 0.5 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1), 0.04 + 0.08 * math.abs(shade - 0.5))
				local block = part(Vector3.one * CELL, position, color, zone.material)
				block.Name = "Block"
				block:SetAttribute("Owner", self.owner)
				block:SetAttribute("X", x)
				block:SetAttribute("L", layer)
				block:SetAttribute("Z", z)
				local gem = MineGen.gemAt(self.seed, x, layer, z)
				if gem then
					block:SetAttribute("Gem", gem)
					flecks(block, position, Gems.byId[gem].color)
				elseif MineGen.geodeAt(self.seed, x, layer, z) then
					block:SetAttribute("Geode", true)
					geodeFlecks(block, position)
				end
				block.Parent = folder
				self.blocks[k] = block
				self.hp[k] = MineGen.hp(layer)
			end
		end
	end
	-- the walls (the first layer's are the plot's ground, built with the plot)
	if layer > 1 then
		local y = -(layer - 0.5) * CELL
		local reach = SHAFT / 2 + WALL / 2
		local long = SHAFT + WALL * 2
		for _, w in {
			{ Vector3.new(long, CELL, WALL), Vector3.new(0, y, reach) },
			{ Vector3.new(long, CELL, WALL), Vector3.new(0, y, -reach) },
			{ Vector3.new(WALL, CELL, SHAFT), Vector3.new(reach, y, 0) },
			{ Vector3.new(WALL, CELL, SHAFT), Vector3.new(-reach, y, 0) },
		} do
			local wall = part(w[1], center + w[2], Color3.fromRGB(40, 40, 50), Enum.Material.Slate)
			wall.Name = "Wall"
			wall.CanQuery = false
			wall.Parent = folder
		end
	end
	folder.Parent = self.folder
end

-- Builds the layers round `layer` and removes the ones far from it
function Mine.ensure(self: Mine, layer: number)
	local first = math.max(1, layer - MineConfig.KEEP_ABOVE)
	local last = math.min(MineConfig.MAX_LAYER + 1, layer + MineConfig.AHEAD)
	for l = first, last do
		self:build(l)
	end
	for l, folder in self.built do
		if l < first or l > last then
			for x = 1, WIDTH do
				for z = 1, WIDTH do
					local k = key(x, l, z)
					self.blocks[k] = nil
					self.hp[k] = nil
				end
			end
			folder:Destroy()
			self.built[l] = nil
		end
	end
end

-- The gem kind a cube holds (nil if none), whether or not it's built
function Mine.gemAt(self: Mine, x: number, layer: number, z: number): string?
	return MineGen.gemAt(self.seed, x, layer, z)
end

local function fail(reason: string): Outcome
	return { ok = false, reason = reason }
end

-- What's inside a cube: a gem cube holds one gem, a geode several (rolled a bit deeper, so a bit rarer)
local function rollLoot(block: Part, layer: number, random: any): { Gem.Item }?
	local kind = block:GetAttribute("Gem")
	if type(kind) == "string" then
		return { Gem.roll(kind, random) }
	end
	if block:GetAttribute("Geode") == true then
		local items = {}
		for _ = 1, MineConfig.GEODE_GEMS do
			local found = Gem.pick(math.min(MineConfig.MAX_LAYER, layer + MineConfig.GEODE_DEEPER), random) or "Quartz"
			table.insert(items, Gem.roll(found, random))
		end
		return items
	end
	return nil
end

-- A swing of the shovel at cube (x, layer, z), by a player standing at `from`, at time `now` (seconds). `data` is
-- their saved data (shovel, backpack). The outcome says what happened; gems that fall out go to the backpack.
function Mine.swing(self: Mine, data: any, x: number, layer: number, z: number, from: Vector3, now: number, random: any): Outcome
	if x < 1 or x > WIDTH or z < 1 or z > WIDTH or layer < 1 or layer > MineConfig.MAX_LAYER or x ~= math.floor(x) or z ~= math.floor(z) or layer ~= math.floor(layer) then
		return fail("outside")
	end
	local shovel = Gear.SHOVELS[data.shovel] or Gear.SHOVELS[1]
	if now - self.lastSwing < shovel.cooldown * 0.85 then
		return fail("cooldown")
	end
	local k = key(x, layer, z)
	local block = self.blocks[k]
	if not block then
		return fail("empty")
	end
	local position = Layout.cellCenter(self.index, x, layer, z)
	if (position - from).Magnitude > MineConfig.REACH + CELL then
		return fail("far")
	end
	local needs = MineGen.needs(layer)
	if data.shovel < needs then
		return { ok = false, reason = "tooHard", needs = needs }
	end
	-- what's inside is rolled when its cube is first hit, and kept, so a full backpack doesn't change it
	local items = self.loot[k]
	if not items then
		items = rollLoot(block, layer, random)
		if items then
			self.loot[k] = items
		end
	end
	if items and not Backpack.fitsAll(data, items) then
		return fail("full")
	end
	self.lastSwing = now
	local hp = (self.hp[k] or 1) - shovel.power
	local color = block.Color
	local geode = block:GetAttribute("Geode") == true
	if hp > 0 then
		self.hp[k] = hp
		local fraction = hp / MineGen.hp(layer)
		block.Color = MineGen.zone(layer).color:Lerp(Color3.new(0, 0, 0), 0.5 * (1 - fraction))
		return { ok = true, broke = false, position = position, color = block.Color, hpFraction = fraction, geode = geode }
	end
	-- broken
	block:Destroy()
	self.blocks[k] = nil
	self.hp[k] = nil
	self.loot[k] = nil
	self.dug[k] = true
	self.lastDug = { x = x, l = layer, z = z }
	data.stats.dug += 1
	data.deepest = math.max(data.deepest, layer)
	if items then
		for _, item in items do
			Backpack.add(data, item)
		end
	end
	self:ensure(layer)
	return { ok = true, broke = true, item = if items then items[1] else nil, items = items, geode = geode, position = position, color = color, hpFraction = 0 }
end

-- Where a player lands to continue: the middle of the cube they last dug, or the bottom of the cleared shaft
-- (open both ways: they dug it); nil if there's neither
function Mine.depthSpot(self: Mine): Vector3?
	local last = self.lastDug
	if last then
		self:ensure(last.l)
		return Layout.cellCenter(self.index, last.x, last.l, last.z) + Vector3.new(0, 0.4, 0)
	end
	if self.shaft >= 1 then
		self:ensure(self.shaft)
		return Layout.cellCenter(self.index, MID, self.shaft, MID) + Vector3.new(0, 0.4, 0)
	end
	return nil
end

-- Starts the mine again: every cube back, a new seed (so the gems are somewhere else), the shaft down to the
-- saved depth cleared
function Mine.reset(self: Mine, seed: number, checkpoint: number)
	for _, folder in self.built do
		folder:Destroy()
	end
	table.clear(self.built)
	table.clear(self.blocks)
	table.clear(self.hp)
	table.clear(self.loot)
	self.seed = seed
	self.shaft = checkpoint
	self.dug = shaftCells(checkpoint)
	self.lastDug = nil
	self:ensure(1)
end

function Mine.destroy(self: Mine)
	self.folder:Destroy()
end

return Mine
