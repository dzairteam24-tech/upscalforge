-- Floating seats: draws the seat each player sits on (player attribute "RideSeat", the seat's name, set by the
-- server from their equipped ride) under their character, every frame on each client.
--
-- The seat (SeatModel) floats under the rider, bobbing gently and tipping a little into the run; the rider
-- sits on it cross-legged (SeatPose: feet crossed in front, hands on the knees). Each client poses every
-- rider itself every frame through the joints' Transform (RideIK bends the arms and legs, so no uploaded
-- animation is needed and it fits any avatar's size). The rider's own client turns off their walk animations
-- and sets the height they float at.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RideIK = require(Shared.RideIK)
local SeatModel = require(Shared.SeatModel)
local SeatPose = require(Shared.SeatPose)

local RideClient = {}

-- Only when a limb can't be solved (a rig without those joints): a fixed pose, in degrees
local POSE = {
	hipPitch = 95,
	hipRoll = 45,
	kneePitch = -95,
	kneeRoll = 15,
	armPitch = 0,
	armRoll = 48,
	elbowPitch = 68,
}
-- R6 legs aren't part of HipHeight: the root's bottom stands this high above the ground plus HipHeight
local R6_LEGS = 2

-- A floating seat under a player
type SeatMount = {
	name: string,
	seat: SeatModel.Seat,
	phase: number,
	run: number, -- 0 standing .. 1 moving, eased
	posed: Model?,
}
local seats: { [Player]: SeatMount } = {}
-- The floating seat: its underside this high above the ground, bobbing this much up and down every BOB_TIME
local SEAT_FLOAT = 1.2
local SEAT_BOB = 0.15
local SEAT_BOB_TIME = 2.6
local SEAT_FORWARD = 0.45 -- the seat's middle is this far in front of the hips (under the crossed legs)
local container = Instance.new("Folder")
container.Name = "Rides"
local LOCAL = Players.LocalPlayer
local seated: Model? = nil -- the local character, while it sits on a seat (its walk animations are off)

---------------------------------------------------------------------------------------------------------------
-- Rider pose: R15 joints bent through their Transform, set after animations every frame

-- Joint names are the same in both rigs Roblox uses for R15: Motor6D joints, and the newer AnimationConstraint
-- joints (Workspace.AvatarJointUpgrade). Both have a Transform that bends the limb.
local JOINT_NAMES = {
	"Root",
	"Waist",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}
local POSED = { "Waist", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }

-- The character's joints by name, found once per character
local jointCache: { [Model]: { [string]: Instance } } = setmetatable({}, { __mode = "k" }) :: any
local warned: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function jointsOf(character: Model): { [string]: Instance }
	local cached = jointCache[character]
	if cached and next(cached) then
		return cached
	end
	local wanted: { [string]: boolean } = {}
	for _, name in JOINT_NAMES do
		wanted[name] = true
	end
	local found: { [string]: Instance } = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and wanted[d.Name] and not found[d.Name] then
			found[d.Name] = d
		end
	end
	jointCache[character] = found
	if not next(found) and not warned[character] then
		warned[character] = true
		warn("[Ride] no R15 joints found on", character.Name, "- can't pose the rider")
	end
	return found
end

-- A joint's parent part and its two frames: child = parent * c0 * Transform * c1:Inverse()
type Frame = { parent: BasePart, c0: CFrame, c1: CFrame }

local function frameOf(joint: Instance?): Frame?
	if not joint then
		return nil
	end
	if joint:IsA("Motor6D") then
		local parent = joint.Part0
		return if parent then { parent = parent, c0 = joint.C0, c1 = joint.C1 } else nil
	elseif joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		local parent = a0 and a0.Parent
		if a0 and a1 and parent and parent:IsA("BasePart") then
			return { parent = parent, c0 = a0.CFrame, c1 = a1.CFrame }
		end
	end
	return nil
end

local function setTransform(joint: Instance?, transform: CFrame)
	if joint then
		(joint :: any).Transform = transform
	end
end

local function attachmentIn(character: Model, part: string, name: string): CFrame
	local p = character:FindFirstChild(part)
	local att = p and p:FindFirstChild(name)
	return if att and att:IsA("Attachment") then att.CFrame else CFrame.identity
end

