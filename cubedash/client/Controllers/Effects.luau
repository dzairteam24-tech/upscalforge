--!strict
-- How it feels: the view widens and speed lines stream past the faster you really go, a trail of light behind
-- the runner, orbs fly into you with a rising ping, crashes and walls burst into cubes, and the camera shakes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)
local SpeedConfig = require(Shared.Config.Speed)

local Effects = {}

local LOCAL = Players.LocalPlayer
local LINES = 18

-- (built-in sounds, so nothing needs uploading)
local SOUNDS = {
	pickup = "rbxasset://sounds/electronicpingshort.wav",
	smash = "rbxasset://sounds/collide.wav",
	crash = "rbxasset://sounds/collide.wav",
	checkpoint = "rbxasset://sounds/electronicpingshort.wav",
}

local shakeUntil, shakeStrength = 0, 0
local combo, comboAt = 0, 0
local trail: Trail? = nil
local lineFrames: { { frame: Frame, angle: number, r: number, speed: number } } = {}
local popupGui: ScreenGui? = nil

local function play(name: string, pitch: number?, volume: number?)
	local id = SOUNDS[name]
	if not id then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	pcall(function()
		SoundService:PlayLocalSound(sound)
	end)
	task.delay(2, function()
		sound:Destroy()
	end)
end

function Effects.shake(strength: number, seconds: number)
	shakeStrength = math.max(shakeStrength * (if os.clock() < shakeUntil then 1 else 0), strength)
	shakeUntil = math.max(shakeUntil, os.clock() + seconds)
end

-- Small cubes flying out from a point
local function burst(at: Vector3, color: Color3, count: number, speed: number, size: number)
	for _ = 1, count do
		local cube = Instance.new("Part")
		cube.Size = Vector3.new(size, size, size) * (0.6 + math.random() * 0.8)
		cube.CFrame = CFrame.new(at + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2)
		cube.Color = if math.random() < 0.6 then color else Color3.new(1, 1, 1)
		cube.Material = Enum.Material.Neon
		cube.CanCollide = false
		cube.CanQuery = false
		cube.CanTouch = false
		cube.CastShadow = false
		cube.Parent = workspace
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5).Unit
		cube.AssemblyLinearVelocity = dir * speed * (0.5 + math.random())
		cube.AssemblyAngularVelocity = Vector3.new(math.random(-15, 15), math.random(-15, 15), math.random(-15, 15))
		TweenService:Create(cube, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 }):Play()
		task.delay(1, function()
			cube:Destroy()
		end)
	end
end

-- The runner bursts into cubes
function Effects.shatter(at: Vector3, color: Color3)
	burst(at, color, 22, 34, 0.9)
	play("crash", 0.7, 0.6)
end

-- A wall breaks
function Effects.smash(at: Vector3, color: Color3)
	burst(at, color, 30, 60, 1.6)
	Effects.shake(1.4, 0.6)
	play("smash", 0.55, 0.9)
	Effects.flash(color)
end

function Effects.checkpoint()
	play("checkpoint", 0.8, 0.4)
end

-- A colored flash over the whole screen
function Effects.flash(color: Color3)
	if not popupGui then
		return
	end
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.55
	f.BorderSizePixel = 0
	f.ZIndex = 1
	f.Parent = popupGui
	TweenService:Create(f, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	task.delay(0.5, function()
		f:Destroy()
	end)
end

-- Big coins number rising in the middle
function Effects.coins(coins: number)
	if not popupGui then
		return
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(400, 50)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.62)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "+" .. Format.short(coins) .. " COINS"
	label.TextColor3 = Color3.fromRGB(255, 205, 80)
	label.TextStrokeTransparency = 0.5
	label.Parent = popupGui
	TweenService:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0.5), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.5, function()
		label:Destroy()
	end)
end

