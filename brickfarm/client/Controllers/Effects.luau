--!strict
-- The little things that make the farm feel alive: a puff of soil bricks when you plant, a sparkle when a crop
-- grows, the harvest's bricks hopping into you, "+2 Carrot" floating up, confetti bricks for a new level.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crops = require(Shared.Config.Crops)

local Effects = {}

local LOCAL = Players.LocalPlayer
local SOIL = Color3.fromRGB(124, 92, 70)
local CONFETTI = { Color3.fromRGB(196, 40, 28), Color3.fromRGB(13, 105, 172), Color3.fromRGB(245, 205, 48), Color3.fromRGB(75, 151, 75), Color3.fromRGB(255, 146, 44) }

-- (built-in sounds, so nothing needs uploading)
local SOUNDS = {
	plant = "rbxasset://sounds/clickfast.wav",
	harvest = "rbxasset://sounds/electronicpingshort.wav",
	level = "rbxasset://sounds/victory.wav",
}

Effects.onBanner = nil :: ((title: string, sub: string?, color: Color3?) -> ())?
local screen: ScreenGui? = nil

local function play(name: string, pitch: number?, volume: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = SOUNDS[name]
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	pcall(function()
		SoundService:PlayLocalSound(sound)
	end)
	task.delay(3, function()
		sound:Destroy()
	end)
end

local function rootPart(): BasePart?
	local character = LOCAL.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Small bricks hopping out of a point and falling away
local function puff(at: Vector3, colors: { Color3 }, count: number, height: number)
	for i = 1, count do
		local p = Instance.new("Part")
		p.Size = Vector3.new(0.5, 0.3, 0.5)
		p.Color = colors[(i - 1) % #colors + 1]
		p.Material = Enum.Material.Plastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = CFrame.new(at)
		p.Parent = workspace
		local a = i / count * math.pi * 2 + math.random()
		local out = Vector3.new(math.cos(a), 0, math.sin(a)) * (1 + math.random() * 1.5)
		TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(at + out * 0.6 + Vector3.new(0, height, 0)) * CFrame.Angles(a, a, 0) }):Play()
		task.delay(0.22, function()
			TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(at + out), Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.1) }):Play()
		end)
		task.delay(0.6, function()
			p:Destroy()
		end)
	end
end

function Effects.planted(at: Vector3)
	puff(at + Vector3.new(0, 1, 0), { SOIL, SOIL:Lerp(Color3.new(), 0.2) }, 6, 1.2)
	play("plant", 1.1, 0.4)
end

function Effects.grew(at: Vector3)
	puff(at + Vector3.new(0, 1.5, 0), { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 230, 120) }, 4, 1.6)
end

-- A harvest: the crop's bricks hop up and fly into the farmer
function Effects.harvest(tile: BasePart, key: string, model: Model?)
	play("harvest", 0.9 + math.random() * 0.25, 0.45)
	local crop = Crops.byKey[key]
	local root = rootPart()
	local parts: { BasePart } = {}
	if model then
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(parts, p)
			end
		end
	end
	if #parts == 0 and crop then
		puff(tile.CFrame.Position + Vector3.new(0, 1.5, 0), { crop.fruit, crop.leaf }, 8, 2)
		return
	end
	for i, p in parts do
		local start = p.CFrame
		local up = start * CFrame.new(0, 2.5 + math.random() * 1.5, 0)
		task.delay(i * 0.015, function()
			TweenService:Create(p, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = up }):Play()
			task.wait(0.2)
			local target = if root then root.CFrame.Position else up.Position
			TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(target), Size = p.Size * 0.2 }):Play()
		end)
	end
	if model then
		task.delay(0.8, function()
			model:Destroy()
		end)
	end
end

-- "+2 Carrot  +2 XP" rising over the farmer
function Effects.gained(key: string, amount: number, xp: number)
	local root = rootPart()
	local crop = Crops.byKey[key]
	if not root or not crop then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffsetWorldSpace = root.CFrame.Position + Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = ("+%d %s  +%d XP"):format(amount, crop.name, xp)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = crop.fruit:Lerp(Color3.new(), 0.5)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = workspace.Terrain
	TweenService:Create(gui, TweenInfo.new(1), { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 3, 0) }):Play()
	task.delay(0.6, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(1.1, function()
		gui:Destroy()
	end)
end

-- A new level: a banner, confetti bricks, and what it unlocked
function Effects.levelUp(level: number, unlocked: { string })
	play("level", 1, 0.6)
	local names = {}
	for _, key in unlocked do
		local crop = Crops.byKey[key]
		if crop then
			table.insert(names, crop.name)
		end
	end
	if Effects.onBanner then
		Effects.onBanner("LEVEL " .. level .. "!", if #names > 0 then "New seeds: " .. table.concat(names, ", ") else "More land to buy", Color3.fromRGB(255, 200, 40))
	end
	local root = rootPart()
	if root then
		puff(root.CFrame.Position + Vector3.new(0, 3, 0), CONFETTI, 24, 6)
	end
end

function Effects.init(gui: ScreenGui)
	screen = gui
	local _ = screen
end

return Effects
