-- Cubeling Ride: draws the creature each player is riding (player attribute "RidePet", set by the server
-- from the strongest creature in their team) under their character, every frame on each client.
--
-- The creature comes from RideModel: reshaped like a pony and wearing a saddle (art: the Cubeling Ride
-- concept sheet). Creature and rider move as one body: no hop, the creature walks with its legs and tail and
-- leans a little into the run, and a jump lifts both. The rider sits on the saddle straddling the creature,
-- hands on the handle: each client poses every rider's hips, knees and shoulders itself (Motor6D.Transform),
-- so no uploaded animation is needed. The rider's own client turns off their walk animations and sets the
-- height they sit at. PetFollow hides the ridden creature from the followers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RideModel = require(Shared.RideModel)
local Cosmetics = require(Shared.Config.Cosmetics)

local RideClient = {}

-- Legs walk in diagonal pairs, like the followers
local LEG_PHASE = { legFL = 0, legBR = 0, legFR = math.pi, legBL = math.pi }

-- The riding pose, in degrees (R15). Roll is outward for the legs, inward for the arms.
local POSE = { hipPitch = 15, hipRoll = 55, kneePitch = -10, kneeRoll = -45, armPitch = 50, armRoll = 8 }
-- How far below the rider's hips their HumanoidRootPart's bottom is (R15), or their legs' length (R6)
local HIPS_ABOVE_ROOT_BOTTOM = { R15 = 0.6, R6 = 2 }

type Mount = {
	value: string,
	ride: RideModel.Ride,
	phase: number,
	openUntil: number,
	nextChirp: number,
	mouthOpen: boolean,
	drop: number, -- height of the character's root above the creature's feet
	run: number, -- 0 standing .. 1 running, eased
	posed: Model?, -- the character whose joints this mount is posing
}

local mounts: { [Player]: Mount } = {}
local container = Instance.new("Folder")
container.Name = "Rides"
local LOCAL = Players.LocalPlayer
local seated: Model? = nil -- the local character, while it rides (its walk animations are off)

local function parse(value: string): { s: string, v: string, z: string }?
	local s, v, z = string.match(value, "^([^|]+)|([^|]+)|([^|]+)")
	if not s then
		return nil
	end
	return { s = s :: string, v = v :: string, z = z :: string }
end

---------------------------------------------------------------------------------------------------------------
-- Rider pose: R15 joints bent by Motor6D.Transform, set after animations every frame

local JOINTS = {
	{ part = "LeftUpperLeg", motor = "LeftHip", side = -1, kind = "hip" },
	{ part = "RightUpperLeg", motor = "RightHip", side = 1, kind = "hip" },
	{ part = "LeftLowerLeg", motor = "LeftKnee", side = -1, kind = "knee" },
	{ part = "RightLowerLeg", motor = "RightKnee", side = 1, kind = "knee" },
	{ part = "LeftUpperArm", motor = "LeftShoulder", side = -1, kind = "arm" },
	{ part = "RightUpperArm", motor = "RightShoulder", side = 1, kind = "arm" },
}

local function jointTransform(kind: string, side: number): CFrame
	if kind == "hip" then
		return CFrame.Angles(math.rad(POSE.hipPitch), 0, math.rad(POSE.hipRoll) * side)
	elseif kind == "knee" then
		return CFrame.Angles(math.rad(POSE.kneePitch), 0, math.rad(POSE.kneeRoll) * side)
	end
	return CFrame.Angles(math.rad(POSE.armPitch), 0, math.rad(POSE.armRoll) * -side)
end

local function setPose(character: Model, on: boolean)
	for _, joint in JOINTS do
		local limb = character:FindFirstChild(joint.part)
		local motor = limb and limb:FindFirstChild(joint.motor)
		if motor and motor:IsA("Motor6D") then
			motor.Transform = if on then jointTransform(joint.kind, joint.side) else CFrame.identity
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- The local rider: walk animations off while riding, and the height that puts their hips on the saddle

local function stand()
	if not seated then
		return
	end
	local animate = seated:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = true
	end
	seated = nil
end

local function sit(character: Model)
	if seated == character then
		return
	end
	stand()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not humanoid or not animator then
		return
	end
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = false
	end
	for _, playing in animator:GetPlayingAnimationTracks() do
		playing:Stop(0.1)
	end
	seated = character
end

local function seatHeight(mount: Mount, humanoid: Humanoid): number
	local hipsAboveGround = Cosmetics.RIDE_CREATURE_HEIGHT / 2 + mount.ride.seat.Y
	local below = if humanoid.RigType == Enum.HumanoidRigType.R6 then HIPS_ABOVE_ROOT_BOTTOM.R6 else HIPS_ABOVE_ROOT_BOTTOM.R15
	return hipsAboveGround - below
end

---------------------------------------------------------------------------------------------------------------
-- Mounts

local function remove(player: Player)
	local mount = mounts[player]
	if mount then
		if mount.posed then
			setPose(mount.posed, false)
		end
		mount.ride.built.model:Destroy()
		mounts[player] = nil
	end
end

