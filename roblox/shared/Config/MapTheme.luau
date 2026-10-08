--!strict
-- How each zone looks: the ground, and the tall wall around it that hides the rest of the map.
-- Keyed by zone id (World1). Zones without an entry use DEFAULT.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

export type Theme = {
	ground: Enum.Material,
	wall: Enum.Material,
	wallColor: Color3,
	capColor: Color3, -- the band along the top of the wall and the entrance arches
}

local DEFAULT: Theme = {
	ground = Enum.Material.Grass,
	wall = Enum.Material.Slate,
	wallColor = rgb(120, 126, 136),
	capColor = rgb(160, 166, 176),
}

local themes: { [number]: Theme } = {
	[0] = { ground = Enum.Material.Cobblestone, wall = Enum.Material.Brick, wallColor = rgb(176, 120, 92), capColor = rgb(236, 220, 190) }, -- Hub
	[1] = { ground = Enum.Material.Grass, wall = Enum.Material.Grass, wallColor = rgb(70, 140, 72), capColor = rgb(118, 186, 96) }, -- Spawn Meadow
	[2] = { ground = Enum.Material.Grass, wall = Enum.Material.Grass, wallColor = rgb(96, 150, 84), capColor = rgb(246, 170, 205) }, -- Flower Field
	[3] = { ground = Enum.Material.LeafyGrass, wall = Enum.Material.Wood, wallColor = rgb(104, 74, 52), capColor = rgb(52, 110, 60) }, -- Forest
	[4] = { ground = Enum.Material.Sand, wall = Enum.Material.Sandstone, wallColor = rgb(214, 190, 140), capColor = rgb(110, 200, 220) }, -- Beach
	[5] = { ground = Enum.Material.Slate, wall = Enum.Material.Rock, wallColor = rgb(66, 56, 84), capColor = rgb(150, 110, 220) }, -- Mushroom Cave
	[6] = { ground = Enum.Material.Sand, wall = Enum.Material.Sandstone, wallColor = rgb(200, 160, 100), capColor = rgb(232, 200, 130) }, -- Desert
	[7] = { ground = Enum.Material.Snow, wall = Enum.Material.Rock, wallColor = rgb(150, 160, 176), capColor = rgb(245, 250, 255) }, -- Snow Peak
	[8] = { ground = Enum.Material.Basalt, wall = Enum.Material.Basalt, wallColor = rgb(56, 46, 46), capColor = rgb(255, 110, 40) }, -- Volcano
	[9] = { ground = Enum.Material.Glacier, wall = Enum.Material.Ice, wallColor = rgb(150, 200, 235), capColor = rgb(230, 248, 255) }, -- Frozen Lake
	[10] = { ground = Enum.Material.SmoothPlastic, wall = Enum.Material.Metal, wallColor = rgb(40, 34, 70), capColor = rgb(200, 90, 255) }, -- Pixel Zone
}

local MapTheme = {
	WALL_HEIGHT = 40, -- taller than the camera usually sits, so each zone feels closed
	WALL_THICKNESS = 4,
	-- Bridges between zones are walled corridors in this neutral stone
	CORRIDOR = { wall = Enum.Material.Slate, wallColor = rgb(118, 112, 106), capColor = rgb(170, 160, 150) } :: { wall: Enum.Material, wallColor: Color3, capColor: Color3 },
}

function MapTheme.get(zoneId: number): Theme
	return themes[zoneId] or DEFAULT
end

return MapTheme
