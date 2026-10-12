--!strict
-- How an egg looks: an egg built of bricks with studs on top, like a toy, after the game's own egg sheet. Any
-- egg part becomes one: the part keeps its size (what it's held by, what sits in a nest, the prompts on it) but
-- draws nothing (its sphere mesh is shrunk to nothing), and the bricks, welded to it, are what's seen. Its
-- Transparency still says whether it's there (a Wild nest's empty egg): setVisible follows it to the bricks.
-- An egg with a known creature in it (Logic/Hatch) is painted like it: its shell's colors and pattern, and a
-- little of it poking out of the shell (ears, a comb, a tail). It's an egg, not the creature: no face.

local Creatures = require(script.Parent.Config.Creatures)
local Mystery = require(script.Parent.Config.Mystery)

local EggModel = {}

-- (the shell's layers, bottom to top: each one's width as a share of the egg's)
local WIDTHS = { 0.6, 0.82, 0.95, 1, 1, 0.96, 0.86, 0.7, 0.45 }
local TALL = 1.3 -- (an egg is drawn this many times as tall as it's wide)

local rgb = Color3.fromRGB

-- A brick on the shell: on one of its sides (front -Z, back, left, right), from layer `from` up `layers`
-- layers, `along` the side (-1 to 1), this wide (a share of the egg); a cross is a "+" of two bricks
type Patch = { side: string, from: number, layers: number?, along: number?, wide: number?, color: Color3, cross: boolean? }
-- A piece of the creature poking out: its size, where (in the egg's widths: across, up from the middle (its top
-- at 0.65), back), turned (degrees), its color
type Piece = { size: Vector3, at: Vector3, turn: Vector3?, color: Color3 }
-- A design: its shell's color, the layers' own colors (stripes, a rainbow, a dark cap), its bricks and pieces,
-- and its sparkles (a rare egg)
type Design = { shell: Color3, layers: { [number]: Color3 }?, patches: { Patch }?, pieces: { Piece }?, sparkle: ColorSequence? }

local v = Vector3.new
local PURPLE_SPARKLE = ColorSequence.new(rgb(200, 120, 255), rgb(240, 200, 255))

local DESIGNS: { [string]: Design } = {
	Dog = { -- cream, brown patches, floppy brown ears
		shell = rgb(242, 222, 188),
		patches = {
			{ side = "front", from = 3, layers = 2, along = -0.45, wide = 0.36, color = rgb(132, 76, 38) },
			{ side = "front", from = 6, layers = 1, along = 0.5, wide = 0.26, color = rgb(132, 76, 38) },
			{ side = "left", from = 2, layers = 2, along = 0.3, wide = 0.34, color = rgb(132, 76, 38) },
			{ side = "right", from = 5, layers = 2, along = -0.3, wide = 0.3, color = rgb(132, 76, 38) },
			{ side = "back", from = 4, layers = 2, along = 0.1, wide = 0.4, color = rgb(132, 76, 38) },
		},
		pieces = {
			{ size = v(0.2, 0.5, 0.34), at = v(-0.44, 0.42, 0), turn = v(0, 0, -20), color = rgb(132, 76, 38) },
			{ size = v(0.2, 0.5, 0.34), at = v(0.44, 0.42, 0), turn = v(0, 0, 20), color = rgb(132, 76, 38) },
		},
	},
	Chicken = { -- white, yellow crosses, a red "+" comb
		shell = rgb(250, 250, 246),
		patches = {
			{ side = "front", from = 5, along = 0.45, wide = 0.3, color = rgb(255, 205, 40), cross = true },
			{ side = "front", from = 2, along = -0.35, wide = 0.3, color = rgb(255, 205, 40), cross = true },
			{ side = "left", from = 4, along = 0, wide = 0.3, color = rgb(255, 205, 40), cross = true },
			{ side = "right", from = 3, along = 0.3, wide = 0.3, color = rgb(255, 205, 40), cross = true },
			{ side = "back", from = 6, along = -0.2, wide = 0.3, color = rgb(255, 205, 40), cross = true },
		},
		pieces = {
			{ size = v(0.12, 0.34, 0.12), at = v(0, 0.78, 0), color = rgb(230, 40, 40) },
			{ size = v(0.34, 0.12, 0.12), at = v(0, 0.8, 0), color = rgb(230, 40, 40) },
		},
	},
	Cat = { -- orange stripes, pointy ears pink inside
		shell = rgb(255, 176, 60),
		layers = { [2] = rgb(240, 110, 30), [4] = rgb(240, 110, 30), [6] = rgb(240, 110, 30), [8] = rgb(240, 110, 30) },
		pieces = {
			{ size = v(0.24, 0.3, 0.12), at = v(-0.2, 0.68, 0), turn = v(0, 0, 16), color = rgb(240, 110, 30) },
			{ size = v(0.24, 0.3, 0.12), at = v(0.2, 0.68, 0), turn = v(0, 0, -16), color = rgb(240, 110, 30) },
			{ size = v(0.12, 0.16, 0.04), at = v(-0.2, 0.67, -0.07), turn = v(0, 0, 16), color = rgb(255, 170, 200) },
			{ size = v(0.12, 0.16, 0.04), at = v(0.2, 0.67, -0.07), turn = v(0, 0, -16), color = rgb(255, 170, 200) },
		},
	},
	Pig = { -- pink, darker pink blotches, floppy ears, a curly tail
		shell = rgb(255, 196, 214),
		patches = {
			{ side = "front", from = 3, layers = 2, along = 0.3, wide = 0.36, color = rgb(244, 110, 160) },
			{ side = "front", from = 6, along = -0.45, wide = 0.28, color = rgb(244, 110, 160) },
			{ side = "left", from = 4, layers = 2, along = -0.2, wide = 0.34, color = rgb(244, 110, 160) },
			{ side = "right", from = 2, layers = 2, along = 0.2, wide = 0.3, color = rgb(244, 110, 160) },
			{ side = "back", from = 5, layers = 2, along = 0, wide = 0.36, color = rgb(244, 110, 160) },
		},
		pieces = {
			{ size = v(0.24, 0.12, 0.26), at = v(-0.3, 0.66, 0), turn = v(0, 0, 25), color = rgb(255, 160, 195) },
			{ size = v(0.24, 0.12, 0.26), at = v(0.3, 0.66, 0), turn = v(0, 0, -25), color = rgb(255, 160, 195) },
			-- (the curly tail: a few little bricks round and round)
			{ size = v(0.08, 0.08, 0.16), at = v(0.1, -0.05, 0.56), color = rgb(255, 160, 195) },
			{ size = v(0.08, 0.16, 0.08), at = v(0.16, 0.04, 0.62), color = rgb(255, 160, 195) },
			{ size = v(0.14, 0.08, 0.08), at = v(0.12, 0.1, 0.62), color = rgb(255, 160, 195) },
		},
	},
	Bunny = { -- white, pink crosses, tall ears pink inside
		shell = rgb(250, 248, 250),
		patches = {
			{ side = "front", from = 2, along = -0.4, wide = 0.3, color = rgb(255, 140, 190), cross = true },
			{ side = "front", from = 4, along = 0.45, wide = 0.3, color = rgb(255, 140, 190), cross = true },
			{ side = "left", from = 5, along = 0, wide = 0.3, color = rgb(255, 140, 190), cross = true },
			{ side = "right", from = 3, along = -0.2, wide = 0.3, color = rgb(255, 140, 190), cross = true },
			{ side = "back", from = 3, along = 0.2, wide = 0.3, color = rgb(255, 140, 190), cross = true },
		},
		pieces = {
			{ size = v(0.16, 0.6, 0.1), at = v(-0.15, 0.95, 0), color = rgb(250, 248, 250) },
			{ size = v(0.16, 0.6, 0.1), at = v(0.15, 0.95, 0), color = rgb(250, 248, 250) },
			{ size = v(0.08, 0.46, 0.03), at = v(-0.15, 0.95, -0.06), color = rgb(255, 160, 200) },
			{ size = v(0.08, 0.46, 0.03), at = v(0.15, 0.95, -0.06), color = rgb(255, 160, 200) },
		},
	},
	Sheep = { -- wool all over, a dark cap, dark floppy ears
		shell = rgb(246, 242, 232),
		layers = { [8] = rgb(80, 78, 86), [9] = rgb(80, 78, 86) },
		pieces = {
			{ size = v(0.22, 0.14, 0.36), at = v(-0.46, 0.38, 0), turn = v(0, 0, -25), color = rgb(80, 78, 86) },
			{ size = v(0.22, 0.14, 0.36), at = v(0.46, 0.38, 0), turn = v(0, 0, 25), color = rgb(80, 78, 86) },
		},
	},
	Bear = { -- brown, a tan belly, round ears tan inside; it sparkles (Epic)
		shell = rgb(150, 86, 44),
		layers = { [3] = rgb(132, 74, 36), [6] = rgb(132, 74, 36) },
		patches = {
			{ side = "front", from = 2, layers = 4, along = 0, wide = 0.56, color = rgb(232, 196, 140) },
		},
		pieces = {
			{ size = v(0.28, 0.26, 0.14), at = v(-0.26, 0.66, 0), color = rgb(150, 86, 44) },
			{ size = v(0.28, 0.26, 0.14), at = v(0.26, 0.66, 0), color = rgb(150, 86, 44) },
			{ size = v(0.14, 0.13, 0.04), at = v(-0.26, 0.66, -0.08), color = rgb(232, 196, 140) },
			{ size = v(0.14, 0.13, 0.04), at = v(0.26, 0.66, -0.08), color = rgb(232, 196, 140) },
		},
		sparkle = PURPLE_SPARKLE,
	},
	Horse = { -- chestnut, a cream stripe down its front, a dark mane, ears pink inside; it sparkles (Epic)
		shell = rgb(168, 92, 44),
		patches = {
			{ side = "front", from = 1, layers = 8, along = 0, wide = 0.24, color = rgb(244, 226, 196) },
		},
		pieces = {
			{ size = v(0.16, 0.12, 0.5), at = v(0, 0.7, 0.05), color = rgb(70, 40, 24) },
			{ size = v(0.14, 0.5, 0.14), at = v(0, 0.35, 0.42), turn = v(-12, 0, 0), color = rgb(70, 40, 24) },
			{ size = v(0.2, 0.3, 0.12), at = v(-0.2, 0.74, -0.05), turn = v(0, 0, 14), color = rgb(168, 92, 44) },
			{ size = v(0.2, 0.3, 0.12), at = v(0.2, 0.74, -0.05), turn = v(0, 0, -14), color = rgb(168, 92, 44) },
			{ size = v(0.1, 0.16, 0.04), at = v(-0.2, 0.73, -0.12), turn = v(0, 0, 14), color = rgb(255, 170, 200) },
			{ size = v(0.1, 0.16, 0.04), at = v(0.2, 0.73, -0.12), turn = v(0, 0, -14), color = rgb(255, 170, 200) },
		},
		sparkle = PURPLE_SPARKLE,
	},
	-- The Mystery Egg: rainbow layers, a big gold "?" on its front (drawn in dress), gold stars all round
	Mystery = {
		shell = rgb(190, 120, 255),
		layers = {
			[1] = rgb(150, 70, 230), [2] = rgb(90, 90, 240), [3] = rgb(60, 170, 250), [4] = rgb(60, 210, 140),
			[5] = rgb(150, 220, 60), [6] = rgb(255, 220, 50), [7] = rgb(255, 160, 40), [8] = rgb(250, 80, 60), [9] = rgb(240, 60, 110),
		},
		sparkle = ColorSequence.new(rgb(255, 220, 80), rgb(255, 250, 200)),
	},
}

-- The color an egg with this creature in it is (its shell's), or nil when it's not a known one
function EggModel.colorOf(species: string?): Color3?
	local design = if species then DESIGNS[species] else nil
	if design then
		return design.shell
	end
	local creature = if species then Creatures.byId[species] else nil
	return if creature then creature.color else nil
end

local function brick(parent: BasePart, name: string, size: Vector3, frame: CFrame, color: Color3, golden: boolean?, hidden: boolean, studs: boolean?)
	local b = Instance.new("Part")
	b.Name = name
	b.Size = size
	b.CFrame = frame
	b.Color = if golden then color:Lerp(rgb(255, 205, 70), 0.75) else color
	b.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
	b.TopSurface = if studs then Enum.SurfaceType.Studs else Enum.SurfaceType.Smooth
	b.BottomSurface = Enum.SurfaceType.Smooth
	b.Anchored = false
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.Massless = true
	b.CastShadow = false
	b.Transparency = if hidden then 1 else 0
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parent
	weld.Part1 = b
	weld.Parent = b
	b.Parent = parent
end

-- Draws the egg part as a brick egg in this color (golden: shining); with the creature in it known, in its
-- design (DESIGNS). Again on the same part, it redraws it (a new color, size or creature).
function EggModel.dress(part: BasePart, color: Color3, golden: boolean?, species: string?)
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
	local tall = if scale.Y > 0 then TALL else (part:GetAttribute("EggTall") or TALL) :: number
	part:SetAttribute("EggTall", tall)
	;(mesh :: SpecialMesh).Scale = Vector3.zero -- (the part itself draws nothing)
	local design = if species then DESIGNS[species] else nil
	local shell = if design then design.shell else color
	local width = math.min(part.Size.X, part.Size.Z)
	local height = part.Size.Y * tall
	local step = height / #WIDTHS
	local hidden = part.Transparency >= 1
	-- (turned to face the way it should: a Wild egg faces the gate players come from, its EggFacing in radians)
	local facing = part:GetAttribute("EggFacing")
	local frame = part.CFrame * CFrame.Angles(0, if type(facing) == "number" then facing else 0, 0)
	local function layerY(i: number): number
		return -height / 2 + step * (i - 0.5)
	end
	-- The shell: a layer of bricks each, studs on top
	for i, share in WIDTHS do
		local own = if design and design.layers then design.layers[i] else nil
		local layerColor = own or shell:Lerp(Color3.new(1, 1, 1), (i - 1) / #WIDTHS * 0.12)
		brick(part, "EggLayer", Vector3.new(width * share, step, width * share), frame * CFrame.new(0, layerY(i), 0), layerColor, golden, hidden, true)
	end
	if not design then
		return
	end
	-- Its pattern: bricks set into the shell's sides, each on its own layer's face (so it hugs the shell, stepped)
	local SIDES: { [string]: CFrame } = { front = CFrame.identity, back = CFrame.Angles(0, math.pi, 0), left = CFrame.Angles(0, math.pi / 2, 0), right = CFrame.Angles(0, -math.pi / 2, 0) }
	local thick = width * 0.05
	local function onFace(side: CFrame, i: number, along: number, wide: number, color: Color3)
		local half = WIDTHS[i] * width / 2
		local w = math.min(wide, half * 2)
		local x = math.clamp(along, -half + w / 2, half - w / 2)
		brick(part, "EggLayer", Vector3.new(w, step, thick), frame * side * CFrame.new(x, layerY(i), -half - thick * 0.3), color, golden, hidden)
	end
	for _, patch in design.patches or {} do
		local side = SIDES[patch.side] or CFrame.identity
		local wide = (patch.wide or 0.3) * width
		local top = math.min(#WIDTHS, patch.from + (patch.layers or 1) - 1)
		local along = (patch.along or 0) * width * 0.3
		if patch.cross then
			-- (a "+": a bar across its layer, a block over and under it)
			onFace(side, patch.from, along, wide, patch.color)
			for _, i in { patch.from - 1, patch.from + 1 } do
				if WIDTHS[i] then
					onFace(side, i, along, wide * 0.36, patch.color)
				end
			end
		else
			for i = patch.from, top do
				onFace(side, i, along, wide, patch.color)
			end
		end
	end
	-- The Mystery Egg's "?": a pixel letter on its front, following the shell
	if species == Mystery.ID then
		local QUESTION = { ".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.." }
		local cell = width * 0.12
		for row, line in QUESTION do
			local y = width * 0.42 - (row - 1) * cell
			local i = math.clamp(math.floor((y + height / 2) / step) + 1, 1, #WIDTHS)
			local half = WIDTHS[i] * width / 2
			for col = 1, #line do
				if string.sub(line, col, col) == "#" then
					brick(part, "EggLayer", Vector3.new(cell, cell, thick * 1.6), frame * CFrame.new((col - 3) * cell, y, -half - thick * 0.6), rgb(255, 210, 50), true, hidden)
				end
			end
		end
	end
	-- And a little of the creature poking out of it
	for _, piece in design.pieces or {} do
		local turn = piece.turn or Vector3.zero
		local at = frame * CFrame.new(piece.at * width) * CFrame.Angles(math.rad(turn.X), math.rad(turn.Y), math.rad(turn.Z))
		brick(part, "EggLayer", piece.size * width, at, piece.color, golden, hidden, true)
	end
	-- (the sheep's wool: bumpy bricks all over its sides)
	if species == "Sheep" then
		for i = 2, 7 do
			local half = WIDTHS[i] * width / 2
			for k = 0, 3 do
				local turn = CFrame.Angles(0, k * math.pi / 2 + (if i % 2 == 0 then 0.4 else -0.3), 0)
				for _, along in { -0.45, 0.3 } do
					brick(part, "EggLayer", Vector3.one * width * 0.24, frame * turn * CFrame.new(along * half, layerY(i), -half), shell:Lerp(Color3.new(1, 1, 1), 0.3), golden, hidden, true)
				end
			end
		end
	end
	-- A rare one sparkles, seen from afar
	if design.sparkle then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "EggSparkle"
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = design.sparkle
		sparkle.LightEmission = 0.9
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, width * 0.4), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Rate = if species == Mystery.ID then 10 else 5
		sparkle.Speed = NumberRange.new(0.6, 1.6)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Acceleration = Vector3.new(0, 1, 0)
		sparkle.Enabled = not hidden
		sparkle.Parent = part
	end
end

-- Shows or hides a dressed egg (its bricks and sparkles with it)
function EggModel.setVisible(part: BasePart, visible: boolean)
	part.Transparency = if visible then 0 else 1
	for _, child in part:GetChildren() do
		if child.Name == "EggLayer" and child:IsA("BasePart") then
			child.Transparency = if visible then 0 else 1
		elseif child:IsA("ParticleEmitter") then
			child.Enabled = visible
		end
	end
end

return EggModel
