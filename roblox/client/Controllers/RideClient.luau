-- Cubeling Ride: draws the creature each player is riding (player attribute "RidePet", set by the server
-- from the strongest creature in their team) under their character, every frame on each client.
-- It is drawn RIDE_CREATURE_HEIGHT tall whatever its size (taller than the rider). Creature and rider move as
-- one body: no hop (that read as the rider jumping), the creature walks with its legs and tail and leans a
-- little into the run, and a jump lifts both. It wears a saddle (art: the Cubeling Ride concept sheet) and
-- opens its mouth now and then. PetFollow hides the same creature from the followers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local PetModel = require(Shared.PetModel)

local RideClient = {}

-- Legs walk in diagonal pairs, like the followers
local LEG_PHASE = { legFL = 0, legBR = 0, legFR = math.pi, legBL = math.pi }

type Mount = {
	value: string,
	built: PetModel.Built,
	offsets: { CFrame },
	pivots: { [number]: Vector3 },
	phase: number,
	openUntil: number,
	nextChirp: number,
	mouthOpen: boolean,
	drop: number, -- height of the character's root above the creature's feet
	run: number, -- 0 standing .. 1 running, eased
}

local mounts: { [Player]: Mount } = {}
local container = Instance.new("Folder")
container.Name = "Rides"
local LOCAL = Players.LocalPlayer
local SIT_FALLBACK = { R15 = "rbxassetid://2506281703", R6 = "rbxassetid://178130996" }
-- The local rider's sit pose, while riding (see sit/stand below)
local seated: { character: Model, track: AnimationTrack }? = nil

local function parse(value: string): { s: string, v: string, z: string }?
	local s, v, z = string.match(value, "^([^|]+)|([^|]+)|([^|]+)")
	if not s then
		return nil
	end
	return { s = s :: string, v = v :: string, z = z :: string }
end

local function remove(player: Player)
	local mount = mounts[player]
	if mount then
		mount.built.model:Destroy()
		mounts[player] = nil
	end
end

