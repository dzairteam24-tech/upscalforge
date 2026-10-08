--!strict
-- The Cubeling Ride's saddle (art: the saddle model sheet from ChatGPT): a brown leather frame with rounded
-- corners, a raised red-orange cushion with a cream piping, a back rest, a U-shaped handle in front, and on
-- each side a rounded leather panel with a gold paw coin, gold buckles and straps down the creature's sides.
--
-- Built from simple parts; rounded corners come from cylinders at the corners of a box. Returns the pieces
-- relative to the saddle's origin: the middle of its bottom, sitting on the creature's back (front is -Z).

export type Piece = { name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType? }

local RideSaddle = {}

local LEATHER = Color3.fromRGB(128, 72, 38)
local LEATHER_DARK = Color3.fromRGB(96, 52, 28)
local CUSHION = Color3.fromRGB(226, 84, 44)
local CREAM = Color3.fromRGB(252, 236, 210)
local GOLD = Color3.fromRGB(255, 198, 58)
local GOLD_DARK = Color3.fromRGB(205, 140, 30)

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up (its axis is X)

RideSaddle.LENGTH = 3.2 -- front to back
RideSaddle.SEAT_HEIGHT = 0.95 -- top of the cushion above the saddle's origin: where the rider's hips go

-- A slab seen from above with rounded corners: two crossed boxes and an upright cylinder in each corner
local function roundedSlab(pieces: { Piece }, name: string, center: Vector3, size: Vector3, radius: number, color: Color3, material: Enum.Material)
	local r = math.min(radius, size.X / 2, size.Z / 2)
	table.insert(pieces, { name = name, size = Vector3.new(size.X - 2 * r, size.Y, size.Z), cframe = CFrame.new(center), color = color, material = material })
	table.insert(pieces, { name = name, size = Vector3.new(size.X, size.Y, size.Z - 2 * r), cframe = CFrame.new(center), color = color, material = material })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local at = center + Vector3.new(sx * (size.X / 2 - r), 0, sz * (size.Z / 2 - r))
			table.insert(pieces, { name = name, size = Vector3.new(size.Y, 2 * r, 2 * r), cframe = CFrame.new(at) * UPRIGHT, color = color, material = material, shape = Enum.PartType.Cylinder })
		end
	end
end

-- A flat panel standing on the side (thin along X) with rounded corners: two crossed boxes and a cylinder
-- pointing out of the side in each corner
local function sidePanel(pieces: { Piece }, name: string, center: Vector3, thickness: number, height: number, length: number, radius: number, color: Color3, material: Enum.Material)
	local r = math.min(radius, height / 2, length / 2)
	table.insert(pieces, { name = name, size = Vector3.new(thickness, height - 2 * r, length), cframe = CFrame.new(center), color = color, material = material })
	table.insert(pieces, { name = name, size = Vector3.new(thickness, height, length - 2 * r), cframe = CFrame.new(center), color = color, material = material })
	for _, sy in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local at = center + Vector3.new(0, sy * (height / 2 - r), sz * (length / 2 - r))
			table.insert(pieces, { name = name, size = Vector3.new(thickness, 2 * r, 2 * r), cframe = CFrame.new(at), color = color, material = material, shape = Enum.PartType.Cylinder })
		end
	end
end

-- A gold coin with a paw on the outside of a side panel (`side` = -1 left, 1 right)
local function pawCoin(pieces: { Piece }, at: Vector3, side: number, radius: number)
	local out = Vector3.new(side, 0, 0)
	table.insert(pieces, { name = "SaddleCoin", size = Vector3.new(0.14, radius * 2, radius * 2), cframe = CFrame.new(at), color = GOLD, material = Enum.Material.SmoothPlastic, shape = Enum.PartType.Cylinder })
	table.insert(pieces, { name = "SaddleCoin", size = Vector3.new(0.16, radius * 1.55, radius * 1.55), cframe = CFrame.new(at + out * 0.02), color = CUSHION, material = Enum.Material.SmoothPlastic, shape = Enum.PartType.Cylinder })
	-- The paw: a big pad and three toes
	local paw = at + out * 0.1
	table.insert(pieces, { name = "SaddlePaw", size = Vector3.new(0.06, radius * 0.62, radius * 0.62), cframe = CFrame.new(paw + Vector3.new(0, -radius * 0.14, 0)), color = GOLD, material = Enum.Material.SmoothPlastic, shape = Enum.PartType.Cylinder })
	for _, toe in { Vector3.new(0, radius * 0.32, -radius * 0.3), Vector3.new(0, radius * 0.42, 0), Vector3.new(0, radius * 0.32, radius * 0.3) } do
		table.insert(pieces, { name = "SaddlePaw", size = Vector3.new(0.06, radius * 0.26, radius * 0.26), cframe = CFrame.new(paw + toe), color = GOLD, material = Enum.Material.SmoothPlastic, shape = Enum.PartType.Cylinder })
	end
