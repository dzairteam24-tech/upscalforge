-- Latest data from the server, with change signals for the UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Store = {
	data = nil :: { [string]: any }?,
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
	},
}

local dataChanged = Instance.new("BindableEvent")
local currencyChanged = Instance.new("BindableEvent")
Store.DataChanged = dataChanged.Event
Store.CurrencyChanged = currencyChanged.Event

function Store.init()
	Net.event("Data").OnClientEvent:Connect(function(snapshot)
		Store.data = snapshot
		dataChanged:Fire(snapshot)
	end)
	Net.event("Currency").OnClientEvent:Connect(function(currency)
		Store.currency = currency
		currencyChanged:Fire(currency)
	end)
end

function Store.isUnlocked(zoneId: number): boolean
	local data = Store.data
	return data ~= nil and data.unlockedZones[tostring(zoneId)] == true
end

return Store
