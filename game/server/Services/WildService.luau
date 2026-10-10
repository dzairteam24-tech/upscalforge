--!strict
-- The Wild (Config/Wild, Logic/Wild, built by WorldService): a player steals an egg from a nest and runs back
-- through the gate with it; the biome's guardians chase them (and any guardian they run past), and if one
-- catches them the egg goes back to its nest and they're sent back to the gate. Through the gate, the egg goes
-- into their bag. The nests fill up again every few minutes. Also: speed, trained on the treadmill in each
-- garden (and upgraded at its console), and the HUD's Home and Wild buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WildConfig = require(Shared.Config.Wild)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Layout = require(Shared.Logic.Layout)
local Wild = require(Shared.Logic.Wild)
local PetModel = require(Shared.PetModel)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local HeistService = require(script.Parent.HeistService)
local IslandService = require(script.Parent.IslandService)
local RaidService = require(script.Parent.RaidService)

local WildService = {}

type Nest = { egg: BasePart, prompt: ProximityPrompt, full: boolean, biome: number, index: number }
type Carry = { nest: Nest, part: Part }
type Guardian = {
	biome: number,
	home: Vector3,
	position: Vector3,
	wander: Vector3,
	rest: number,
	chasing: Player?,
	built: PetModel.Built?,
	tag: Part,
}

local nests: { Nest } = {}
local carrying: { [Player]: Carry } = {}
local guardians: { Guardian } = {}
local rng = Random.new()

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- The player's run speed, as it should be now (slower with an egg; RaidService slows a raid thief itself)
local function applySpeed(player: Player)
	local data = DataService.get(player)
	local humanoid = humanoidOf(player)
	if not data or not humanoid or RaidService.isCarrying(player) then
		return
	end
	humanoid.WalkSpeed = if carrying[player] then Wild.carrying(data.speed) else data.speed
	player:SetAttribute("Speed", data.speed)
end

local function busy(player: Player): boolean
	return carrying[player] ~= nil or RaidService.isCarrying(player) or HeistService.isCarrier(player)
end

local function gateSpot(): CFrame
	return CFrame.new(Layout.wildGate() + Vector3.new(rng:NextNumber(-4, 4), 4, 10))
end

---------------------------------------------------------------------------------------------------------------
-- Nests and carrying

local function setFull(nest: Nest, full: boolean)
	nest.full = full
	nest.egg.Transparency = if full then 0 else 1
	nest.prompt.Enabled = full
end

-- Ends a carry: the egg goes into the thief's bag (`kept`) or back to its nest
local function finish(player: Player, kept: boolean)
	local carry = carrying[player]
	if not carry then
		return
	end
	carrying[player] = nil
	player:SetAttribute("WildEgg", nil)
	carry.part:Destroy()
	for _, guardian in guardians do
		if guardian.chasing == player then
			guardian.chasing = nil
		end
	end
	local biome = WildConfig.BIOMES[carry.nest.biome]
	local egg = Hatch.egg(biome.tier)
	local data = DataService.get(player)
	if kept and data then
		local key = tostring(biome.tier)
		data.eggs[key] = (data.eggs[key] or 0) + 1
		data.stats.stolen += 1
		IslandService.notify(player, ("You got away with a %s! 🥚 Put it in an incubator"):format(if egg then egg.name else "egg"), "success")
		IslandService.push(player)
	else
		setFull(carry.nest, true)
	end
	applySpeed(player)
end

