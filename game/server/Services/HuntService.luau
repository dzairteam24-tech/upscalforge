--!strict
-- Hunting (Config/Hunt, Logic/Hunt): wild creatures come out of the den at the far end of the street, one every
-- few seconds, and walk down the carpet past the gardens to the burrow by the shops. A player walks up to one and
-- starts the catching game; the server picks where the green is and when the marker starts, and checks the
-- click itself. Caught, the creature goes to the player's garden (or storage); missed, it runs off. Now and then
-- a shiny comes out, announced to everyone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local HuntConfig = require(Shared.Config.Hunt)
local Mutations = require(Shared.Config.Mutations)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Hunt = require(Shared.Logic.Hunt)
local Layout = require(Shared.Logic.Layout)
local Weather = require(Shared.Logic.Weather)
local PetModel = require(Shared.PetModel)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local HeistService = require(script.Parent.HeistService)
local IslandService = require(script.Parent.IslandService)
local RaidService = require(script.Parent.RaidService)

local HuntService = {}

type Wild = {
	id: string,
	zone: number,
	species: string,
	mutation: string,
	rarity: string,
	shiny: boolean,
	position: Vector3,
	sway: number, -- its side of the carpet
	progress: number, -- studs walked from the den
	built: PetModel.Built?,
	hitbox: Part,
	catcher: Player?,
	game: { start: number, speed: number, center: number, width: number, net: string }?,
}

local wilds: { [string]: Wild } = {}
local nextId = 1
local rng = Random.new()
local lastTry: { [Player]: number } = {}

local function folder(): Instance?
	local world = workspace:FindFirstChild("World")
	return world and world:FindFirstChild("WildCreatures")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local DEN, BURROW = Layout.carpet()
local LENGTH = (BURROW - DEN).Magnitude
local DOWN = (BURROW - DEN).Unit
local ACROSS = Vector3.new(-DOWN.Z, 0, DOWN.X)

local function zoneOf(wild: Wild): HuntConfig.Zone
	return HuntConfig.ZONES[wild.zone]
end

-- The player's best egg tier, or nil without data
local function bestTier(player: Player): number?
	local data = DataService.get(player)
	return if data then IslandService.bestTier(data) else nil
end

---------------------------------------------------------------------------------------------------------------
-- Wild creatures

local function draw(wild: Wild)
	if wild.built then
		wild.built.model:Destroy()
	end
	local parent = folder()
	if not parent then
		return
	end
	local built = PetModel.build({ s = wild.species, v = wild.mutation, z = "Normal" })
	for _, p in built.parts do
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
	end
	built.model.Parent = parent
	wild.built = built
end

local function place(wild: Wild)
	local built = wild.built
	local facing = Layout.facing(wild.position, wild.position + DOWN)
	if built then
		PetModel.place(built, facing * CFrame.new(0, built.height / 2, 0))
	end
	wild.hitbox.CFrame = CFrame.new(wild.position + Vector3.new(0, 2, 0))
end

