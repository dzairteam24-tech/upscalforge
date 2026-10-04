-- Builds a creature as a 3D model from blocks: one cube body + face + top part + variant look.
-- Every part is anchored; callers move them with workspace:BulkMoveTo using the returned offsets.

local Config = script.Parent.Config
local Sizes = require(Config.Sizes)
local World1 = require(Config.World1)

export type Built = {
	model: Model,
	body: BasePart,
	parts: { BasePart },
	offsets: { CFrame }, -- offset of each part from the body
	height: number, -- full height in studs
	radius: number, -- footprint radius in studs
}

local PetModel = {}

local BASE_SIZE = 2.2

local INK = Color3.fromRGB(34, 37, 43)

local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

function PetModel.build(pet: { s: string, v: string, z: string }): Built
	local species = World1.species[pet.s]
	local size = Sizes.byId[pet.z] or Sizes.byId.Normal
	local b = BASE_SIZE * size.scale
	local baseColor = if species then species.color else Color3.fromRGB(200, 200, 200)
	local top = if species then species.top else "none"
	local face = if species then species.face else "round"

	local model = Instance.new("Model")
	model.Name = pet.s
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}

	local function add(part: BasePart, offset: CFrame)
		part.Parent = model
		table.insert(parts, part)
		table.insert(offsets, offset)
	end

	-- Body look per variant
	local bodyColor = baseColor
	local material = Enum.Material.SmoothPlastic
	local transparency = 0
	local eyeColor = INK
	local reflectance = 0
	if pet.v == "Golden" then
		bodyColor = Color3.fromRGB(245, 197, 66)
		material = Enum.Material.Foil
		reflectance = 0.15
	elseif pet.v == "Crystal" then
		bodyColor = Color3.fromRGB(170, 225, 250)
		material = Enum.Material.Glass
		transparency = 0.25
	elseif pet.v == "Lava" then
		bodyColor = Color3.fromRGB(55, 40, 42)
		material = Enum.Material.Basalt
		eyeColor = Color3.fromRGB(255, 181, 71)
	elseif pet.v == "Neon" then
		bodyColor = Color3.fromRGB(18, 22, 39)
		eyeColor = Color3.fromRGB(43, 245, 154)
	elseif pet.v == "Pixel" then
		transparency = 1
	end

	local body = newPart({
		Name = "Body",
		Size = Vector3.one * b,
		Color = bodyColor,
		Material = material,
		Transparency = transparency,
		Reflectance = reflectance,
	})
	add(body, CFrame.identity)
	model.PrimaryPart = body

	if pet.v == "Pixel" then
		-- 2x2x2 voxels with slightly different shades: the 8-bit look
		local half = b / 2
		local shades = { 0, 0.12, 0.06, 0.18 }
		local i = 0
		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					i += 1
					local shade = shades[(i % 4) + 1]
					add(
						newPart({
							Name = "Voxel",
							Size = Vector3.one * (half - 0.02),
							Color = if shade > 0.1 then darken(baseColor, shade) else lighten(baseColor, shade),
						}),
						CFrame.new(x * half / 2, y * half / 2, z * half / 2)
					)
				end
			end
		end
		for _, offset in { Vector3.new(0.8, 0.6, -0.2), Vector3.new(-0.85, -0.1, 0.3), Vector3.new(0.5, 0.95, 0.4) } do
			add(
				newPart({
					Name = "Bit",
					Size = Vector3.one * b * 0.12,
					Color = Color3.fromRGB(185, 166, 245),
					Material = Enum.Material.Neon,
				}),
				CFrame.new(offset * b)
			)
		end
	elseif pet.v == "Lava" then
		for _, crack in {
			{ Vector3.new(-0.3, 0.2, -0.505), 35 },
			{ Vector3.new(0.32, -0.15, -0.505), -40 },
			{ Vector3.new(0.505, 0.1, 0.1), 60 },
			{ Vector3.new(-0.505, -0.2, -0.1), -30 },
		} do
			local pos: Vector3, angle: number = crack[1], crack[2]
			local isSide = math.abs(pos.X) > 0.5
			add(
				newPart({
					Name = "Crack",
					Size = if isSide then Vector3.new(0.02, 0.05, 0.35) * b else Vector3.new(0.35, 0.05, 0.02) * b,
					Color = Color3.fromRGB(255, 122, 26),
					Material = Enum.Material.Neon,
				}),
				CFrame.new(pos * b) * (if isSide then CFrame.Angles(math.rad(angle), 0, 0) else CFrame.Angles(0, 0, math.rad(angle)))
			)
		end
	elseif pet.v == "Neon" then
		add(
			newPart({
				Name = "Glow",
				Size = Vector3.one * b * 1.08,
				Color = Color3.fromRGB(43, 245, 154),
				Material = Enum.Material.Neon,
				Transparency = 0.78,
			}),
			CFrame.identity
		)
	elseif pet.v == "Golden" or pet.v == "Crystal" then
		add(
			newPart({
				Name = "Sparkle",
				Size = Vector3.one * b * 0.14,
				Color = if pet.v == "Golden" then Color3.fromRGB(255, 240, 160) else Color3.fromRGB(230, 250, 255),
				Material = Enum.Material.Neon,
			}),
			CFrame.new(0.62 * b, 0.55 * b, -0.3 * b) * CFrame.Angles(0, 0, math.rad(45))
		)
	end

	-- Face (front is -Z)
	local zFace = -0.5 * b - 0.01
	local function eye(x: number, sizeX: number, sizeY: number, color: Color3?, angle: number?)
		add(
			newPart({ Name = "Eye", Size = Vector3.new(sizeX, sizeY, 0.04) * b, Color = color or eyeColor }),
			CFrame.new(x * b, 0.08 * b, zFace) * CFrame.Angles(0, 0, math.rad(angle or 0))
		)
	end
	if face == "shades" then
		add(newPart({ Name = "Shades", Size = Vector3.new(0.78, 0.2, 0.04) * b, Color = INK }), CFrame.new(0, 0.08 * b, zFace))
	elseif face == "happy" or face == "sleepy" or face == "closed" then
		for _, x in { -0.22, 0.22 } do
			eye(x, 0.2, 0.05)
		end
	elseif face == "square" then
		for _, x in { -0.22, 0.22 } do
			eye(x, 0.17, 0.13, if pet.v == "Normal" then Color3.fromRGB(124, 245, 224) else nil)
		end
	else
		for _, x in { -0.22, 0.22 } do
			eye(x, 0.14, 0.16)
			add(
				newPart({ Name = "Shine", Size = Vector3.new(0.05, 0.05, 0.04) * b, Color = Color3.new(1, 1, 1) }),
				CFrame.new((x + 0.03) * b, 0.12 * b, zFace - 0.01)
			)
		end
		if face == "angry" then
			for _, side in { -1, 1 } do
				add(
					newPart({ Name = "Brow", Size = Vector3.new(0.18, 0.04, 0.04) * b, Color = eyeColor }),
					CFrame.new(side * 0.22 * b, 0.22 * b, zFace) * CFrame.Angles(0, 0, math.rad(side * -20))
				)
			end
		end
	end
	add(newPart({ Name = "Mouth", Size = Vector3.new(0.16, 0.04, 0.04) * b, Color = eyeColor }), CFrame.new(0, -0.15 * b, zFace))

	-- Feet
	for _, x in { -0.25, 0.25 } do
		add(
			newPart({ Name = "Foot", Size = Vector3.new(0.28, 0.1, 0.32) * b, Color = darken(bodyColor, 0.3) }),
			CFrame.new(x * b, -0.55 * b, 0)
		)
	end

	-- Top part
	local topColor = if pet.v == "Pixel" then baseColor else bodyColor
	local cream = Color3.fromRGB(245, 230, 200)
	local gold = Color3.fromRGB(255, 212, 71)
	local topY = 0.5 * b
	if top == "cat" then
		for _, x in { -0.3, 0.3 } do
			add(
				newPart({ Name = "Ear", Size = Vector3.new(0.3, 0.3, 0.12) * b, Color = topColor }),
				CFrame.new(x * b, topY, 0) * CFrame.Angles(0, 0, math.rad(45))
			)
		end
	elseif top == "bunny" then
		for _, x in { -0.22, 0.22 } do
			add(
				newPart({ Name = "Ear", Size = Vector3.new(0.18, 0.6, 0.1) * b, Color = topColor }),
				CFrame.new(x * b, topY + 0.28 * b, 0)
			)
		end
	elseif top == "round" then
		for _, x in { -0.35, 0.35 } do
			add(
				newPart({ Name = "Ear", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.32 * b, Color = topColor }),
				CFrame.new(x * b, topY, 0)
			)
		end
	elseif top == "horns" then
		for _, side in { -1, 1 } do
			add(
				newPart({ Name = "Horn", Size = Vector3.new(0.12, 0.38, 0.12) * b, Color = cream }),
				CFrame.new(side * 0.3 * b, topY + 0.15 * b, 0) * CFrame.Angles(0, 0, math.rad(side * -25))
			)
		end
	elseif top == "antenna" then
		add(newPart({ Name = "Stick", Size = Vector3.new(0.06, 0.35, 0.06) * b, Color = INK }), CFrame.new(0, topY + 0.17 * b, 0))
		add(
			newPart({
				Name = "Tip",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.16 * b,
				Color = Color3.fromRGB(255, 90, 90),
				Material = Enum.Material.Neon,
			}),
			CFrame.new(0, topY + 0.38 * b, 0)
		)
	elseif top == "leaf" then
		add(
			newPart({ Name = "Stem", Size = Vector3.new(0.05, 0.2, 0.05) * b, Color = Color3.fromRGB(62, 142, 78) }),
			CFrame.new(0, topY + 0.1 * b, 0)
		)
		add(
			newPart({ Name = "Leaf", Size = Vector3.new(0.36, 0.06, 0.2) * b, Color = Color3.fromRGB(108, 200, 111) }),
			CFrame.new(0.15 * b, topY + 0.22 * b, 0) * CFrame.Angles(0, 0, math.rad(20))
		)
	elseif top == "unihorn" then
		add(
			newPart({ Name = "Horn", Size = Vector3.new(0.12, 0.45, 0.12) * b, Color = gold }),
			CFrame.new(0, topY + 0.2 * b, -0.12 * b) * CFrame.Angles(math.rad(-15), 0, 0)
		)
	elseif top == "halo" then
		add(
			newPart({
				Name = "Halo",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.05, 0.6, 0.6) * b,
				Color = gold,
				Material = Enum.Material.Neon,
			}),
			CFrame.new(0, topY + 0.32 * b, 0) * CFrame.Angles(0, 0, math.rad(90))
		)
	elseif top == "crown" then
		add(newPart({ Name = "Crown", Size = Vector3.new(0.6, 0.14, 0.6) * b, Color = gold, Material = Enum.Material.Foil }), CFrame.new(0, topY + 0.07 * b, 0))
		for _, x in { -0.22, 0, 0.22 } do
			add(
				newPart({ Name = "Spike", Size = Vector3.new(0.12, 0.2, 0.12) * b, Color = gold, Material = Enum.Material.Foil }),
				CFrame.new(x * b, topY + 0.22 * b, -0.22 * b)
			)
		end
	elseif top == "hat" then
		add(
			newPart({ Name = "Brim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 0.8, 0.8) * b, Color = INK }),
			CFrame.new(0, topY + 0.03 * b, 0) * CFrame.Angles(0, 0, math.rad(90))
		)
		add(
			newPart({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 0.5, 0.5) * b, Color = INK }),
			CFrame.new(0, topY + 0.25 * b, 0) * CFrame.Angles(0, 0, math.rad(90))
		)
	elseif top == "cap" then
		add(
			newPart({
				Name = "Cap",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, 1.3, 1.3) * b,
				Color = Color3.fromRGB(215, 60, 60),
			}),
			CFrame.new(0, topY + 0.1 * b, 0) * CFrame.Angles(0, 0, math.rad(90))
		)
	elseif top == "flame" then
		for i, color in { Color3.fromRGB(255, 120, 30), Color3.fromRGB(255, 190, 60), Color3.fromRGB(255, 240, 150) } do
			add(
				newPart({
					Name = "Flame",
					Size = Vector3.new(0.32 - i * 0.07, 0.3, 0.32 - i * 0.07) * b,
					Color = color,
					Material = Enum.Material.Neon,
				}),
				CFrame.new(0, topY + (0.1 + i * 0.12) * b, 0) * CFrame.Angles(0, math.rad(i * 25), 0)
			)
		end
	end

	return {
		model = model,
		body = body,
		parts = parts,
		offsets = offsets,
		height = b * 1.1,
		radius = b * 0.75,
	}
end

-- Places a freshly built model at a CFrame (used for icons and previews).
function PetModel.place(built: Built, cframe: CFrame)
	for i, p in built.parts do
		p.CFrame = cframe * built.offsets[i]
	end
end

return PetModel
