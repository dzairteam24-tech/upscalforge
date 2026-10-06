-- Clans across servers. Clan documents live in a DataStore; points earned by members are added up
-- in memory and written once a minute. The weekly ranking uses one OrderedDataStore per week, and
-- members of the top clans get their reward the next time they join after the week ends.
-- Names and tags are shown to everyone, so they go through Roblox's text filter.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClanConfig = require(Shared.Config.Clans)
local Clans = require(Shared.Logic.Clans)
local Format = require(Shared.Logic.Format)
local Unlocks = require(Shared.Logic.Unlocks)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData
type Clan = Clans.Clan

local ClanService = {}

local FLUSH_EVERY = 60
local CACHE_SECONDS = 30
local TOP_EVERY = 120
local CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

local store: DataStore? = nil
local cache: { [string]: { clan: Clan?, at: number } } = {}
local pending: { [string]: { [string]: number } } = {}
local top: { { id: string, name: string, tag: string, points: number } } = {}
local rng = Random.new()

local function key(id: string): string
	return "clan_" .. id
end

local function weekBoard(week: number): OrderedDataStore?
	local ok, board = pcall(function()
		return DataStoreService:GetOrderedDataStore("ClanPoints_" .. week)
	end)
	return if ok then board else nil
end

-- Returns the clan (nil when it doesn't exist) and whether the read worked.
local function load(id: string, fresh: boolean?): (Clan?, boolean)
	local cached = cache[id]
	if cached and not fresh and os.clock() - cached.at < CACHE_SECONDS then
		return cached.clan, true
	end
	if not store then
		return nil, false
	end
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync(key(id))
	end)
	if not ok then
		return if cached then cached.clan else nil, false
	end
	local clan = if type(result) == "table" then result :: Clan else nil
	cache[id] = { clan = clan, at = os.clock() }
	return clan, true
end

-- Runs `change` on the stored clan; it returns false to cancel. Returns the saved clan or nil.
local function update(id: string, change: (Clan?) -> (Clan?, boolean)): Clan?
	if not store then
		return nil
	end
	local saved: Clan? = nil
	local kept = false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(id), function(old)
			local clan, keep = change(old)
			kept = keep
			if not keep then
				return nil
			end
			saved = clan
			return clan
		end)
	end)
	if not ok then
		warn("[Clans] update failed", err)
		return nil
	end
	-- A cancelled change (full clan, second kick today...) leaves the cache as it was
	if kept then
		cache[id] = { clan = saved, at = os.clock() }
	end
	return saved
end

local function filter(player: Player, text: string): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or result ~= text then
		return nil
	end
	return result
end

local function setTag(player: Player, clan: Clan?)
	local runtime = State.get(player)
	if runtime then
		runtime.clanTag = if clan then clan.tag else nil
		GameService.refreshTitles(player)
	end
end

-- What the client shows in the Clan window.
local function send(player: Player, message: string?)
	local data = DataService.get(player)
	if not data then
		return
	end
	local clan = if data.clan.id ~= "" then (load(data.clan.id)) else nil
	-- Removed by the owner while away
	if clan and not clan.members[tostring(player.UserId)] then
		data.clan.id = ""
		GameService.markDirty(player)
		setTag(player, nil)
		clan = nil
	end
	local info = nil
	if clan then
		local members = {}
		for userId, member in clan.members do
			table.insert(members, { id = tonumber(userId), name = member.name, points = member.points })
		end
		table.sort(members, function(a, b)
			return a.points > b.points
		end)
		local rank = nil
		for i, entry in top do
			if entry.id == clan.id then
				rank = i
			end
		end
		info = {
			id = clan.id,
			name = clan.name,
			tag = clan.tag,
			owner = clan.owner,
			points = if clan.week == Clans.week(os.time()) then clan.points else 0,
			members = members,
			rank = rank,
		}
	end
	Net.event("ClanData"):FireClient(player, info, top, store ~= nil, message)
end

local function canUse(player: Player, data: PlayerData): boolean
	if not store then
		GameService.notify(player, "Clans turn on when the game is published", "error")
		return false
	end
	if not Unlocks.has(data, "Clans") then
		GameService.notify(player, Unlocks.lockedText("Clans"), "error")
		return false
	end
	return true
