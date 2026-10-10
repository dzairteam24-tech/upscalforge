--!strict
-- Each player's saved data: loaded when they join, saved every minute and when they leave. If the DataStore
-- can't be reached (a place that isn't published, Studio without API access), the player plays with fresh
-- data that isn't saved.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared.Config.Island)

export type Creature = { s: string, m: string }
export type Data = {
	coins: number,
	gems: number,
	eggs: { [string]: number }, -- egg tier -> how many the player holds
	creatures: { [string]: Creature }, -- creature id -> species and mutation
	placed: { string }, -- the creatures living on the island (they earn)
	incubators: number,
	incubating: { [string]: { tier: number, start: number } }, -- incubator slot -> its egg and os.time() it went in
	pens: number,
	shop: { window: number, bought: { [string]: number } }, -- eggs bought in the current restock window
	nextId: number,
	lastSeen: number,
	stats: { hatched: number, earned: number, caught: number },
	nets: { [string]: number }, -- net id -> how many the player holds (the basic net is free)
	firstPlayed: number, -- os.time() of their first visit (a new player's garden can't be robbed at first)
	food: { [string]: number }, -- food id -> how many the player holds (in their trough)
	fedUntil: number, -- os.time() the creatures are fed until (Config/Food)
	storage: number, -- the barn's level (Config/Island STORAGE)
}

local DataService = {}

local STORE_NAME = "CubelingsNest_v1"
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
		eggs = { ["1"] = 1 },
		creatures = {},
		placed = {},
		incubators = IslandConfig.INCUBATORS,
		incubating = {},
		pens = IslandConfig.PENS,
		shop = { window = -1, bought = {} },
		nextId = 1,
		lastSeen = 0,
		stats = { hatched = 0, earned = 0, caught = 0 },
		nets = {},
		firstPlayed = 0,
		food = {},
		fedUntil = 0,
		storage = 1,
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
	if data.firstPlayed == 0 then
		data.firstPlayed = os.time()
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
	if not data or not store then
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
