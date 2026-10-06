-- Latest data from the server, with change signals for the UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared:WaitForChild("Config"):WaitForChild("Progression"))
local Net = require(Shared:WaitForChild("Net"))

local Store = {
	data = nil :: { [string]: any }?,
	dataTime = 0, -- os.clock() when the latest snapshot arrived
	currency = {
		coins = 0,
		gems = 0,
		power = 0,
		combo = 0,
		comboMult = 1,
		zoneId = nil :: number?,
		zoneProgress = 0,
		auto = false,
		boosts = {} :: { [string]: { mult: number, left: number } },
		rift = nil :: number?,
		questProgress = nil :: { daily: { number }, weekly: { number } }?,
	},
}

local dataChanged = Instance.new("BindableEvent")
local currencyChanged = Instance.new("BindableEvent")
Store.DataChanged = dataChanged.Event
Store.CurrencyChanged = currencyChanged.Event

function Store.init()
	Net.event("Data").OnClientEvent:Connect(function(snapshot)
		Store.data = snapshot
		Store.dataTime = os.clock()
		dataChanged:Fire() -- no argument: listeners read Store.data (a BindableEvent would copy the table per listener)
	end)
	Net.event("Currency").OnClientEvent:Connect(function(currency)
		Store.currency = currency
		currencyChanged:Fire()
	end)
end

-- Seconds until the next playtime gift (0 = ready), or nil when today's gifts are opened.
function Store.giftSecondsLeft(): number?
	local data = Store.data
	local state = data and data.playtime
	if not state then
		return nil
	end
	local count = #Progression.PLAYTIME_GIFTS
	if state.claimed >= count then
		return nil
	end
	local played = state.seconds + (os.clock() - Store.dataTime)
	return math.max(0, (state.claimed + 1) * Progression.GIFT_SECONDS - played)
end

-- Low-end mode: fewer effects and no creatures of other players.
function Store.lowEnd(): boolean
	local data = Store.data
	return data ~= nil and data.settings.lowEnd == true
end

function Store.isUnlocked(zoneId: number): boolean
	local data = Store.data
	return data ~= nil and data.unlockedZones[tostring(zoneId)] == true
end

return Store
