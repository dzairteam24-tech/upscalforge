-- Cubeling Ride: draws the creature each player is riding (player attribute "RidePet", set by the server
-- from the strongest creature in their team) under their character, every frame on each client.
--
-- The creature comes from RideModel: reshaped like a pony and wearing a saddle (art: the Cubeling Ride
-- concept sheet). Creature and rider move as one body: no hop, the creature walks with its legs and tail and
-- leans a little into the run, and a jump lifts both. The rider sits on the saddle straddling the creature,
-- hands on the handle: each client poses every rider's hips, knees and shoulders itself (the joints' Transform),
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

-- The riding pose, in degrees (R15), like the riding model sheet (art/renders/RideSheet.png): the hips down in
-- the seat, leaning a little forward at the waist, thighs forward and out over the front of the seat, knees
-- bent so the lower legs go down beside the side flaps with the feet in the stirrups; elbows bent so both
-- hands hold the handle. Roll is outward for the legs, inward for the arms. (Fitted against the pony and
-- saddle meshes offline; art/blender/pony.py poses its rider with the same numbers.)
local POSE = {
	waistPitch = -12,
	hipPitch = 80,
	hipRoll = 50,
	kneePitch = -70,
	kneeRoll = 10,
	armPitch = -6,
	armRoll = 60,
	elbowPitch = 90,
}
-- Jumping: the creature tucks its legs (front forward, back backward) and tilts with its climb or fall
local JUMP_TUCK = 40
local JUMP_TILT = 12
local FRONT_LEGS = { legFL = true, legFR = true }
-- R6 legs aren't part of HipHeight: the root's bottom stands this high above the ground plus HipHeight
local R6_LEGS = 2

