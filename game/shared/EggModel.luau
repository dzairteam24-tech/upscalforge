--!strict
-- How an egg looks, like Steal an Egg's: stacked cube layers in an egg's outline (narrow at the bottom, widest
-- low down, small at the top), not a smooth ball. Any egg part becomes one: the part itself keeps its size (what
-- it's held by, what sits in a nest, the prompts on it) but draws nothing (its sphere mesh is shrunk to nothing),
-- and the layers, welded to it, are what's seen. Its Transparency still says whether it's there (a Wild nest's
-- empty egg): setVisible follows it to the layers.

local EggModel = {}

local Creatures = require(script.Parent.Config.Creatures)
local Mystery = require(script.Parent.Config.Mystery)

-- (each layer, bottom to top: its width as a share of the egg's)
local WIDTHS = { 0.62, 0.88, 1, 0.97, 0.86, 0.66, 0.4 }

-- An egg with a known creature in it looks like it, like Steal an Egg's: its color, and a few of its features
-- (in the egg's widths: across, up from the middle (its top at 0.65), back; turned in degrees; a shade of its color
-- or a color of its own). Front is -Z.
type Feature = { size: Vector3, at: Vector3, turn: Vector3?, shade: number?, color: Color3? }
local v = Vector3.new
local FEATURES: { [string]: { Feature } } = {
	Dog = { -- floppy ears, a little tail, a dark patch round one eye
		{ size = v(0.16, 0.36, 0.12), at = v(-0.46, 0.22, 0), turn = v(0, 0, -12), shade = -0.25 },
		{ size = v(0.16, 0.36, 0.12), at = v(0.46, 0.22, 0), turn = v(0, 0, 12), shade = -0.25 },
		{ size = v(0.1, 0.1, 0.3), at = v(0, -0.15, 0.55), turn = v(35, 0, 0) },
		{ size = v(0.26, 0.24, 0.04), at = v(-0.18, 0.18, -0.5), shade = -0.35 },
	},
	Cat = { -- pointy ears, a long tail curling up
		{ size = v(0.2, 0.22, 0.1), at = v(-0.15, 0.68, 0), turn = v(0, 0, 18) },
		{ size = v(0.2, 0.22, 0.1), at = v(0.15, 0.68, 0), turn = v(0, 0, -18) },
		{ size = v(0.09, 0.09, 0.5), at = v(0, -0.1, 0.62), turn = v(50, 0, 0), shade = -0.15 },
		{ size = v(0.08, 0.06, 0.03), at = v(-0.12, 0.42, -0.45), color = Color3.fromRGB(255, 170, 200) }, -- (the inside of its ears)
		{ size = v(0.08, 0.06, 0.03), at = v(0.12, 0.42, -0.45), color = Color3.fromRGB(255, 170, 200) },
	},
	Bunny = { -- long ears, pink inside
		{ size = v(0.13, 0.5, 0.08), at = v(-0.12, 0.85, 0) },
		{ size = v(0.13, 0.5, 0.08), at = v(0.12, 0.85, 0) },
		{ size = v(0.06, 0.36, 0.02), at = v(-0.12, 0.85, -0.05), color = Color3.fromRGB(255, 170, 200) },
		{ size = v(0.06, 0.36, 0.02), at = v(0.12, 0.85, -0.05), color = Color3.fromRGB(255, 170, 200) },
		{ size = v(0.24, 0.24, 0.2), at = v(0, -0.3, 0.52), shade = 0.4 }, -- (a fluffy tail)
	},
	Bear = { -- round ears
		{ size = v(0.22, 0.2, 0.14), at = v(-0.2, 0.62, 0), shade = -0.2 },
		{ size = v(0.22, 0.2, 0.14), at = v(0.2, 0.62, 0), shade = -0.2 },
		{ size = v(0.46, 0.5, 0.04), at = v(0, -0.08, -0.5), shade = 0.35 }, -- (a light belly)
	},
	Chicken = { -- a red comb, a yellow beak
		{ size = v(0.09, 0.2, 0.32), at = v(0, 0.7, 0), color = Color3.fromRGB(230, 50, 50) },
		{ size = v(0.16, 0.1, 0.14), at = v(0, 0.15, -0.55), color = Color3.fromRGB(255, 190, 60) },
		{ size = v(0.08, 0.36, 0.42), at = v(-0.52, 0, 0.05), turn = v(0, 0, 8), shade = -0.12 }, -- (little wings)
		{ size = v(0.08, 0.36, 0.42), at = v(0.52, 0, 0.05), turn = v(0, 0, -8), shade = -0.12 },
	},
	Pig = { -- a snout, little ears, a curly tail
		{ size = v(0.32, 0.22, 0.08), at = v(0, 0, -0.52), shade = -0.12 },
		{ size = v(0.16, 0.14, 0.08), at = v(-0.2, 0.62, 0), turn = v(0, 0, 25), shade = -0.12 },
		{ size = v(0.16, 0.14, 0.08), at = v(0.2, 0.62, 0), turn = v(0, 0, -25), shade = -0.12 },
		{ size = v(0.08, 0.08, 0.2), at = v(0, -0.05, 0.55), turn = v(60, 30, 0), shade = -0.12 },
		{ size = v(0.2, 0.16, 0.04), at = v(0.3, 0.3, -0.38), turn = v(0, 30, 0), shade = -0.18 }, -- (spots)
		{ size = v(0.16, 0.14, 0.04), at = v(-0.35, -0.25, -0.33), turn = v(0, -30, 0), shade = -0.18 },
	},
	Sheep = { -- woolly bumps all round, a dark face
		{ size = v(0.32, 0.32, 0.32), at = v(-0.42, 0.05, 0) },
		{ size = v(0.32, 0.32, 0.32), at = v(0.42, 0.05, 0) },
		{ size = v(0.32, 0.32, 0.32), at = v(0, 0.05, 0.42) },
		{ size = v(0.3, 0.3, 0.3), at = v(-0.25, 0.38, 0.2) },
		{ size = v(0.3, 0.3, 0.3), at = v(0.25, 0.38, 0.2) },
		{ size = v(0.34, 0.3, 0.06), at = v(0, 0.12, -0.5), color = Color3.fromRGB(70, 66, 72) },
	},
	Horse = { -- a dark mane down its back, a tail
		{ size = v(0.12, 0.6, 0.14), at = v(0, 0.3, 0.42), turn = v(-15, 0, 0), shade = -0.45 },
		{ size = v(0.1, 0.42, 0.1), at = v(0, -0.25, 0.56), turn = v(-25, 0, 0), shade = -0.45 },
		{ size = v(0.12, 0.5, 0.04), at = v(0, 0.1, -0.5), color = Color3.fromRGB(250, 248, 240) }, -- (a white blaze)
	},
	-- The Mystery Egg: a gold "?" on its front (its layers are a rainbow)
	Mystery = {
		{ size = v(0.36, 0.11, 0.05), at = v(0, 0.42, -0.44), color = Color3.fromRGB(255, 215, 70) },
		{ size = v(0.11, 0.2, 0.05), at = v(0.13, 0.31, -0.46), color = Color3.fromRGB(255, 215, 70) },
		{ size = v(0.2, 0.11, 0.05), at = v(0.05, 0.19, -0.48), color = Color3.fromRGB(255, 215, 70) },
		{ size = v(0.11, 0.14, 0.05), at = v(0, 0.08, -0.5), color = Color3.fromRGB(255, 215, 70) },
		{ size = v(0.11, 0.11, 0.05), at = v(0, -0.12, -0.5), color = Color3.fromRGB(255, 215, 70) },
	},
}

-- Patterns on the layers themselves: a cat's stripes (every other layer darker); the Mystery Egg's rainbow
local function layerColor(species: string?, color: Color3, i: number, count: number): Color3
	if species == Mystery.ID then
		return Color3.fromHSV((i - 1) / count * 0.85, 0.55, 1)
	elseif species == "Cat" and i % 2 == 0 then
		return color:Lerp(Color3.new(0, 0, 0), 0.22)
	end
	return color:Lerp(Color3.new(1, 1, 1), (i - 1) / count * 0.25) -- (a little lighter toward the top, like light on it)
end

-- Sparkles round a rare egg, so it's seen from afar: Rare blue, Epic purple, Legendary gold, the Mystery Egg a
-- rainbow (nil: none)
local function sparkleColors(species: string?): ColorSequence?
	if species == Mystery.ID then
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 110, 255)),
		})
	end
	local creature = if species then Creatures.byId[species] else nil
	local rarity = if creature then creature.rarity else ""
	local color = if rarity == "Rare" then Color3.fromRGB(90, 180, 255) elseif rarity == "Epic" then Color3.fromRGB(200, 110, 255) elseif rarity == "Legendary" or rarity == "Mythic" then Color3.fromRGB(255, 215, 80) else nil
	return if color then ColorSequence.new(color) else nil
