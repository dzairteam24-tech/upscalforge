--!strict
-- Week 0 client: the stacking loop on the phone. A block slides; tap anywhere to drop it. The phone plays the run
-- itself (so a tap is never delayed by the network) and sends the tap times when the run ends; the server replays
-- them. Three feel presets (A, B, C) to compare, and a stats line for the test report.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Stack = require(Shared.Config.Stack)
local StackSim = require(Shared.Logic.StackSim)

local LOCAL = Players.LocalPlayer
local H = Stack.LAYER_HEIGHT
local joinedAt = os.clock()

-- (no thumbstick or walking during runs: the whole screen is the button)
pcall(function()
	local module = require(LOCAL:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any)
	module:GetControls():Disable()
end)

-- Glow
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.8
bloom.Size = 30
bloom.Threshold = 0.85
bloom.Parent = Lighting

local function sound(id: string, pitch: number, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = pitch
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 2)
end
local PING = "rbxasset://sounds/electronicpingshort.wav"
local THUNK = "rbxasset://sounds/button.wav"
local FALL = "rbxasset://sounds/impact_water.mp3"

local function hue(layer: number): Color3
	return Color3.fromHSV((layer * 0.025) % 1, 0.65, 1)
end

---------------------------------------------------------------------------------------------------------------
-- The screen

local screen = Instance.new("ScreenGui")
screen.Name = "Glowspire"
screen.ResetOnSpawn = false
screen.Parent = LOCAL:WaitForChild("PlayerGui")

local function label(text: string, size: UDim2, position: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.3
	l.Parent = screen
	return l
end

local count = label("0", UDim2.fromOffset(200, 70), UDim2.new(0.5, -100, 0, 20))
local banner = label("", UDim2.fromOffset(420, 44), UDim2.new(0.5, -210, 0, 96), Color3.fromRGB(255, 225, 120))
local result = label("", UDim2.fromOffset(520, 60), UDim2.new(0.5, -260, 0.62, 0), Color3.fromRGB(255, 240, 200))
local hint = label("TAP", UDim2.fromOffset(240, 60), UDim2.new(0.5, -120, 0.78, 0), Color3.fromRGB(180, 230, 255))
local stats = label("", UDim2.fromOffset(520, 22), UDim2.new(0, 10, 1, -30), Color3.fromRGB(170, 170, 200))
stats.TextXAlignment = Enum.TextXAlignment.Left

TweenService:Create(hint, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.6 }):Play()

---------------------------------------------------------------------------------------------------------------
-- The run

local presetKey = Stack.DEFAULT
local state = StackSim.new(presetKey)
local taps: { number } = {}
local tower: { BasePart } = {}
local moving: Part? = nil
local spawnAt = os.clock()
local waitingRestart = false
local firstTapAt: number? = nil
local tapTimes: { number } = {} -- (os.clock of recent taps, for taps per minute)

