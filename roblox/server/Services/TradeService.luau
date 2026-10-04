-- Player-to-player trading of creatures.
-- Flow: request -> accept -> both pick creatures -> Ready (locked 3s after any change) -> Confirm -> swap.
-- The swap re-checks ownership, locks and storage on the server, then saves both players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local TradeLogic = require(Shared.Logic.TradeLogic)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local PetService = require(script.Parent.PetService)

local TradeService = {}

local TradeIncoming = Net.event("TradeIncoming")
local TradeStateRemote = Net.event("TradeState")
local TradeClosed = Net.event("TradeClosed")

-- requests[target][from] = expiry time
local requests: { [number]: { [number]: number } } = {}
local sessions: { [number]: TradeLogic.Session } = {}

local function playerById(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

function TradeService.isTrading(player: Player): boolean
	return sessions[player.UserId] ~= nil
end

local function petsView(data: any, ids: { string }): { [string]: any }
	local view = {}
	for _, petId in ids do
		local pet = data and data.pets[petId]
		if pet then
			view[petId] = { s = pet.s, v = pet.v, z = pet.z }
		end
	end
	return view
end

local function push(session: TradeLogic.Session)
	local now = os.clock()
	for _, userId in { session.a, session.b } do
		local player = playerById(userId)
		local otherId = TradeLogic.other(session, userId)
		local other = playerById(otherId)
		if player and other then
			TradeStateRemote:FireClient(player, {
				otherName = other.DisplayName,
				stage = session.stage,
				lockLeft = math.max(0, session.lockUntil - now),
				myReady = session.ready[userId],
				theirReady = session.ready[otherId],
				myConfirmed = session.confirmed[userId],
				theirConfirmed = session.confirmed[otherId],
				mine = petsView(DataService.get(player), session.offers[userId]),
				theirs = petsView(DataService.get(other), session.offers[otherId]),
				version = session.version,
			})
		end
	end
end

local function close(session: TradeLogic.Session, reason: string)
	if session.stage ~= "Done" then
		session.stage = "Cancelled"
	end
	for _, userId in { session.a, session.b } do
		if sessions[userId] == session then
			sessions[userId] = nil
		end
		local player = playerById(userId)
		if player then
			TradeClosed:FireClient(player, reason)
		end
	end
end

local function sideFor(player: Player): TradeLogic.Side?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	return { pets = data.pets, equipped = data.equipped, capacity = GameService.capacity(player) }
end

local function record(player: Player, otherName: string, gave: { any }, got: { any })
	local data = DataService.get(player)
	if not data then
		return
	end
	table.insert(data.tradeHistory, 1, { t = os.time(), with = otherName, gave = gave, got = got })
	while #data.tradeHistory > Constants.TRADE_HISTORY_SIZE do
		table.remove(data.tradeHistory)
	end
	data.stats.trades = (data.stats.trades or 0) + 1
end

local function execute(session: TradeLogic.Session)
	local playerA, playerB = playerById(session.a), playerById(session.b)
	if not playerA or not playerB then
		close(session, "The other player left")
		return
	end
	local sideA, sideB = sideFor(playerA), sideFor(playerB)
	if not sideA or not sideB then
		close(session, "Data not loaded")
		return
	end
	local ok, err = TradeLogic.validate(session, sideA, sideB)
	if not ok then
		close(session, err or "Trade failed")
		return
	end
	local movedA, movedB = TradeLogic.execute(session, sideA, sideB)
	record(playerA, playerB.DisplayName, movedA, movedB)
	record(playerB, playerA.DisplayName, movedB, movedA)
	GameService.refresh(playerA)
	GameService.refresh(playerB)
	task.spawn(DataService.save, playerA, false)
	task.spawn(DataService.save, playerB, false)
	GameService.notify(playerA, "Trade complete!", "success")
	GameService.notify(playerB, "Trade complete!", "success")
	close(session, "Trade complete")
end

local function onRequest(player: Player, targetUserId: any)
	if type(targetUserId) ~= "number" or targetUserId == player.UserId then
		return
	end
	local target = playerById(targetUserId)
	local data = DataService.get(player)
	local targetData = target and DataService.get(target)
	if not target or not data or not targetData then
		return
	end
	if sessions[player.UserId] or sessions[targetUserId] then
		GameService.notify(player, "One of you is already trading", "error")
		return
	end
	if not targetData.settings.allowTrades then
		GameService.notify(player, target.DisplayName .. " has trading turned off", "error")
		return
	end
	local pending = requests[targetUserId] or {}
	requests[targetUserId] = pending
	if pending[player.UserId] and pending[player.UserId] > os.clock() then
		GameService.notify(player, "Request already sent", "error")
		return
	end
	pending[player.UserId] = os.clock() + Constants.TRADE_REQUEST_TIMEOUT
	TradeIncoming:FireClient(target, player.UserId, player.DisplayName)
	GameService.notify(player, "Trade request sent to " .. target.DisplayName)
end

local function onRespond(player: Player, fromUserId: any, accept: any)
	if type(fromUserId) ~= "number" or type(accept) ~= "boolean" then
		return
	end
	local pending = requests[player.UserId]
	local expiry = pending and pending[fromUserId]
	if pending then
		pending[fromUserId] = nil
	end
	local from = playerById(fromUserId)
	if not expiry or expiry < os.clock() or not from then
		GameService.notify(player, "That request expired", "error")
		return
	end
	if not accept then
		GameService.notify(from, player.DisplayName .. " declined your trade", "error")
		return
	end
	if sessions[player.UserId] or sessions[fromUserId] then
		GameService.notify(player, "One of you is already trading", "error")
		return
	end
	local session = TradeLogic.new(fromUserId, player.UserId, os.clock())
	sessions[fromUserId] = session
	sessions[player.UserId] = session
	push(session)
end

local function withSession(player: Player, fn: (TradeLogic.Session) -> ())
	local session = sessions[player.UserId]
	if session then
		fn(session)
	end
end

function TradeService.init()
	PetService.isTrading = TradeService.isTrading

	Net.event("TradeRequest").OnServerEvent:Connect(onRequest)
	Net.event("TradeRespond").OnServerEvent:Connect(onRespond)

	Net.event("TradeOffer").OnServerEvent:Connect(function(player, petIds)
		if type(petIds) ~= "table" then
			return
		end
		withSession(player, function(session)
			local data = DataService.get(player)
			local clean = {}
			for _, petId in petIds do
				local pet = data and type(petId) == "string" and data.pets[petId]
				if pet and not pet.lk then
					table.insert(clean, petId)
				end
			end
			local ok, err = TradeLogic.setOffer(session, player.UserId, clean, os.clock())
			if not ok and err then
				GameService.notify(player, err, "error")
			end
			push(session)
			-- Let both clients know when the Ready button unlocks
			task.delay(Constants.TRADE_LOCK_SECONDS + 0.05, function()
				if sessions[player.UserId] == session then
					push(session)
				end
			end)
		end)
	end)

	Net.event("TradeReady").OnServerEvent:Connect(function(player)
		withSession(player, function(session)
			local ok, err = TradeLogic.setReady(session, player.UserId, os.clock())
			if not ok and err then
				GameService.notify(player, err, "error")
			end
			push(session)
		end)
	end)

	Net.event("TradeConfirm").OnServerEvent:Connect(function(player)
		withSession(player, function(session)
			local both, err = TradeLogic.confirm(session, player.UserId)
			if err then
				GameService.notify(player, err, "error")
			end
			if both then
				execute(session)
			else
				push(session)
			end
		end)
	end)

	Net.event("TradeCancel").OnServerEvent:Connect(function(player)
		withSession(player, function(session)
			close(session, player.DisplayName .. " cancelled the trade")
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		requests[player.UserId] = nil
		local session = sessions[player.UserId]
		if session then
			close(session, "The other player left")
		end
	end)
end

return TradeService
