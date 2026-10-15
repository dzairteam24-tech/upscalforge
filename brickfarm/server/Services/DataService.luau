--!strict
-- Each player's saved data (Brick Farm): loaded when they join, saved every minute and when they leave. If the DataStore can't
-- be reached (an unpublished place, Studio without API access) they play with fresh data that isn't saved. In
-- Studio the player starts with test coins (Config/Game STUDIO_COINS) and nothing is saved.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Net = require(Shared.Net)
local Crops = require(Shared.Config.Crops)
local Land = require(Shared.Logic.Land)
local Level = require(Shared.Logic.Level)
local Snapshot = require(Shared.Logic.Snapshot)

export type Data = {
	coins: number,
	xp: number,
	tiles: number, -- how many tiles of land (Logic/Land)
	plots: { [string]: { c: string, t: number } }, -- what grows on each tile, and when it was planted (os.time)
	seeds: { [string]: number },
	barn: { [string]: number }, -- harvested, not sold yet
	stats: { planted: number, harvested: number, sold: number, earned: number },
	receipts: { string }, -- the last purchases handled (so a receipt is never paid twice)
	guide: number, -- how far the first-minutes guide has got
	lastSeen: number,
}

local DataService = {}

-- Which farm of the village is theirs (FarmService sets this)
DataService.farmOf = function(_player: Player): number?
	return nil
end

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
local onPushed: { (Player, Data) -> () } = {}
local pushing: { [Player]: boolean } = {}

DataService.START_COINS = 20
DataService.START_SEEDS = 6 -- carrot seeds: the first thing they do is plant

local function fresh(): Data
	return {
		coins = if TESTING then Game.STUDIO_COINS else DataService.START_COINS,
		xp = 0,
		tiles = Land.START,
		plots = {},
		seeds = { carrot = DataService.START_SEEDS },
		barn = {},
		stats = { planted = 0, harvested = 0, sold = 0, earned = 0 },
		receipts = {},
		guide = 0,
		lastSeen = os.time(),
	}
end

-- Fills in what an older save is missing (and drops anything the wrong shape)
local function reconcile(saved: any): Data
	if type(saved) ~= "table" then
		return fresh()
	end
	local data = fresh()
	data.seeds = {}
	for k, default in data :: any do
		local v = saved[k]
		if type(v) == type(default) and type(v) ~= "table" then
			(data :: any)[k] = v
		end
	end
	local function counts(from: any, into: any)
		if type(from) ~= "table" then
			return
		end
		for k, v in from do
			if type(k) == "string" and type(v) == "number" and v > 0 and Crops.byKey[k] then
				into[k] = math.floor(v)
			end
		end
	end
	counts(saved.seeds, data.seeds)
	counts(saved.barn, data.barn)
	if type(saved.stats) == "table" then
		for k in data.stats :: any do
			if type(saved.stats[k]) == "number" then
				(data.stats :: any)[k] = saved.stats[k]
			end
		end
	end
	data.tiles = math.clamp(math.floor(data.tiles), Land.START, Land.MAX)
	if type(saved.plots) == "table" then
		for k, v in saved.plots do
			local n = tonumber(k)
			if n and n >= 1 and n <= data.tiles and type(v) == "table" and type(v.c) == "string" and Crops.byKey[v.c] and type(v.t) == "number" then
				data.plots[tostring(math.floor(n))] = { c = v.c, t = v.t }
			end
		end
	end
	if type(saved.receipts) == "table" then
		for _, r in saved.receipts do
			if type(r) == "string" then
				table.insert(data.receipts, r)
			end
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

-- Called each time their data has changed and been sent (the farm shows it)
function DataService.onPushed(fn: (Player, Data) -> ())
	table.insert(onPushed, fn)
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
			Net.event("Data"):FireClient(player, Snapshot.of(data, DataService.farmOf(player)))
			-- (the player list: level and coins)
			if typeof(player) == "Instance" then
				local board = player:FindFirstChild("leaderstats")
				if board then
					local values = { Level = (Level.of(data.xp)), Coins = math.floor(data.coins) }
					for name, value in values do
						local v = board:FindFirstChild(name) :: IntValue?
						if v then
							v.Value = value
						end
					end
				end
			end
			for _, fn in onPushed do
				fn(player, data)
			end
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
	if typeof(player) == "Instance" then
		local board = Instance.new("Folder")
		board.Name = "leaderstats"
		for _, name in { "Level", "Coins" } do
			local value = Instance.new("IntValue")
			value.Name = name
			value.Parent = board
		end
		board.Parent = player
	end
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
