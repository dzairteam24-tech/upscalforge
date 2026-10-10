--!strict
-- Each player's saved data: loaded when they join, saved every minute and when they leave. If the DataStore
-- can't be reached (a place that isn't published, Studio without API access), the player plays with fresh
-- data that isn't saved.
--
-- Gifts (DataService.gift) go from one player to another, in this server or any other, even while they're away:
-- what a Homesick creature sends home (Config/Raid), and a creature sent back home.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared.Config.Island)
local WildConfig = require(Shared.Config.Wild)

-- g: a snapped creature's grade (Config/Snap); h, hn: a Homesick creature's home and its name
export type Creature = { s: string, m: string, g: string?, h: number?, hn: string? }
export type Data = {
	coins: number,
	gems: number,
	eggs: { [string]: number }, -- egg tier -> how many the player holds
	creatures: { [string]: Creature }, -- creature id -> species and mutation
	placed: { string }, -- the creatures living on the island (they earn)
	incubators: number,
	incubating: { [string]: { tier: number, start: number, h: number?, hn: string? } }, -- incubator slot -> its egg and os.time() it went in (h, hn: a stolen egg's home)
	pens: number,
	shop: { window: number, bought: { [string]: number } }, -- eggs bought in the current restock window
	nextId: number,
	lastSeen: number,
	stats: { hatched: number, earned: number, stolen: number },
	speed: number, -- how fast the player runs (Config/Wild), trained on the treadmill
	treadmill: number, -- the treadmill's level
	firstPlayed: number, -- os.time() of their first visit (a new player's garden can't be robbed at first)
	food: { [string]: number }, -- food id -> how many the player holds (in their trough)
	fedUntil: number, -- os.time() the creatures are fed until (Config/Food)
	storage: number, -- the barn's level (Config/Island STORAGE)
	starter: boolean, -- whether they got their free first egg (IslandService)
	daily: { day: number, progress: { [string]: number }, claimed: boolean }, -- today's tasks (Logic/Daily)
}

local DataService = {}

local STORE_NAME = "CubelingsNest_v1"
local GIFTS_NAME = "CubelingsNest_gifts_v1"
local SAVE_EVERY = 60

local store: DataStore? = nil
local giftStore: DataStore? = nil
do
	local ok, result, gifts = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME), DataStoreService:GetDataStore(GIFTS_NAME)
	end)
	if ok then
		store = result
		giftStore = gifts
	else
		warn("[Data] No DataStore, playing without saving:", result)
	end
end

type Gift = { coins: number, creatures: { Creature } }
-- Gifts not yet delivered: user id -> gift (sent with the saves)
local outbox: { [number]: Gift } = {}
-- Called when a player gets a gift (a plain list, like onLoaded)
local onGift: { (Player, number, { Creature }) -> () } = {}

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
		creatures = {},
		placed = {},
		incubators = IslandConfig.INCUBATORS,
		incubating = {},
		pens = IslandConfig.PENS,
		shop = { window = -1, bought = {} },
		nextId = 1,
		lastSeen = 0,
		stats = { hatched = 0, earned = 0, stolen = 0 },
		speed = WildConfig.START_SPEED,
		treadmill = 1,
		firstPlayed = 0,
		food = {},
		fedUntil = 0,
		storage = 1,
		starter = false,
		daily = { day = -1, progress = {}, claimed = false },
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

local collectGifts: (Player) -> ()

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
		task.delay(5, collectGifts, player)
	end
end

function DataService.onGift(fn: (Player, number, { Creature }) -> ())
	table.insert(onGift, fn)
end

-- Gives a player coins and creatures (they arrive within a minute, wherever the player is)
function DataService.gift(userId: number, coins: number, creature: Creature?)
	local gift = outbox[userId] or { coins = 0, creatures = {} }
	outbox[userId] = gift
	gift.coins += coins
	if creature then
		table.insert(gift.creatures, creature)
	end
end

local function receive(player: Player, data: Data, gift: Gift)
	local coins = math.floor(gift.coins)
	data.coins += coins
	for _, creature in gift.creatures do
		local id = tostring(data.nextId)
		data.nextId += 1
		data.creatures[id] = { s = creature.s, m = creature.m } -- (home: not Homesick anymore)
		if #data.placed < data.pens then
			table.insert(data.placed, id)
		end
	end
	if coins > 0 or #gift.creatures > 0 then
		for _, fn in onGift do
			task.spawn(fn, player, coins, gift.creatures)
		end
	end
end

-- Sends the gifts out: straight to the players in this server, into the gift store for the others
local function sendGifts()
	local sending = outbox
	outbox = {}
	for userId, gift in sending do
		local player = Players:GetPlayerByUserId(userId)
		local data = player and loaded[player]
		if player and data then
			receive(player, data, gift)
		elseif giftStore then
			local ok = pcall(function()
				(giftStore :: DataStore):UpdateAsync("u" .. userId, function(old: any)
					local saved = if type(old) == "table" then old else { coins = 0, creatures = {} }
					saved.coins = (tonumber(saved.coins) or 0) + gift.coins
					saved.creatures = if type(saved.creatures) == "table" then saved.creatures else {}
					for _, creature in gift.creatures do
						table.insert(saved.creatures, creature)
					end
					return saved
				end)
			end)
			if not ok then
				DataService.gift(userId, gift.coins) -- try again next time
				for _, creature in gift.creatures do
					DataService.gift(userId, 0, creature)
				end
			end
		end
	end
end

-- Takes the gifts waiting for a player in the gift store
function collectGifts(player: Player)
	if not giftStore then
		return
	end
	local taken: any = nil
	local ok = pcall(function()
		(giftStore :: DataStore):UpdateAsync("u" .. player.UserId, function(old: any)
			taken = nil
			if type(old) ~= "table" or ((tonumber(old.coins) or 0) < 1 and (type(old.creatures) ~= "table" or #old.creatures == 0)) then
				return nil -- nothing waiting: no write
			end
			taken = old
			return { coins = 0, creatures = {} }
		end)
	end)
	local data = loaded[player]
	if ok and taken and data then
		local creatures = {}
		if type(taken.creatures) == "table" then
			for _, creature in taken.creatures do
				if type(creature) == "table" and type(creature.s) == "string" and type(creature.m) == "string" then
					table.insert(creatures, { s = creature.s, m = creature.m })
				end
			end
		end
		receive(player, data, { coins = tonumber(taken.coins) or 0, creatures = creatures })
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
		sendGifts()
		for player in loaded do
			DataService.save(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(SAVE_EVERY)
			sendGifts()
			for player in loaded do
				task.spawn(collectGifts, player)
				task.spawn(DataService.save, player)
			end
		end
	end)
end

return DataService