type Mount = {
	value: string,
	ride: RideModel.Ride,
	phase: number,
	openUntil: number,
	nextChirp: number,
	mouthOpen: boolean,
	run: number, -- 0 standing .. 1 running, eased
	air: number, -- 0 on the ground .. 1 in a jump, eased
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
-- Rider pose: R15 joints bent through their Transform, set after animations every frame

-- Joint names are the same in both rigs Roblox uses for R15: Motor6D joints, and the newer AnimationConstraint
-- joints (Workspace.AvatarJointUpgrade). Both have a Transform that bends the limb.
local JOINTS = {
	{ name = "Waist", side = 0, kind = "waist" },
	{ name = "LeftHip", side = -1, kind = "hip" },
	{ name = "RightHip", side = 1, kind = "hip" },
	{ name = "LeftKnee", side = -1, kind = "knee" },
	{ name = "RightKnee", side = 1, kind = "knee" },
	{ name = "LeftShoulder", side = -1, kind = "arm" },
	{ name = "RightShoulder", side = 1, kind = "arm" },
	{ name = "LeftElbow", side = -1, kind = "elbow" },
	{ name = "RightElbow", side = 1, kind = "elbow" },
}

local function jointTransform(kind: string, side: number): CFrame
	if kind == "hip" then
		return CFrame.Angles(math.rad(POSE.hipPitch), 0, math.rad(POSE.hipRoll) * side)
	elseif kind == "waist" then
		return CFrame.Angles(math.rad(POSE.waistPitch), 0, 0)
	elseif kind == "elbow" then
		return CFrame.Angles(math.rad(POSE.elbowPitch), 0, 0)
	elseif kind == "knee" then
		return CFrame.Angles(math.rad(POSE.kneePitch), 0, math.rad(POSE.kneeRoll) * side)
	end
	return CFrame.Angles(math.rad(POSE.armPitch), 0, math.rad(POSE.armRoll) * -side)
end

-- The character's joints by name, found once per character
local jointCache: { [Model]: { [string]: Instance } } = setmetatable({}, { __mode = "k" }) :: any
local warned: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function jointsOf(character: Model): { [string]: Instance }
	local cached = jointCache[character]
	if cached and next(cached) then
		return cached
	end
	local found: { [string]: Instance } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			for _, joint in JOINTS do
				if d.Name == joint.name and not found[joint.name] then
					found[joint.name] = d
				end
			end
		end
	end
	jointCache[character] = found
	if not next(found) and not warned[character] then
		warned[character] = true
		warn("[Ride] no R15 leg/arm joints found on", character.Name, "- can't pose the rider")
	end
	return found
end

local function setPose(character: Model, on: boolean)
	local joints = jointsOf(character)
	for _, joint in JOINTS do
		local instance = joints[joint.name]
		if instance then
			(instance :: any).Transform = if on then jointTransform(joint.kind, joint.side) else CFrame.identity
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

-- How far the rider's hip joints are below their HumanoidRootPart's center, measured on the character: the
-- hip attachments of the R15 LowerTorso (the riding pose bends the legs, not the LowerTorso, so it doesn't
-- change this). It depends on the avatar's body and scale, which is why it isn't a constant: a fixed guess
-- sat small avatars inside the saddle. R6, or a rig without those attachments: the hips are at the root's
-- bottom.
local function hipsBelowRoot(character: Model, root: BasePart): number
	local lower = character:FindFirstChild("LowerTorso")
	local left = lower and lower:FindFirstChild("LeftHipRigAttachment")
	local right = lower and lower:FindFirstChild("RightHipRigAttachment")
	if left and right and left:IsA("Attachment") and right:IsA("Attachment") then
		return root.Position.Y - (left.WorldPosition.Y + right.WorldPosition.Y) / 2
	end
	return root.Size.Y / 2
end

-- The local rider's HipHeight that puts the creature's feet on the ground while their hips are on the saddle
local function seatHeight(mount: Mount, humanoid: Humanoid, character: Model, root: BasePart): number
	local rootAboveFeet = hipsBelowRoot(character, root) + mount.ride.seat.Y + Cosmetics.RIDE_CREATURE_HEIGHT / 2
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then R6_LEGS else 0
	return rootAboveFeet - root.Size.Y / 2 - legs
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
		run = 0,
		air = 0,
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
			local hip = seatHeight(mount, humanoid, character, root)
			if math.abs(humanoid.HipHeight - hip) > 0.01 then
				humanoid.HipHeight = hip
			end
		end

		local velocity = root.AssemblyLinearVelocity
		local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 2
		local airborne = humanoid.FloorMaterial == Enum.Material.Air
		-- The creature is fixed under the rider, at the exact distance that puts the rider's hips on the saddle:
		-- they never come apart, so a jump lifts both. (Measuring the ground instead left the creature behind
		-- at the start of a jump.)
		-- (the saddle's seat goes exactly where the rider's hips are)
		local feetY = root.Position.Y - hipsBelowRoot(character, root) - mount.ride.seat.Y - height / 2
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		-- The saddle (seat.Z behind the creature's middle) is under the rider, so the middle is ahead of them
		local ahead = flat * mount.ride.seat.Z
		local center = Vector3.new(root.Position.X + ahead.X, feetY + height / 2, root.Position.Z + ahead.Z)
		mount.run += ((if moving and not airborne then 1 else 0) - mount.run) * math.min(1, dt * 6)
		mount.air += ((if airborne then 1 else 0) - mount.air) * math.min(1, dt * 12)
		-- A slight lean into the run on the ground; in a jump, nose up while climbing and down while falling
		local climb = math.clamp(velocity.Y / 40, -1, 1)
		local tilt = math.rad(-4) * mount.run * (1 - mount.air) + math.rad(JUMP_TILT) * climb * mount.air
		local frame = CFrame.lookAt(center, center + flat) * CFrame.Angles(tilt, 0, 0)

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
				if leg and (mount.run > 0.05 or mount.air > 0.05) then
					local walk = math.sin(now * 14 + mount.phase + leg) * math.rad(32) * mount.run * (1 - mount.air)
					local tuck = math.rad(if FRONT_LEGS[anim] then JUMP_TUCK else -JUMP_TUCK) * mount.air
					swing = CFrame.Angles(walk + tuck, 0, 0)
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
	-- The creature models, the pony and the saddle may arrive after the first build (under any name: RideModel
	-- finds the pony and saddle by their parts): rebuild everyone's ride then, once their parts are in
	ReplicatedStorage.ChildAdded:Connect(function()
		task.delay(1, function()
			local riding: { [Player]: string } = {}
			for player, mount in mounts do
				riding[player] = mount.value
			end
			for player, value in riding do
				build(player, value)
			end
		end)
	end)
	RunService.RenderStepped:Connect(draw)
	RunService.Stepped:Connect(pose)
end

return RideClient