end

-- A square gold buckle on a strap, on the outside of a side panel
local function buckle(pieces: { Piece }, at: Vector3, side: number, size: number)
	local out = Vector3.new(side, 0, 0)
	local t = size * 0.22
	for _, bar in {
		{ Vector3.new(0, size / 2 - t / 2, 0), Vector3.new(0.12, t, size) },
		{ Vector3.new(0, -size / 2 + t / 2, 0), Vector3.new(0.12, t, size) },
		{ Vector3.new(0, 0, size / 2 - t / 2), Vector3.new(0.12, size, t) },
		{ Vector3.new(0, 0, -size / 2 + t / 2), Vector3.new(0.12, size, t) },
	} do
		table.insert(pieces, { name = "SaddleBuckle", size = bar[2], cframe = CFrame.new(at + out * 0.06 + bar[1]), color = GOLD, material = Enum.Material.SmoothPlastic })
	end
end

-- The saddle for a creature `width` wide, whose sides go `drop` down from its back
function RideSaddle.build(width: number, drop: number): { Piece }
	local pieces: { Piece } = {}
	local half = width / 2
	local length = RideSaddle.LENGTH

	-- Frame: a leather base on the back, a cream piping and the raised cushion
	roundedSlab(pieces, "SaddleBase", Vector3.new(0, 0.15, 0), Vector3.new(width + 0.3, 0.3, length), 0.45, LEATHER, Enum.Material.Leather) -- reaches the side panels
	roundedSlab(pieces, "SaddlePiping", Vector3.new(0, 0.38, 0.1), Vector3.new(2.5, 0.16, 2.5), 0.5, CREAM, Enum.Material.SmoothPlastic)
	roundedSlab(pieces, "SaddleSeat", Vector3.new(0, 0.66, 0.1), Vector3.new(2.3, 0.42, 2.3), 0.45, CUSHION, Enum.Material.SmoothPlastic)

	-- Back rest: a rounded leather wall behind the seat with a cream edge
	roundedSlab(pieces, "SaddleBack", Vector3.new(0, 0.85, length / 2 - 0.25), Vector3.new(2.4, 0.9, 0.42), 0.2, LEATHER, Enum.Material.Leather)
	table.insert(pieces, { name = "SaddleBack", size = Vector3.new(2.5, 0.24, 0.24), cframe = CFrame.new(0, 1.32, length / 2 - 0.25), color = CREAM, material = Enum.Material.SmoothPlastic, shape = Enum.PartType.Cylinder })

	-- Handle in front: two posts and a bar, rounded where they meet
	local handleZ = -length / 2 + 0.3
	for _, sx in { -1, 1 } do
		table.insert(pieces, { name = "SaddleHandle", size = Vector3.new(1.3, 0.3, 0.3), cframe = CFrame.new(sx * 0.75, 0.95, handleZ) * UPRIGHT, color = LEATHER_DARK, material = Enum.Material.Leather, shape = Enum.PartType.Cylinder })
		table.insert(pieces, { name = "SaddleHandle", size = Vector3.one * 0.3, cframe = CFrame.new(sx * 0.75, 1.6, handleZ), color = LEATHER_DARK, material = Enum.Material.Leather, shape = Enum.PartType.Ball })
	end
	table.insert(pieces, { name = "SaddleHandle", size = Vector3.new(1.5, 0.3, 0.3), cframe = CFrame.new(0, 1.6, handleZ), color = LEATHER_DARK, material = Enum.Material.Leather, shape = Enum.PartType.Cylinder })

	-- Each side: a rounded leather panel with a cream edge, a paw coin, two straps with buckles
	local panelHeight = math.min(drop * 0.75, 2.6)
	for _, side in { -1, 1 } do
		local x = side * (half + 0.08)
		local mid = Vector3.new(x, -panelHeight / 2 + 0.2, 0.1)
		sidePanel(pieces, "SaddlePanel", mid, 0.14, panelHeight + 0.2, length * 0.92 + 0.2, 0.45, CREAM, Enum.Material.SmoothPlastic)
		sidePanel(pieces, "SaddlePanel", mid + Vector3.new(side * 0.03, 0, 0), 0.14, panelHeight, length * 0.92, 0.4, LEATHER, Enum.Material.Leather)
		pawCoin(pieces, mid + Vector3.new(side * 0.1, 0.1, 0.15), side, 0.55)
		-- Straps down the creature's side, front and back of the panel, each with a gold buckle
		for _, z in { -length * 0.36, length * 0.36 } do
			table.insert(pieces, { name = "SaddleStrap", size = Vector3.new(0.12, drop, 0.32), cframe = CFrame.new(x + side * 0.1, -drop / 2 + 0.15, z), color = LEATHER_DARK, material = Enum.Material.Leather })
			buckle(pieces, Vector3.new(x + side * 0.1, -panelHeight * 0.55, z), side, 0.5)
		end
	end
	return pieces
end

return RideSaddle
