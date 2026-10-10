--!strict
-- The Wild (Config/Wild, Logic/Wild, built by WorldService): the guardians sleep by their nests. A player steals
-- an egg; a moment later that biome's guardian wakes and comes after them, inside its biome only (out of it
-- they're safe). If it catches them they drop the egg right there and are sent back to the gate: the egg waits
-- a minute for whoever picks it up (then goes back to its nest). Through the gate, the egg goes into their bag. The nests fill up again every few minutes, some biomes with a golden nest (a Golden Egg,
-- chased harder). On the way back, other players can steal the egg from the one carrying it. Also: speed, trained on the treadmill in each
-- garden (and upgraded at its console), and the HUD's Home and Wild buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RaidConfig = require(Shared.Config.Raid)
local WildConfig = require(Shared.Config.Wild)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Layout = require(Shared.Logic.Layout)
local Wild = require(Shared.Logic.Wild)
local PetModel = require(Shared.PetModel)
local Net = require(Shared.Net)

local DailyService = require(script.Parent.DailyService)
local DataService = require(script.Parent.DataService)
local HeistService = require(script.Parent.HeistService)
local IslandService = require(script.Parent.IslandService)
local RaidService = require(script.Parent.RaidService)

local WildService = {}

type Nest = { egg: BasePart, prompt: ProximityPrompt, full: boolean, golden: boolean, color: Color3, biome: number, index: number }
type Carry = { nest: Nest, part: Part, safe: boolean, golden: boolean, guardUntil: number }
type Drop = { nest: Nest, part: Part, golden: boolean, expires: number }
type Guardian = {
	biome: number,
	home: Vector3,
	position: Vector3,
	wander: Vector3,
	rest: number,
	chasing: Player?,
	text: TextLabel,
	label: string,
	asleep: boolean, -- (lying on its side)
	wakeAt: number, -- (os.clock(): when the chase starts)
	built: PetModel.Built?,
	tag: Part,
}

local nests: { Nest } = {}
local carrying: { [Player]: Carry } = {}
local guardians: { Guardian } = {}
local drops: { [BasePart]: Drop } = {} -- eggs lying where their thief was caught
local rng = Random.new()

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- The player's run speed, as it should be now (slower with an egg; faster on the floating seat, or sprinting:
-- MoveService; RaidService slows a raid thief itself)
local function applySpeed(player: Player)
	local data = DataService.get(player)
	local humanoid = humanoidOf(player)
	if not data or not humanoid or RaidService.isCarrying(player) then
		return
	end
	local seat = player:GetAttribute("RideSeat")
	local free = not HeistService.isCarrier(player)
	local riding = type(seat) == "string" and seat ~= "" and free
	local sprinting = player:GetAttribute("Sprinting") == true and free
	local carry = carrying[player]
	humanoid.WalkSpeed = if carry and not carry.safe then Wild.carrying(data.speed)
		elseif riding then math.min(WildConfig.SEAT_MAX_SPEED, data.speed * WildConfig.SEAT_SPEED)
		elseif sprinting then data.speed * WildConfig.SPRINT
		else data.speed
	player:SetAttribute("Speed", data.speed)
end
WildService.applySpeed = applySpeed

-- Whether the player is carrying an egg (from the Wild, a raid or the Heist)
function WildService.busy(player: Player): boolean
	return carrying[player] ~= nil or RaidService.isCarrying(player) or HeistService.isCarrier(player)
end

