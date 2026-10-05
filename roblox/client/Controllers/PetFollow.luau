-- Draws every player's team and moves it: following behind the player, or hopping around the target source.
-- Runs on each client so the server never has to move creature models. Low-end mode hides other players' teams.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetModel = require(Shared.PetModel)

local Store = require(script.Parent.Parent.Store)

local PetFollow = {}

type Entry = {
	built: PetModel.Built,
	pet: { s: string, v: string, z: string },
	current: CFrame,
	phase: number,
	eyes: { { part: BasePart, size: Vector3 } }, -- for blinking
	nextBlink: number,
	lastHop: number, -- hop height last frame (to squash on landing)
	squash: number, -- 0..1, fades out after a landing
}

-- Eye parts of a built creature (block or 3D version), with their normal size
local function findEyes(built: PetModel.Built): { { part: BasePart, size: Vector3 } }
	local eyes = {}
	for _, p in built.parts do
		local name = string.lower(p.Name)
		if name == "eye" or name == "shine" then
			table.insert(eyes, { part = p, size = p.Size })
		end
	end
	return eyes
end

type Owner = {
	player: Player,
	entries: { [string]: Entry },
	order: { string },
}

local owners: { [number]: Owner } = {}
local container = Instance.new("Folder")
container.Name = "Pets"
local LOCAL = Players.LocalPlayer
local othersHidden = false

local function hidden(owner: Owner): boolean
	return othersHidden and owner.player ~= LOCAL
end

-- "species|variant|size|sticker" (the sticker part may be empty)
local function parse(value: string): { s: string, v: string, z: string, st: string? }?
	local s, v, z, st = string.match(value, "^([^|]+)|([^|]+)|([^|]+)|?([^|]*)$")
	if not s then
		return nil
	end
	return { s = s :: string, v = v :: string, z = z :: string, st = if st and st ~= "" then st else nil }
end

local function rebuildOrder(owner: Owner)
	local ids = {}
	for petId in owner.entries do
		table.insert(ids, petId)
	end
	-- Big creatures first so they get the front spots
	table.sort(ids, function(a, b)
		local ra, rb = owner.entries[a].built.radius, owner.entries[b].built.radius
		if ra ~= rb then
			return ra > rb
		end
		return a < b
	end)
	owner.order = ids
end

local function startPosition(player: Player): CFrame
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.CFrame else CFrame.new()
end

local function addPet(owner: Owner, value: StringValue)
	local pet = parse(value.Value)
	if not pet then
		return
	end
	local built = PetModel.build(pet)
	built.model.Parent = if hidden(owner) then nil else container
	local entry: Entry = {
		built = built,
		pet = pet,
		current = startPosition(owner.player),
		phase = math.random() * math.pi * 2,
		eyes = findEyes(built),
		nextBlink = os.clock() + 1 + math.random() * 4,
		lastHop = 0,
		squash = 0,
	}
	PetModel.place(built, entry.current)
	owner.entries[value.Name] = entry
	rebuildOrder(owner)
end

local function removePet(owner: Owner, petId: string)
	local entry = owner.entries[petId]
	if entry then
		entry.built.model:Destroy()
		owner.entries[petId] = nil
		rebuildOrder(owner)
	end
end

local function watchFolder(folder: Instance)
	local userId = tonumber(folder.Name)
	local player = userId and Players:GetPlayerByUserId(userId)
	if not userId or not player then
		return
	end
	local owner: Owner = { player = player, entries = {}, order = {} }
	owners[userId] = owner
	local function onChild(child: Instance)
		if child:IsA("StringValue") then
			addPet(owner, child)
			child:GetPropertyChangedSignal("Value"):Connect(function()
				removePet(owner, child.Name)
				addPet(owner, child)
			end)
		end
	end
	for _, child in folder:GetChildren() do
		onChild(child)
	end
	folder.ChildAdded:Connect(onChild)
	folder.ChildRemoved:Connect(function(child)
		removePet(owner, child.Name)
	end)
	folder.AncestryChanged:Connect(function(_, parent)
		if not parent then
			for petId in owner.entries do
				removePet(owner, petId)
			end
			owners[userId] = nil
		end
	end)
end

