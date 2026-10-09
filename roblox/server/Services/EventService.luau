-- Limited-time events (Config/Events): tokens from breaking sources, an event shop of looks and items,
-- and a game-wide bonus that GameService reads through GameService.event().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Items = require(Shared.Config.Items)
local Events = require(Shared.Logic.Events)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local BreakableService = require(script.Parent.BreakableService)
local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData

local EventService = {}

local rng = Random.new()

local function stateFor(data: PlayerData, eventId: string): Events.EventState
	local state = data.events[eventId]
	if not state then
		state = { tokens = 0, bought = {} }
		data.events[eventId] = state
	end
	return state
end

local function onBroken(source: BreakableService.Source, contributors: { [Player]: number })
	local event = GameService.event()
	if not event then
		return
	end
	local kind = if source.special then source.special.type else source.kind.id
	for player, share in contributors do
		local data = DataService.get(player)
		if data and share > 0 then
			local tokens = Events.tokensFor(event, kind, function()
				return rng:NextNumber()
			end)
			if tokens > 0 then
				stateFor(data, event.id).tokens += tokens
				GameService.markDirty(player)
			end
		end
	end
end

local function buy(player: Player, offerId: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	local event = GameService.event()
	if not data or not runtime or not event or type(offerId) ~= "string" then
		return
	end
	if not State.throttle(runtime, "EventBuy", 0.3) then
		return
	end
	local state = stateFor(data, event.id)
	local ok, err = Events.canBuy(event, state, offerId)
	if not ok then
		GameService.notify(player, err or "Can't buy that", "error")
		return
	end
	local offer = Events.buy(event, state, offerId)
	local got = ""
	if offer.title then
		data.titles[offer.title] = true
		local title = Cosmetics.titleById[offer.title]
		got = "Title: " .. (if title then title.text else offer.title)
	elseif offer.trail then
		data.trails[offer.trail] = true
		local trail = Cosmetics.trailById[offer.trail]
		got = if trail then trail.name else offer.trail
	elseif offer.ride then
		data.rides[offer.ride] = true
		local ride = Cosmetics.rideById[offer.ride]
		got = "Ride: " .. (if ride then ride.name else offer.ride)
	elseif offer.itemId then
		GameService.giveItem(player, offer.itemId, offer.amount or 1, false)
		got = Items.byId[offer.itemId].name
	end
	GameService.notify(player, ("%s %s: %s!"):format(event.tokenIcon, event.name, got), "success")
	GameService.markDirty(player)
end

function EventService.init()
	BreakableService.Broken:Connect(onBroken)
	-- Each haul the team brings in counts like a coin pile broken
	GameService.Gathered:Connect(function(player)
		local event = GameService.event()
		local data = DataService.get(player)
		if not event or not data then
			return
		end
		local tokens = Events.tokensFor(event, "Pile", function()
			return rng:NextNumber()
		end)
		if tokens > 0 then
			stateFor(data, event.id).tokens += tokens
			GameService.markDirty(player)
		end
	end)
	Net.event("EventBuy").OnServerEvent:Connect(buy)
	-- Tell clients which event runs (so a Studio test event shows too)
	task.spawn(function()
		local announced: string? = nil
		while true do
			local event = GameService.event()
			local id = if event then event.id else ""
			ReplicatedStorage:SetAttribute("EventId", id)
			if event and announced ~= event.id then
				announced = event.id
				GameService.notifyAll(("%s %s is on! Collect %s for the event shop."):format(event.tokenIcon, event.name, event.token), "rare")
			end
			task.wait(30)
		end
	end)
end

return EventService
