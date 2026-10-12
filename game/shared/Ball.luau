--!strict
-- A creature carried as a ball (like a Pokéball): a sphere in its rarity's color with a dark belt and a white
-- button, so what's carried isn't the creature itself.

local Creatures = require(script.Parent.Config.Creatures)

local COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(170, 176, 190),
	Uncommon = Color3.fromRGB(92, 214, 110),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(176, 110, 255),
	Legendary = Color3.fromRGB(255, 190, 50),
	Mythic = Color3.fromRGB(255, 60, 110),
}

local Ball = {}

Ball.SIZE = 2.2

-- The color of a species' ball (its rarity's)
function Ball.color(species: string): Color3
	local found = Creatures.byId[species]
	return COLORS[if found then found.rarity else "Common"] or COLORS.Common
end

-- The ball's parts, round `at` (its middle), welded to its body. Returns the model and its body.
function Ball.build(species: string, at: CFrame, anchored: boolean): (Model, Part)
	local model = Instance.new("Model")
	model.Name = "Ball"
	local function part(name: string, shape: Enum.PartType, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = frame
		p.Color = color
		p.Material = material
		p.Anchored = anchored
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local body = part("Body", Enum.PartType.Ball, Vector3.one * Ball.SIZE, at, Ball.color(species), Enum.Material.SmoothPlastic)
	-- (a thin disc a little wider than the ball: the belt round its middle)
	local belt = part("Belt", Enum.PartType.Cylinder, Vector3.new(0.3, Ball.SIZE + 0.1, Ball.SIZE + 0.1), at * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(34, 30, 46), Enum.Material.SmoothPlastic)
	local button = part("Button", Enum.PartType.Ball, Vector3.one * 0.8, at * CFrame.new(0, 0, -Ball.SIZE / 2), Color3.new(1, 1, 1), Enum.Material.Neon)
	for _, other in { belt, button } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = body, other
		weld.Parent = other
	end
	model.PrimaryPart = body
	return model, body
end

return Ball
