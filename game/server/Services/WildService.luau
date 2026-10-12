--!strict
-- The Wild (Config/Wild, Logic/Wild, built by WorldService): the guardians sleep by their nests. A player steals
-- an egg; a moment later that biome's guardian wakes and comes after them, inside its biome only (out of it
-- they're safe). If it catches them they drop the egg right there and are sent back to the gate: the egg waits
-- a minute for whoever picks it up (then goes back to its nest). Once they carry it into their own garden the egg goes into their bag. A nest gets a new egg a little after its egg is taken (its size, and now and then gold, by luck: a Golden Egg is
-- chased harder). Also: speed, trained on the treadmill in each
-- garden (and upgraded at its console).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trails = require(Shared.Config.Trails)
local WildConfig = require(Shared.Config.Wild)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Layout = require(Shared.Logic.Layout)
local Wild = require(Shared.Logic.Wild)
local Carry = require(Shared.Carry)
local PetModel = require(Shared.PetModel)
local SleepPose = require(Shared.SleepPose)
local EggModel = require(Shared.EggModel)
local Net = require(Shared.Net)

local DailyService = require(script.Parent.DailyService)
local DataService = require(script.Parent.DataService)
local HeistService = require(script.Parent.HeistService)
local IslandService = require(script.Parent.IslandService)

local WildService = {}

