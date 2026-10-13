--!strict
-- What digging looks and sounds like: a puff of cubes where the shovel hits, a burst when a cube breaks, sparkles
-- and a chime when a gem drops. The server tells the digging player where (Net "Fx").

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Effects = {}

local function sound(id: string, pitch: number, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = pitch
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 2)
end
Effects.sound = sound

local function burst(position: Vector3, color: Color3, amount: number, size: number, speed: number, glow: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = glow
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Rate = 0
	emitter.Parent = holder
	holder.Parent = workspace
	emitter:Emit(amount)
	Debris:AddItem(holder, 1.5)
end

function Effects.init()
	Net.event("Fx").OnClientEvent:Connect(function(kind: string, position: Vector3, color: Color3)
		if kind == "Hit" then
			burst(position, color, 5, 1.2, 18, 0)
			sound("rbxasset://sounds/button.wav", 0.55 + math.random() * 0.15, 0.4)
		elseif kind == "Break" then
			burst(position, color, 16, 2, 26, 0)
			sound("rbxasset://sounds/impact_water.mp3", 1.6, 0.5)
		elseif kind == "Geode" then
			burst(position, Color3.fromRGB(210, 120, 255), 34, 3, 32, 1)
			sound("rbxasset://sounds/impact_water.mp3", 1.1, 0.7)
			sound("rbxasset://sounds/electronicpingshort.wav", 1.0, 0.6)
		elseif kind == "Gem" then
			burst(position, color, 22, 2.4, 22, 1)
			sound("rbxasset://sounds/electronicpingshort.wav", 1.4, 0.7)
		end
	end)
end

return Effects