-- Whether an egg slows the player down (a Wild egg only until they've got away from its guardian)
function WildService.slowed(player: Player): boolean
	local carry = carrying[player]
	return (carry ~= nil and not carry.safe) or RaidService.isCarrying(player) or HeistService.isCarrier(player)
end

local function busy(player: Player): boolean
	return carrying[player] ~= nil or RaidService.isCarrying(player) or HeistService.isCarrier(player)
end

local function gateSpot(): CFrame
	return CFrame.new(Layout.wildGate() + Vector3.new(rng:NextNumber(-4, 4), 4, 10))
end

---------------------------------------------------------------------------------------------------------------
-- Nests and carrying

local GOLD = Color3.fromRGB(255, 205, 70)
local PEACEFUL = game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0

local function setFull(nest: Nest, full: boolean)
	nest.full = full
	nest.egg.Transparency = if full then 0 else 1
	nest.prompt.Enabled = full
end

-- Makes a nest golden (or plain again): its egg shines, with a label over it
local function setGolden(nest: Nest, golden: boolean)
	nest.golden = golden
	nest.egg.Color = if golden then GOLD else nest.color
	nest.egg.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local label = nest.egg:FindFirstChild("GoldenLabel")
	if golden and not label then
		local gui = Instance.new("BillboardGui")
		gui.Name = "GoldenLabel"
		gui.Size = UDim2.fromScale(8, 1.6)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 250
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextScaled = true
		text.Font = Enum.Font.FredokaOne
		text.TextColor3 = GOLD
		text.TextStrokeTransparency = 0.2
		text.Text = "✨ GOLDEN EGG"
		text.Parent = gui
		gui.Parent = nest.egg
	elseif not golden and label then
		label:Destroy()
	end
	nest.prompt.ObjectText = (if golden then "✨ Golden " else "") .. string.gsub(nest.prompt.ObjectText, "^✨ Golden ", "")
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
		if carry.golden then
			data.golden[key] = (data.golden[key] or 0) + 1
		else
			data.eggs[key] = (data.eggs[key] or 0) + 1
		end
		data.stats.stolen += 1
		DailyService.add(player, "wild")
		IslandService.notify(player, ("You got away with a %s%s! 🥚 Put it in an incubator"):format(if carry.golden then "✨ Golden " else "", if egg then egg.name else "egg"), "success")
		IslandService.push(player)
	else
		setFull(carry.nest, true)
		setGolden(carry.nest, carry.golden)
	end
	applySpeed(player)
end

-- The player now carries this egg
local function hold(player: Player, held: Carry)
	carrying[player] = held
	player:SetAttribute("WildEgg", true) -- (RaidService and HeistService won't let them carry another)
	held.part:SetAttribute("Carrier", player.UserId)
	local prompt = held.part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = "Steal"
		prompt.Enabled = not PEACEFUL -- (no stealing from each other in a Peaceful server)
	end
	applySpeed(player)
end

-- The nearest free guardian of a biome wakes up and, a moment later, comes after the player
local function wake(biome: number, player: Player, from: Vector3)
	local best: Guardian? = nil
	for _, guardian in guardians do
		if guardian.biome == biome and not guardian.chasing then
			if not best or (guardian.position - from).Magnitude < (best.position - from).Magnitude then
				best = guardian
			end
		end
	end
	if best then
		best.chasing = player
		best.wakeAt = os.clock() + WildConfig.WAKE
	end
end

-- A caught thief drops the egg where they are; it waits there for a while
local function drop(player: Player, at: Vector3)
	local held = carrying[player]
	if not held then
		return
	end
	carrying[player] = nil
	player:SetAttribute("WildEgg", nil)
	for _, guardian in guardians do
		if guardian.chasing == player then
			guardian.chasing = nil
		end
	end
	applySpeed(player)
	held.part.Position = Vector3.new(at.X, 1.8, at.Z)
	held.part:SetAttribute("Carrier", 0)
	local prompt = held.part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = "Grab"
		prompt.Enabled = true
	end
	drops[held.part] = { nest = held.nest, part = held.part, golden = held.golden, expires = os.clock() + WildConfig.DROP_TIME }
end

-- Someone picks up a dropped egg: its guardian (if they're still in its biome) wakes again
function WildService.pickUp(player: Player, part: BasePart)
	local dropped = drops[part]
	local root = rootOf(player)
	if not dropped or not root or busy(player) or (root.Position - part.Position).Magnitude > WildConfig.ROB_RANGE + 4 then
		return
	end
	drops[part] = nil
	local safe = Layout.biomeAt(root.Position, #WildConfig.BIOMES) ~= dropped.nest.biome
	hold(player, { nest = dropped.nest, part = dropped.part, safe = safe, golden = dropped.golden, guardUntil = os.clock() + WildConfig.ROB_GUARD })
	if not safe then
		wake(dropped.nest.biome, player, root.Position)
		IslandService.notify(player, "🥚 Got it back! Run before the guardian wakes up!", "success")
	else
		IslandService.notify(player, "🥚 Got it! Take it through the gate", "success")
	end
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
	local golden = nest.golden
	setFull(nest, false)
	setGolden(nest, false)
	local part = Instance.new("Part")
	part.Name = "CarriedEgg"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2.6, 2.6, 2.6)
	part.Color = if golden then GOLD else nest.color
	part.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = part
	part.Position = root.Position + Vector3.new(0, 5, 0)
	part.Parent = workspace
	part:AddTag("WildCarry")
	-- Others can steal it on the way back, or grab it where it's dropped
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Steal"
	prompt.ObjectText = (if golden then "✨ Golden " else "") .. (Hatch.egg(WildConfig.BIOMES[nest.biome].tier) or { name = "Egg" }).name
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = WildConfig.ROB_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(taker)
		if drops[part] then
			WildService.pickUp(taker, part)
		else
			WildService.rob(taker, part)
		end
	end)
	hold(player, { nest = nest, part = part, safe = false, golden = golden, guardUntil = os.clock() + WildConfig.ROB_GUARD })
	local biome = WildConfig.BIOMES[nest.biome]
	if Wild.outruns(data.speed, biome) then
		IslandService.notify(player, ("Got it! Run out of the %s before its guardian wakes up! 🏃"):format(biome.name), "success")
	else
		IslandService.notify(player, ("Got it! But its guardian is faster than you (⚡ %d needed). Run!"):format(Wild.needs(biome)), "info")
	end
	wake(nest.biome, player, root.Position)
end

-- Another player takes a Wild egg from the one carrying it (their guardian, if still after it, now chases
-- the robber)
function WildService.rob(robber: Player, part: BasePart)
	local victim: Player? = nil
	for player, carry in carrying do
		if carry.part == part then
			victim = player
		end
	end
	local carry = if victim then carrying[victim] else nil
	local root, victimRoot = rootOf(robber), if victim then rootOf(victim) else nil
	local robberData = DataService.get(robber)
	if not victim or not carry or victim == robber or not root or not victimRoot or not robberData or busy(robber) then
		return
	end
	if os.clock() < carry.guardUntil or (root.Position - victimRoot.Position).Magnitude > WildConfig.ROB_RANGE + 4 then
		return
	end
	local victimData = DataService.get(victim)
	if victimData and os.time() - victimData.firstPlayed < RaidConfig.NEW_PLAYER_SAFE then
		IslandService.notify(robber, ("%s is new here: leave their egg be"):format(victim.DisplayName), "error")
		return
	end
	carrying[victim] = nil
	victim:SetAttribute("WildEgg", nil)
	applySpeed(victim)
	carry.safe = Layout.biomeAt(root.Position, #WildConfig.BIOMES) ~= carry.nest.biome
	carry.guardUntil = os.clock() + WildConfig.ROB_GUARD
	hold(robber, carry)
	for _, guardian in guardians do
		if guardian.chasing == victim then
			guardian.chasing = robber
		end
	end
	IslandService.notify(robber, "🥚 You stole it! Run to the gate!", "success")
	IslandService.notify(victim, ("😱 %s stole your egg! Get it back!"):format(robber.DisplayName), "error")
end

-- Every nest gets its egg back (not the ones being carried)
local function refill()
	local carried: { [Nest]: boolean } = {}
	for _, carry in carrying do
		carried[carry.nest] = true
	end
	for _, dropped in drops do
		carried[dropped.nest] = true
	end
	for _, nest in nests do
		if not carried[nest] then
			setFull(nest, true)
			setGolden(nest, false)
		end
	end
	-- Some biomes get a golden nest
	local goldenIn = {}
	for i, biome in WildConfig.BIOMES do
		if rng:NextNumber() < WildConfig.GOLDEN_CHANCE then
			local free = {}
			for _, nest in nests do
				if nest.biome == i and not carried[nest] then
					table.insert(free, nest)
				end
			end
			if #free > 0 then
				setGolden(free[rng:NextInteger(1, #free)], true)
				table.insert(goldenIn, biome.name)
			end
		end
	end
	for _, player in Players:GetPlayers() do
		IslandService.notify(player, "🌿 The Wild's nests are full of eggs again!", "info")
		if #goldenIn > 0 then
			IslandService.notify(player, ("✨ Golden Eggs in: %s!"):format(table.concat(goldenIn, ", ")), "rare")
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Guardians

local function place(guardian: Guardian, toward: Vector3)
	local built = guardian.built
	local facing = if (toward - guardian.position).Magnitude > 0.1 then Layout.facing(guardian.position, toward) else CFrame.new(guardian.position)
	if built and guardian.asleep then
		-- On its side: rolled over, its middle as high as half its width
		PetModel.place(built, CFrame.new(guardian.position + Vector3.new(0, built.radius, 0)) * facing.Rotation * CFrame.Angles(0, 0, math.rad(90)))
	elseif built then
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
			local home = Layout.biome(i) + Vector3.new(if WildConfig.GUARDIANS == 1 then 0 elseif g % 2 == 1 then -10 else 10, 0, 0)
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
			local label = ("%s · ⚡ %d needed"):format(biome.name, Wild.needs(biome))
			text.Text = "💤 " .. label
			text.Parent = gui
			gui.Parent = tag
			tag.Parent = folder
			local guardian: Guardian = { biome = i, home = home, position = home, wander = home, rest = 0, chasing = nil, text = text, label = label, asleep = true, wakeAt = 0, built = nil, tag = tag }
			table.insert(guardians, guardian)
			draw(guardian)
		end
	end
end

-- Ten times a second: guardians wander near home, chase the thief of their biome's egg (while they're still in
-- the biome), and catch them; thieves carry their egg, and keep it once through the gate
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
		if not player.Parent or not root or not humanoid then
			finish(player, false)
			continue
		elseif humanoid.Health <= 0 then
			drop(player, root.Position)
			continue
		end
		carry.part.Position = root.Position + Vector3.new(0, 5, 0)
		if Layout.pastGate(root.Position) then
			finish(player, true)
		elseif not carry.safe and Layout.biomeAt(root.Position, #WildConfig.BIOMES) ~= carry.nest.biome then
			carry.safe = true
			applySpeed(player)
			IslandService.notify(player, "😮‍💨 You got away! Take the egg back through the gate", "success")
		end
	end
	-- Dropped eggs nobody came for go back to their nest
	for part, dropped in drops do
		if os.clock() >= dropped.expires then
			drops[part] = nil
			part:Destroy()
			setFull(dropped.nest, true)
			setGolden(dropped.nest, dropped.golden)
		end
	end
	for _, guardian in guardians do
		local biome = WildConfig.BIOMES[guardian.biome]
		local target: Vector3
		local speed = biome.guardian
		local thief = guardian.chasing
		local carry = if thief then carrying[thief] else nil
		if carry and carry.golden then
			speed *= WildConfig.GOLDEN_GUARDIAN
		end
		local root = if thief and carry and not carry.safe then rootOf(thief) else nil
		if thief and root and os.clock() < guardian.wakeAt then
			guardian.text.Text = "❗ " .. guardian.label
			if guardian.asleep then
				guardian.asleep = false -- (gets up)
				place(guardian, root.Position)
			end
			continue -- (waking up: the thief's head start)
		elseif thief and root then
			guardian.asleep = false
			guardian.text.Text = "😡 " .. guardian.label
			target = Vector3.new(root.Position.X, 0, root.Position.Z)
			if (target - guardian.position).Magnitude <= WildConfig.CATCH_RANGE then
				IslandService.notify(thief, "🐾 The guardian caught you! You dropped the egg: go back for it before someone else takes it", "error")
				drop(thief, root.Position)
				root.CFrame = gateSpot()
				root.AssemblyLinearVelocity = Vector3.zero
				continue
			end
		else
			-- Back home to sleep
			guardian.chasing = nil
			speed = 8
			target = guardian.home
			if (guardian.home - guardian.position).Magnitude < 0.5 then
				guardian.text.Text = "💤 " .. guardian.label
				if not guardian.asleep then
					guardian.asleep = true -- (lies down)
					place(guardian, guardian.position + Vector3.new(0, 0, 1))
				end
				continue
			end
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
				local nest: Nest = { egg = egg, prompt = prompt, full = true, golden = false, color = egg.Color, biome = biome, index = index }
				table.insert(nests, nest)
				prompt.Triggered:Connect(function(player)
					steal(player, nest)
				end)
			end
		end
	end
	spawnGuardians()
	refill() -- (the first golden nests)
	Net.event("Travel").OnServerEvent:Connect(travel)
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, player)
		local index = prompt:GetAttribute("Treadmill")
		if type(index) == "number" then
			upgradeTreadmill(player, index)
		end
	end)
	DataService.onLoaded(function(player, data)
		data.speed = math.max(data.speed, WildConfig.START_SPEED) -- (saves from when players started slower)
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
