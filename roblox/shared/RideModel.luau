--!strict
-- The Cubeling Ride's creature: the rider's strongest creature, built by PetModel, reshaped into a mount and
-- wearing a saddle (art: the Cubeling Ride concept sheet). Clients draw it under the rider (RideClient).
--
-- Reshaped like a pony rather than a cube: RIDE_CREATURE_HEIGHT tall whatever its size, RIDE_LENGTH times
-- longer front to back and RIDE_WIDTH as wide, so there is a back to sit on with the head in front and the
-- rider's legs reach down its sides. The saddle sits RIDE_SEAT_BACK
-- behind the middle: a leather base with flaps down each side, a red-orange cushion with a cream trim, a
-- handle in front for the hands, a back rest with a gold paw coin, gold buckles and a side bag.

local Cosmetics = require(script.Parent.Config.Cosmetics)
local PetModel = require(script.Parent.PetModel)

local RideModel = {}

export type Ride = {
	built: PetModel.Built,
	offsets: { CFrame }, -- per part, from the creature's center (front is -Z)
	pivots: { [number]: Vector3 }, -- per moving piece, the point it turns around
	seat: Vector3, -- top of the cushion, from the creature's center: where the rider's hips go
}

type Piece = { name: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?, turn: CFrame? }

local LEATHER = Color3.fromRGB(122, 70, 38)
local DARK_LEATHER = Color3.fromRGB(92, 52, 28)
local CUSHION = Color3.fromRGB(236, 98, 50)
local CREAM = Color3.fromRGB(252, 236, 208)
local GOLD = Color3.fromRGB(255, 196, 60)
local FACING_SIDE = CFrame.identity -- cylinders point along X: their round faces look left/right
local FACING_BACK = CFrame.Angles(0, math.rad(90), 0) -- round faces look front/back

-- The saddle's pieces around `back` (the top of the creature's back under the cushion), `width` wide
local function saddlePieces(back: Vector3, width: number): { Piece }
	local side = width / 2
	local pieces: { Piece } = {
		-- Base and cushion
		{ name = "SaddleBase", size = Vector3.new(width + 0.12, 0.2, 3.1), at = Vector3.new(0, 0.1, 0), color = LEATHER, material = Enum.Material.Leather },
		{ name = "SaddleTrim", size = Vector3.new(math.min(2.7, width + 0.1), 0.14, 2.5), at = Vector3.new(0, 0.26, 0), color = CREAM, material = Enum.Material.SmoothPlastic },
		{ name = "SaddleSeat", size = Vector3.new(math.min(2.5, width - 0.1), 0.42, 2.3), at = Vector3.new(0, 0.5, 0), color = CUSHION, material = Enum.Material.Fabric },
		-- Handle in front of the rider: two posts and a bar
		{ name = "SaddleHandle", size = Vector3.new(0.28, 0.95, 0.28), at = Vector3.new(0.72, 0.78, -1.2), color = LEATHER, material = Enum.Material.Leather },
		{ name = "SaddleHandle", size = Vector3.new(0.28, 0.95, 0.28), at = Vector3.new(-0.72, 0.78, -1.2), color = LEATHER, material = Enum.Material.Leather },
		{ name = "SaddleHandle", size = Vector3.new(1.75, 0.34, 0.34), at = Vector3.new(0, 1.28, -1.2), color = LEATHER, material = Enum.Material.Leather, shape = Enum.PartType.Cylinder, turn = FACING_SIDE },
		-- Back rest with a cream top and a gold paw coin on the back
		{ name = "SaddleBack", size = Vector3.new(math.min(2.5, width - 0.1), 0.85, 0.36), at = Vector3.new(0, 0.72, 1.22), color = LEATHER, material = Enum.Material.Leather },
		{ name = "SaddleBack", size = Vector3.new(math.min(2.56, width), 0.14, 0.42), at = Vector3.new(0, 1.17, 1.22), color = CREAM, material = Enum.Material.SmoothPlastic },
		{ name = "SaddleCoin", size = Vector3.new(0.12, 0.62, 0.62), at = Vector3.new(0, 0.72, 1.42), color = GOLD, material = Enum.Material.Foil, shape = Enum.PartType.Cylinder, turn = FACING_BACK },
	}
	for _, sign in { -1, 1 } do
		-- A flap down each side: leather, an orange panel, a gold buckle
		table.insert(pieces, { name = "SaddleFlap", size = Vector3.new(0.14, 1.9, 2.5), at = Vector3.new(sign * (side + 0.07), -0.9, 0), color = LEATHER, material = Enum.Material.Leather })
		table.insert(pieces, { name = "SaddleFlap", size = Vector3.new(0.06, 1.4, 1.9), at = Vector3.new(sign * (side + 0.16), -0.85, 0), color = CUSHION, material = Enum.Material.Fabric })
		table.insert(pieces, { name = "SaddleBuckle", size = Vector3.new(0.1, 0.48, 0.52), at = Vector3.new(sign * (side + 0.22), -1.5, -0.45), color = GOLD, material = Enum.Material.Foil })
	end
	-- A bag on the right side with a gold paw coin
	table.insert(pieces, { name = "SaddleBag", size = Vector3.new(0.5, 0.95, 1.1), at = Vector3.new(side + 0.42, -0.95, 0.55), color = DARK_LEATHER, material = Enum.Material.Leather })
	table.insert(pieces, { name = "SaddleCoin", size = Vector3.new(0.1, 0.55, 0.55), at = Vector3.new(side + 0.72, -0.95, 0.55), color = GOLD, material = Enum.Material.Foil, shape = Enum.PartType.Cylinder, turn = FACING_SIDE })
	for _, piece in pieces do
		piece.at += back
	end
	return pieces