local function groundY(position: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position.Y else position.Y - 3
end

local frame = 0

local function applyLowEnd()
	local hide = Store.lowEnd()
	if hide == othersHidden then
		return
	end
	othersHidden = hide
	for _, owner in owners do
		if owner.player ~= LOCAL then
			for _, entry in owner.entries do
				entry.built.model.Parent = if hide then nil else container
			end
		end
	end
end

local function step(dt: number)
	frame += 1
	applyLowEnd()
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local now = os.clock()
	local alpha = 1 - math.exp(-dt * 8)
	local breakables = workspace:FindFirstChild("Breakables")

	for _, owner in owners do
		if hidden(owner) then
			continue
		end
		local character = owner.player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not character then
			continue
		end
		local targetName = owner.player:GetAttribute("Target")
		local target = if type(targetName) == "string" and targetName ~= "" and breakables
			then breakables:FindFirstChild(targetName) :: BasePart?
			else nil
		local baseY = groundY(root.Position, { character, container })
		local count = #owner.order

		for index, petId in owner.order do
			local entry = owner.entries[petId]
			local built = entry.built
			local goal: CFrame
			local hop = 0
			if target then
				-- Circle around the source and hop while collecting
				local angle = (index / math.max(count, 1)) * math.pi * 2
				local radius = math.max(target.Size.X, target.Size.Z) / 2 + built.radius + 1.5
				local center = target.Position
				local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				local y = center.Y - target.Size.Y / 2 + built.height / 2
				hop = math.abs(math.sin(now * 8 + entry.phase)) * built.height * 0.35
				goal = CFrame.lookAt(Vector3.new(pos.X, y + hop, pos.Z), Vector3.new(center.X, y + hop, center.Z))
			else
				-- Rows of 4 behind the player
				local row = (index - 1) // 4
				local col = (index - 1) % 4
				local spacing = 4 + built.radius
				local offset = Vector3.new((col - 1.5) * spacing, 0, 6 + row * spacing)
				local pos = (root.CFrame * CFrame.new(offset)).Position
				local moving = root.AssemblyLinearVelocity.Magnitude > 2
				hop = if moving then math.abs(math.sin(now * 10 + entry.phase)) * 0.8 else math.sin(now * 2 + entry.phase) * 0.15
				local y = baseY + built.height / 2 + hop
				local look = root.CFrame.LookVector
				goal = CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(pos.X + look.X, y, pos.Z + look.Z))
			end
			entry.current = entry.current:Lerp(goal, alpha)

			-- Life: squash when landing a hop, lean into the movement, blink now and then
			if entry.lastHop > 0.25 and hop < 0.08 then
				entry.squash = 1
			end
			entry.lastHop = hop
			entry.squash = math.max(0, entry.squash - dt * 6)
			local squash = math.sin(entry.squash * math.pi) * 0.12
			local stretch = if hop > 0.1 then 0.05 else 0
			local sy = 1 - squash + stretch
			local sxz = 1 + squash * 0.6 - stretch * 0.5
			local moving = not target and root.AssemblyLinearVelocity.Magnitude > 2
			local lean = if moving then CFrame.Angles(math.rad(-10), 0, math.sin(now * 10 + entry.phase) * math.rad(4)) else CFrame.identity
			local visual = entry.current * lean
			local scale = Vector3.new(sxz, sy, sxz)
			for i, p in built.parts do
				local offset = built.offsets[i]
				table.insert(parts, p)
				table.insert(cframes, visual * CFrame.new(offset.Position * scale) * offset.Rotation)
			end
			if now >= entry.nextBlink and #entry.eyes > 0 then
				entry.nextBlink = now + 2.5 + math.random() * 3.5
				for _, eye in entry.eyes do
					eye.part.Size = Vector3.new(eye.size.X, eye.size.Y * 0.12, eye.size.Z)
				end
				local eyes = entry.eyes
				task.delay(0.13, function()
					for _, eye in eyes do
						if eye.part.Parent then
							eye.part.Size = eye.size
						end
					end
				end)
			end
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- The 3D models can arrive after the first creatures were drawn (they load from Roblox at server start):
-- then every creature is rebuilt with its model.
local function rebuildAll()
	PetModel.reset()
	for _, owner in owners do
		for _, entry in owner.entries do
			local parent = entry.built.model.Parent
			entry.built.model:Destroy()
			entry.built = PetModel.build(entry.pet)
			entry.built.model.Parent = parent
			entry.eyes = findEyes(entry.built)
			PetModel.place(entry.built, entry.current)
		end
		rebuildOrder(owner)
	end
end

function PetFollow.init()
	container.Parent = workspace
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "CreatureModels" then
			task.wait(0.5) -- let the whole folder replicate
			rebuildAll()
		end
	end)
	local display = ReplicatedStorage:WaitForChild("PetDisplay")
	for _, folder in display:GetChildren() do
		task.spawn(watchFolder, folder)
	end
	display.ChildAdded:Connect(function(folder)
		task.spawn(watchFolder, folder)
	end)
	RunService.RenderStepped:Connect(step)
end

return PetFollow
