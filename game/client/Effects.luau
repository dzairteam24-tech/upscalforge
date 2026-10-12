--!strict
-- Sounds (Config/Sounds) and bursts of particles: the UI's clicks and messages, and what happens in the world
-- (the server's Fx event): an egg hatching, set down, stolen, brought home.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

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
	Steal = function(at)
		Effects.sound("Steal", at)
	end,
	Hit = function(at)
		Effects.sound("Hit", at)
	end,
	Home = function(at, color)
		Effects.burst(at + Vector3.new(0, 3, 0), { count = 24, colors = { color or CONFETTI[2], CONFETTI[1], CONFETTI[3] }, size = 0.6, speed = 22, life = 1.2, up = -30, spread = 50 })
		Effects.sound("Home", at)
		task.delay(0.15, Effects.sound, "Chime", at)
	end,
}

function Effects.init()
	Net.event("Fx").OnClientEvent:Connect(function(kind: string, at: Vector3, color: Color3?)
		local play = KINDS[kind]
		if play and typeof(at) == "Vector3" and near(at) then
			play(at, if typeof(color) == "Color3" then color else nil)
		end
	end)
end

return Effects
