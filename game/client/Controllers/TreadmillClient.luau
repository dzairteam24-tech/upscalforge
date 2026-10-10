--!strict
-- The treadmills: their belts move (slats sliding along them, drawn on this screen only), and on their own
-- treadmill the player runs by themselves: their character turns to face along it and plays its run, staying
-- where it is, for as long as they don't steer themselves; steering walks them off. WildService counts the
-- seconds they spend on it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("Layout"))

local TreadmillClient = {}

local LOCAL = Players.LocalPlayer
local SLATS = 8
local BELT_SPEED = 9 -- studs a second the belt runs
local ANIMATE_RANGE = 160

-- The player's own steering, from Roblox's control module (zero when they don't touch the controls)
local controls: any = nil
local function steering(): Vector3
	if controls == nil then
		local ok, module = pcall(function()
			local scripts = LOCAL:WaitForChild("PlayerScripts")
			return (require :: any)(scripts:WaitForChild("PlayerModule")):GetControls()
		end)
		controls = if ok then module else false
	end
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			return vector
		end
	end
	return Vector3.zero
end

-- Each belt's slats
type Belt = { belt: BasePart, slats: { Part }, offset: number }
local belts: { [BasePart]: Belt } = {}

local function addBelt(instance: Instance)
	if not instance:IsA("BasePart") or belts[instance] then
		return
	end
	local belt = instance :: BasePart
	local slats = {}
	for _ = 1, SLATS do
		local slat = Instance.new("Part")
		slat.Name = "Slat"
		slat.Anchored = true
		slat.CanCollide = false
		slat.CanQuery = false
		slat.CanTouch = false
		slat.CastShadow = false
		slat.Size = Vector3.new(0.35, 0.05, belt.Size.Z - 0.2)
		slat.Color = Color3.fromRGB(95, 98, 110)
		slat.Material = Enum.Material.SmoothPlastic
		slat.Parent = belt
		table.insert(slats, slat)
	end
	belts[belt] = { belt = belt, slats = slats, offset = 0 }
	belt.AncestryChanged:Connect(function()
		if not belt.Parent then
			belts[belt] = nil
		end
	end)
end

-- The slats slide back along the belt (away from the console), as a real belt under a runner
local function moveBelts(dt: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for belt, entry in belts do
		if (belt.Position - eye).Magnitude > ANIMATE_RANGE then
			continue
		end
		local length = belt.Size.X
		entry.offset = (entry.offset + BELT_SPEED * dt) % length
		for i, slat in entry.slats do
			local x = ((i - 1) * length / SLATS + entry.offset) % length - length / 2
			slat.CFrame = belt.CFrame * CFrame.new(x, belt.Size.Y / 2 + 0.03, 0)
		end
	end
end

-- The player's own treadmill, if they stand on it
local function onTreadmill(root: BasePart): CFrame?
	local index = LOCAL:GetAttribute("Island")
	if type(index) ~= "number" then
		return nil
	end
	local mill = Layout.garden(index) * CFrame.new(Layout.TREADMILL)
	local inside = mill:PointToObjectSpace(root.Position)
	if math.abs(inside.X) <= 5.5 and math.abs(inside.Z) <= 2.7 and inside.Y < 8 then
		return mill
	end
	return nil
end

-- The character's own run animation (from its Animate script), played while on the treadmill
local track: AnimationTrack? = nil
local trackFor: Model? = nil
local function runTrack(character: Model, humanoid: Humanoid): AnimationTrack?
	if trackFor == character and track then
		return track
	end
	track, trackFor = nil, character
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local animate = character:FindFirstChild("Animate")
	local run = animate and animate:FindFirstChild("run")
	local animation = run and run:FindFirstChildOfClass("Animation")
	if animator and animation then
		local loaded = animator:LoadAnimation(animation)
		loaded.Looped = true
		loaded.Priority = Enum.AnimationPriority.Action
		track = loaded
	end
	return track
end

local running = false
local function step()
	local character = LOCAL.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local mill = if root then onTreadmill(root) else nil
	local seated = LOCAL:GetAttribute("RideSeat")
	local should = mill ~= nil and humanoid ~= nil and steering().Magnitude < 0.1 and (seated == nil or seated == "")
	if should and character and humanoid and root and mill then
		-- Facing the console, as on a real treadmill, staying where they are
		local facing = -mill.RightVector
		root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(facing.X, 0, facing.Z))
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		local anim = runTrack(character, humanoid)
		if anim and not anim.IsPlaying then
			anim:Play(0.2)
		end
		running = true
	elseif running then
		running = false
		if track and track.IsPlaying then
			track:Stop(0.2)
		end
	end
end

function TreadmillClient.init()
	for _, belt in CollectionService:GetTagged("TreadmillBelt") do
		addBelt(belt)
	end
	CollectionService:GetInstanceAddedSignal("TreadmillBelt"):Connect(addBelt)
	RunService.RenderStepped:Connect(moveBelts)
	-- (after the controls have set the character's movement for this frame)
	RunService:BindToRenderStep("Treadmill", Enum.RenderPriority.Character.Value + 1, step)
end

return TreadmillClient
