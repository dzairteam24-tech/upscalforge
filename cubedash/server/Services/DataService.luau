--!strict
-- Each player's saved data (Cubedash): loaded when they join, saved every minute and when they leave. If the DataStore can't
-- be reached (an unpublished place, Studio without API access) they play with fresh data that isn't saved. In
-- Studio the player starts with test coins (Config/Game STUDIO_COINS) and nothing is saved.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Net = require(Shared.Net)
local Economy = require(Shared.Logic.Economy)
local Progress = require(Shared.Logic.Progress)
local Snapshot = require(Shared.Logic.Snapshot)

export type Data = {
	coins: number,
	speed: number, -- speed collected from orbs (Logic/Progress)
	stage: number, -- their furthest stage (STAGES + 1 once the last wall is smashed)
	upgrades: { [string]: number },
	rebirths: number,
	passes: { [string]: boolean }, -- the passes they own (Config/Passes)
	boostUntil: number, -- os.time() their double-coins boost ends
	stats: { orbs: number, smashes: number, crashes: number, runs: number },
	daily: { last: number, streak: number }, -- the daily reward (Logic/Daily)
	receipts: { string }, -- the last purchases handled (so a receipt is never paid twice)
	guide: number, -- how far the first-minutes guide has got
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
local onPushed: { (Player, Data) -> () } = {}
local pushing: { [Player]: boolean } = {}

local function fresh(): Data
	return {
		coins = if TESTING then Game.STUDIO_COINS else 0,
		speed = 0,
		stage = 1,
		upgrades = {},
		rebirths = 0,
		passes = {},
		boostUntil = 0,
		stats = { orbs = 0, smashes = 0, crashes = 0, runs = 0 },
		daily = { last = 0, streak = 0 },
		receipts = {},
		guide = 0,
		lastSeen = os.time(),
	}
end

-- Fills in what an older save is missing (and drops anything the wrong shape)
local function reconcile(saved: any): Data
	local data = fresh()
	if type(saved) ~= "table" then
		return data
	end
	for k, default in data :: any do
		local v = saved[k]
		if type(v) == type(default) and type(v) ~= "table" then
			(data :: any)[k] = v
		end
	end
	local function numbers(from: any, into: any)
		if type(from) ~= "table" then
			return
		end
		for k, v in from do
			if type(k) == "string" and type(v) == "number" then
				into[k] = v
			end
		end
	end
	numbers(saved.upgrades, data.upgrades)
	numbers(saved.stats, data.stats)
	numbers(saved.daily, data.daily)
	if type(saved.passes) == "table" then
		for k, v in saved.passes do
			if type(k) == "string" and v == true then
				data.passes[k] = true
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
	data.stage = math.clamp(math.floor(data.stage), 1, Economy.STAGES + 1)
	return data
end

function DataService.onLoaded(fn: (Player, Data) -> ())
	table.insert(onLoaded, fn)
end

function DataService.onLeaving(fn: (Player) -> ())
	table.insert(onLeaving, fn)
end

-- Called each time their data has changed and been sent (the course uses it to set their walking speed)
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
			Net.event("Data"):FireClient(player, Snapshot.of(data, os.time()))
			-- (the player list: speed, stage, rebirths)
			if typeof(player) == "Instance" then
				local board = player:FindFirstChild("leaderstats")
				if board then
					local values = { Speed = math.min(2 ^ 52, Progress.stat(data)), Stage = math.min(data.stage, Economy.STAGES), Rebirths = data.rebirths }
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
		for _, name in { "Speed", "Stage", "Rebirths" } do
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