local function slab(name: string, w: number, d: number, position: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(w / 100, H, d / 100)
	p.CFrame = CFrame.new(position)
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = workspace
	return p
end

local function layerY(layer: number): number
	return (layer - 0.5) * H
end

-- Where the sliding block is drawn now
local function movingPosition(t: number): Vector3
	local offset = StackSim.offset(state, t)
	local y = layerY(state.layer + 1)
	if StackSim.axis(state) == "x" then
		return Vector3.new((state.cx + offset) / 100, y, state.cz / 100)
	end
	return Vector3.new(state.cx / 100, y, (state.cz + offset) / 100)
end

local function spawnBlock()
	moving = slab("Moving", state.w, state.d, movingPosition(0), hue(state.layer + 1))
	spawnAt = os.clock()
end

local function pulse(y: number, size: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, size, size)
	ring.CFrame = CFrame.new(state.cx / 100, y, state.cz / 100) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.45), { Size = Vector3.new(0.1, size * 2.2, size * 2.2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.5)
end

local function falling(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	Debris:AddItem(p, 3)
end

local function reset()
	for _, p in tower do
		p:Destroy()
	end
	table.clear(tower)
	if moving then
		moving:Destroy()
		moving = nil
	end
	state = StackSim.new(presetKey)
	table.clear(taps)
	count.Text = "0"
	result.Text = ""
	banner.Text = ""
	hint.Visible = true
	waitingRestart = false
	spawnBlock()
end

local function finish()
	waitingRestart = true
	Net.event("Finish"):FireServer(presetKey, taps)
	result.Text = "..."
	task.delay(0.9, function()
		hint.Text = "TAP TO GO AGAIN"
		hint.Visible = true
	end)
end

local function tap()
	if waitingRestart then
		if hint.Visible then
			reset()
		end
		return
	end
	local block = moving
	if not block then
		return
	end
	local now = os.clock()
	firstTapAt = firstTapAt or (now - joinedAt)
	table.insert(tapTimes, now)
	hint.Visible = false
	local t = math.floor((now - spawnAt) * 1000)
	local axis = StackSim.axis(state)
	local outcome = StackSim.tap(state, t)
	table.insert(taps, t)
	moving = nil
	if outcome.kind == "miss" then
		falling(block)
		sound(FALL, 0.8, 0.6)
		finish()
		return
	end
	-- the placed slab, exactly where the simulation says
	block:Destroy()
	local y = layerY(state.layer)
	local placed = slab("Layer", state.w, state.d, Vector3.new(state.cx / 100, y, state.cz / 100), hue(state.layer))
	table.insert(tower, placed)
	count.Text = tostring(state.layer)
	if outcome.kind == "perfect" then
		sound(PING, math.min(2.2, 0.9 + state.combo * 0.07), 0.6)
		pulse(y, math.max(state.w, state.d) / 100, hue(state.layer))
		banner.Text = if state.combo >= 2 then "PERFECT x" .. state.combo else "PERFECT"
	else
		sound(THUNK, 0.7, 0.5)
		banner.Text = ""
		local cut = outcome.cut
		if cut then
			local w = if cut.axis == "x" then cut.size else state.w
			local d = if cut.axis == "z" then cut.size else state.d
			local cx = if cut.axis == "x" then cut.center else state.cx
			local cz = if cut.axis == "z" then cut.center else state.cz
			falling(slab("Cut", w, d, Vector3.new(cx / 100, y, cz / 100), hue(state.layer)))
		end
	end
	spawnBlock()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.Space then
		tap()
	end
end)

-- Presets (switching starts a new run)
for i, key in { "A", "B", "C" } do
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(54, 44)
	b.Position = UDim2.new(1, -64 * (4 - i) - 6, 0, 20)
	b.Text = key
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = Color3.fromRGB(60, 60, 100)
	b.Parent = screen
	local corner = Instance.new("UICorner")
	corner.Parent = b
	b.Activated:Connect(function()
		presetKey = key
		reset()
		banner.Text = Stack.PRESETS[key].name
	end)
end

Net.event("Result").OnClientEvent:Connect(function(layers: number, perfects: number, tier: string?, best: number)
	if tier then
		result.Text = ("SPIRE: %s  (%d layers, %d perfect)  best %d"):format(tier, layers, perfects, best)
		sound(PING, 1.5, 0.8)
	else
		result.Text = ("%d layers: %d more for a Spire  (best %d)"):format(layers, Stack.TIERS[1].layers - layers, best)
	end
end)

---------------------------------------------------------------------------------------------------------------
-- Every frame: slide the block, follow the tower with the camera, the stats line

local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
local camY = 0
local fps = 60
RunService.RenderStepped:Connect(function(dt)
	local block = moving
	if block then
		block.CFrame = CFrame.new(movingPosition((os.clock() - spawnAt) * 1000))
	end
	camY += (state.layer * H - camY) * math.min(1, dt * 4)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(Vector3.new(16, camY + 13, 16), Vector3.new(0, camY - 1, 0))
	fps += ((1 / math.max(dt, 1e-3)) - fps) * 0.05
	local now = os.clock()
	while tapTimes[1] and now - tapTimes[1] > 60 do
		table.remove(tapTimes, 1)
	end
	stats.Text = ("preset %s | %d fps | %d taps/min | first tap %s"):format(presetKey, math.floor(fps + 0.5), #tapTimes, if firstTapAt then string.format("%.1fs", firstTapAt) else "-")
end)

spawnBlock()
