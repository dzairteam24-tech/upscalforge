--!strict
-- The Nest (Config/Nest, Logic/Nest): each player in the server gets one of the islands in the Nest field
-- (WorldBuilder) while they play. On it, incubators hatch eggs in real time: an egg put in keeps going while
-- its owner is away, and when it's done it hatches with extra luck, at least as rare as the weather was when
-- it finished. The incubators' state lives in the player's data (nest.eggs); this service copies it onto
-- the island's pads as attributes (Owner, Zone, Start, Duration) for NestClient to draw.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NestConfig = require(Shared.Config.Nest)
local World1 = require(Shared.Config.World1)
local Format = require(Shared.Logic.Format)
local Inventory = require(Shared.Logic.Inventory)
local Nest = require(Shared.Logic.Nest)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData

local NestService = {}

local REACH = 16 -- how close to an incubator a player has to stand to use it

local owners: { [number]: Player } = {} -- island -> player
local plotOf: { [Player]: number } = {}

local function plotModel(index: number): Instance?
	local world = workspace:FindFirstChild("World")
	local field = world and world:FindFirstChild("NestField")
	return field and field:FindFirstChild("NestPlot_" .. index)
end

-- Copies a player's incubators onto their island (or clears it when `player` is nil)
local function render(index: number, player: Player?, data: PlayerData?)
	local plot = plotModel(index)
	if not plot then
		return
	end
	plot:SetAttribute("Owner", if player then player.UserId else 0)
	plot:SetAttribute("Slots", if data then data.nest.slots else 0)
	local sign = plot:FindFirstChild("OwnerSign")
	local text = sign and sign:FindFirstChild("Text", true)
	if text and text:IsA("TextLabel") then
		text.Text = if player then ("🥚 %s's Nest"):format(player.DisplayName) else "Free island"
	end
	for _, pad in plot:GetChildren() do
		local slot = pad:GetAttribute("Slot")
		if type(slot) == "number" then
			local egg = if data then data.nest.eggs[tostring(slot)] else nil
			pad:SetAttribute("Zone", if egg then egg.zone else 0)
			pad:SetAttribute("Start", if egg then egg.start else 0)
			pad:SetAttribute("Duration", if egg then Nest.incubateSeconds(egg.zone) else 0)
			pad:SetAttribute("Owner", if player then player.UserId else 0)
			pad:SetAttribute("Open", if data then slot <= data.nest.slots else false)
			pad:SetAttribute("Price", if data and slot == data.nest.slots + 1 then Nest.slotPrice(data.nest.slots) or 0 else 0)
		end
	end
end

local function assign(player: Player)
	-- Wait for the player's data
	local data: PlayerData? = nil
	for _ = 1, 60 do
		data = DataService.get(player)
		if data or not player.Parent then
			break
		end
		task.wait(0.5)
	end
	if not data or not player.Parent then
		return
	end
	for index = 1, NestConfig.PLOTS do
		if not owners[index] then
			owners[index] = player
			plotOf[player] = index
			render(index, player, data)
			player:SetAttribute("NestPlot", index)
			return
		end
	end
end

local function release(player: Player)
	local index = plotOf[player]
	if index then
		owners[index] = nil
		plotOf[player] = nil
		render(index, nil, nil)
	end
end

-- The best egg the player can afford to put in: the furthest unlocked zone's
local function bestEgg(data: PlayerData): number?
	local best: number? = nil
	for _, zone in World1.zones do
		if zone.eggPrice > 0 and data.unlockedZones[tostring(zone.id)] and data.coins >= Nest.eggPrice(zone.id) then
			best = zone.id
		end
	end
	return best
end

local function use(player: Player, plotIndex: any, slot: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(plotIndex) ~= "number" or type(slot) ~= "number" then
		return
	end
	if plotOf[player] ~= plotIndex or slot ~= slot // 1 or slot < 1 or slot > Nest.maxSlots() then
		return
	end
	if not State.throttle(runtime, "Nest", 0.4) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local plot = plotModel(plotIndex)
	local pad: BasePart? = nil
	if plot then
		for _, child in plot:GetChildren() do
			if child:IsA("BasePart") and child:GetAttribute("Slot") == slot then
				pad = child
			end
		end
	end
	if not root or not pad or (root.Position - pad.Position).Magnitude > REACH then
		return
	end

	local key = tostring(slot)
	-- A locked incubator: buy it (only the next one)
	if slot > data.nest.slots then
		local price = Nest.slotPrice(data.nest.slots)
		if slot ~= data.nest.slots + 1 or not price then
			GameService.notify(player, "Unlock the incubators in order", "error")
			return
		end
		if data.coins < price then
			GameService.notify(player, ("You need %s coins"):format(Format.abbrev(price)), "error")
			return
		end
		data.coins -= price
		data.nest.slots += 1
		GameService.notify(player, "New incubator! 🥚", "success")
	else
		local egg = data.nest.eggs[key]
		if egg then
			-- Done? Hatch it, as rare as the weather when it finished
			local finished = egg.start + Nest.incubateSeconds(egg.zone)
			local now = os.time()
			if now < finished then
				GameService.notify(player, ("Still incubating: %s left"):format(Format.time(finished - now)), "info")
				return
			end
			if Inventory.count(data) >= GameService.capacity(player) then
				GameService.notify(player, "Your storage is full. Delete or fuse some creatures.", "error")
				return
			end
			data.nest.eggs[key] = nil
			local weather = Nest.weatherAt(finished)
			GameService.hatchPaid(player, egg.zone, NestConfig.LUCK, weather.minVariant)
			GameService.progress(player, "NestHatch", 1)
		else
			-- Empty: put in the best egg the player can afford
			local zoneId = bestEgg(data)
			if not zoneId then
				local cheapest = Nest.eggPrice(1)
				GameService.notify(player, ("A nest egg costs %s coins"):format(Format.abbrev(cheapest)), "error")
				return
			end
			data.coins -= Nest.eggPrice(zoneId)
			data.nest.eggs[key] = { zone = zoneId, start = os.time() }
			GameService.notify(player, ("%s egg is incubating: %s"):format(World1.zonesById[zoneId].name, Format.time(Nest.incubateSeconds(zoneId))), "success")
		end
	end
	GameService.markDirty(player)
	GameService.refresh(player)
	render(plotIndex, player, data)
end

function NestService.init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(assign, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(assign, player)
	end
	Players.PlayerRemoving:Connect(release)
	Net.event("NestUse").OnServerEvent:Connect(use)
end

-- Where a player's island is (for "go to my nest"), or nil
function NestService.plotOf(player: Player): number?
	return plotOf[player]
end

return NestService
