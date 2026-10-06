-- Live Events: an admin types "/live luck 3 30" and every server gets Luck x3 for 30 minutes.
-- Servers hear about it through MessagingService, and new servers read it from MemoryStore so they join
-- in. Clients read ReplicatedStorage attributes: LiveStat, LiveMult, LiveEnds (unix time).

local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LiveEvent = require(Shared.Logic.LiveEvent)

local GameService = require(script.Parent.GameService)

local LiveEventService = {}

local TOPIC = "LiveEvent"
local KEY = "current"

local map: MemoryStoreSortedMap? = nil

local function apply(live: LiveEvent.Live?, announce: boolean)
	if live and os.time() >= live.ends then
		live = nil
	end
	local wasRunning = GameService.live ~= nil
	GameService.live = live
	ReplicatedStorage:SetAttribute("LiveStat", if live then live.stat else nil)
	ReplicatedStorage:SetAttribute("LiveMult", if live then live.mult else nil)
	ReplicatedStorage:SetAttribute("LiveEnds", if live then live.ends else nil)
	if not announce then
		return
	end
	if live then
		local minutes = math.ceil((live.ends - os.time()) / 60)
		GameService.notifyAll(("🔴 LIVE EVENT! %s x%g for %d minutes!"):format(live.stat, live.mult, minutes), "rare")
	elseif wasRunning then
		GameService.notifyAll("The Live Event is over. Thanks for playing!", "info")
	end
end

local function isOwner(player: Player): boolean
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		return ok and rank >= 255
	end
	return game.CreatorId > 0 and player.UserId == game.CreatorId
end

local function start(player: Player, text: string)
	local isStudio = RunService:IsStudio()
	if not LiveEvent.isAdmin(player.UserId, isOwner(player), isStudio) then
		return
	end
	local command, why = LiveEvent.parse(text)
	if not command then
		GameService.notify(player, why or "Wrong command", "error")
		return
	end
	local live: LiveEvent.Live? = nil
	if not command.stop then
		live = {
			stat = command.stat :: string,
			mult = command.mult :: number,
			ends = os.time() + math.floor((command.minutes :: number) * 60),
		}
	end
	apply(live, true)
	-- Tell the other servers, and remember it for servers that start later
	if not isStudio then
		local payload: { [string]: any } = if live then table.clone(live) else { stop = true }
		payload.from = game.JobId -- this server already applied it
		pcall(function()
			MessagingService:PublishAsync(TOPIC, payload)
		end)
		if map then
			pcall(function()
				if live then
					(map :: MemoryStoreSortedMap):SetAsync(KEY, live, math.max(1, live.ends - os.time()))
				else
					(map :: MemoryStoreSortedMap):RemoveAsync(KEY)
				end
			end)
		end
	end
end

function LiveEventService.init()
	-- The chat command (only admins get a reply; everyone else's "/live" does nothing)
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local command = Instance.new("TextChatCommand")
		command.Name = "LiveCommand"
		command.PrimaryAlias = "/live"
		command.Parent = TextChatService
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				start(player, text)
			end
		end)
	else
		Players.PlayerAdded:Connect(function(player)
			player.Chatted:Connect(function(text)
				if string.sub(string.lower(text), 1, 5) == "/live" then
					start(player, text)
				end
			end)
		end)
	end

	if RunService:IsStudio() then
		return
	end
	pcall(function()
		map = MemoryStoreService:GetSortedMap("LiveEvent")
	end)
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local data = message.Data
			if type(data) == "table" and data.from == game.JobId then
				return
			end
			if type(data) == "table" and data.stop then
				apply(nil, true)
			elseif LiveEvent.valid(data) then
				apply(data, true)
			end
		end)
	end)
	-- A server that starts mid-event joins in
	task.spawn(function()
		if not map then
			return
		end
		local okGet, value = pcall(function()
			return (map :: MemoryStoreSortedMap):GetAsync(KEY)
		end)
		if okGet and LiveEvent.valid(value) then
			apply(value, false)
		end
	end)
	-- Clear it when the time is up
	task.spawn(function()
		while true do
			task.wait(5)
			local live = GameService.live
			if live and os.time() >= live.ends then
				apply(nil, true)
			end
		end
	end)
end

return LiveEventService