local function steal(player: Player, nest: Nest)
	local root = rootOf(player)
	local data = DataService.get(player)
	if not nest.full or not root or not data or busy(player) then
		return
	end
	if (root.Position - nest.egg.Position).Magnitude > 14 then
		return
	end
	setFull(nest, false)
	local part = Instance.new("Part")
	part.Name = "CarriedEgg"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2.6, 2.6, 2.6)
	part.Color = nest.egg.Color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = part
	part.Position = root.Position + Vector3.new(0, 5, 0)
	part.Parent = workspace
	carrying[player] = { nest = nest, part = part }
	player:SetAttribute("WildEgg", true) -- (RaidService and HeistService won't let them carry another)
	applySpeed(player)
	local biome = WildConfig.BIOMES[nest.biome]
	if Wild.outruns(data.speed, biome) then
		IslandService.notify(player, "Got it! Run back through the gate! 🏃", "success")
	else
		IslandService.notify(player, ("Got it! But the guardians here are fast: ⚡ %d to outrun them. Run!"):format(Wild.needs(biome)), "info")
	end
	-- The nearest free guardian of the biome comes after them
	local best: Guardian? = nil
	for _, guardian in guardians do
		if guardian.biome == nest.biome and not guardian.chasing then
			if not best or (guardian.position - root.Position).Magnitude < (best.position - root.Position).Magnitude then
				best = guardian
			end
		end
	end
	if best then
		best.chasing = player
	end
end

-- Every nest gets its egg back (not the ones being carried)
local function refill()
	local carried: { [Nest]: boolean } = {}
	for _, carry in carrying do
		carried[carry.nest] = true
	end
	for _, nest in nests do
		if not carried[nest] then
			setFull(nest, true)
		end
	end
	for _, player in Players:GetPlayers() do
		IslandService.notify(player, "🌿 The Wild's nests are full of eggs again!", "info")
	end
end

---------------------------------------------------------------------------------------------------------------
-- Guardians

local function place(guardian: Guardian, toward: Vector3)
	local built = guardian.built
	local facing = if (toward - guardian.position).Magnitude > 0.1 then Layout.facing(guardian.position, toward) else CFrame.new(guardian.position)
	if built then
		PetModel.place(built, facing * CFrame.new(0, built.height / 2, 0))
	end
	guardian.tag.CFrame = CFrame.new(guardian.position + Vector3.new(0, 2, 0))
end

local function draw(guardian: Guardian)
	if guardian.built then
		guardian.built.model:Destroy()
	end
	local world = workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild("Wild") and (world :: any).Wild:FindFirstChild("Guardians")
	if not folder then
		return
	end
	local biome = WildConfig.BIOMES[guardian.biome]
	local egg = Hatch.egg(biome.tier)
	local species = if egg then egg.creatures[#egg.creatures] else "Bear"
	local built = PetModel.build({ s = species, v = "Normal", z = "Big" })
	for _, p in built.parts do
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
	end
	built.model.Name = "Guardian"
	built.model.Parent = folder
	guardian.built = built
	place(guardian, guardian.position + Vector3.new(0, 0, 1))
end

local function spawnGuardians()
	local world = workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild("Wild") and (world :: any).Wild:FindFirstChild("Guardians")
	for i, biome in WildConfig.BIOMES do
		for g = 1, WildConfig.GUARDIANS do
			local home = Layout.biome(i) + Vector3.new(if g % 2 == 1 then -10 else 10, 0, 0)
			local tag = Instance.new("Part")
			tag.Name = "GuardianTag"
			tag.Size = Vector3.one
			tag.Transparency = 1
			tag.Anchored = true
			tag.CanCollide = false
			tag.CanQuery = false
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromScale(8, 1.6)
			gui.StudsOffset = Vector3.new(0, 7, 0)
			gui.MaxDistance = 90
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.TextScaled = true
			text.Font = Enum.Font.FredokaOne
			text.TextColor3 = Color3.fromRGB(255, 120, 110)
			text.TextStrokeTransparency = 0.3
			text.Text = ("🐾 Guardian · ⚡ %d"):format(biome.guardian)
			text.Parent = gui
			gui.Parent = tag
			tag.Parent = folder
			local guardian: Guardian = { biome = i, home = home, position = home, wander = home, rest = 0, chasing = nil, built = nil, tag = tag }
			table.insert(guardians, guardian)
			draw(guardian)
		end
	end
end

-- Ten times a second: guardians wander near home, chase thieves (their own biome's, or any carrying an egg
-- past them), and catch them; thieves carry their egg, and keep it once through the gate
local STEP = 0.1
local pending = 0
local function tick(frame: number)
	pending += frame
	if pending < STEP then
		return
	end
	local dt = pending
	pending = 0
	for player, carry in carrying do
		local root = rootOf(player)
		local humanoid = humanoidOf(player)
		if not player.Parent or not root or not humanoid or humanoid.Health <= 0 then
			finish(player, false)
			continue
		end
		carry.part.Position = root.Position + Vector3.new(0, 5, 0)
		if Layout.pastGate(root.Position) then
			finish(player, true)
		end
	end
	for _, guardian in guardians do
		local biome = WildConfig.BIOMES[guardian.biome]
		-- A thief running past
		if not guardian.chasing then
			for player in carrying do
				local root = rootOf(player)
				if root and (root.Position - guardian.position).Magnitude <= WildConfig.SEE_RANGE then
					guardian.chasing = player
					break
				end
			end
		end
		local target: Vector3
		local speed = biome.guardian
		local thief = guardian.chasing
		local root = if thief and carrying[thief] then rootOf(thief) else nil
		if thief and root then
			target = Vector3.new(root.Position.X, 0, root.Position.Z)
			if (target - guardian.position).Magnitude <= WildConfig.CATCH_RANGE then
				IslandService.notify(thief, "🐾 A guardian caught you! The egg went back to its nest", "error")
				finish(thief, false)
				root.CFrame = gateSpot()
				root.AssemblyLinearVelocity = Vector3.zero
				continue
			end
			-- (it gives up at the gate)
			if Layout.pastGate(target) then
				guardian.chasing = nil
			end
		else
			guardian.chasing = nil
			speed = 6
			if (guardian.wander - guardian.position).Magnitude < 0.5 then
				guardian.rest -= dt
				if guardian.rest <= 0 then
					guardian.wander = guardian.home + Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-12, 12))
					guardian.rest = rng:NextNumber(1, 4)
				end
				continue
			end
			target = guardian.wander
		end
		local offset = target - guardian.position
		if offset.Magnitude > 0.05 then
			guardian.position += offset.Unit * math.min(offset.Magnitude, speed * dt)
			place(guardian, target)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Speed and the treadmill