end

local function create(player: Player, name: any, tag: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(name) ~= "string" or type(tag) ~= "string" then
		return
	end
	if not State.throttle(runtime, "Clan", 3) or not canUse(player, data) then
		return
	end
	if data.clan.id ~= "" then
		GameService.notify(player, "Leave your clan first", "error")
		return
	end
	name = string.match(name, "^%s*(.-)%s*$") or ""
	tag = string.upper(tag)
	local okName, whyName = Clans.checkName(name)
	local okTag, whyTag = Clans.checkTag(tag)
	if not okName or not okTag then
		GameService.notify(player, whyName or whyTag or "Check the name and tag", "error")
		return
	end
	if data.gems < ClanConfig.CREATE_COST then
		GameService.notify(player, ("A clan costs 💎 %d"):format(ClanConfig.CREATE_COST), "error")
		return
	end
	if not filter(player, name) or not filter(player, tag) then
		GameService.notify(player, "That name or tag isn't allowed", "error")
		return
	end
	for _ = 1, 5 do
		local code = ""
		for _ = 1, 6 do
			local i = rng:NextInteger(1, #CODE_CHARS)
			code ..= string.sub(CODE_CHARS, i, i)
		end
		local clan = update(code, function(old)
			if old then
				return nil, false -- code taken, try another
			end
			return Clans.new(code, name, tag, player.UserId, player.DisplayName, os.time()), true
		end)
		if clan then
			data.gems -= ClanConfig.CREATE_COST
			data.clan.id = code
			GameService.markDirty(player)
			setTag(player, clan)
			send(player, ("Clan created! Share the code %s with friends."):format(code))
			return
		end
	end
	GameService.notify(player, "Couldn't create the clan, try again", "error")
end

local function join(player: Player, code: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or type(code) ~= "string" then
		return
	end
	if not State.throttle(runtime, "Clan", 3) or not canUse(player, data) then
		return
	end
	if data.clan.id ~= "" then
		GameService.notify(player, "Leave your clan first", "error")
		return
	end
	code = string.upper((string.gsub(code, "%s", "")))
	if not string.match(code, "^%w+$") or #code > 12 then
		GameService.notify(player, "That code doesn't look right", "error")
		return
	end
	local why: string? = "No clan with that code"
	local clan = update(code, function(old)
		if not old then
			return nil, false
		end
		local ok, err = Clans.addMember(old, player.UserId, player.DisplayName, os.time())
		why = err
		return old, ok
	end)
	if not clan then
		GameService.notify(player, why or "Couldn't join", "error")
		return
	end
	data.clan.id = code
	GameService.markDirty(player)
	setTag(player, clan)
	send(player, ("Welcome to %s!"):format(clan.name))
end

local function leave(player: Player)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or data.clan.id == "" or not State.throttle(runtime, "Clan", 3) then
		return
	end
	local id = data.clan.id
	local empty = false
	update(id, function(old)
		if not old then
			return nil, false
		end
		empty = not Clans.removeMember(old, player.UserId)
		return old, true
	end)
	if empty and store then
		pcall(function()
			(store :: DataStore):RemoveAsync(key(id))
		end)
		local board = weekBoard(Clans.week(os.time()))
		if board then
			pcall(function()
				(board :: OrderedDataStore):RemoveAsync(id)
			end)
		end
		cache[id] = nil
	end
	data.clan.id = ""
	GameService.markDirty(player)
	setTag(player, nil)
	send(player, "You left the clan")
end

local function kick(player: Player, targetId: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or data.clan.id == "" or type(targetId) ~= "number" then
		return
	end
	if not State.throttle(runtime, "Clan", 3) then
		return
	end
	local why: string? = nil
	local clan = update(data.clan.id, function(old)
		if not old then
			return nil, false
		end
		local ok, err = Clans.kick(old, player.UserId, targetId, os.time())
		why = err
		return old, ok
	end)
	if not clan then
		GameService.notify(player, why or "Couldn't remove that member", "error")
		return
	end
	-- If they're in this server, update them now; others find out when they next load
	local target = Players:GetPlayerByUserId(targetId)
	local targetData = if target then DataService.get(target) else nil
	if target and targetData and targetData.clan.id == clan.id then
		targetData.clan.id = ""
		GameService.markDirty(target)
		setTag(target, nil)
		send(target, "You were removed from the clan")
	end
	send(player, "Member removed")
end

local function onProgress(player: Player, event: string, amount: number)
	local data = DataService.get(player)
	if not data or data.clan.id == "" then
		return
	end
	local points = Clans.pointsFor(event, amount)
	if points <= 0 then
		return
	end
	local clanPending = pending[data.clan.id] or {}
	pending[data.clan.id] = clanPending
	local userId = tostring(player.UserId)
	clanPending[userId] = (clanPending[userId] or 0) + points
end

local function flush()
	local batch = pending
	pending = {}
	local now = os.time()
	local board = weekBoard(Clans.week(now))
	for id, contributions in batch do
		local clan = update(id, function(old)
			if not old then
				return nil, false
			end
			Clans.addPoints(old, contributions, now)
			return old, true
		end)
		if clan and board then
			pcall(function()
				(board :: OrderedDataStore):SetAsync(id, clan.points)
			end)
		end
	end
end

local function refreshTop()
	local board = weekBoard(Clans.week(os.time()))
	if not board then
		return
	end
	local ok, pages = pcall(function()
		return (board :: OrderedDataStore):GetSortedAsync(false, 10)
	end)
	if not ok then
		return
	end
	local list = {}
	for _, entry in (pages :: DataStorePages):GetCurrentPage() do
		local clan = load(entry.key)
		if clan then
			table.insert(list, { id = clan.id, name = clan.name, tag = clan.tag, points = entry.value })
		end
	end
	top = list
end

-- Last week's reward, once, the next time a member joins.
local function weeklyReward(player: Player, data: PlayerData)
	local lastWeek = Clans.week(os.time()) - 1
	if data.clan.id == "" or data.clan.rewardWeek >= lastWeek then
		return
	end
	data.clan.rewardWeek = lastWeek
	local board = weekBoard(lastWeek)
	if not board then
		return
	end
	local ok, pages = pcall(function()
		return (board :: OrderedDataStore):GetSortedAsync(false, 10)
	end)
	if not ok then
		return
	end
	for rank, entry in (pages :: DataStorePages):GetCurrentPage() do
		if entry.key == data.clan.id then
			local gems = Clans.rewardFor(rank)
			data.gems += gems
			data.titles[ClanConfig.REWARD_TITLE] = true
			GameService.notify(player, ("🛡️ Your clan was #%d last week! +💎 %s and the Top Clan title"):format(rank, Format.abbrev(gems)), "rare")
			GameService.markDirty(player)
		end
	end
end

function ClanService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("Clans")
	end)
	store = if ok then result else nil

	GameService.Progress:Connect(onProgress)
	DataService.Loaded:Connect(function(player: Player, data: PlayerData)
		if data.clan.id == "" then
			return
		end
		local clan, readOk = load(data.clan.id, true)
		-- Removed from a clan that no longer exists, or kicked while away (not when the read failed)
		if store and readOk and (clan == nil or not (clan :: Clan).members[tostring(player.UserId)]) then
			data.clan.id = ""
			return
		end
		setTag(player, clan)
		weeklyReward(player, data)
	end)
	Net.event("ClanCreate").OnServerEvent:Connect(create)
	Net.event("ClanJoin").OnServerEvent:Connect(join)
	Net.event("ClanLeave").OnServerEvent:Connect(leave)
	Net.event("ClanKick").OnServerEvent:Connect(kick)
	Net.event("ClanRequest").OnServerEvent:Connect(function(player)
		local runtime = State.get(player)
		if runtime and State.throttle(runtime, "ClanRequest", 2) then
			send(player)
		end
	end)
	game:BindToClose(function()
		pcall(flush)
	end)

	task.spawn(function()
		local lastTop = -math.huge
		while true do
			task.wait(FLUSH_EVERY)
			pcall(flush)
			if os.clock() - lastTop >= TOP_EVERY then
				lastTop = os.clock()
				pcall(refreshTop)
			end
		end
	end)
	task.defer(function()
		pcall(refreshTop)
	end)
end

return ClanService
