--!strict
-- How an egg looks, like Steal an Egg's: stacked cube layers in an egg's outline (narrow at the bottom, widest
-- low down, small at the top), not a smooth ball. Any egg part becomes one: the part itself keeps its size (what
-- it's held by, what sits in a nest, the prompts on it) but draws nothing (its sphere mesh is shrunk to nothing),
-- and the layers, welded to it, are what's seen. Its Transparency still says whether it's there (a Wild nest's
-- empty egg): setVisible follows it to the layers.

local EggModel = {}

-- (each layer, bottom to top: its width as a share of the egg's)
local WIDTHS = { 0.62, 0.88, 1, 0.97, 0.86, 0.66, 0.4 }

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

-- Draws the egg part as stacked layers in this color (golden: shining). Again on the same part, it redraws them
-- (a new color or size).
function EggModel.dress(part: BasePart, color: Color3, golden: boolean?)
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
