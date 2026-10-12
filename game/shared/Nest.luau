--!strict
-- A nest an egg sits in, like Steal an Egg's: a bed, the soft inside, and a rim of twigs (or petals, stones,
-- shells, ice...) in two colors, in the look of an egg tier's biome (Config/Eggs: Meadow is straw). Used by the
-- Wild's nests (WorldService) and the eggs set down in a garden (IslandService).

local Nest = {}

type Look = { bed: Color3, inner: Color3, rim: { Color3 }, rimMaterial: Enum.Material, innerMaterial: Enum.Material }
local rgb = Color3.fromRGB
local LOOKS: { Look } = {
	{ bed = rgb(116, 78, 44), inner = rgb(236, 200, 112), rim = { rgb(198, 146, 78), rgb(168, 116, 60) }, rimMaterial = Enum.Material.Wood, innerMaterial = Enum.Material.Fabric }, -- Meadow: straw
	{ bed = rgb(96, 160, 80), inner = rgb(255, 228, 238), rim = { rgb(255, 160, 200), rgb(255, 205, 225) }, rimMaterial = Enum.Material.SmoothPlastic, innerMaterial = Enum.Material.Fabric }, -- Flower: petals
	{ bed = rgb(84, 62, 40), inner = rgb(112, 170, 88), rim = { rgb(64, 132, 66), rgb(92, 160, 76) }, rimMaterial = Enum.Material.Grass, innerMaterial = Enum.Material.Grass }, -- Forest: leaves and moss
	{ bed = rgb(232, 206, 142), inner = rgb(244, 226, 172), rim = { rgb(252, 242, 226), rgb(250, 196, 186) }, rimMaterial = Enum.Material.SmoothPlastic, innerMaterial = Enum.Material.Sand }, -- Beach: sand and shells
	{ bed = rgb(70, 62, 80), inner = rgb(92, 72, 128), rim = { rgb(120, 112, 132), rgb(150, 110, 220) }, rimMaterial = Enum.Material.Slate, innerMaterial = Enum.Material.Slate }, -- Cave: stones and crystals
	{ bed = rgb(196, 146, 84), inner = rgb(236, 200, 140), rim = { rgb(214, 164, 98), rgb(184, 128, 72) }, rimMaterial = Enum.Material.Sandstone, innerMaterial = Enum.Material.Sand }, -- Desert: sandstone
	{ bed = rgb(200, 220, 236), inner = rgb(246, 250, 255), rim = { rgb(255, 255, 255), rgb(222, 236, 250) }, rimMaterial = Enum.Material.Snow, innerMaterial = Enum.Material.Snow }, -- Snow
	{ bed = rgb(46, 40, 40), inner = rgb(255, 112, 40), rim = { rgb(66, 56, 56), rgb(96, 70, 62) }, rimMaterial = Enum.Material.Basalt, innerMaterial = Enum.Material.Neon }, -- Volcano: basalt round lava
	{ bed = rgb(120, 180, 220), inner = rgb(214, 240, 255), rim = { rgb(160, 216, 246), rgb(200, 236, 255) }, rimMaterial = Enum.Material.Ice, innerMaterial = Enum.Material.Glacier }, -- Ice
	{ bed = rgb(36, 28, 64), inner = rgb(60, 44, 110), rim = { rgb(160, 90, 255), rgb(70, 220, 255) }, rimMaterial = Enum.Material.Neon, innerMaterial = Enum.Material.SmoothPlastic }, -- Pixel
	{ bed = rgb(150, 110, 40), inner = rgb(255, 238, 170), rim = { rgb(255, 204, 70), rgb(255, 232, 140) }, rimMaterial = Enum.Material.Metal, innerMaterial = Enum.Material.Fabric }, -- Legendary: gold
}

-- Builds a nest into parent, standing on the ground at base, in tier's look, scale times the usual size (5.4 studs
-- across, its egg sitting about 0.9 above the ground)
function Nest.build(parent: Instance, base: CFrame, tier: number?, scale: number?)
	local look = LOOKS[tier or 1] or LOOKS[1]
	local k = scale or 1
	local function bit(props: { [string]: any })
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for key, value in props do
			(p :: any)[key] = value
		end
		p.Parent = parent
	end
	local flat = CFrame.Angles(0, 0, math.rad(90)) -- (a cylinder's axis up)
	bit({ Name = "NestBed", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 5.4, 5.4) * k, CFrame = base * CFrame.new(0, 0.2 * k, 0) * flat, Color = look.bed, Material = Enum.Material.Wood })
	bit({ Name = "NestInside", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4.2, 4.2) * k, CFrame = base * CFrame.new(0, 0.42 * k, 0) * flat, Color = look.inner, Material = look.innerMaterial })
	local twigs = 10
	for i = 1, twigs do
		local turn = (i - 1) * 2 * math.pi / twigs
		local lean = if i % 2 == 0 then 1 else -1
		bit({
			Name = "NestRim",
			Size = Vector3.new(2, 0.75, 0.9) * k,
			CFrame = base * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0.75 * k, -2.35 * k) * CFrame.Angles(math.rad(-14), 0, math.rad(9 * lean)),
			Color = look.rim[i % 2 + 1],
			Material = look.rimMaterial,
		})
	end
end

return Nest
