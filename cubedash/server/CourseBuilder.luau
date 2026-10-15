--!strict
-- Builds the course that everyone shares: each stage's glowing lane, its gate, its checkpoints, the frame its
-- wall of cubes sits in and the floating cubes around it, then the finish at the end, and the night it is all in.
-- (What moves, the orbs and the walls themselves are each player's own and are made on their screen.)

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseConfig = require(Shared.Config.Course)
local Economy = require(Shared.Logic.Economy)
local Format = require(Shared.Logic.Format)
local Layout = require(Shared.Logic.Layout)
local Rng = require(Shared.Logic.Rng)
local Stage = require(Shared.Logic.Stage)

local CourseBuilder = {}

local W = CourseConfig.WIDTH

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function neon(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = part(parent, name, size, cframe, color, Enum.Material.Neon)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Big text on a part's face
local function sign(p: BasePart, face: Enum.NormalId, lines: { { text: string, color: Color3, scale: number } })
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Brightness = 2
	local y = 0
	for _, line in lines do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, line.scale)
		label.Position = UDim2.fromScale(0, y)
		label.Text = line.text
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = line.color
		label.Parent = gui
		y += line.scale
	end
	gui.Parent = p
end

-- A gate across the lane: two pillars and a beam (text on the beam, facing the runner)
local function gate(parent: Instance, name: string, z: number, height: number, color: Color3, lines: { any }?): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, side in { -1, 1 } do
		part(model, "Pillar", Vector3.new(2, height, 2), CFrame.new(side * (W / 2 + 1.5), height / 2, z), Color3.fromRGB(20, 22, 34))
		neon(model, "Glow", Vector3.new(0.4, height, 0.4), CFrame.new(side * (W / 2 + 0.4), height / 2, z), color)
	end
	local beam = part(model, "Beam", Vector3.new(W + 5, 4, 2), CFrame.new(0, height + 2, z), Color3.fromRGB(20, 22, 34))
	neon(model, "BeamGlow", Vector3.new(W + 5, 0.4, 2.2), CFrame.new(0, height, z), color)
	if lines then
		sign(beam, Enum.NormalId.Back, lines)
	end
	model.Parent = parent
	return model
end

-- One stage: its stretch of lane (with the gap after its wall), rails, gate, checkpoints, wall frame, decoration
function CourseBuilder.stage(parent: Instance, k: number): Model
	local theme = CourseConfig.THEMES[(k - 1) % #CourseConfig.THEMES + 1]
	local model = Instance.new("Model")
	model.Name = "Stage" .. k
	local length = Economy.stageLength(k)
	local z0 = Layout.startZ(k)
	local span = length + CourseConfig.WALL_THICK + CourseConfig.GAP
	local mid = z0 - span / 2

	-- the lane
	local floor = part(model, "Floor", Vector3.new(W, 4, span), CFrame.new(0, -2, mid), theme.floor)
	floor.Material = Enum.Material.Glass
	floor.Reflectance = 0.15
	for _, side in { -1, 1 } do
		neon(model, "Edge", Vector3.new(0.5, 0.3, span), CFrame.new(side * (W / 2 - 0.25), 0.1, mid), theme.accent)
		-- a low rail to see, and a tall clear wall to keep everyone on
		local rail = part(model, "Rail", Vector3.new(1, 2.4, span), CFrame.new(side * (W / 2 + 0.5), 1.2, mid), Color3.fromRGB(14, 16, 26))
		rail.Material = Enum.Material.Glass
		rail.Transparency = 0.3
		neon(model, "RailGlow", Vector3.new(1.05, 0.25, span), CFrame.new(side * (W / 2 + 0.5), 2.4, mid), theme.accent2)
		local guard = part(model, "Guard", Vector3.new(1, 30, span), CFrame.new(side * (W / 2 + 1.5), 15, mid), Color3.new())
		guard.Transparency = 1
		guard.CanQuery = false
	end
	-- lines across the lane, closer together the faster the stage (they make speed readable)
	local every = 20
	local d = every
	while d < length do
		local line = neon(model, "Line", Vector3.new(W - 1, 0.06, 0.35), CFrame.new(0, 0.03, z0 - d), theme.accent)
		line.Transparency = 0.55
		d += every
	end

	-- the gate at the start
	gate(model, "Gate", z0 - 1, 16, theme.accent, {
		{ text = "STAGE " .. k, color = Color3.new(1, 1, 1), scale = 0.6 },
		{ text = string.upper(theme.name), color = theme.accent, scale = 0.4 },
	})
	-- two checkpoints (a runner who crashes starts again at the last one they passed)
	for i = 1, 2 do
		local at = Stage.checkpoint(k, i)
		local cp = gate(model, "Checkpoint" .. i, z0 - at, 12, theme.accent2)
		cp:SetAttribute("Stage", k)
		cp:SetAttribute("Index", i)
		local pad = neon(cp, "Pad", Vector3.new(W - 2, 0.08, 3), CFrame.new(0, 0.05, z0 - at), theme.accent2)
		pad.Transparency = 0.4
	end
	-- the frame the wall sits in, and what it needs
	local wz = z0 - length - CourseConfig.WALL_THICK / 2
	local h = CourseConfig.WALL_HEIGHT
	for _, side in { -1, 1 } do
		part(model, "WallPillar", Vector3.new(4, h + 6, CourseConfig.WALL_THICK + 4), CFrame.new(side * (W / 2 + 2), (h + 6) / 2, wz), Color3.fromRGB(20, 22, 34))
		neon(model, "WallGlow", Vector3.new(0.5, h + 6, CourseConfig.WALL_THICK + 4.2), CFrame.new(side * (W / 2 + 0.2), (h + 6) / 2, wz), theme.accent)
	end
	local top = part(model, "WallTop", Vector3.new(W + 8, 6, CourseConfig.WALL_THICK + 4), CFrame.new(0, h + 3, wz), Color3.fromRGB(20, 22, 34))
	sign(top, Enum.NormalId.Back, {
		{ text = "NEEDS " .. Format.short(Economy.needs(k)) .. " SPEED", color = theme.accent, scale = 1 },
	})

	-- floating cubes on both sides, out in the dark
	local rng = Rng.new(500 + k * 31)
	for _ = 1, 26 do
		local size = Rng.range(rng, 2, 11)
		local side = if Rng.float(rng) < 0.5 then -1 else 1
		local x = side * Rng.range(rng, W / 2 + 10, W / 2 + 70)
		local y = Rng.range(rng, -18, 34)
		local z = z0 - Rng.range(rng, 0, span)
		local cframe = CFrame.new(x, y, z) * CFrame.Angles(Rng.range(rng, 0, 6.3), Rng.range(rng, 0, 6.3), Rng.range(rng, 0, 6.3))
		if Rng.float(rng) < 0.35 then
			neon(model, "Float", Vector3.new(size, size, size), cframe, if Rng.float(rng) < 0.5 then theme.accent else theme.accent2)
		else
			local cube = part(model, "Float", Vector3.new(size, size, size), cframe, theme.floor:Lerp(theme.accent, 0.25), Enum.Material.Glass)
			cube.Transparency = 0.25
			cube.CanCollide = false
			cube.CanQuery = false
		end
	end
	model.Parent = parent
	return model
end

-- The finish: a wide floor after the last wall, with the way to rebirth
function CourseBuilder.finish(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Finish"
	local z0 = Layout.startZ(CourseConfig.STAGES + 1)
	local floor = part(model, "Floor", Vector3.new(90, 4, 140), CFrame.new(0, -2, z0 - 70), Color3.fromRGB(18, 16, 30), Enum.Material.Glass)
	floor.Reflectance = 0.2
	for _, side in { -1, 1 } do
		neon(model, "Edge", Vector3.new(0.6, 0.3, 140), CFrame.new(side * 44.7, 0.1, z0 - 70), Color3.fromRGB(255, 220, 120))
	end
	gate(model, "Gate", z0 - 1, 18, Color3.fromRGB(255, 220, 120), {
		{ text = "YOU BEAT THE COURSE", color = Color3.new(1, 1, 1), scale = 0.6 },
		{ text = "REBIRTH TO RUN IT AGAIN, FASTER", color = Color3.fromRGB(255, 220, 120), scale = 0.4 },
	})
	-- a ring to look at
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		neon(model, "Ring", Vector3.new(3, 3, 3), CFrame.new(math.cos(a) * 22, 26 + math.sin(a) * 22, z0 - 110) * CFrame.Angles(0, 0, a), Color3.fromRGB(255, 220, 120))
	end
	model.Parent = parent
	return model
end

-- The night: dark, with glow
function CourseBuilder.lighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(40, 44, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(50, 54, 90)
	Lighting.GlobalShadows = false
	Lighting.EnvironmentDiffuseScale = 0.3
	Lighting.EnvironmentSpecularScale = 0.6
	local function effect(className: string, props: { [string]: any })
		local existing = Lighting:FindFirstChildOfClass(className)
		local e: any = existing or Instance.new(className)
		for k, v in props do
			e[k] = v
		end
		e.Parent = Lighting
	end
	effect("BloomEffect", { Intensity = 1.1, Size = 32, Threshold = 0.85 })
	effect("ColorCorrectionEffect", { Contrast = 0.12, Saturation = 0.15, Brightness = 0.02 })
	effect("Atmosphere", { Density = 0.32, Offset = 0.1, Color = Color3.fromRGB(40, 30, 80), Decay = Color3.fromRGB(10, 10, 30), Glare = 0, Haze = 1.2 })
	effect("Sky", { StarCount = 3000, CelestialBodiesShown = false })
end

-- Everything (call once)
function CourseBuilder.build(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Course"
	for k = 1, CourseConfig.STAGES do
		CourseBuilder.stage(folder, k)
	end
	CourseBuilder.finish(folder)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, -0.45, -6)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Parent = folder
	folder.Parent = parent
	CourseBuilder.lighting()
	return folder
end

return CourseBuilder