local function build(player: Player, value: string)
	remove(player)
	local pet = parse(value)
	if not pet then
		return
	end
	local ride = RideModel.build(pet)
	ride.built.model.Parent = container
	mounts[player] = {
		value = value,
		ride = ride,
		phase = math.random() * math.pi * 2,
		openUntil = 0,
		nextChirp = os.clock() + 2,
		mouthOpen = false,
		drop = Cosmetics.RIDE_CREATURE_HEIGHT + 2,
		run = 0,
		posed = nil,
	}
end

local function syncSeat()
	local character = LOCAL.Character
	local value = LOCAL:GetAttribute("RidePet")
	if character and type(value) == "string" and value ~= "" then
		sit(character)
	else
		stand()
	end
end

local function sync(player: Player)
	local value = player:GetAttribute("RidePet")
	if type(value) ~= "string" or value == "" then
		remove(player)
	elseif not mounts[player] or mounts[player].value ~= value then
		build(player, value)
	end
	if player == LOCAL then
		syncSeat()
	end
end

local function setMouth(mount: Mount, open: boolean)
	if mount.mouthOpen == open then
		return
	end
	mount.mouthOpen = open
	local built = mount.ride.built
	for i, anim in built.anims do
		if anim == "mouthO" then
			built.parts[i].Transparency = if open then 0 else 1
		elseif anim == "mouthC" then
			built.parts[i].Transparency = if open then 1 else 0
		end
	end
end

-- Draws every creature under its rider
local function draw(dt: number)
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local now = os.clock()
	local height = Cosmetics.RIDE_CREATURE_HEIGHT
	for player, mount in mounts do
		local built = mount.ride.built
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid then
			built.model.Parent = nil
			continue
		end
		built.model.Parent = container
		if player == LOCAL and seated == character then
			local hip = seatHeight(mount, humanoid)
			if math.abs(humanoid.HipHeight - hip) > 0.01 then
				humanoid.HipHeight = hip
			end
		end

		local velocity = root.AssemblyLinearVelocity
		local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 2
		local airborne = humanoid.FloorMaterial == Enum.Material.Air
		-- The creature stands on the ground under the rider, and a jump carries it along
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, container }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -(height + 8), 0), params)
		if hit and not airborne then
			mount.drop = root.Position.Y - hit.Position.Y
		end
		local feetY = root.Position.Y - mount.drop
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		-- The saddle (seat.Z behind the creature's middle) is under the rider, so the middle is ahead of them
		local ahead = flat * mount.ride.seat.Z
		local center = Vector3.new(root.Position.X + ahead.X, feetY + height / 2, root.Position.Z + ahead.Z)
		mount.run += ((if moving and not airborne then 1 else 0) - mount.run) * math.min(1, dt * 6)
		local frame = CFrame.lookAt(center, center + flat) * CFrame.Angles(math.rad(-4) * mount.run, 0, 0)

		if now >= mount.nextChirp then
			mount.openUntil = now + 0.4 + math.random() * 0.4
			mount.nextChirp = now + 4 + math.random() * 6
		end
		setMouth(mount, now < mount.openUntil)

		for i, p in built.parts do
			local cf = mount.ride.offsets[i]
			local anim = built.anims[i]
			local swing: CFrame? = nil
			if anim then
				local leg = LEG_PHASE[anim]
				if leg and mount.run > 0.05 then
					swing = CFrame.Angles(math.sin(now * 14 + mount.phase + leg) * math.rad(32) * mount.run, 0, 0)
				elseif string.sub(anim, 1, 4) == "wing" then
					local side = if anim == "wingL" then 1 else -1
					swing = CFrame.Angles(0, 0, side * (math.sin(now * (if moving then 16 else 8) + mount.phase) * math.rad(30) + math.rad(8)))
				elseif anim == "tail" then
					swing = CFrame.Angles(0, math.sin(now * (if moving then 14 else 5) + mount.phase) * math.rad(22), 0)
				end
			end
			local pivot = mount.ride.pivots[i]
			if swing and pivot then
				cf = CFrame.new(pivot) * swing * CFrame.new(-pivot) * cf
			end
			table.insert(parts, p)
			table.insert(cframes, frame * cf)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Poses every rider (after animations, before physics, so nothing overwrites it)
local function pose()
	for player, mount in mounts do
		local character = player.Character
		if mount.posed and mount.posed ~= character then
			setPose(mount.posed, false)
			mount.posed = nil
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
			setPose(character, true)
			mount.posed = character
		end
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("RidePet"):Connect(function()
		sync(player)
	end)
	sync(player)
end

function RideClient.init()
	container.Parent = workspace
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(remove)
	LOCAL.CharacterAdded:Connect(function(character)
		seated = nil -- the old character took its state with it
		character:WaitForChild("Humanoid")
		character:WaitForChild("Animate", 5)
		syncSeat()
	end)
	-- The creature models may arrive after the first build: rebuild everyone's ride then
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "CreatureModels" then
			local riding: { [Player]: string } = {}
			for player, mount in mounts do
				riding[player] = mount.value
			end
			for player, value in riding do
				build(player, value)
			end
		end
	end)
	RunService.RenderStepped:Connect(draw)
	RunService.Stepped:Connect(pose)
end

return RideClient