-- The fixed pose, for a limb that can't be solved
local function fixedLimb(joints: { [string]: Instance }, side: string, limb: string)
	local s = if side == "Left" then -1 else 1
	if limb == "arm" then
		setTransform(joints[side .. "Shoulder"], CFrame.Angles(math.rad(POSE.armPitch), 0, math.rad(POSE.armRoll) * -s))
		setTransform(joints[side .. "Elbow"], CFrame.Angles(math.rad(POSE.elbowPitch), 0, 0))
	else
		setTransform(joints[side .. "Hip"], CFrame.Angles(math.rad(POSE.hipPitch), 0, math.rad(POSE.hipRoll) * s))
		setTransform(joints[side .. "Knee"], CFrame.Angles(math.rad(POSE.kneePitch), 0, math.rad(POSE.kneeRoll) * s))
	end
end

-- Bends one limb (shoulder-elbow-wrist or hip-knee-ankle) so its end lands on the target. Returns the frame of
-- the limb's last part before its end joint (the lower arm or leg), or nil when it can't be solved.
local function solveLimb(joints: { [string]: Instance }, parentFrame: CFrame, names: { string }, tip: CFrame, target: Vector3, pole: Vector3): (CFrame?, Frame?)
	local a, b, c = frameOf(joints[names[1]]), frameOf(joints[names[2]]), frameOf(joints[names[3]])
	if not a or not b or not c then
		return nil, nil
	end
	local base = parentFrame * a.c0
	local midRel = a.c1:Inverse() * b.c0
	local tipRel = b.c1:Inverse() * c.c0 * c.c1:Inverse() * tip
	local first, second = RideIK.solve(base, midRel, tipRel, target, pole)
	setTransform(joints[names[1]], first)
	setTransform(joints[names[2]], second)
	local lower = base * first * a.c1:Inverse() * b.c0 * second * b.c1:Inverse()
	return lower, c
end

-- Poses a rider on their mount: leaning a little forward, hands on the grips, feet in the stirrups (flat)
-- How long the character's leg is, hip joint to sole, over a standard R15 leg: the seat pose scales with it
local function legScale(joints: { [string]: Instance }, sole: CFrame): number
	local a, b, c = frameOf(joints.LeftHip), frameOf(joints.LeftKnee), frameOf(joints.LeftAnkle)
	if not a or not b or not c then
		return 1
	end
	local length = (a.c1:Inverse() * b.c0).Position.Magnitude + (b.c1:Inverse() * c.c0 * c.c1:Inverse() * sole).Position.Magnitude
	return length / SeatPose.STANDARD_LEG
end

-- Poses a rider on a floating seat: cross-legged, leaning a little forward, hands on the knees
local function poseSeated(character: Model)
	local joints = jointsOf(character)
	local lowerTorso = character:FindFirstChild("LowerTorso") :: BasePart?
	if not lowerTorso then
		return
	end
	local rootJoint = frameOf(joints.Root)
	local lower = if rootJoint then rootJoint.parent.CFrame * rootJoint.c0 * (joints.Root :: any).Transform * rootJoint.c1:Inverse() else lowerTorso.CFrame
	local lean = CFrame.Angles(math.rad(SeatPose.LEAN), 0, 0)
	setTransform(joints.Waist, lean)
	local waist = frameOf(joints.Waist)
	local upper = if waist then lower * waist.c0 * lean * waist.c1:Inverse() else lower
	local left, right = frameOf(joints.LeftHip), frameOf(joints.RightHip)
	local middle = if left and right then ((lower * left.c0).Position + (lower * right.c0).Position) / 2 else lower.Position
	local hips = CFrame.new(middle) * lower.Rotation
	local scale = legScale(joints, attachmentIn(character, "LeftFoot", "LeftFootAttachment"))
	for _, side in { "Left", "Right" } do
		local sole = attachmentIn(character, side .. "Foot", side .. "FootAttachment")
		local target, kneePole, foot = SeatPose.leg(hips, side, scale)
		local shin, ankle = solveLimb(joints, lower, { side .. "Hip", side .. "Knee", side .. "Ankle" }, sole, target, kneePole)
		local knee = frameOf(joints[side .. "Knee"])
		if shin and ankle and knee then
			setTransform(joints[side .. "Ankle"], RideIK.orient(shin, ankle.c0, ankle.c1, foot))
			-- The hand on the knee (the knee joint's pivot: the shin's frame at the joint)
			local hand, elbowPole = SeatPose.hand(hips, (shin * knee.c1).Position, side, scale)
			local tip = attachmentIn(character, side .. "Hand", side .. "GripAttachment")
			if not solveLimb(joints, upper, { side .. "Shoulder", side .. "Elbow", side .. "Wrist" }, tip, hand, elbowPole) then
				fixedLimb(joints, side, "arm")
			end
		else
			fixedLimb(joints, side, "leg")
			fixedLimb(joints, side, "arm")
			setTransform(joints[side .. "Ankle"], CFrame.identity)
		end
		setTransform(joints[side .. "Wrist"], CFrame.identity)
	end
