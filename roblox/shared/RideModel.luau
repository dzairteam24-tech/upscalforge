--!strict
-- The Cubeling Ride's creature (art: the Cubeling pony model sheet): a pony in the creature's color, with the
-- rider's strongest creature as its head (its face and ears; its own legs and tail are left out), wearing a
-- saddle on its back. Clients draw it under the rider (RideClient).
--
-- The pony body (art/blender/pony.py, art/models/Pony.glb) and the saddle (art/blender/saddle.py,
-- art/models/Saddle.glb) are Blender models, found by their part names (Pony__..., Saddle__...) in
-- ReplicatedStorage.RideModels or ReplicatedStorage.SaddleModel (imported in Studio, or loaded by
-- ArtService from Config/Art). Until the pony is there the creature itself is reshaped into a slim, long
-- creature on long legs, and until the saddle is there it is the simpler saddle made of parts (RideSaddle).

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

-- The Blender models as exported (front +Z, in the files' units). One part of each, with its box center and
-- width in those units, is how the game finds the scale and origin of an import.
local SADDLE = { ref = "cushion", center = Vector3.new(0, 0.201, 0), width = 0.779 }
local SADDLE_BODY = 1.6 -- the saddle is made for a back this wide (the pony's)
local SADDLE_SEAT_TOP = 0.16 -- the rider's hips: down in the seat (its top is about 0.24)
local SADDLE_COLORS: { [string]: Color3 } = {
	cushion = Color3.fromRGB(232, 88, 40),
	cream = Color3.fromRGB(244, 230, 208),
	leather = Color3.fromRGB(128, 66, 36),
	dark = Color3.fromRGB(92, 46, 24),
	gold = Color3.fromRGB(255, 192, 52),
	paw = Color3.fromRGB(245, 118, 38),
}
-- The pony: 1.6 wide (the saddle's back), its feet at 0, the top of its back at PONY_BACK
local PONY = { ref = "body", center = Vector3.new(0, 1.997, -0.422), width = 1.593 }
local PONY_BACK = 2.35
local PONY_BELLY = 0.65 -- where the legs meet the body: the point they swing around
local PONY_SADDLE_Z = 0.3 -- the saddle's middle, behind the body's middle
local PONY_HEAD = { width = 1.6, bottom = 1.0, z = -1.4 } -- the creature as the head
local PONY_CREAM = Color3.fromRGB(252, 232, 200)
local PONY_HOOF = Color3.fromRGB(96, 54, 30)
local FLIP = CFrame.Angles(0, math.pi, 0) -- the files' front (+Z) to the game's front (-Z)

type Piece = { role: string, part: BasePart, at: Vector3, rotation: CFrame, size: Vector3 }

local artOverride: Instance? = nil -- tests and previews point this at models of their own

function RideModel.useArt(root: Instance?)
	artOverride = root
end
RideModel.useSaddle = RideModel.useArt

-- The parts of a Blender model named `prefix`__<role>, in its design units with the game's front, or nil when
-- it isn't loaded
local function meshPieces(prefix: string, model: { ref: string, center: Vector3, width: number }): { Piece }?
	-- Looked up safely: the offline tests run this module without a full game
	local ok, roots = pcall(function(): { Instance }
		if artOverride then
			return { artOverride }
		end
		local storage = game:GetService("ReplicatedStorage")
		local found = {}
		for _, name in { "RideModels", "SaddleModel", "PonyModel" } do
			local root = storage:FindFirstChild(name)
			if root then
				table.insert(found, root)
			end
		end
		return found
	end)
	if not ok then
		return nil
	end
	local found: { [string]: BasePart } = {}
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				local role = string.match((string.gsub(d.Name, "%.%d+$", "")), "^" .. prefix .. "__(.+)$")
				if role and not found[role] then
					found[role] = d
				end
			end
		end
	end
	local base = found[model.ref]
	if not base then
		return nil
	end
	local importScale = base.Size.X / model.width
	local pieces: { Piece } = {}
	for role, p in found do
		local design = base.CFrame:PointToObjectSpace(p.CFrame.Position) / importScale + model.center
		local clone = p:Clone()
		for _, child in clone:GetChildren() do
			if not child:IsA("DataModelMesh") then
				child:Destroy()
			end
		end
		if clone:IsA("MeshPart") then
			clone.TextureID = ""
		end
		clone.Material = Enum.Material.SmoothPlastic
		clone.Reflectance = 0
		table.insert(pieces, {
			role = role,
			part = clone,
			at = Vector3.new(-design.X, design.Y, -design.Z),
			rotation = FLIP * (base.CFrame.Rotation:Inverse() * p.CFrame.Rotation),
			size = p.Size / importScale,
		})
	end
	return pieces
end

local function quiet(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

-- The pony: the creature's head on the Blender pony body. Returns the back's middle, and the saddle's scale.
local function ponyShape(built: PetModel.Built, pony: { Piece }, offsets: { CFrame }, pivots: { [number]: Vector3 }): (Vector3, number)
	local k = Cosmetics.RIDE_PONY_SCALE
	local feet = -Cosmetics.RIDE_CREATURE_HEIGHT / 2

	-- The head: the creature without its legs and tail, its body PONY_HEAD.width wide
	local bodyIndex = table.find(built.parts, built.body) or 1
	local body = built.parts[bodyIndex]
	local bodyOffset = built.offsets[bodyIndex].Position
	local s = PONY_HEAD.width * k / math.max(body.Size.X, 0.1)
	local headCenter = Vector3.new(0, feet + PONY_HEAD.bottom * k + body.Size.Y * s / 2, PONY_HEAD.z * k)
	local parts: { BasePart } = {}
	local anims: { [number]: string } = {}
	for i, p in built.parts do
		local anim = built.anims[i] or ""
		if string.match(anim, "^leg") or anim == "tail" then
			p:Destroy()
			continue
		end
		local o = built.offsets[i]
		p.Size *= s
		quiet(p)
		table.insert(parts, p)
		offsets[#parts] = CFrame.new(headCenter + (o.Position - bodyOffset) * s) * o.Rotation
		if anim ~= "" then
			anims[#parts] = anim
			if built.pivots[i] then
				pivots[#parts] = headCenter + (built.pivots[i] - bodyOffset) * s
			end
		end
	end

	-- The pony body in the creature's color, its mane a little darker
	local color = body.Color
	for _, piece in pony do
		local role, leg = string.match(piece.role, "^(%a+)__(%w+)$")
		role = role or piece.role
		local p = piece.part
		p.Name = "Pony_" .. piece.role
		p.Color = if role == "cream" then PONY_CREAM elseif role == "hoof" then PONY_HOOF elseif role == "mane" then color:Lerp(Color3.new(0.45, 0.12, 0), 0.3) else color
		p.Size = piece.size * k
		quiet(p)
		p.Parent = built.model
		local at = piece.at * k + Vector3.new(0, feet, 0)
		table.insert(parts, p)
		offsets[#parts] = CFrame.new(at) * piece.rotation
		if leg then
			anims[#parts] = leg
			pivots[#parts] = Vector3.new(at.X, feet + PONY_BELLY * k, at.Z)
		end
	end

	built.parts = parts
	built.anims = anims
	built.pivots = {}
	return Vector3.new(0, feet + PONY_BACK * k, PONY_SADDLE_Z * k), k
end

-- Without the pony model: the creature itself, narrower and longer, on long legs. Returns the back's middle
-- and the saddle's scale.
local function stretchedShape(built: PetModel.Built, offsets: { CFrame }, pivots: { [number]: Vector3 }): (Vector3, number)
	local legs = Cosmetics.RIDE_LEG_EXTRA
	local scale = (Cosmetics.RIDE_STRETCH_HEIGHT - legs) / math.max(built.height, 0.1)
	local stretch = Vector3.new(scale * Cosmetics.RIDE_SLIM, scale, scale * Cosmetics.RIDE_LONG)
	local bodyIndex = table.find(built.parts, built.body) or 1
	local bodyDepth = built.parts[bodyIndex].Size.Z
	-- The top of the back: the body is about as tall as it is wide (ears stick up above that)
	local backAboveBottom = built.parts[bodyIndex].Size.X * 0.95 * scale
	local isLeg: { [number]: boolean } = {}
	local feet = math.huge
	for i, p in built.parts do
		local o = built.offsets[i]
		local size = p.Size
		if string.match(built.anims[i] or "", "^leg") then
			-- Legs stay square posts
			isLeg[i] = true
			p.Size = size * Vector3.new(stretch.X, stretch.Y, stretch.X)
			feet = math.min(feet, o.Position.Y * stretch.Y - p.Size.Y / 2)
		elseif size.Z < bodyDepth * 0.25 and o.Position.Z < -bodyDepth * 0.3 then
			-- Face pieces (eyes, mouth, blush...) keep their shape on the narrower face
			p.Size = size * stretch.X
		else
			-- Body, belly, ears, wings: stretched with the body (the parts are turned about Y only, so their
			-- size is along the world axes)
			p.Size = size * stretch
		end
		quiet(p)
		offsets[i] = CFrame.new(o.Position * stretch) * o.Rotation
	end
	-- Lift everything by the extra leg length, and the legs reach down to the ground
	if feet == math.huge then
		feet = offsets[bodyIndex].Y - built.parts[bodyIndex].Size.Y / 2
	end
	local lift = -Cosmetics.RIDE_CREATURE_HEIGHT / 2 - feet + legs
	for i, p in built.parts do
		if isLeg[i] then
			p.Size += Vector3.new(0, legs, 0)
			offsets[i] = offsets[i] + Vector3.new(0, lift - legs / 2, 0)
		else
			offsets[i] = offsets[i] + Vector3.new(0, lift, 0)
		end
	end
	for i, pivot in built.pivots do
		pivots[i] = pivot * stretch + Vector3.new(0, lift, 0)
	end

	local body = built.parts[bodyIndex]
	local backY = offsets[bodyIndex].Y - body.Size.Y / 2 + backAboveBottom
	-- The saddle sits on the back half, behind the ears and head
	return Vector3.new(0, backY, body.Size.Z * Cosmetics.RIDE_SEAT_BACK), body.Size.X / SADDLE_BODY
end

function RideModel.build(pet: { s: string, v: string, z: string }): Ride
	local built = PetModel.build(pet)
	local offsets: { CFrame } = {}
	local pivots: { [number]: Vector3 } = {}
	local pony = meshPieces("Pony", PONY)
	local back, fit
	if pony then
		back, fit = ponyShape(built, pony, offsets, pivots)
	else
		back, fit = stretchedShape(built, offsets, pivots)
	end

	local function add(p: BasePart, offset: CFrame)
		quiet(p)
		p.CastShadow = false
		p.Parent = built.model
		table.insert(built.parts, p)
		table.insert(offsets, offset)
	end

	local seat: Vector3
	local saddle = meshPieces("Saddle", SADDLE)
	if saddle then
		-- The Blender saddle, sized to this back
		for _, piece in saddle do
			local p = piece.part
			p.Name = "Saddle_" .. piece.role
			p.Color = SADDLE_COLORS[piece.role] or SADDLE_COLORS.leather
			p.Reflectance = if piece.role == "gold" then 0.15 else 0
			p.Size = piece.size * fit
			add(p, CFrame.new(back + piece.at * fit) * piece.rotation)
		end
		seat = back + Vector3.new(0, SADDLE_SEAT_TOP * fit, 0)
	else
		-- The saddle made of parts, until the model is loaded
		local width = SADDLE_BODY * fit
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
