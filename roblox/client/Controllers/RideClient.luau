-- Cubeling Ride: draws the creature each player is riding (player attribute "RidePet", set by the server
-- from the strongest creature in their team) under their character, every frame on each client.
-- It is drawn RIDE_CREATURE_HEIGHT tall whatever its size (taller than the rider), hops and swings its legs while moving, and
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
	seatHip: number, -- the rider's HipHeight sitting on it (as the server sets it), before the hop
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

-- The rider's HipHeight on the creature, the same as the server sets (GameService applyTitles)
local function seatHipFor(player: Player): number
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local base = character and character:GetAttribute("BaseHipHeight")
	local legs = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else 0
	return math.max(if type(base) == "number" then base else 2, Cosmetics.RIDE_CREATURE_HEIGHT - 0.3 - legs)
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
	-- Saddle on its back, where the rider sits (RIDE_FORWARD behind the middle): a blanket, a seat with
	-- a raised front and back, and a strap down each side
	local halfWidth = built.body.Size.X / 2
	local top = Cosmetics.RIDE_CREATURE_HEIGHT / 2
	local seatZ = Cosmetics.RIDE_FORWARD
	local leather = Color3.fromRGB(120, 72, 40)
	local saddle: { { size: Vector3, offset: Vector3, color: Color3, material: Enum.Material } } = {
		{ size = Vector3.new(halfWidth * 2 + 0.2, 0.18, 3.6), offset = Vector3.new(0, top + 0.05, seatZ), color = Color3.fromRGB(200, 50, 60), material = Enum.Material.Fabric },
		{ size = Vector3.new(halfWidth * 2 + 0.25, 0.08, 3.7), offset = Vector3.new(0, top + 0.1, seatZ), color = Color3.fromRGB(255, 205, 80), material = Enum.Material.Fabric },
		{ size = Vector3.new(2.6, 0.4, 2.8), offset = Vector3.new(0, top + 0.3, seatZ), color = leather, material = Enum.Material.Leather },
		{ size = Vector3.new(1.2, 0.9, 0.5), offset = Vector3.new(0, top + 0.7, seatZ - 1.25), color = leather, material = Enum.Material.Leather },
		{ size = Vector3.new(2.6, 0.7, 0.5), offset = Vector3.new(0, top + 0.6, seatZ + 1.3), color = leather, material = Enum.Material.Leather },
		{ size = Vector3.new(0.18, top * 0.9, 0.7), offset = Vector3.new(halfWidth + 0.1, top * 0.55, seatZ), color = Color3.fromRGB(90, 55, 32), material = Enum.Material.Leather },
		{ size = Vector3.new(0.18, top * 0.9, 0.7), offset = Vector3.new(-halfWidth - 0.1, top * 0.55, seatZ), color = Color3.fromRGB(90, 55, 32), material = Enum.Material.Leather },
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
		seatHip = seatHipFor(player),
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

local function step()
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
		local hop = if moving and not airborne then math.abs(math.sin(now * 8 + mount.phase)) * 0.5 else math.sin(now * 2 + mount.phase) * 0.06
		-- The rider goes up and down with the creature: it's the creature that hops, carrying them.
		-- Each client moves its own character (it owns its physics), and everyone sees it.
		if player == LOCAL and seated and seated.character == character then
			humanoid.HipHeight = mount.seatHip + math.max(hop, 0)
		end
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			flat = Vector3.new(0, 0, -1)
		end
		local ahead = flat.Unit * Cosmetics.RIDE_FORWARD
		local center = Vector3.new(root.Position.X + ahead.X, feetY + height / 2 + hop, root.Position.Z + ahead.Z)
		local lean = if moving then CFrame.Angles(math.rad(-8), 0, math.sin(now * 9 + mount.phase) * math.rad(3)) else CFrame.identity
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
				if leg and moving then
					swing = CFrame.Angles(math.sin(now * 14 + mount.phase + leg) * math.rad(32), 0, 0)
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
