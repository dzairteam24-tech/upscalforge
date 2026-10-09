--!strict
-- The floating seats (art: the floating seats sheet): a soft seat that floats under the player, who sits on
-- it cross-legged. Clients draw it and pose the rider (RideClient).
--
-- The seats are Blender models (art/blender/seats.py, art/models/Seats.glb; Config/SeatLooks says what each
-- looks like), three per zone, found like the
-- saddle (RideModel): by their part names (Cloud__body, Cloud__eye, ...) in a model anywhere directly in
-- ReplicatedStorage. The models are made in studs, standing on the ground (y = 0) with their face to the
-- front; a tiny marker part (<Seat>__front) in front of the face tells which way Studio's importer turned
-- them. Until the model is there the seat is a plain cloud of balls.

local RideModel = require(script.Parent.RideModel)
local SeatLooks = require(script.Parent.Config.SeatLooks)

local SeatModel = {}

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
local function importTurn(pieces: { RideModel.Piece }): CFrame
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

	local pieces = RideModel.pieces(name, design.model)
	local body: BasePart? = nil
	if pieces then
		RideModel.place(pieces, design.model, importTurn(pieces))
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