local function upgradeTreadmill(player: Player, index: number)
	local data = DataService.get(player)
	if not data or IslandService.islandOf(player) ~= index then
		IslandService.notify(player, "That's not your treadmill", "error")
		return
	end
	local price = WildConfig.TREADMILL_PRICES[data.treadmill]
	if not price then
		IslandService.notify(player, "Your treadmill is as good as it gets", "error")
		return
	end
	if data.coins < price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
		return
	end
	data.coins -= price
	data.treadmill += 1
	player:SetAttribute("Treadmill", data.treadmill)
	IslandService.notify(player, ("Treadmill level %d! You train faster 🏃"):format(data.treadmill), "success")
	IslandService.push(player)
end

-- Once a second: whoever is walking on their own treadmill gets faster
local function train()
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		local index = IslandService.islandOf(player)
		local root = rootOf(player)
		local humanoid = humanoidOf(player)
		if not data or not index or not root or not humanoid or humanoid.MoveDirection.Magnitude < 0.3 then
			continue
		end
		local inside = Layout.garden(index):PointToObjectSpace(root.Position) - Layout.TREADMILL
		if math.abs(inside.X) <= 5 and math.abs(inside.Z) <= 2.5 and inside.Y < 8 then
			data.speed = Wild.train(data.speed, data.treadmill, 1)
			applySpeed(player)
		end
	end
end

local function travel(player: Player, where: any)
	local root = rootOf(player)
	if not root then
		return
	end
	if busy(player) then
		IslandService.notify(player, "Not while you're carrying an egg: run!", "error")
		return
	end
	if where == "home" then
		IslandService.sendHome(player)
	elseif where == "wild" then
		root.CFrame = gateSpot()
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- When the creature models arrive, the guardians are drawn again with them
function WildService.redraw()
	for _, guardian in guardians do
		draw(guardian)
	end
end

function WildService.init()
	local world = workspace:FindFirstChild("World")
	local wild = world and world:FindFirstChild("Wild")
	if wild then
		for _, egg in wild:GetChildren() do
			local biome, index = egg:GetAttribute("Biome"), egg:GetAttribute("Nest")
			local prompt = egg:FindFirstChildOfClass("ProximityPrompt")
			if egg:IsA("BasePart") and type(biome) == "number" and type(index) == "number" and prompt then
				local nest: Nest = { egg = egg, prompt = prompt, full = true, biome = biome, index = index }
				table.insert(nests, nest)
				prompt.Triggered:Connect(function(player)
					steal(player, nest)
				end)
			end
		end
	end
	spawnGuardians()
	Net.event("Travel").OnServerEvent:Connect(travel)
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, player)
		local index = prompt:GetAttribute("Treadmill")
		if type(index) == "number" then
			upgradeTreadmill(player, index)
		end
	end)
	DataService.onLoaded(function(player, data)
		player:SetAttribute("Speed", data.speed)
		player:SetAttribute("Treadmill", data.treadmill)
		applySpeed(player)
	end)
	local function onCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			applySpeed(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		onCharacter(player)
	end
	Players.PlayerAdded:Connect(onCharacter)
	Players.PlayerRemoving:Connect(function(player)
		finish(player, false)
	end)
	RunService.Heartbeat:Connect(tick)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			train()
			if os.clock() - last >= WildConfig.RESET then
				last = os.clock()
				refill()
			end
		end
	end)
end

return WildService
