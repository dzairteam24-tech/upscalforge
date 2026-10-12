--!strict
-- Sounds (Config/Sounds) and bursts of particles: the UI's clicks and messages, and what happens in the world
-- (the server's Fx event): an egg hatching, set down, stolen, brought home.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Net = require(Shared.Net)

local Effects = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local HEARING = 160 -- (studs: further away, nothing plays)

-- Plays a sound: at a spot in the world (it fades with distance), or for the player alone
function Effects.sound(name: string, at: Vector3?)
	pcall(Effects.play, name, at)
end

function Effects.play(name: string, at: Vector3?)
	local def = (Sounds :: any)[name] :: Sounds.Sound?
	if not def then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume
	sound.PlaybackSpeed = def.pitch
	if at then
		local holder = Instance.new("Attachment")
		holder.Parent = workspace.Terrain
		holder.WorldPosition = at
		sound.RollOffMaxDistance = HEARING
		sound.Parent = holder
		sound.Ended:Connect(function()
			holder:Destroy()
		end)
		task.delay(6, holder.Destroy, holder)
		sound:Play()
	else
		sound.Parent = SoundService
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
		sound:Play()
	end
end

type Burst = { count: number, colors: { Color3 }, texture: string?, size: number, speed: number, life: number, up: number?, spread: number? }

-- A one-off burst of particles at a spot
function Effects.burst(at: Vector3, burst: Burst)
	local holder = Instance.new("Attachment")
	holder.Parent = workspace.Terrain
	holder.WorldPosition = at
	for _, color in burst.colors do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Texture = burst.texture or SPARKLE
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = 0.6
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, burst.size), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime = NumberRange.new(burst.life * 0.6, burst.life)
		emitter.Speed = NumberRange.new(burst.speed * 0.5, burst.speed)
		emitter.SpreadAngle = Vector2.new(burst.spread or 180, burst.spread or 180)
		emitter.Acceleration = Vector3.new(0, burst.up or -12, 0)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-180, 180)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Parent = holder
		emitter:Emit(math.max(1, burst.count // #burst.colors))
	end
	task.delay(burst.life + 0.5, holder.Destroy, holder)
end

local CONFETTI = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 210, 70), Color3.fromRGB(90, 200, 255), Color3.fromRGB(120, 230, 120), Color3.fromRGB(190, 120, 255) }

local function near(at: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - at).Magnitude < HEARING
end

-- What each world event looks and sounds like: a sound for each, and a small burst of confetti only for the
-- big moments (a hatch, an egg brought home), to keep the screen clear and the game light
local KINDS: { [string]: (Vector3, Color3?) -> () } = {
	Hatch = function(at, color)
		local colors = { CONFETTI[1], CONFETTI[2], CONFETTI[3] }
		if color then
			table.insert(colors, color)
		end
		Effects.burst(at + Vector3.new(0, 2, 0), { count = 24, colors = colors, size = 0.6, speed = 22, life = 1.2, up = -30, spread = 50 })
		Effects.sound("Chime", at)
	end,
	SetEgg = function(at)
		Effects.sound("SetEgg", at)
	end,
	-- (an egg grabbed from its nest: a puff of its color)
	Steal = function(at, color)
		Effects.burst(at + Vector3.new(0, 1, 0), { count = 16, colors = { color or Color3.new(1, 1, 1), Color3.fromRGB(255, 240, 180) }, size = 0.6, speed = 16, life = 0.7, up = -20, spread = 70 })
		Effects.sound("Steal", at)
	end,
	-- (out of the guardian's biome: a green puff of relief)
	Escape = function(at)
		Effects.burst(at + Vector3.new(0, 2, 0), { count = 14, colors = { Color3.fromRGB(120, 230, 120), Color3.new(1, 1, 1) }, size = 0.6, speed = 14, life = 0.8, up = 4, spread = 180 })
		Effects.sound("Escape", at)
	end,
	Swing = function(at)
		Effects.sound("Swing", at)
	end,
	-- (a bat hit: stars round the head; the knock-out one bigger and louder)
	Hit = function(at)
		Effects.burst(at + Vector3.new(0, 2, 0), { count = 10, colors = { Color3.fromRGB(255, 230, 90), Color3.new(1, 1, 1) }, size = 0.7, speed = 14, life = 0.5, up = 0, spread = 180 })
		Effects.sound("Hit", at)
	end,
	Knock = function(at)
		Effects.burst(at + Vector3.new(0, 2, 0), { count = 24, colors = { Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 120, 60), Color3.new(1, 1, 1) }, size = 1, speed = 24, life = 0.8, up = -20, spread = 180 })
		Effects.sound("Knock", at)
	end,
	Home = function(at, color)
		Effects.burst(at + Vector3.new(0, 3, 0), { count = 24, colors = { color or CONFETTI[2], CONFETTI[1], CONFETTI[3] }, size = 0.6, speed = 22, life = 1.2, up = -30, spread = 50 })
		Effects.sound("Home", at)
		task.delay(0.15, Effects.sound, "Chime", at)
	end,
}

-- A bat hit this player: they're pushed back, the screen shakes; the knock-down hit lays them out, stunned (no
-- moving) for a moment
local function knocked(push: Vector3, hard: boolean, stun: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	if hard then
		humanoid.PlatformStand = true -- (falls over, and can't walk)
		task.delay(stun, function()
			if humanoid.Parent then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
	root.AssemblyLinearVelocity = push
	task.spawn(function()
		for i = 1, if hard then 10 else 5 do
			local strength = (if hard then 0.5 else 0.25) * (1 - i / 11)
			humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
			task.wait(0.03)
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

-- The swinger's count over the one they hit ("1/2", then "💥"): it pops up and fades
local function hitMark(target: Model, hits: number, needed: number)
	local head = target:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local old = head:FindFirstChild("HitMark")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "HitMark"
	gui.Size = UDim2.fromScale(3, 1.5)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.LuckiestGuy
	text.Text = if hits >= needed then "💥" else ("%d/%d"):format(hits, needed)
	text.TextColor3 = if hits >= needed then Color3.fromRGB(255, 120, 60) else Color3.fromRGB(255, 230, 90)
	text.TextStrokeColor3 = Color3.fromRGB(28, 24, 40)
	text.TextStrokeTransparency = 0
	text.Parent = gui
	gui.Parent = head
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = text
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.6, function()
		TweenService:Create(text, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(1, gui.Destroy, gui)
end

function Effects.init()
	Net.event("Knocked").OnClientEvent:Connect(function(push: Vector3, hard: boolean, stun: number?)
		if typeof(push) == "Vector3" then
			knocked(push, hard == true, if type(stun) == "number" then math.clamp(stun, 0, 5) else 2)
		end
	end)
	Net.event("HitMark").OnClientEvent:Connect(function(target: Model, hits: number, needed: number)
		if typeof(target) == "Instance" and target:IsA("Model") and type(hits) == "number" and type(needed) == "number" then
			hitMark(target, hits, needed)
		end
	end)
	Net.event("Fx").OnClientEvent:Connect(function(kind: string, at: Vector3, color: Color3?)
		local play = KINDS[kind]
		if play and typeof(at) == "Vector3" and near(at) then
			play(at, if typeof(color) == "Color3" then color else nil)
		end
	end)
end

return Effects