end

local function clearPose(character: Model)
	local joints = jointsOf(character)
	for _, name in POSED do
		setTransform(joints[name], CFrame.identity)
	end
end

---------------------------------------------------------------------------------------------------------------
-- The local rider: walk animations off while sitting

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
-- hip attachments of the R15 LowerTorso (the sitting pose bends the legs, not the LowerTorso, so it doesn't
-- change this). It depends on the avatar's body and scale, which is why it isn't a constant: a fixed guess
-- sat small avatars inside the seat. R6, or a rig without those attachments: the hips are at the root's
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

local function syncSeat()
	local character = LOCAL.Character
	local seat = LOCAL:GetAttribute("RideSeat")
	if character and type(seat) == "string" and seat ~= "" then
		sit(character)
	else
		stand()
	end
end

local function removeSeat(player: Player)
	local mount = seats[player]
	if mount then
		if mount.posed then
			clearPose(mount.posed)
		end
		mount.seat.model:Destroy()
		seats[player] = nil
	end
end

local function buildSeat(player: Player, name: string)
	removeSeat(player)
	local seat = SeatModel.build(name)
	seat.model.Parent = container
	seats[player] = { name = name, seat = seat, phase = math.random() * math.pi * 2, run = 0, posed = nil }
end

local function syncSeatRide(player: Player)
	local name = player:GetAttribute("RideSeat")
	if type(name) ~= "string" or name == "" then
		removeSeat(player)
	elseif not seats[player] or seats[player].name ~= name then
		buildSeat(player, name)
	end
	if player == LOCAL then
		syncSeat()
	end
end

-- Draws every floating seat under its rider; the local rider's HipHeight floats them (with a gentle bob)
local function draw(dt: number)
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local now = os.clock()
	for player, mount in seats do
		local seat = mount.seat
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid then
			seat.model.Parent = nil
			continue
		end
		seat.model.Parent = container
		local scale = legScale(jointsOf(character), attachmentIn(character, "LeftFoot", "LeftFootAttachment"))
		local lift = SeatPose.LIFT * scale
		local hipsBelow = hipsBelowRoot(character, root)
		if player == LOCAL and seated == character then
			local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then R6_LEGS else 0
			local bob = SEAT_BOB * math.sin(now * (2 * math.pi / SEAT_BOB_TIME) + mount.phase)
			local hip = SEAT_FLOAT + bob + seat.top + lift + hipsBelow - root.Size.Y / 2 - legs
			if math.abs(humanoid.HipHeight - hip) > 0.005 then
				humanoid.HipHeight = hip
			end
		end
		local velocity = root.AssemblyLinearVelocity
		local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 2
		mount.run += ((if moving then 1 else 0) - mount.run) * math.min(1, dt * 5)
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		-- Fixed under the hips (they never come apart, so a jump lifts both), tipping a little into the run and
		-- rocking softly
		local origin = root.Position - Vector3.new(0, hipsBelow + lift + seat.top, 0) + flat * SEAT_FORWARD
		local rock = math.sin(now * 1.7 + mount.phase) * math.rad(2)
		local frame = CFrame.lookAt(origin, origin + flat) * CFrame.Angles(math.rad(-5) * mount.run, 0, rock)
		for i, p in seat.parts do
			table.insert(parts, p)
			table.insert(cframes, frame * seat.offsets[i])
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Poses every rider (after animations, before physics, so nothing overwrites it)
local function pose()
	for player, mount in seats do
		local character = player.Character
		if mount.posed and mount.posed ~= character then
			clearPose(mount.posed)
			mount.posed = nil
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
			poseSeated(character)
			mount.posed = character
		end
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("RideSeat"):Connect(function()
		syncSeatRide(player)
	end)
	syncSeatRide(player)
end

function RideClient.init()
	container.Parent = workspace
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(removeSeat)
	LOCAL.CharacterAdded:Connect(function(character)
		seated = nil -- the old character took its state with it
		character:WaitForChild("Humanoid")
		character:WaitForChild("Animate", 5)
		syncSeat()
	end)
	-- The seat models may arrive after the first build (under any name: SeatModel finds them by their parts):
	-- rebuild everyone's seat then, once their parts are in
	ReplicatedStorage.ChildAdded:Connect(function()
		task.delay(1, function()
			local sitting: { [Player]: string } = {}
			for player, mount in seats do
				sitting[player] = mount.name
			end
			for player, name in sitting do
				buildSeat(player, name)
			end
		end)
	end)
	RunService.RenderStepped:Connect(draw)
	RunService.Stepped:Connect(pose)
end

return RideClient
