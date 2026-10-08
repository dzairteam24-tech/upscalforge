--!strict
-- The Cubeling Ride's creature: the rider's strongest creature, built by PetModel at its normal shape and
-- RIDE_CREATURE_HEIGHT tall whatever its size, wearing a saddle on its back (art: the Cubeling Ride model
-- sheet). Clients draw it under the rider (RideClient).
--
-- The saddle is the Blender model (art/blender/saddle.py, art/models/Saddle.glb) once it is in
-- ReplicatedStorage.SaddleModel (imported in Studio, or loaded by ArtService from Config/Art), fitted to
-- the creature's back. Until then it is the simpler saddle made of parts (RideSaddle).

local Cosmetics = require(script.Parent.Config.Cosmetics)
local PetModel = require(script.Parent.PetModel)
local RideSaddle = require(script.Parent.RideSaddle)

local RideModel = {}

export type Ride = {
	built: PetModel.Built,
	offsets: { CFrame }, -- per part, from the creature's center (front is -Z)
	pivots: { [number]: Vector3 }, -- per moving piece, the point it turns around
	seat: Vector3, -- top of the cushion, from the creature's center: where the rider's hips go
}

-- The Blender saddle, as exported (Saddle.glb): designed for a body SADDLE_BODY wide, its origin on the
-- middle of the back, front +Z. Its cushion is how the game finds the scale and origin of the import.
local SADDLE_BODY = 2
local SADDLE_CUSHION_CENTER = Vector3.new(0, 0.36, -0.04)
local SADDLE_CUSHION_WIDTH = 1.498
local SADDLE_SEAT_TOP = 0.53
local SADDLE_COLORS: { [string]: Color3 } = {
	cushion = Color3.fromRGB(232, 88, 40),
	cream = Color3.fromRGB(244, 230, 208),
	leather = Color3.fromRGB(128, 66, 36),
	dark = Color3.fromRGB(92, 46, 24),
	gold = Color3.fromRGB(255, 192, 52),
	paw = Color3.fromRGB(245, 118, 38),
}
local FLIP = CFrame.Angles(0, math.pi, 0) -- the file's front (+Z) to the game's front (-Z)

type SaddlePiece = { part: BasePart, at: Vector3, rotation: CFrame, size: Vector3 }

local saddleOverride: Instance? = nil -- tests and previews point this at a SaddleModel of their own

function RideModel.useSaddle(root: Instance?)
	saddleOverride = root
end

-- The Blender saddle's parts, in its design units with the game's front, or nil when it isn't loaded
local function meshSaddle(): { SaddlePiece }?
	-- Looked up safely: the offline tests run this module without a full game
	local ok, root = pcall(function()
		return saddleOverride or game:GetService("ReplicatedStorage"):FindFirstChild("SaddleModel")
	end)
	if not ok or not root then
		return nil
	end
	local found: { [string]: BasePart } = {}
	local cushion: BasePart? = nil
	for _, d in (root :: Instance):GetDescendants() do
		if d:IsA("BasePart") then
			local role = string.match((string.gsub(d.Name, "%.%d+$", "")), "^Saddle__(%a+)$")
			if role and SADDLE_COLORS[role] then
				found[role] = d
				if role == "cushion" then
					cushion = d
				end
			end
		end
	end
	if not cushion then
		return nil
	end
	local base = cushion :: BasePart
	local importScale = base.Size.X / SADDLE_CUSHION_WIDTH
	local pieces: { SaddlePiece } = {}
	for role, p in found do
		local design = base.CFrame:PointToObjectSpace(p.CFrame.Position) / importScale + SADDLE_CUSHION_CENTER
		local clone = p:Clone()
		for _, child in clone:GetChildren() do
			if not child:IsA("DataModelMesh") then
				child:Destroy()
			end
		end
		if clone:IsA("MeshPart") then
			clone.TextureID = ""
		end
		clone.Name = "Saddle_" .. role
		clone.Color = SADDLE_COLORS[role]
		clone.Material = Enum.Material.SmoothPlastic
		clone.Reflectance = if role == "gold" then 0.15 else 0
		table.insert(pieces, {
			part = clone,
			at = Vector3.new(-design.X, design.Y, -design.Z),
			rotation = FLIP * (base.CFrame.Rotation:Inverse() * p.CFrame.Rotation),
			size = p.Size / importScale,
		})
	end
	return pieces
end

function RideModel.build(pet: { s: string, v: string, z: string }): Ride
	local built = PetModel.build(pet)
	local scale = Cosmetics.RIDE_CREATURE_HEIGHT / math.max(built.height, 0.1)
	local offsets: { CFrame } = {}
	for i, p in built.parts do
		local o = built.offsets[i]
		p.Size *= scale
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		offsets[i] = CFrame.new(o.Position * scale) * o.Rotation
	end
	local pivots: { [number]: Vector3 } = {}
	for i, pivot in built.pivots do
		pivots[i] = pivot * scale
	end

	-- The top of the back: the body is about as tall as it is wide (ears stick up above that)
	local bodyIndex = table.find(built.parts, built.body) or 1
	local body = built.parts[bodyIndex]
	local width = body.Size.X
	local backY = offsets[bodyIndex].Y - body.Size.Y / 2 + width * 0.95
	local back = Vector3.new(0, backY, Cosmetics.RIDE_SEAT_BACK)

	local function add(p: BasePart, offset: CFrame)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = built.model
		table.insert(built.parts, p)
		table.insert(offsets, offset)
	end

	local seat: Vector3
	local pieces = meshSaddle()
	if pieces then
		-- The Blender saddle, sized to this body
		local fit = width / SADDLE_BODY
		for _, piece in pieces do
			piece.part.Size = piece.size * fit
			add(piece.part, CFrame.new(back + piece.at * fit) * piece.rotation)
		end
		seat = back + Vector3.new(0, SADDLE_SEAT_TOP * fit, 0)
	else
		-- The saddle made of parts, until the model is loaded
		for _, piece in RideSaddle.build(width, width * 0.8) do
			local p = Instance.new("Part")
			p.Name = piece.name
			if piece.shape then
				p.Shape = piece.shape
			end
			p.Size = piece.size
			p.Color = piece.color
			p.Material = piece.material
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			add(p, CFrame.new(back) * piece.cframe)
		end
		seat = back + Vector3.new(0, RideSaddle.SEAT_HEIGHT, 0)
	end

	return {
		built = built,
		offsets = offsets,
		pivots = pivots,
		seat = seat,
	}
end

return RideModel
