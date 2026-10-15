--!strict
-- The client's copy of the player's data: the server's latest picture (Logic/Snapshot), and who wants to know.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Store = {}

Store.data = nil :: any
local listeners: { () -> () } = {}

function Store.onChanged(fn: () -> ())
	table.insert(listeners, fn)
	if Store.data then
		fn()
	end
end

function Store.init()
	Net.event("Data").OnClientEvent:Connect(function(snapshot)
		Store.data = snapshot
		for _, fn in listeners do
			fn()
		end
	end)
end

return Store
