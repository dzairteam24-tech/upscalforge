--!strict
-- Each player's saved data: loaded when they join, saved every minute and when they leave. If the DataStore
-- can't be reached (a place that isn't published, Studio without API access), the player plays with fresh
-- data that isn't saved.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local IslandConfig = require(Shared.Config.Island)
local WildConfig = require(Shared.Config.Wild)

-- g: a snapped creature's grade (Config/Snap)
export type Creature = { s: string, m: string, g: string?, w: string? } -- (w: its egg's size, Config/EggSizes)
export type Data = {
	coins: number,
	gems: number,
	eggs: { [string]: number }, -- egg key (Logic/Hatch.key: its tier, and its size unless Normal: "1", "1_Big") -> how many the player holds
	golden: { [string]: number }, -- egg key -> how many Golden Eggs (from the Wild's golden nests) they hold
	storedEggs: { [string]: number }, -- egg key -> how many they keep in the barn (out of the hotbar)
	storedGolden: { [string]: number }, -- the same for Golden Eggs
	stored: { [string]: boolean }, -- creature ids kept in the barn (safe, not in the hotbar); the rest of those not in the garden are carried
	creatures: { [string]: Creature }, -- creature id -> species and mutation
	placed: { string }, -- the creatures living on the island (they earn)
	incubators: number, -- nests on the ground
	machines: number, -- incubators at the back of the garden (Config/Island MACHINE_PRICES)
	incubating: { [string]: { tier: number, start: number, m: string?, w: string?, x: number?, z: number? } }, -- slot -> its egg and os.time() it went in (w: its size; m: a Golden Egg's least mutation; x, z: where it was set down in the garden, for one on the grass)
	pens: number,
	nextId: number,
	lastSeen: number,
	stats: { hatched: number, earned: number, stolen: number },
	power: number, -- the player's speed (⚡, a big number: Logic/Wild.walk), trained on the treadmill
	treadmill: number, -- the treadmill's level (Config/Wild TREADMILL)
	firstPlayed: number, -- os.time() of their first visit (when they first played)
	food: { [string]: number }, -- food id -> how many the player holds (in their trough)
	fedUntil: number, -- os.time() the creatures are fed until (Config/Food)
	storage: number, -- the barn's level (Config/Island STORAGE)
	pasture: number, -- how far the pasture has grown (Config/Island PASTURE_GROWTH)
	starter: boolean, -- whether they got their free first egg (IslandService)
	daily: { day: number, progress: { [string]: number }, claimed: boolean }, -- today's tasks (Logic/Daily)
	index: { [string]: boolean }, -- every species they've hatched (the Index, Logic/Index)
	indexClaimed: { [string]: boolean }, -- the Index pages (egg tiers) whose reward they took
	trails: { [string]: boolean }, -- the trails they bought (Config/Trails)...
	trail: string, -- ...and the one they wear ("": none)
}

local DataService = {}

-- Species renamed since older saves: old name -> new name
local RENAMED: { [string]: string } = { Cubby = "Dog", Kitty = "Cat" }

local STORE_NAME = "CubelingsNest_v1"
-- (testing in Studio with test coins: nothing is saved)
local TESTING = RunService:IsStudio() and IslandConfig.STUDIO_COINS > 0
local SAVE_EVERY = 60

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Data] No DataStore, playing without saving:", result)
	end
end

local loaded: { [Player]: Data } = {}
-- Called with each player's data once it's loaded (a plain list: a BindableEvent would copy the table)
local onLoaded: { (Player, Data) -> () } = {}

function DataService.onLoaded(fn: (Player, Data) -> ())
	table.insert(onLoaded, fn)
end

local function template(): Data
	return {
		coins = IslandConfig.START_COINS,
		gems = 0,
		eggs = {},
		golden = {},
		storedEggs = {},
		storedGolden = {},
		stored = {},
		creatures = {},
		placed = {},
		incubators = IslandConfig.INCUBATORS,
		machines = 0,
		incubating = {},
		pens = IslandConfig.PENS,
		nextId = 1,
		lastSeen = 0,
		stats = { hatched = 0, earned = 0, stolen = 0 },
		power = 0,
		treadmill = 1,
		firstPlayed = 0,
		food = {},
		fedUntil = 0,
		storage = 1,
		pasture = 1,
		starter = false,
		daily = { day = -1, progress = {}, claimed = false },
		index = {},
		indexClaimed = {},
		trails = {},
		trail = "",
	}
end

-- Fills in what an older save is missing
local function reconcile(data: { [string]: any }, defaults: { [string]: any })
	for key, value in defaults do
		if data[key] == nil then
			data[key] = value
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil then
			reconcile(data[key], value)
		end
	end
end

local function key(player: Player): string
	return "u" .. player.UserId
end

local function load(player: Player)
	local data = template()
	if store then
		local ok, saved = pcall(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok and type(saved) == "table" then
			reconcile(saved, data)
			data = saved :: any
		elseif not ok then
			warn("[Data] Couldn't load", player.Name, saved)
		end
	end
	-- (creatures renamed since: Meadow's are real animals now)
	for _, creature in data.creatures do
		creature.s = RENAMED[creature.s] or creature.s
	end
	for old, new in RENAMED do
		if data.index[old] then
			data.index[old] = nil
			data.index[new] = true
		end
	end
	-- (the old creatures are gone: only the new animals are kept, in the garden and the Index)
	for id, creature in data.creatures do
		if not Creatures.byId[creature.s] then
			data.creatures[id] = nil
		end
	end
	for i = #data.placed, 1, -1 do
		if not data.creatures[data.placed[i]] then
			table.remove(data.placed, i)
		end
	end
	for species in data.index do
		if not Creatures.byId[species] then
			data.index[species] = nil
		end
	end
	-- (the Index starts with what they already have)
	for _, creature in data.creatures do
		data.index[creature.s] = true
	end
	if data.firstPlayed == 0 then
		data.firstPlayed = os.time()
	end
	if TESTING then
		data.coins = math.max(data.coins, IslandConfig.STUDIO_COINS)
	end
	if player.Parent then
		loaded[player] = data
		for _, fn in onLoaded do
			task.spawn(fn, player, data)
		end
	end
end

function DataService.save(player: Player)
	local data = loaded[player]
	if not data or not store or TESTING then
		return
	end
	data.lastSeen = os.time()
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(key(player), data)
	end)
	if not ok then
		warn("[Data] Couldn't save", player.Name, err)
	end
end

function DataService.get(player: Player): Data?
	return loaded[player]
end

function DataService.init()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		loaded[player] = nil
	end)
	game:BindToClose(function()
		for player in loaded do
			DataService.save(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(SAVE_EVERY)
			for player in loaded do
				task.spawn(DataService.save, player)
			end
		end
	end)
end

return DataService