local function spawn(zone: number, shiny: boolean)
	local info = HuntConfig.ZONES[zone]
	local tier = info.tiers[rng:NextInteger(1, #info.tiers)]
	local weather = Weather.at(os.time())
	local species, mutation = Hatch.roll(tier, function()
		return rng:NextNumber()
	end, weather.mutation)
	if shiny then
		local egg = Hatch.egg(tier)
		species = if egg then egg.creatures[math.min(4, #egg.creatures)] else species
		if Mutations.byId[mutation].order < Mutations.byId[HuntConfig.SHINY_MUTATION].order then
			mutation = HuntConfig.SHINY_MUTATION
		end
	end
	local creature = Creatures.byId[species]
	local id = tostring(nextId)
	nextId += 1
	local hitbox = Instance.new("Part")
	hitbox.Name = "WildHitbox"
	hitbox.Size = Vector3.new(4, 4, 4)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox:SetAttribute("WildId", id)
	hitbox:SetAttribute("Zone", zone)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Catch"
	prompt.ObjectText = (if mutation ~= "Normal" then mutation .. " " else "") .. species
	prompt.MaxActivationDistance = HuntConfig.CATCH_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = hitbox
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromScale(7, 1.4)
	tag.StudsOffset = Vector3.new(0, 3.5, 0)
	tag.MaxDistance = 60
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = if shiny then Color3.fromRGB(255, 215, 80) else Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = (if shiny then "✨ " else "") .. (if creature then creature.rarity else "")
	text.Parent = tag
	tag.Parent = hitbox
	local wild: Wild = {
		id = id,
		zone = zone,
		species = species,
		mutation = mutation,
		rarity = if creature then creature.rarity else "Common",
		shiny = shiny,
		position = DEN,
		sway = rng:NextNumber(-1, 1) * (Layout.CARPET_WIDTH / 2 - 1),
		progress = 0,
		built = nil,
		hitbox = hitbox,
		catcher = nil,
		game = nil,
	}
	wilds[id] = wild
	prompt.Triggered:Connect(function(player)
		HuntService.start(player, id)
	end)
	hitbox.Parent = folder()
	draw(wild)
	place(wild)
	if shiny then
		for _, player in Players:GetPlayers() do
			IslandService.notify(player, ("✨ A shiny %s %s is walking down the street! Catch it first!"):format(mutation, species), "rare")
		end
	end
end

-- Takes a wild creature away
local function remove(wild: Wild)
	wilds[wild.id] = nil
	if wild.built then
		wild.built.model:Destroy()
	end
	wild.hitbox:Destroy()
end

-- Ten times a second: the wild creatures walk down the carpet (they stop while someone's catching them) and go
-- into the burrow at its end
local STEP = 0.1
local pending = 0
local function walk(frame: number)
	pending += frame
	if pending < STEP then
		return
	end
	local dt = pending
	pending = 0
	for _, wild in wilds do
		if wild.catcher then
			continue
		end
		wild.progress += HuntConfig.WALK_SPEED * (if wild.shiny then 1.4 else 1) * dt
		if wild.progress >= LENGTH then
			remove(wild)
			continue
		end
		wild.position = DEN + DOWN * wild.progress + ACROSS * wild.sway
		place(wild)
	end
end

-- Which kind of creature comes out next (Config/Hunt weights)
local function pickZone(): number
	local total = 0
	for _, zone in HuntConfig.ZONES do
		total += zone.weight
	end
	local roll = rng:NextNumber(0, total)
	for i, zone in HuntConfig.ZONES do
		roll -= zone.weight
		if roll <= 0 then
			return i
		end
	end
	return 1
end

---------------------------------------------------------------------------------------------------------------
-- Catching

local function release(wild: Wild)
	wild.catcher = nil
	wild.game = nil
end

-- The best net the player holds (the basic one is always there)
local function bestNet(data: DataService.Data): HuntConfig.Net
	for i = #HuntConfig.NETS, 2, -1 do
		local net = HuntConfig.NETS[i]
		if (data.nets[net.id] or 0) > 0 then
			return net
		end
	end
	return HuntConfig.NETS[1]
end

function HuntService.start(player: Player, id: string)
	local wild = wilds[id]
	local data = DataService.get(player)
	local root = rootOf(player)
	local best = bestTier(player)
	if not wild or not data or not root or not best then
		return
	end
	if wild.catcher then
		if wild.catcher ~= player then
			IslandService.notify(player, ("%s is catching that one!"):format(wild.catcher.DisplayName), "error")
		end
		return
	end
	local zone = zoneOf(wild)
	if not Hunt.unlocked(zone, best) then
		local egg = Hatch.egg(zone.need)
		IslandService.notify(player, ("Hatch a %s creature to catch %s creatures"):format(if egg then egg.name else "better", zone.name), "error")
		return
	end
	if (root.Position - wild.position).Magnitude > HuntConfig.CATCH_RANGE + 4 then
		return
	end
	if os.clock() - (lastTry[player] or 0) < HuntConfig.COOLDOWN then
		return
	end
	local count = 0
	for _ in data.creatures do
		count += 1
	end
	if count >= IslandService.storage(data) then
		IslandService.notify(player, "Your storage is full: sell some creatures or grow your barn", "error")
		return
	end
	local net = bestNet(data)
	local width, speed = Hunt.bar(wild.rarity, net)
	local start = workspace:GetServerTimeNow() + 0.6
	local center = rng:NextNumber(width / 2 + 0.05, 1 - width / 2 - 0.05)
	wild.catcher = player
	wild.game = { start = start, speed = speed, center = center, width = width, net = net.id }
	Net.event("CatchGame"):FireClient(player, id, start, speed, center, width, net.id)
	-- Bored if the player doesn't try in time
	task.delay(HuntConfig.GAME_TIME + 1, function()
		if wild.catcher == player and wild.game and wild.game.start == start then
			release(wild)
		end
	end)
end

local function try(player: Player, id: any, clickAt: any)
	if type(id) ~= "string" or type(clickAt) ~= "number" then
		return
	end
	local wild = wilds[id]
	local data = DataService.get(player)
	if not wild or not data or wild.catcher ~= player or not wild.game then
		return
	end
	local catchGame = wild.game
	local now = workspace:GetServerTimeNow()
	-- The click can't be from the future, or long ago (the player's ping aside)
	local at = math.clamp(clickAt, math.max(catchGame.start, now - 1), now)
	lastTry[player] = os.clock()
	release(wild)
	if catchGame.net ~= "Basic" then
		data.nets[catchGame.net] = math.max(0, (data.nets[catchGame.net] or 0) - 1)
	end
	if not Hunt.hit(at - catchGame.start, catchGame.speed, catchGame.center, catchGame.width) then
		IslandService.notify(player, ("Missed! The %s ran off 💨"):format(wild.species), "error")
		remove(wild)
		IslandService.push(player)
		return
	end
	local creatureId = IslandService.addCreature(player, data, wild.species, wild.mutation)
	if not creatureId then
		IslandService.push(player)
		return
	end
	data.stats.hatched -= 1 -- (addCreature counts a hatch)
	data.stats.caught += 1
	remove(wild)
	IslandService.notify(player, ("Caught a %s%s! 🎉"):format(if wild.mutation ~= "Normal" then wild.mutation .. " " else "", wild.species), "success")
	if wild.shiny then
		for _, other in Players:GetPlayers() do
			IslandService.notify(other, ("✨ %s caught the shiny %s!"):format(player.DisplayName, wild.species), "rare")
		end
	end
	IslandService.render(player)
	IslandService.push(player)
end

---------------------------------------------------------------------------------------------------------------
-- Going home, and nets

-- Home (the HUD's button): not while carrying an egg off
local function travel(player: Player, where: any)
	if where ~= "home" then
		return
	end
	if RaidService.isCarrying(player) or HeistService.isCarrier(player) then
		IslandService.notify(player, "Not while you're carrying an egg: run!", "error")
		return
	end
	IslandService.sendHome(player)
end

local function buyNet(player: Player, id: any)
	local data = DataService.get(player)
	local net = if type(id) == "string" then HuntConfig.netById[id] else nil
	if not data or not net or net.share == 0 then
		return
	end
	local price = Hunt.netPrice(net, IslandService.bestTier(data))
	if data.coins < price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
		return
	end
	data.coins -= price
	data.nets[net.id] = (data.nets[net.id] or 0) + 1
	IslandService.notify(player, ("Bought a %s %s! It's used on your next catch"):format(net.icon, net.name), "success")
	IslandService.push(player)
end

-- When the creature models arrive, the wild creatures are drawn again with them
function HuntService.redraw()
	for _, wild in wilds do
		draw(wild)
		place(wild)
	end
end

function HuntService.init()
	Net.event("CatchTry").OnServerEvent:Connect(try)
	Net.event("Travel").OnServerEvent:Connect(travel)
	Net.event("BuyNet").OnServerEvent:Connect(buyNet)
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
		for _, wild in wilds do
			if wild.catcher == player then
				release(wild)
			end
		end
	end)
	RunService.Heartbeat:Connect(walk)
	task.spawn(function()
		while true do
			local out = 0
			for _ in wilds do
				out += 1
			end
			if out < HuntConfig.MAX_OUT then
				spawn(pickZone(), false)
			end
			task.wait(HuntConfig.SPAWN_EVERY)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(HuntConfig.SHINY_EVERY)
			spawn(pickZone(), true)
		end
	end)
end

return HuntService