-- Builds the creature at the ride height: parts and their offsets grow or shrink together
local function build(player: Player, value: string)
	remove(player)
	local pet = parse(value)
	if not pet then
		return
	end
	local built = PetModel.build(pet)
	local scale = Cosmetics.RIDE_CREATURE_HEIGHT / math.max(built.height, 0.1)
	local offsets: { CFrame } = {}
	for i, p in built.parts do
		p.Size *= scale
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		local o = built.offsets[i]
		offsets[i] = CFrame.new(o.Position * scale) * o.Rotation
	end
	local pivots: { [number]: Vector3 } = {}
	for i, pivot in built.pivots do
		pivots[i] = pivot * scale
	end
	-- Saddle on its back, where the rider sits (RIDE_FORWARD behind the middle), from the concept sheet:
	-- a red-orange seat with a cream trim on a brown leather frame, a handle in front for the rider's hands,
	-- straps with gold buckles down each side and a little bag with a gold paw coin
	local halfWidth = built.body.Size.X / 2
	local top = Cosmetics.RIDE_CREATURE_HEIGHT / 2
	local seatZ = Cosmetics.RIDE_FORWARD
	local leather = Color3.fromRGB(110, 66, 38)
	local seatColor = Color3.fromRGB(232, 96, 52)
	local cream = Color3.fromRGB(250, 236, 210)
	local gold = Color3.fromRGB(255, 196, 60)
	type Piece = { size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType? }
	local saddle: { Piece } = {
		-- frame and seat
		{ size = Vector3.new(halfWidth * 2 * 0.8, 0.3, 3.2), offset = Vector3.new(0, top + 0.1, seatZ), color = leather, material = Enum.Material.Leather },
		{ size = Vector3.new(halfWidth * 2 * 0.72, 0.18, 2.9), offset = Vector3.new(0, top + 0.32, seatZ), color = cream, material = Enum.Material.SmoothPlastic },
		{ size = Vector3.new(halfWidth * 2 * 0.66, 0.35, 2.6), offset = Vector3.new(0, top + 0.5, seatZ), color = seatColor, material = Enum.Material.Fabric },
		{ size = Vector3.new(halfWidth * 2 * 0.7, 0.8, 0.45), offset = Vector3.new(0, top + 0.75, seatZ + 1.35), color = leather, material = Enum.Material.Leather },
		-- handle in front: two posts and a bar
		{ size = Vector3.new(0.25, 1.1, 0.25), offset = Vector3.new(0.75, top + 0.85, seatZ - 1.4), color = leather, material = Enum.Material.Leather },
		{ size = Vector3.new(0.25, 1.1, 0.25), offset = Vector3.new(-0.75, top + 0.85, seatZ - 1.4), color = leather, material = Enum.Material.Leather },
		{ size = Vector3.new(1.8, 0.28, 0.32), offset = Vector3.new(0, top + 1.4, seatZ - 1.4), color = gold, material = Enum.Material.SmoothPlastic },
		-- straps and buckles down each side
		{ size = Vector3.new(0.16, top * 1.1, 0.6), offset = Vector3.new(halfWidth + 0.08, top * 0.45, seatZ), color = leather, material = Enum.Material.Leather },
		{ size = Vector3.new(0.16, top * 1.1, 0.6), offset = Vector3.new(-halfWidth - 0.08, top * 0.45, seatZ), color = leather, material = Enum.Material.Leather },
		{ size = Vector3.new(0.22, 0.55, 0.75), offset = Vector3.new(halfWidth + 0.12, top * 0.3, seatZ), color = gold, material = Enum.Material.SmoothPlastic },
		{ size = Vector3.new(0.22, 0.55, 0.75), offset = Vector3.new(-halfWidth - 0.12, top * 0.3, seatZ), color = gold, material = Enum.Material.SmoothPlastic },
		-- bag on the right side with a gold paw coin
		{ size = Vector3.new(0.6, 1.2, 1.3), offset = Vector3.new(halfWidth + 0.35, top * 0.7, seatZ + 0.4), color = leather, material = Enum.Material.Leather },
		{ size = Vector3.new(0.12, 0.75, 0.75), offset = Vector3.new(halfWidth + 0.68, top * 0.7, seatZ + 0.4), color = gold, material = Enum.Material.SmoothPlastic, shape = Enum.PartType.Cylinder },
	}
	for _, piece in saddle do
		local p = Instance.new("Part")
		p.Name = "Saddle"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = piece.size
		p.Color = piece.color
		p.Material = piece.material
		if piece.shape then
			p.Shape = piece.shape
		end
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = built.model
		table.insert(built.parts, p)
		table.insert(offsets, CFrame.new(piece.offset))
	end
	built.model.Parent = container
	mounts[player] = {
		value = value,
		built = built,
		offsets = offsets,
		pivots = pivots,
		phase = math.random() * math.pi * 2,
		openUntil = 0,
		nextChirp = os.clock() + 2,
		mouthOpen = false,
		drop = Cosmetics.RIDE_CREATURE_HEIGHT + 2,
		run = 0,
	}
end

local function sync(player: Player)
	local value = player:GetAttribute("RidePet")
	if type(value) ~= "string" or value == "" then
		remove(player)
	elseif not mounts[player] or mounts[player].value ~= value then
		build(player, value)
	end
end

local function setMouth(mount: Mount, open: boolean)
	if mount.mouthOpen == open then
		return
	end
	mount.mouthOpen = open
	for i, anim in mount.built.anims do
		if anim == "mouthO" then
			mount.built.parts[i].Transparency = if open then 0 else 1
		elseif anim == "mouthC" then
			mount.built.parts[i].Transparency = if open then 1 else 0
		end
	end
end

