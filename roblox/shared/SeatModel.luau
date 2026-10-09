--!strict
-- The floating seats (art: the floating seats sheet): a soft seat that floats under the player, who sits on
-- it cross-legged. Clients draw it and pose the rider (RideClient).
--
-- The seats are Blender models (art/blender/seats.py, art/models/Seats.glb; Config/SeatLooks says what each
-- looks like), three per zone, found by their part names (Cloud__body, Cloud__eye, ...) in a model anywhere
-- directly in ReplicatedStorage (imported in Studio, or loaded by ArtService from Config/Art). The models are made in studs, standing on the ground (y = 0) with their face to the
-- front; a tiny marker part (<Seat>__front) in front of the face tells which way Studio's importer turned
-- them. Until the model is there the seat is a plain cloud of balls.

local SeatLooks = require(script.Parent.Config.SeatLooks)

local SeatModel = {}

local FLIP = CFrame.Angles(0, math.pi, 0) -- the files' front (+Z) to the game's front (-Z)

type ArtModel = { ref: string, center: Vector3, size: Vector3 }
-- A part of an imported model: where it is from the reference part (in the import's own axes, which Studio
-- may have turned) and, once placed (`place`), where it goes in the game's axes
type Piece = { role: string, part: BasePart, rel: Vector3, turn: CFrame, size: Vector3, at: Vector3, rotation: CFrame }

local artOverride: Instance? = nil -- tests and previews point this at models of their own

function SeatModel.useArt(root: Instance?)
	artOverride = root
end

local reported: { [string]: string } = {}

-- Says once per change in the Output which model a ride uses, so a model that isn't picked up is easy to spot
local function report(prefix: string, message: string)
	if reported[prefix] ~= message then
		reported[prefix] = message
		print("[Seat] " .. message)
	end
end

-- The parts of a Blender model named `prefix`__<role>, in its design units with the game's front, or nil when
-- it isn't loaded. The model can be anywhere directly in ReplicatedStorage under any name (Studio's importer
-- calls it "Scene"); when there are several, the last one added wins, so a re-imported model replaces the old
-- one even when the old one is left there.
local function meshPieces(prefix: string, model: ArtModel): { Piece }?
	local refName = prefix .. "__" .. model.ref
	-- Looked up safely: the offline tests run this module without a full game
	local ok, roots = pcall(function(): { Instance }
		if artOverride then
			return { artOverride }
		end
		local children = game:GetService("ReplicatedStorage"):GetChildren()
		local found = {}
		for i = #children, 1, -1 do
			table.insert(found, children[i])
		end
		return found
	end)
	if not ok then
		return nil
	end
	local found: { [string]: BasePart } = {}
	local source: Instance? = nil
	local candidates = 0
	for _, root in roots do
		local parts: { [string]: BasePart } = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				-- The part's name, or its model's when the importer kept the mesh's own name on the part
				local function roleOf(name: string): string?
					return string.match((string.gsub(name, "%.%d+$", "")), "^" .. prefix .. "__(.+)$")
				end
				local role = roleOf(d.Name) or (if d.Parent then roleOf(d.Parent.Name) else nil)
				if role and not parts[role] then
					parts[role] = d
				end
			end
		end
		if parts[model.ref] then
			candidates += 1
			if not source then
				source = root
				found = parts
			end
		end
	end
	if not source then
		report(prefix, ("no %s model in ReplicatedStorage (no part named %s): using the stand-in"):format(prefix, refName))
		return nil
	end
	report(prefix, ("%s model: ReplicatedStorage.%s%s"):format(prefix, (source :: Instance).Name, if candidates > 1 then (" (the newest of %d: delete the old ones)"):format(candidates) else ""))
	local base = found[model.ref]
	if not base then
		return nil
	end
	-- (the size's length doesn't change if the importer turned the part's axes)
	local importScale = base.Size.Magnitude / model.size.Magnitude
	local pieces: { Piece } = {}
	for role, p in found do
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
			rel = base.CFrame:PointToObjectSpace(p.CFrame.Position) / importScale,
			turn = base.CFrame.Rotation:Inverse() * p.CFrame.Rotation,
			size = p.Size / importScale,
			at = Vector3.zero,
			rotation = CFrame.identity,
		})
	end
	return pieces
end

-- Places a model's pieces in the game's axes: undoing the importer's turn, then the file's front to the game's
local function place(pieces: { Piece }, model: ArtModel, turn: CFrame)
	for _, piece in pieces do
		local design = turn:VectorToWorldSpace(piece.rel) + model.center
		piece.at = Vector3.new(-design.X, design.Y, -design.Z)
		piece.rotation = FLIP * turn * piece.turn
	end
end