end

-- The color an egg with this creature in it is (its own), or nil when it's not a known one
function EggModel.colorOf(species: string?): Color3?
	if species == Mystery.ID then
		return Color3.fromRGB(190, 120, 255)
	end
	local creature = if species then Creatures.byId[species] else nil
	return if creature then creature.color else nil
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

-- Draws the egg part as stacked layers in this color (golden: shining); with the creature in it known, in its
-- color, with its features. Again on the same part, it redraws them (a new color, size or creature).
function EggModel.dress(part: BasePart, color: Color3, golden: boolean?, species: string?)
	color = EggModel.colorOf(species) or color
	for _, old in part:GetChildren() do
		if old.Name == "EggLayer" or old.Name == "EggSparkle" then
			old:Destroy()
		end
	end
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if not mesh then
		local made = Instance.new("SpecialMesh")
		made.MeshType = Enum.MeshType.Sphere
		made.Parent = part
		mesh = made
	end
	local scale = (mesh :: SpecialMesh).Scale
	local tall = if scale.Y > 0 then 1.3 else (part:GetAttribute("EggTall") or 1.3) :: number
	part:SetAttribute("EggTall", tall)
	;(mesh :: SpecialMesh).Scale = Vector3.zero -- (the part itself draws nothing)
	local width = math.min(part.Size.X, part.Size.Z)
	local height = part.Size.Y * tall
	local step = height / #WIDTHS
	local hidden = part.Transparency >= 1
	-- (turned to face the way it should: a Wild egg faces the gate players come from, its EggFacing in radians)
	local facing = part:GetAttribute("EggFacing")
	local frame = part.CFrame * CFrame.Angles(0, if type(facing) == "number" then facing else 0, 0)
	for i, share in WIDTHS do
		local layer = Instance.new("Part")
		layer.Name = "EggLayer"
		layer.Size = Vector3.new(width * share, step, width * share)
		layer.CFrame = frame * CFrame.new(0, -height / 2 + step * (i - 0.5), 0)
		layer.Color = if golden then Color3.fromRGB(255, 205, 70):Lerp(Color3.fromRGB(255, 240, 160), i / #WIDTHS * 0.5) else layerColor(species, color, i, #WIDTHS)
		layer.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
		layer.TopSurface = Enum.SurfaceType.Smooth
		layer.BottomSurface = Enum.SurfaceType.Smooth
		layer.Anchored = false
		layer.CanCollide = false
		layer.CanQuery = false
		layer.CanTouch = false
		layer.Massless = true
		layer.Transparency = if hidden then 1 else 0
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = layer
		weld.Parent = layer
		layer.Parent = part
	end
	-- (the creature's features: ears, a comb, a tail...)
	for _, feature in (if species then FEATURES[species] else nil) or {} do
		local bit = Instance.new("Part")
		bit.Name = "EggLayer"
		bit.Size = feature.size * width
		local turn = feature.turn or Vector3.zero
		bit.CFrame = frame * CFrame.new(feature.at * width) * CFrame.Angles(math.rad(turn.X), math.rad(turn.Y), math.rad(turn.Z))
		local shade = feature.shade or 0
		bit.Color = if golden then Color3.fromRGB(255, 220, 110) elseif feature.color then feature.color elseif shade < 0 then color:Lerp(Color3.new(0, 0, 0), -shade) else lighten(color, shade)
		bit.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
		bit.Anchored = false
		bit.CanCollide = false
		bit.CanQuery = false
		bit.CanTouch = false
		bit.Massless = true
		bit.Transparency = if hidden then 1 else 0
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = bit
		weld.Parent = bit
		bit.Parent = part
	end
	-- (a rare one sparkles)
	local colors = sparkleColors(species)
	if colors then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "EggSparkle"
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = colors
		sparkle.LightEmission = 0.8
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, width * 0.35), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Rate = if species == Mystery.ID then 8 else 4
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Acceleration = Vector3.new(0, 1, 0)
		sparkle.Enabled = not hidden
		sparkle.Parent = part
	end
end

-- Shows or hides a dressed egg (its layers with it)
function EggModel.setVisible(part: BasePart, visible: boolean)
	part.Transparency = if visible then 0 else 1
	for _, layer in part:GetChildren() do
		if layer.Name == "EggLayer" and layer:IsA("BasePart") then
			layer.Transparency = if visible then 0 else 1
		elseif layer:IsA("ParticleEmitter") then
			layer.Enabled = visible
		end
	end
end

return EggModel
