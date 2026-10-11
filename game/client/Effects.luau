--!strict
-- Sounds (Config/Sounds) and bursts of particles: the UI's clicks and messages, and what happens in the world
-- (the server's Fx and Bump events): an egg hatching, set down, stolen, brought home; a bat hit; a trap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Net = require(Shared.Net)

local Effects = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local HEARING = 160 -- (studs: further away, nothing plays)

-- Plays a sound: at a spot in the world (it fades with distance), or for the player alone
function Effects.sound(name: string, at: Vector3?)
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
		emitter.LightEmission = if burst.texture == SMOKE then 0 else 0.6
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

-- What each world event looks and sounds like
local KINDS: { [string]: (Vector3, Color3?) -> () } = {
	Hatch = function(at, color)
		local colors = table.clone(CONFETTI)
		if color then
			table.insert(colors, color)
			table.insert(colors, color)
		end
		Effects.burst(at + Vector3.new(0, 2, 0), { count = 70, colors = colors, size = 0.7, speed = 28, life = 1.6, up = -30, spread = 60 })
		Effects.burst(at + Vector3.new(0, 1, 0), { count = 14, colors = { Color3.fromRGB(255, 250, 235) }, texture = SMOKE, size = 3, speed = 6, life = 1, up = 2 })
		Effects.sound("Chime", at)
	end,
	SetEgg = function(at, color)
		Effects.burst(at, { count = 12, colors = { Color3.fromRGB(205, 185, 150) }, texture = SMOKE, size = 2.2, speed = 8, life = 0.8, up = 1, spread = 80 })
		Effects.burst(at + Vector3.new(0, 1, 0), { count = 10, colors = { color or Color3.new(1, 1, 1) }, size = 0.5, speed = 10, life = 0.8 })
		Effects.sound("SetEgg", at)
	end,
	Steal = function(at, color)
		Effects.burst(at + Vector3.new(0, 2, 0), { count = 30, colors = { color or Color3.new(1, 1, 1), Color3.fromRGB(255, 240, 160) }, size = 0.6, speed = 18, life = 1, up = -20, spread = 70 })
		Effects.sound("Steal", at)
	end,
	Home = function(at, color)
		Effects.burst(at + Vector3.new(0, 3, 0), { count = 60, colors = { color or CONFETTI[2], CONFETTI[1], CONFETTI[3], CONFETTI[4] }, size = 0.7, speed = 26, life = 1.6, up = -30, spread = 50 })
		Effects.sound("Home", at)
		task.delay(0.15, Effects.sound, "Chime", at)
	end,
	Hit = function(at)
		Effects.burst(at + Vector3.new(0, 2, 0), { count = 24, colors = { Color3.fromRGB(255, 230, 90), Color3.new(1, 1, 1) }, size = 0.8, speed = 24, life = 0.5, up = 0 })
		Effects.sound("Hit", at)
	end,
	Trap = function(at)
		Effects.burst(at, { count = 20, colors = { Color3.fromRGB(90, 90, 100) }, texture = SMOKE, size = 3, speed = 10, life = 1, up = 3, spread = 70 })
		Effects.sound("Trap", at)
	end,
}

function Effects.init()
	Net.event("Fx").OnClientEvent:Connect(function(kind: string, at: Vector3, color: Color3?)
		local play = KINDS[kind]
		if play and typeof(at) == "Vector3" and near(at) then
			play(at, if typeof(color) == "Color3" then color else nil)
		end
	end)
	Net.event("Bump").OnClientEvent:Connect(function(at: Vector3, kind: string)
		local play = KINDS[kind]
		if play and near(at) then
			play(at)
		end
	end)
end

return Effects