export type Seat = {
	model: Model,
	parts: { BasePart },
	offsets: { CFrame }, -- per part, from the seat's origin: the ground under its middle (front is -Z)
	top: number, -- the sitting surface, above the origin
	bottom: number, -- the seat's underside, above the origin
}

type Design = SeatLooks.Look

local DESIGNS: { [string]: Design } = {}
for _, look in SeatLooks do
	DESIGNS[look.name] = look
end

local SCALE = 1.6 -- the seats are drawn this much bigger than modeled, so a sitting avatar fits on them

-- Roles drawn glossy (as in the renders), and metallic ones a little reflective too
local SHINY = { eye = true, gem = true, pearl = true, crystal = true, glass = true, ice = true, shine = true }
local METAL = { star = true, gold = true }

local function quiet(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

-- How Studio's importer turned a seat: the turn about Y that brings its front marker back in front (+Z in
-- the file), in quarter turns
local function importTurn(pieces: { Piece }): CFrame
	for _, piece in pieces do
		if piece.role == "front" then
			local angle = math.atan2(piece.rel.X, piece.rel.Z)
			return CFrame.Angles(0, -math.round(angle / (math.pi / 2)) * (math.pi / 2), 0)
		end
	end
	return CFrame.identity
end

-- The stand-in until the model is loaded: white balls on a lavender underside
local function standIn(design: Design, add: (BasePart, CFrame) -> ())
	local puffs: { { any } } = {
		{ Vector3.new(0, 0.62, 0), 2.2 },
		{ Vector3.new(-1.05, 0.55, 0.2), 1.6 },
		{ Vector3.new(1.05, 0.55, 0.2), 1.6 },
		{ Vector3.new(-0.5, 0.55, -0.75), 1.4 },
		{ Vector3.new(0.5, 0.55, -0.75), 1.4 },
		{ Vector3.new(0, 0.55, 0.85), 1.4 },
	}
	for i, puff in puffs do
		local p = Instance.new("Part")
		p.Name = "Seat_puff"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * (puff[2] :: number) * SCALE
		local main = design.colors[design.model.ref] or Color3.new(1, 1, 1)
		p.Color = if i == 1 then main else main:Lerp(Color3.new(0, 0, 0), 0.08)
		p.Material = Enum.Material.SmoothPlastic
		add(p, CFrame.new((puff[1] :: Vector3) * SCALE))
	end
end

function SeatModel.has(name: string): boolean
	return DESIGNS[name] ~= nil
end

function SeatModel.build(name: string): Seat
	local design = DESIGNS[name] or DESIGNS.Cloud
	local model = Instance.new("Model")
	model.Name = "Seat_" .. name
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local function add(p: BasePart, offset: CFrame)
		quiet(p)
		p.Parent = model
		table.insert(parts, p)
		table.insert(offsets, offset)
	end

	local pieces = meshPieces(name, design.model)
	local body: BasePart? = nil
	if pieces then
		place(pieces, design.model, importTurn(pieces))
		for _, piece in pieces do
			local p = piece.part
			p.Name = "Seat_" .. piece.role
			p.Size = piece.size * SCALE
			p.Color = design.colors[piece.role] or Color3.new(1, 1, 1)
			p.Reflectance = if METAL[piece.role] then 0.2 else 0
			p.Transparency = if piece.role == "front" then 1 else 0
			if design.glow[piece.role] then
				p.Material = Enum.Material.Neon
			elseif SHINY[piece.role] or METAL[piece.role] then
				p.Material = Enum.Material.Glass
			end
			if piece.role == design.model.ref then
				body = p
			end
			add(p, CFrame.new(piece.at * SCALE) * piece.rotation)
		end
	else
		standIn(design, add)
		body = parts[1]
	end

	-- A soft glow and a few twinkles falling from underneath
	if body then
		local light = Instance.new("PointLight")
		light.Color = design.light
		light.Range = 9
		light.Brightness = 0.7
		light.Shadows = false
		light.Parent = body
		local twinkle = Instance.new("ParticleEmitter")
		twinkle.Name = "Twinkle"
		twinkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		twinkle.Color = ColorSequence.new(design.light, Color3.new(1, 1, 1))
		twinkle.LightEmission = 0.8
		twinkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		twinkle.Transparency = NumberSequence.new(0.2, 1)
		twinkle.Lifetime = NumberRange.new(0.8, 1.4)
		twinkle.Rate = 6
		twinkle.Speed = NumberRange.new(0.5, 1.5)
		twinkle.SpreadAngle = Vector2.new(25, 25)
		twinkle.EmissionDirection = Enum.NormalId.Bottom
		twinkle.Parent = body
	end

	return { model = model, parts = parts, offsets = offsets, top = design.top * SCALE, bottom = design.bottom * SCALE }
end

return SeatModel