-- An orb flies into the runner: a ping that climbs with a quick string of them, and "+N" by the orb
function Effects.pickup(orb: BasePart, root: BasePart?, gain: number)
	local now = os.clock()
	combo = if now - comboAt < 0.9 then math.min(combo + 1, 16) else 0
	comboAt = now
	play("pickup", 1 + combo * 0.06, 0.32)
	local shell = orb:FindFirstChild("Shell") :: BasePart?
	if root then
		local target = root
		local start = orb.CFrame.Position
		local t0 = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local f = math.clamp((os.clock() - t0) / 0.14, 0, 1)
			if not orb.Parent then
				connection:Disconnect()
				return
			end
			orb.CFrame = CFrame.new(start:Lerp(target.CFrame.Position, f))
			if shell then
				shell.CFrame = orb.CFrame
			end
			if f >= 1 then
				connection:Disconnect()
				orb:Destroy()
			end
		end)
	else
		orb:Destroy()
	end
	-- "+N" floating up
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 34)
	gui.StudsOffsetWorldSpace = orb.CFrame.Position + Vector3.new(0, 1.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "+" .. Format.short(gain)
	label.TextColor3 = Color3.fromRGB(140, 255, 250)
	label.TextStrokeTransparency = 0.6
	label.Parent = gui
	gui.Parent = workspace.Terrain
	TweenService:Create(gui, TweenInfo.new(0.7), { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.75, function()
		gui:Destroy()
	end)
end

-- A trail of light behind the runner
function Effects.attach(character: Model)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not rootPart then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.9, 0.4)
	a0.Parent = rootPart
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.1, 0.4)
	a1.Parent = rootPart
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = 0.35
	t.LightEmission = 1
	t.FaceCamera = true
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	t.Color = ColorSequence.new(Color3.fromRGB(0, 229, 255), Color3.fromRGB(255, 64, 200))
	t.Enabled = false
	t.Parent = rootPart
	trail = t
end

-- The trail's colors (the stage's, or gold for VIP)
function Effects.trailColors(a: Color3, b: Color3)
	if trail then
		trail.Color = ColorSequence.new(a, b)
	end
end

function Effects.init(screen: ScreenGui)
	popupGui = screen
	-- speed lines: thin streaks around the edge of the screen
	local holder = Instance.new("Frame")
	holder.Name = "SpeedLines"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 0
	holder.Parent = screen
	for _ = 1, LINES do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(2, 60)
		f.BackgroundTransparency = 1
		f.Parent = holder
		table.insert(lineFrames, { frame = f, angle = math.random() * math.pi * 2, r = 0.35 + math.random() * 0.3, speed = 0.6 + math.random() * 0.8 })
	end

	local fov = SpeedConfig.FOV_MIN
	-- (after the camera has moved this frame, so the shake sticks)
	RunService:BindToRenderStep("CubedashEffects", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = workspace.CurrentCamera
		local character = LOCAL.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not camera then
			return
		end
		-- how fast they really go, flat
		local v = 0
		if rootPart then
			local vel = rootPart.AssemblyLinearVelocity
			v = Vector3.new(vel.X, 0, vel.Z).Magnitude
		end
		local feel = math.clamp((v - SpeedConfig.WALK_MIN - 2) / (SpeedConfig.FEEL_TOP - SpeedConfig.WALK_MIN), 0, 1)
		local target = SpeedConfig.FOV_MIN + (SpeedConfig.FOV_MAX - SpeedConfig.FOV_MIN) * feel
		fov += (target - fov) * math.min(1, dt * 3)
		camera.FieldOfView = fov
		if trail then
			trail.Enabled = v > 20
		end
		-- the lines stream outward, stronger the faster
		local view = camera.ViewportSize
		for _, line in lineFrames do
			line.r += dt * line.speed * (0.4 + feel * 1.6)
			if line.r > 0.75 then
				line.r = 0.35 + math.random() * 0.1
				line.angle = math.random() * math.pi * 2
			end
			local px = 0.5 + math.cos(line.angle) * line.r
			local py = 0.5 + math.sin(line.angle) * line.r * (view.X / math.max(1, view.Y)) * 0.6
			line.frame.Position = UDim2.fromScale(px, py)
			line.frame.Rotation = math.deg(line.angle) + 90
			line.frame.Size = UDim2.fromOffset(2, math.floor(30 + feel * 90))
			line.frame.BackgroundTransparency = if feel < 0.25 then 1 else 1 - (feel - 0.25) * 0.75
		end
		-- the shake
		local now = os.clock()
		if now < shakeUntil then
			local s = shakeStrength * (shakeUntil - now) / 0.6
			camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
		end
	end)
end

return Effects
