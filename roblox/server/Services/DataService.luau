-- Loads and saves player data with a session lock, so two servers never write the same player at once.
-- In Studio without API access it falls back to in-memory data and never saves.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Types = require(Shared.Logic.Types)
local Signal = require(Shared.Signal)

type PlayerData = Types.PlayerData

type Profile = {
	data: PlayerData,
	canSave: boolean,
	saving: boolean,
	released: boolean,
}

local DataService = {}

local profiles: { [Player]: Profile } = {}
-- Fired with the live data table (not a copy).
DataService.Loaded = Signal.new() :: Signal.Signal<Player, PlayerData>

-- Called right before a leaving player's data is saved for the last time.
local beforeRelease: { (Player, PlayerData) -> () } = {}
function DataService.onBeforeRelease(fn: (Player, PlayerData) -> ())
	table.insert(beforeRelease, fn)
end

local store: DataStore? = nil
local storeAvailable = true
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Constants.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		storeAvailable = false
		warn("[Data] DataStore unavailable, using temporary data:", result)
	end
end

local function template(): PlayerData
	return {
		version = 1,
		coins = 0,
		gems = 0,
		pets = {},
		equipped = {},
		unlockedZones = { ["0"] = true, ["1"] = true },
		zoneProgress = {},
		upgrades = {},
		stats = { hatches = 0, coinsEarned = 0, trades = 0 },
		flags = {},
		purchases = {},
		titles = {},
		tradeHistory = {},
		settings = { allowTrades = true, autoEquipBest = true, lowEnd = false, sfx = true, music = true },
		lastSeen = 0,
		lastPower = 0,
		items = {},
		boosts = {},
		daily = { streak = 0, lastDay = -1 },
		quests = { day = -1, week = -1, daily = {}, weekly = {} },
		pass = { season = 0, xp = 0, premium = false, claimedFree = {}, claimedPremium = {} },
		guardians = {},
		trails = {},
		cartridges = {},
		reloads = 0,
		expeditions = {},
		ads = { day = 0, counts = {}, cooldowns = {} },
		playtime = { day = 0, seconds = 0, claimed = 0 },
		achievements = {},
		index = {},
		tutorial = 1,
		tickets = 0,
		wheel = { lastFree = -1 },
		rides = {},
		club = { lastDay = -1 },
	}
end

-- Adds keys that are missing in old saves without touching existing values.
local function reconcile(target: { [any]: any }, defaults: { [any]: any })
	for key, value in defaults do
		if target[key] == nil then
			target[key] = if type(value) == "table" then table.clone(value) else value
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			reconcile(target[key], value)
		end
	end
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function lockIsFresh(lock: any): boolean
	return type(lock) == "table" and type(lock.time) == "number" and os.time() - lock.time < Constants.SESSION_LOCK_SECONDS
end

-- Returns data and whether it may be saved.
local function loadFromStore(player: Player): (PlayerData?, boolean)
	if not store or not storeAvailable then
		return template(), false
	end
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	for attempt = 1, 6 do
		local lockedByOther = false
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key(player), function(saved: any)
				saved = saved or { data = template() }
				if saved.lock and lockIsFresh(saved.lock) and saved.lock.jobId ~= jobId then
					lockedByOther = true
					return nil -- don't write
				end
				saved.lock = { jobId = jobId, time = os.time() }
				return saved
			end)
		end)
		if not ok then
			local message = tostring(result)
			if string.find(message, "StudioAccessToApisNotAllowed") or string.find(message, "403") then
				warn("[Data] Enable 'Studio Access to API Services' to save. Using temporary data.")
				storeAvailable = false
				return template(), false
			end
			warn(("[Data] Load attempt %d failed for %s: %s"):format(attempt, player.Name, message))
		elseif lockedByOther then
			warn(("[Data] %s is still saving in another server (attempt %d)"):format(player.Name, attempt))
		elseif result then
			local data = result.data
			reconcile(data, template())
			return data, true
		end
		if not player.Parent then
			return nil, false
		end
		task.wait(attempt == 6 and 0 or 3)
	end
	return nil, false
end

function DataService.save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile or not profile.canSave or not store then
		return false
	end
	if profile.saving and not release then
		return false
	end
	profile.saving = true
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	profile.data.lastSeen = os.time()
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(player), function(saved: any)
			saved = saved or {}
			if saved.lock and saved.lock.jobId ~= jobId and lockIsFresh(saved.lock) then
				return nil -- another server owns this player now
			end
			saved.data = profile.data
			saved.lock = if release then nil else { jobId = jobId, time = os.time() }
			return saved
		end)
	end)
	profile.saving = false
	if not ok then
		warn(("[Data] Save failed for %s: %s"):format(player.Name, tostring(err)))
	end
	return ok
end

function DataService.get(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.data else nil
end

-- False when data is temporary (Studio without API access), so nothing will be written.
function DataService.canSave(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.canSave
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

local function onPlayerAdded(player: Player)
	local data, canSave = loadFromStore(player)
	if not player.Parent then
		if data and canSave then
			profiles[player] = { data = data, canSave = canSave, saving = false, released = false }
			DataService.save(player, true)
			profiles[player] = nil
		end
		return
	end
	if not data then
		player:Kick("We couldn't load your data. Please rejoin in a minute.")
		return
	end
	profiles[player] = { data = data, canSave = canSave, saving = false, released = false }
	DataService.Loaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	for _, fn in beforeRelease do
		local ok, err = pcall(fn, player, profile.data)
		if not ok then
			warn("[Data] beforeRelease error", err)
		end
	end
	DataService.save(player, true)
	profile.released = true
	profiles[player] = nil
end

function DataService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(Constants.AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(DataService.save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not storeAvailable then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.save(player, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