-- (size: its egg's, rolled at each refill, Config/EggSizes; ground: where the egg rests, under its middle)
-- (respawnAt: os.clock() when it gets a new egg, once its egg is taken)
type Nest = { egg: BasePart, prompt: ProximityPrompt, full: boolean, golden: boolean, size: string, ground: Vector3, color: Color3, biome: number, index: number, respawnAt: number? }
type Carry = { nest: Nest, part: Part, safe: boolean, golden: boolean, size: string }
type Drop = { nest: Nest, part: Part, golden: boolean, size: string, expires: number }
type Guardian = {
	biome: number,
	home: Vector3,
	position: Vector3,
	wander: Vector3,
	rest: number,
	chasing: Player?,
	text: TextLabel,
	label: string,
	asleep: boolean, -- (in its sleeping pose, Shared/SleepPose)
	pose: string, -- (how it sleeps: its creature's, Config/Wild SLEEP_POSES)
	sizes: { Vector3 }, -- (its parts' sizes awake: a pose may squash them)
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

-- The player's run speed, as it should be now (slower with an egg; faster sprinting:
-- MoveService)
local function applySpeed(player: Player)
	local data = DataService.get(player)
	local humanoid = humanoidOf(player)
	if not data or not humanoid then
		return
	end
	local free = not HeistService.isCarrier(player)
	local sprinting = player:GetAttribute("Sprinting") == true and free
	local carry = carrying[player]
	local walk = Wild.walk(data.power)
	humanoid.WalkSpeed = if carry and not carry.safe then Wild.carrying(data.power) * Hatch.size(carry.size).carry -- (a heavy egg slows them)
		elseif sprinting then math.max(walk, math.min(WildConfig.MAX_SPEED, walk * WildConfig.SPRINT))
		else walk
	player:SetAttribute("Speed", data.power)
end
WildService.applySpeed = applySpeed

-- Whether the player is carrying an egg (from the Wild or the Heist)
function WildService.busy(player: Player): boolean
	return carrying[player] ~= nil or HeistService.isCarrier(player)
end

-- Whether an egg slows the player down (a Wild egg only until they've got away from its guardian)
function WildService.slowed(player: Player): boolean
	local carry = carrying[player]
	return (carry ~= nil and not carry.safe) or HeistService.isCarrier(player)
end

local function busy(player: Player): boolean
	return carrying[player] ~= nil or HeistService.isCarrier(player)
end

local function gateSpot(): CFrame
	return CFrame.new(Layout.wildGate() + Vector3.new(rng:NextNumber(-4, 4), 4, 10))
end

---------------------------------------------------------------------------------------------------------------
-- Nests and carrying

local GOLD = Color3.fromRGB(255, 205, 70)

local function setFull(nest: Nest, full: boolean)
	nest.full = full
	EggModel.setVisible(nest.egg, full)
	nest.prompt.Enabled = full
end

-- Dresses a nest's egg for its gold and size: its color, how big it is, and a label over it (golden, big, huge)
local function dress(nest: Nest)
	local egg = nest.egg
	local size = Hatch.size(nest.size)
	egg.Color = if nest.golden then GOLD else nest.color
	egg.Material = if nest.golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
	egg.Size = Vector3.one * 3.2 * size.scale
	egg.Position = nest.ground + Vector3.new(0, 0.7 + egg.Size.Y * 0.65, 0) -- (sitting in its nest: it's drawn 1.3 tall)
	EggModel.dress(egg, nest.color, nest.golden) -- (its layers redrawn for its size and gold)
	local text = if not nest.full then "" else (if nest.golden then "✨ GOLDEN " else "") .. (if nest.size == "Huge" then "⭐ HUGE ⚖️" elseif nest.size == "Big" then "BIG ⚖️" else "")
	local label = egg:FindFirstChild("EggLabel")
	if text ~= "" and not label then
		local gui = Instance.new("BillboardGui")
		gui.Name = "EggLabel"
		gui.Size = UDim2.fromScale(8, 1.6)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 250
		local textLabel = Instance.new("TextLabel")
		textLabel.Size = UDim2.fromScale(1, 1)
		textLabel.BackgroundTransparency = 1
		textLabel.TextScaled = true
		textLabel.Font = Enum.Font.LuckiestGuy
		textLabel.TextStrokeColor3 = Color3.fromRGB(28, 24, 40)
		textLabel.TextStrokeTransparency = 0
		textLabel.Parent = gui
		gui.Parent = egg
		label = gui
	elseif text == "" and label then
		label:Destroy()
		label = nil
	end
	if label then
		local textLabel = label:FindFirstChildOfClass("TextLabel") :: TextLabel
		textLabel.Text = text
		textLabel.TextColor3 = if nest.golden then GOLD elseif nest.size == "Huge" then Color3.fromRGB(255, 120, 230) else Color3.fromRGB(255, 255, 255)
	end
	nest.prompt.ObjectText = Hatch.name(WildConfig.BIOMES[nest.biome].tier, nest.size, nest.golden)
end

-- Makes a nest golden (or plain again)
local function setGolden(nest: Nest, golden: boolean)
	nest.golden = golden
	dress(nest)
end

-- Gives a nest's egg a size (Config/EggSizes)
local function setSize(nest: Nest, size: string)
	nest.size = size
	dress(nest)
end

-- Ends a carry: the egg goes into the thief's bag (`kept`) or back to its nest
local function finish(player: Player, kept: boolean)
	local carry = carrying[player]
	if not carry then
		return
	end
	carrying[player] = nil
	player:SetAttribute("WildEgg", nil)
	player:SetAttribute("Holding", nil)
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
		local key = Hatch.key(biome.tier, carry.size)
		if carry.golden then
			data.golden[key] = (data.golden[key] or 0) + 1
		else
			data.eggs[key] = (data.eggs[key] or 0) + 1
		end
		data.stats.stolen += 1
		DailyService.add(player, "wild")
		IslandService.banner(player, "🏠 HOME SAFE!", Color3.fromRGB(120, 230, 120))
		IslandService.notify(player, ("Home with a %s! 🥚 Click to set it down on your grass"):format(Hatch.name(biome.tier, carry.size, carry.golden)), "success")
		IslandService.push(player)
		IslandService.holdEgg(player, key, carry.golden)
		local root = rootOf(player)
		if root then
			IslandService.fx("Home", root.Position - Vector3.new(0, 2, 0), if carry.golden then GOLD elseif egg then egg.color else nil)
		end -- (still in their hands, now from the inventory)
	else
		-- (back in its nest, if the nest hasn't a new one by now)
		if not carry.nest.full then
			carry.nest.respawnAt = nil
			setFull(carry.nest, true)
			carry.nest.golden = carry.golden
			setSize(carry.nest, carry.size)
		end
	end
	applySpeed(player)
end

-- The player now carries this egg
local function hold(player: Player, held: Carry)
	carrying[player] = held
	Carry.hold(held.part, player)
	player:SetAttribute("WildEgg", true) -- (HeistService won't let them carry another)
	held.part:SetAttribute("Carrier", player.UserId)
	local prompt = held.part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false -- (only once it's dropped)
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
	Carry.release(held.part, Vector3.new(at.X, 1.8, at.Z), player)
	held.part:SetAttribute("Carrier", 0)
	local prompt = held.part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = true
	end
	drops[held.part] = { nest = held.nest, part = held.part, golden = held.golden, size = held.size, expires = os.clock() + WildConfig.DROP_TIME }
end

-- Someone picks up a dropped egg: its guardian (if they're still in its biome) wakes again
function WildService.pickUp(player: Player, part: BasePart)
	local dropped = drops[part]
	local root = rootOf(player)
	if not dropped or not root or busy(player) or (root.CFrame.Position - part.CFrame.Position).Magnitude > WildConfig.GRAB_RANGE + 4 then
		return
	end
	drops[part] = nil
	local safe = Layout.biomeAt(root.CFrame.Position, #WildConfig.BIOMES) ~= dropped.nest.biome
	hold(player, { nest = dropped.nest, part = dropped.part, safe = safe, golden = dropped.golden, size = dropped.size })
	if not safe then
		wake(dropped.nest.biome, player, root.CFrame.Position)
		IslandService.notify(player, "🥚 Got it back! Run before the guardian wakes up!", "success")
	else
		IslandService.notify(player, "🥚 Got it! Take it through the gate", "success")
	end
end

-- The egg taken from a nest, as it's carried off (its Grab prompt for when it's dropped: off till then)
local function carriedEgg(nest: Nest, golden: boolean, size: string, at: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "CarriedEgg"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * 2.6 * Hatch.size(size).scale
	part.Color = if golden then GOLD else nest.color
	part.Material = if golden then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = part
	part.Position = at
	EggModel.dress(part, nest.color, golden)
	part.Parent = workspace
	part:AddTag("WildCarry")
	-- Anyone can grab it where it's dropped (caught by the guardian, knocked by a bat)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = Hatch.name(WildConfig.BIOMES[nest.biome].tier, size, golden)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = WildConfig.GRAB_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(taker)
		WildService.pickUp(taker, part)
	end)
	return part
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
	local golden, size = nest.golden, nest.size
	setFull(nest, false)
	setGolden(nest, false)
	nest.respawnAt = os.clock() + WildConfig.NEST_RESPAWN
	IslandService.fx("Steal", nest.egg.Position, if golden then GOLD else nest.color)
	local part = carriedEgg(nest, golden, size, root.Position)
	hold(player, { nest = nest, part = part, safe = false, golden = golden, size = size })
	local biome = WildConfig.BIOMES[nest.biome]
	-- (the moment, big: run! and why it's harder, when it is)
	local red = Color3.fromRGB(255, 110, 90)
	if size == "Big" or size == "Huge" then
		IslandService.banner(player, ("🏃 RUN! ⚖️ %s egg: you're slower"):format(size), red)
	elseif Wild.outruns(data.power, biome) then
		IslandService.banner(player, "🏃 RUN!", red)
	else
		IslandService.banner(player, ("🏃 RUN! It's faster than you (⚡ %s)"):format(Format.abbrev(Wild.needs(biome))), red)
	end
	wake(nest.biome, player, root.Position)
end

---------------------------------------------------------------------------------------------------------------
-- Studio test bots (TestBotService) steal eggs too: they carry one off, and a bat hit drops it for anyone

local botCarry: { [BasePart]: { nest: Nest, golden: boolean, size: string } } = {}

-- A bot takes the egg from this Wild nest (its egg part): the egg it now carries, or nil when the nest is empty
function WildService.botTake(egg: BasePart): BasePart?
	for _, nest in nests do
		if nest.egg == egg and nest.full then
			local golden, size = nest.golden, nest.size
			setFull(nest, false)
			setGolden(nest, false)
			nest.respawnAt = os.clock() + WildConfig.NEST_RESPAWN
			IslandService.fx("Steal", nest.egg.Position, if golden then GOLD else nest.color)
			local part = carriedEgg(nest, golden, size, egg.Position)
			part:SetAttribute("Carrier", -1) -- (a bot's: not to be grabbed yet; the client shows Grab once it's 0)
			botCarry[part] = { nest = nest, golden = golden, size = size }
			return part
		end
	end
	return nil
end

-- A bot carrying an egg was hit: it drops there, and anyone can grab it (and has to take it home)
function WildService.botDrop(part: BasePart, at: Vector3)
	local carried = botCarry[part]
	if not carried then
		return
	end
	botCarry[part] = nil
	Carry.release(part, Vector3.new(at.X, 1.8, at.Z))
	part:SetAttribute("Carrier", 0) -- (dropped: anyone's to grab)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = true
	end
	drops[part] = { nest = carried.nest, part = part, golden = carried.golden, size = carried.size, expires = os.clock() + WildConfig.DROP_TIME }
end

-- A bot got its egg away: it's gone
function WildService.botKeep(part: BasePart)
	botCarry[part] = nil
	part:Destroy()
end


-- A bat knocked the egg out of a carrier's hands (StealService): it drops right there
function WildService.knock(player: Player)
	local root = rootOf(player)
	if carrying[player] and root then
		IslandService.notify(player, "💥 Knocked out of your hands! Grab it back!", "error")
		drop(player, root.Position)
	end
end

-- Every nest gets its egg back (not the ones being carried)
-- A nest gets a new egg: its size by luck (small, normal, big or, rarely, huge) and, now and then, golden
local function newEgg(nest: Nest, announce: boolean)
	nest.respawnAt = nil
	setFull(nest, true)
	nest.golden = rng:NextNumber() < WildConfig.GOLDEN_CHANCE
	setSize(nest, Hatch.rollSize(function()
		return rng:NextNumber()
	end))
	if nest.golden and announce then
		for _, player in Players:GetPlayers() do
			IslandService.notify(player, ("✨ A Golden Egg in the %s!"):format(WildConfig.BIOMES[nest.biome].name), "rare")
		end
	end
end

-- Every nest with its egg (the server starting)
local function refill()
	for _, nest in nests do
		newEgg(nest, false)
	end
end

-- The nests whose egg was taken a while ago get a new one
local function respawn()
	local now = os.clock()
	for _, nest in nests do
		if not nest.full and nest.respawnAt and now >= nest.respawnAt then
			newEgg(nest, true)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Guardians

local function place(guardian: Guardian, toward: Vector3)
	local built = guardian.built
	local facing = if (toward - guardian.position).Magnitude > 0.1 then Layout.facing(guardian.position, toward) else CFrame.new(guardian.position)
	if built and guardian.asleep then
		-- In its sleeping pose, breathing slowly
		SleepPose.place(built, CFrame.new(guardian.position) * facing.Rotation, guardian.pose, math.sin(os.clock() * 1.6), guardian.sizes)
	elseif built then
		SleepPose.wake(built, guardian.sizes)
		PetModel.place(built, facing * CFrame.new(0, built.height / 2, 0))
	end
	if built and built.model:GetAttribute("Asleep") ~= guardian.asleep then
		built.model:SetAttribute("Asleep", guardian.asleep) -- (the client's Zzz: GuardianClient)
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
	local species = biome.guardian or (if egg then egg.creatures[#egg.creatures] else "Bear")
	local built = PetModel.build({ s = species, v = "Normal", z = biome.guardianSize or "Huge" })
	for _, p in built.parts do
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
	end
	guardian.sizes = SleepPose.sizes(built.parts)
	guardian.pose = WildConfig.SLEEP_POSES[species] or "side"
	built.model.Name = "Guardian"
	built.model.PrimaryPart = built.body
	built.model:SetAttribute("Height", built.height)
	built.model:AddTag("Guardian")
	built.model.Parent = folder
	guardian.built = built
	place(guardian, Vector3.new(Layout.biome(guardian.biome).X, 0, guardian.position.Z)) -- (facing its nests and the road)
end

local function spawnGuardians()
	local world = workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild("Wild") and (world :: any).Wild:FindFirstChild("Guardians")
	for i, biome in WildConfig.BIOMES do
		if not Hatch.open(biome.tier) then
			continue -- (Coming Soon: nobody guards it yet)
		end
		for g = 1, WildConfig.GUARDIANS do
			-- (asleep in its biome's far corner, its nests round it)
			local home = Layout.wildGuardian(i) + Vector3.new(0, 0, (g - 1) * 8)
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
			local label = ("%s · ⚡ %s needed"):format(biome.name, Format.abbrev(Wild.needs(biome)))
			text.Text = "💤 " .. label
			text.Parent = gui
			gui.Parent = tag
			tag.Parent = folder
			local guardian: Guardian = { biome = i, home = home, position = home, wander = home, rest = 0, chasing = nil, text = text, label = label, asleep = true, pose = "side", sizes = {}, wakeAt = 0, built = nil, tag = tag }
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
		Carry.keepHandsFree(player)
		-- Home: into their garden
		local home = IslandService.islandOf(player)
		if home and Layout.gardenAt(root.Position) == home then
			finish(player, true)
		elseif not carry.safe and Layout.biomeAt(root.Position, #WildConfig.BIOMES) ~= carry.nest.biome then
			carry.safe = true
			applySpeed(player)
			IslandService.banner(player, "😮‍💨 ESCAPED! Now take it home", Color3.fromRGB(120, 230, 120))
			IslandService.fx("Escape", root.Position)
		end
	end
	-- Dropped eggs nobody came for go back to their nest
	for part, dropped in drops do
		if os.clock() >= dropped.expires then
			drops[part] = nil
			part:Destroy()
			if not dropped.nest.full then
				dropped.nest.respawnAt = nil
				setFull(dropped.nest, true)
				dropped.nest.golden = dropped.golden
				setSize(dropped.nest, dropped.size)
			end
		end
	end
	for _, guardian in guardians do
		local biome = WildConfig.BIOMES[guardian.biome]
		local target: Vector3
		local speed = Wild.guardian(biome)
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
				IslandService.banner(thief, "🐾 CAUGHT!", Color3.fromRGB(255, 110, 90))
				IslandService.fx("Knock", root.Position)
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
				guardian.asleep = true -- (lies down, facing its nests again: breathing, each step)
				place(guardian, Vector3.new(Layout.biome(guardian.biome).X, 0, guardian.position.Z))
				continue
			end
		end
		local offset = target - guardian.position
		if offset.Magnitude > 0.05 then
			guardian.position += offset.Unit * math.min(offset.Magnitude, speed * dt)
			place(guardian, target)
		end
	end
	-- Who's being chased right now (their screen pulses red, with a heartbeat: client UI/Banner)
	local chased: { [Player]: boolean } = {}
	for _, guardian in guardians do
		local thief = guardian.chasing
		local carry = if thief then carrying[thief] else nil
		if thief and carry and not carry.safe then
			chased[thief] = true
		end
	end
	for _, player in Players:GetPlayers() do
		local now = chased[player] == true
		if (player:GetAttribute("Chased") == true) ~= now then
			player:SetAttribute("Chased", if now then true else nil)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Speed and the treadmill

-- The owner upgrades their treadmill at its console, with coins
local function upgradeTreadmill(player: Player, index: number)
	local data = DataService.get(player)
	if not data or IslandService.islandOf(player) ~= index then
		return
	end
	local price = Wild.upgradePrice(data.treadmill)
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
	IslandService.notify(player, ("Treadmill upgraded! +%s ⚡ every second 🏃"):format(Format.abbrev(Wild.gain(data.treadmill))), "success")
	IslandService.push(player)
end

-- Once a second: whoever is on their own treadmill counts a second; every TREADMILL_EVERY of them they
-- get TREADMILL_GAIN faster
local running: { [Player]: number } = {}
local function train()
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		local index = IslandService.islandOf(player)
		local root = rootOf(player)
		local humanoid = humanoidOf(player)
		-- (standing on it is enough: the player runs on it by themselves, TreadmillClient)
		if not data or not index or not root or not humanoid then
			continue
		end
		local inside = Layout.garden(index):PointToObjectSpace(root.Position) - Layout.TREADMILL
		if math.abs(inside.X) <= 5 and math.abs(inside.Z) <= 2.5 and inside.Y < 8 then
			running[player] = (running[player] or 0) + 1
			if running[player] < WildConfig.TREADMILL_EVERY then
				continue
			end
			running[player] = 0
			local trail = Trails.byId[data.trail] -- (a trail multiplies each step: Config/Trails)
			local gain = Wild.gain(data.treadmill) * (if trail then trail.mult else 1)
			data.power += gain
			applySpeed(player)
			Net.event("SpeedUp"):FireClient(player, gain)
		end
	end
end

-- When the creature models arrive, the guardians are drawn again with them
function WildService.redraw()
	for _, guardian in guardians do
		draw(guardian)
	end
end

function WildService.init()
	IslandService.powerChanged = applySpeed
	local world = workspace:FindFirstChild("World")
	local wild = world and world:FindFirstChild("Wild")
	if wild then
		for _, egg in wild:GetChildren() do
			local biome, index = egg:GetAttribute("Biome"), egg:GetAttribute("Nest")
			local prompt = egg:FindFirstChildOfClass("ProximityPrompt")
			if egg:IsA("BasePart") and type(biome) == "number" and type(index) == "number" and prompt then
				local nest: Nest = { egg = egg, prompt = prompt, full = true, golden = false, size = "Normal", ground = egg.Position - Vector3.new(0, 2.8, 0), color = egg.Color, biome = biome, index = index, respawnAt = nil }
				table.insert(nests, nest)
				prompt.Triggered:Connect(function(player)
					steal(player, nest)
				end)
			end
		end
	end
	spawnGuardians()
	refill() -- (every nest full to start with)
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, player)
		local index = prompt:GetAttribute("Treadmill")
		if type(index) == "number" then
			upgradeTreadmill(player, index)
		end
	end)
	DataService.onLoaded(function(player, data)
		player:SetAttribute("Speed", data.power)
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
		running[player] = nil
		finish(player, false)
	end)
	RunService.Heartbeat:Connect(tick)
	task.spawn(function()
		while true do
			task.wait(1)
			train()
			respawn()
		end
	end)
end

return WildService
