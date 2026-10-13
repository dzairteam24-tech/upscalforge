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

export type Outcome = { ok: boolean, reason: string?, broke: boolean?, item: Gem.Item?, position: Vector3?, color: Color3?, hpFraction: number? }

export type Mine = typeof(setmetatable(
	{} :: {
		index: number,
		seed: number,
		owner: number,
		folder: Instance,
		blocks: { [number]: Part },
		hp: { [number]: number },
		items: { [number]: Gem.Item },
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

function Mine.new(index: number, seed: number, owner: number, parent: Instance): Mine
	local folder = Instance.new("Folder")
	folder.Name = "Mine_" .. owner
	folder.Parent = parent
	return setmetatable({
		index = index,
		seed = seed,
		owner = owner,
		folder = folder,
		blocks = {},
		hp = {},
		items = {},
		dug = {},
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

-- A swing of the shovel at cube (x, layer, z), by a player standing at `from`, at time `now` (seconds). `data` is
-- their saved data (shovel, backpack). The outcome says what happened; a gem that falls out goes to the backpack.
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
	-- a gem is rolled when its cube is first hit, and kept, so a full backpack doesn't change what's in it
	local kind = block:GetAttribute("Gem")
	local item: Gem.Item? = nil
	if type(kind) == "string" then
		item = self.items[k]
		if not item then
			item = Gem.roll(kind, random)
			self.items[k] = item
		end
		if not Backpack.fits(data, item :: Gem.Item) then
			return fail("full")
		end
	end
	self.lastSwing = now
	local hp = (self.hp[k] or 1) - shovel.power
	local color = block.Color
	if hp > 0 then
		self.hp[k] = hp
		local fraction = hp / MineGen.hp(layer)
		block.Color = MineGen.zone(layer).color:Lerp(Color3.new(0, 0, 0), 0.5 * (1 - fraction))
		return { ok = true, broke = false, position = position, color = block.Color, hpFraction = fraction }
	end
	-- broken
	block:Destroy()
	self.blocks[k] = nil
	self.hp[k] = nil
	self.items[k] = nil
	self.dug[k] = true
	self.lastDug = { x = x, l = layer, z = z }
	data.stats.dug += 1
	data.deepest = math.max(data.deepest, layer)
	if item then
		Backpack.add(data, item)
	end
	self:ensure(layer)
	return { ok = true, broke = true, item = item, position = position, color = color, hpFraction = 0 }
end

-- Where a player lands to continue where they last dug: the middle of that cube (open: they dug it), or nil
function Mine.depthSpot(self: Mine): Vector3?
	local last = self.lastDug
	if not last then
		return nil
	end
	self:ensure(last.l)
	return Layout.cellCenter(self.index, last.x, last.l, last.z) + Vector3.new(0, 0.4, 0)
end

function Mine.destroy(self: Mine)
	self.folder:Destroy()
end

return Mine
