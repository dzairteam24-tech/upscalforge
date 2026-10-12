--!strict
-- How an egg looks, like Steal an Egg's: stacked cube layers in an egg's outline (narrow at the bottom, widest
-- low down, small at the top), not a smooth ball. Any egg part becomes one: the part itself keeps its size (what
-- it's held by, what sits in a nest, the prompts on it) but draws nothing (its sphere mesh is shrunk to nothing),
-- and the layers, welded to it, are what's seen. Its Transparency still says whether it's there (a Wild nest's
-- empty egg): setVisible follows it to the layers.

local EggModel = {}

local Creatures = require(script.Parent.Config.Creatures)

-- (each layer, bottom to top: its width as a share of the egg's)
local WIDTHS = { 0.62, 0.88, 1, 0.97, 0.86, 0.66, 0.4 }

-- An egg with a known creature in it looks like it, like Steal an Egg's: its color, and a few of its features
-- (in the egg's widths: across, up from the middle (its top at 0.65), back; turned in degrees; a shade of its color
-- or a color of its own). Front is -Z.
type Feature = { size: Vector3, at: Vector3, turn: Vector3?, shade: number?, color: Color3? }
local v = Vector3.new
local FEATURES: { [string]: { Feature } } = {
	Dog = { -- floppy ears, a little tail
		{ size = v(0.16, 0.36, 0.12), at = v(-0.46, 0.22, 0), turn = v(0, 0, -12), shade = -0.25 },
		{ size = v(0.16, 0.36, 0.12), at = v(0.46, 0.22, 0), turn = v(0, 0, 12), shade = -0.25 },
		{ size = v(0.1, 0.1, 0.3), at = v(0, -0.15, 0.55), turn = v(35, 0, 0) },
	},
	Cat = { -- pointy ears, a long tail curling up
		{ size = v(0.2, 0.22, 0.1), at = v(-0.15, 0.68, 0), turn = v(0, 0, 18) },
		{ size = v(0.2, 0.22, 0.1), at = v(0.15, 0.68, 0), turn = v(0, 0, -18) },
		{ size = v(0.09, 0.09, 0.5), at = v(0, -0.1, 0.62), turn = v(50, 0, 0), shade = -0.15 },
	},
	Bunny = { -- long ears, pink inside
		{ size = v(0.13, 0.5, 0.08), at = v(-0.12, 0.85, 0) },
		{ size = v(0.13, 0.5, 0.08), at = v(0.12, 0.85, 0) },
		{ size = v(0.06, 0.36, 0.02), at = v(-0.12, 0.85, -0.05), color = Color3.fromRGB(255, 170, 200) },
		{ size = v(0.06, 0.36, 0.02), at = v(0.12, 0.85, -0.05), color = Color3.fromRGB(255, 170, 200) },
	},
	Bear = { -- round ears
		{ size = v(0.22, 0.2, 0.14), at = v(-0.2, 0.62, 0), shade = -0.2 },
		{ size = v(0.22, 0.2, 0.14), at = v(0.2, 0.62, 0), shade = -0.2 },
	},
	Chicken = { -- a red comb, a yellow beak
		{ size = v(0.09, 0.2, 0.32), at = v(0, 0.7, 0), color = Color3.fromRGB(230, 50, 50) },
		{ size = v(0.16, 0.1, 0.14), at = v(0, 0.15, -0.55), color = Color3.fromRGB(255, 190, 60) },
	},
	Pig = { -- a snout, little ears, a curly tail
		{ size = v(0.32, 0.22, 0.08), at = v(0, 0, -0.52), shade = -0.12 },
		{ size = v(0.16, 0.14, 0.08), at = v(-0.2, 0.62, 0), turn = v(0, 0, 25), shade = -0.12 },
		{ size = v(0.16, 0.14, 0.08), at = v(0.2, 0.62, 0), turn = v(0, 0, -25), shade = -0.12 },
		{ size = v(0.08, 0.08, 0.2), at = v(0, -0.05, 0.55), turn = v(60, 30, 0), shade = -0.12 },
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
	},
}

-- The color an egg with this creature in it is (its own), or nil when it's not a known one
function EggModel.colorOf(species: string?): Color3?
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
		if old.Name == "EggLayer" then
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
	for i, share in WIDTHS do
		local layer = Instance.new("Part")
		layer.Name = "EggLayer"
		layer.Size = Vector3.new(width * share, step, width * share)
		layer.CFrame = part.CFrame * CFrame.new(0, -height / 2 + step * (i - 0.5), 0)
		-- (a little lighter toward the top, like light on it)
		layer.Color = if golden then Color3.fromRGB(255, 205, 70):Lerp(Color3.fromRGB(255, 240, 160), i / #WIDTHS * 0.5) else lighten(color, (i - 1) / #WIDTHS * 0.25)
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
		bit.CFrame = part.CFrame * CFrame.new(feature.at * width) * CFrame.Angles(math.rad(turn.X), math.rad(turn.Y), math.rad(turn.Z))
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
end

-- Shows or hides a dressed egg (its layers with it)
function EggModel.setVisible(part: BasePart, visible: boolean)
	part.Transparency = if visible then 0 else 1
	for _, layer in part:GetChildren() do
		if layer.Name == "EggLayer" and layer:IsA("BasePart") then
			layer.Transparency = if visible then 0 else 1
		end
	end
end

return EggModel
