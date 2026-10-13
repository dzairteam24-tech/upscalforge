--!strict
-- Each player's saved data: loaded when they join, saved every minute and when they leave. If the DataStore can't
-- be reached (an unpublished place, Studio without API access) they play with fresh data that isn't saved. In
-- Studio the player starts with test coins (Config/Game STUDIO_COINS) and nothing is saved.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Net = require(Shared.Net)
local Snapshot = require(Shared.Logic.Snapshot)

export type Item = { g: string, s: string, m: string? }
export type Data = {
	coins: number,
	shovel: number, -- index in Config/Gear SHOVELS
	pack: number, -- index in Config/Gear PACKS
	items: { [string]: Item }, -- the gems in the backpack, by id
	nextId: number,
	found: { [string]: boolean }, -- the gem kinds they've found (the catalog)
	stats: { dug: number, sold: number, earned: number },
	deepest: number, -- the deepest layer they've dug
	seed: number, -- their mine's seed
	lastSeen: number,
}

local DataService = {}

local TESTING = RunService:IsStudio() and Game.STUDIO_COINS > 0

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Game.STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Data] No DataStore, playing without saving:", result)
	end
end

local loaded: { [Player]: Data } = {}
local onLoaded: { (Player, Data) -> () } = {}
local onLeaving: { (Player) -> () } = {}
local pushing: { [Player]: boolean } = {}

local function fresh(): Data
	return {
		coins = if TESTING then Game.STUDIO_COINS else 0,
		shovel = 1,
		pack = 1,
		items = {},
		nextId = 1,
		found = {},
		stats = { dug = 0, sold = 0, earned = 0 },
		deepest = 0,
		seed = math.random(1, 1000000),
		lastSeen = os.time(),
	}
end

-- Fills in what an older save is missing
local function reconcile(saved: any): Data
	local data = fresh()
	if type(saved) ~= "table" then
		return data
	end
	for k, default in data :: any do
		local v = saved[k]
		if type(v) == type(default) then
			(data :: any)[k] = v
		end
	end
	for k, default in data.stats :: any do
		if type(saved.stats) == "table" and type(saved.stats[k]) == "number" then
			(data.stats :: any)[k] = saved.stats[k]
		else
			(data.stats :: any)[k] = default
		end
	end
	return data
end

function DataService.onLoaded(fn: (Player, Data) -> ())
	table.insert(onLoaded, fn)
end

function DataService.onLeaving(fn: (Player) -> ())
	table.insert(onLeaving, fn)
end

function DataService.get(player: Player): Data?
	return loaded[player]
end

-- Tells the client its data changed (several changes in a moment send one picture)
function DataService.push(player: Player)
	if pushing[player] then
		return
	end
	pushing[player] = true
	task.defer(function()
		pushing[player] = nil
		local data = loaded[player]
		if data and player.Parent then
			Net.event("Data"):FireClient(player, Snapshot.of(data))
		end
	end)
end

local function key(player: Player): string
	return "p" .. player.UserId
end

local function save(player: Player)
	local data = loaded[player]
	if not data or not store or TESTING then
		return
	end
	data.lastSeen = os.time()
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			(store :: DataStore):SetAsync(key(player), data)
		end)
		if ok then
			return
		end
		warn(("[Data] Save failed for %s (try %d): %s"):format(player.Name, attempt, tostring(err)))
		task.wait(attempt)
	end
end
DataService.save = save

local function load(player: Player)
	local saved: any = nil
	if store and not TESTING then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return (store :: DataStore):GetAsync(key(player))
			end)
			if ok then
				saved = result
				break
			end
			warn(("[Data] Load failed for %s (try %d): %s"):format(player.Name, attempt, tostring(result)))
			task.wait(attempt)
		end
	end
	if not player.Parent then
		return
	end
	local data = reconcile(saved)
	loaded[player] = data
	for _, fn in onLoaded do
		task.spawn(fn, player, data)
	end
	DataService.push(player)
end

function DataService.init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		for _, fn in onLeaving do
			fn(player)
		end
		save(player)
		loaded[player] = nil
		pushing[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Game.SAVE_EVERY)
			for player in loaded do
				task.spawn(save, player)
			end
		end
	end)
	game:BindToClose(function()
		for player in loaded do
			save(player)
		end
	end)
end

return DataService