end

function RideModel.build(pet: { s: string, v: string, z: string }): Ride
	local built = PetModel.build(pet)
	local scale = Cosmetics.RIDE_CREATURE_HEIGHT / math.max(built.height, 0.1)
	local stretch = Vector3.new(scale * Cosmetics.RIDE_WIDTH, scale, scale * Cosmetics.RIDE_LENGTH)
	local offsets: { CFrame } = {}
	for i, p in built.parts do
		local o = built.offsets[i]
		local r = o.Rotation
		-- Each of the part's own axes grows by how much the stretch lengthens it
		p.Size *= Vector3.new((r.XVector * stretch).Magnitude, (r.YVector * stretch).Magnitude, (r.ZVector * stretch).Magnitude)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		offsets[i] = CFrame.new(o.Position * stretch) * r
	end
	local pivots: { [number]: Vector3 } = {}
	for i, pivot in built.pivots do
		pivots[i] = pivot * stretch
	end

	-- The top of the back: the body is about as tall as it is wide (ears stick up above that)
	local bodyIndex = table.find(built.parts, built.body) or 1
	local body = built.parts[bodyIndex]
	local bodyOffset = offsets[bodyIndex]
	local width = body.Size.X
	-- (a cube body is about as tall as it was wide before the narrowing)
	local backY = bodyOffset.Y - body.Size.Y / 2 + width / Cosmetics.RIDE_WIDTH * 0.95
	local back = Vector3.new(0, backY, Cosmetics.RIDE_SEAT_BACK)

	for _, piece in saddlePieces(back, width) do
		local p = Instance.new("Part")
		p.Name = piece.name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		if piece.shape then
			p.Shape = piece.shape
		end
		p.Size = piece.size
		p.Color = piece.color
		p.Material = piece.material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = built.model
		table.insert(built.parts, p)
		table.insert(offsets, CFrame.new(piece.at) * (piece.turn or CFrame.identity))
	end

	return {
		built = built,
		offsets = offsets,
		pivots = pivots,
		seat = back + Vector3.new(0, 0.71, 0),
	}
end

return RideModel