local function step(dt: number)
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local now = os.clock()
	local height = Cosmetics.RIDE_CREATURE_HEIGHT
	for player, mount in mounts do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then
			mount.built.model.Parent = nil
			continue
		end
		mount.built.model.Parent = container
		local velocity = root.AssemblyLinearVelocity
		local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 2
		local airborne = humanoid.FloorMaterial == Enum.Material.Air
		-- The creature stands on the ground under the player (or just below the character while jumping)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, container }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -(height + 8), 0), params)
		if hit and not airborne then
			mount.drop = root.Position.Y - hit.Position.Y -- remembered so a jump carries the creature along
		end
		local feetY = root.Position.Y - mount.drop
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.new(0, 0, -1)
		end
		local ahead = flat.Unit * Cosmetics.RIDE_FORWARD
		local center = Vector3.new(root.Position.X + ahead.X, feetY + height / 2, root.Position.Z + ahead.Z)
		-- A slight lean into the run, eased in and out (no bounce: the rider stays put on the saddle)
		local target = if moving and not airborne then 1 else 0
		mount.run += (target - mount.run) * math.min(1, dt * 6)
		local lean = CFrame.Angles(math.rad(-4) * mount.run, 0, 0)
		local frame = CFrame.lookAt(center, center + flat) * lean

		if now >= mount.nextChirp then
			mount.openUntil = now + 0.4 + math.random() * 0.4
			mount.nextChirp = now + 4 + math.random() * 6
		end
		setMouth(mount, now < mount.openUntil)

		for i, p in mount.built.parts do
			local cf = mount.offsets[i]
			local anim = mount.built.anims[i]
			local swing: CFrame? = nil
			if anim then
				local leg = LEG_PHASE[anim]
				if leg and mount.run > 0.1 then
					swing = CFrame.Angles(math.sin(now * 14 + mount.phase + leg) * math.rad(32) * mount.run, 0, 0)
				elseif string.sub(anim, 1, 4) == "wing" then
					local side = if anim == "wingL" then 1 else -1
					swing = CFrame.Angles(0, 0, side * (math.sin(now * (if moving then 16 else 8) + mount.phase) * math.rad(30) + math.rad(8)))
				elseif anim == "tail" then
					swing = CFrame.Angles(0, math.sin(now * (if moving then 14 else 5) + mount.phase) * math.rad(22), 0)
				end
			end
			if swing and mount.pivots[i] then
				local pivot = mount.pivots[i]
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

---------------------------------------------------------------------------------------------------------------
-- The local rider sits still: the walk animations stop and the character's own sit pose plays instead.
-- Animations played on your own character show for everyone.


local function stand()
	if not seated then
		return
	end
	seated.track:Stop(0.2)
	local animate = seated.character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = true
	end
	seated = nil
end

local function sit(character: Model)
	if seated and seated.character == character then
		return
	end
	stand()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not humanoid or not animator then
		return
	end
	local animate = character:FindFirstChild("Animate")
	local sitValue = animate and animate:FindFirstChild("sit")
	local source = sitValue and sitValue:FindFirstChildOfClass("Animation")
	local animation = Instance.new("Animation")
	animation.AnimationId = if source
		then source.AnimationId
		elseif humanoid.RigType == Enum.HumanoidRigType.R6 then SIT_FALLBACK.R6
		else SIT_FALLBACK.R15
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = false
	end
	for _, playing in animator:GetPlayingAnimationTracks() do
		playing:Stop(0.1)
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		if animate and animate:IsA("LocalScript") then
			animate.Enabled = true
		end
		return
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.2)
	seated = { character = character, track = track }
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

local function watch(player: Player)
	player:GetAttributeChangedSignal("RidePet"):Connect(function()
		sync(player)
		if player == LOCAL then
			syncSeat()
		end
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
		seated = nil -- the old character took its animations with it
		character:WaitForChild("Humanoid")
		character:WaitForChild("Animate", 5)
		syncSeat()
	end)
	syncSeat()
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
	RunService.RenderStepped:Connect(step)
end

return RideClient
