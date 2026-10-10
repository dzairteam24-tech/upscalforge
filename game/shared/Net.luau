--!strict
-- Remote names in one place. The server creates them, the client waits for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- client -> server
	"BuyEgg", -- (tier)
	"SellCreature", -- (id)
	"PlaceCreature", -- (id)
	"TakeCreature", -- (id)
	"UseIncubator", -- (slot)
	"BuyIncubator",
	"BuyPen",
	"BuyStorage",
	"BuyFood", -- (food id)
	"Feed",
	"Travel", -- ("home" or "wild")
	"Snap", -- (id): it and matching creatures snap into one (Config/Snap)
	"UpgradeBat", -- at the Gear Shop (Config/Gear)
	"BuyTrap",
	"ClaimDaily", -- the egg for doing all of today's tasks
	"Sprint", -- (on)
	"Seat", -- (seat name, or "" to stand): the floating seat the player rides (SeatModel)
	-- server -> client
	"Data", -- (snapshot)
	"Notify", -- (text, kind)
	"Hatched", -- (creature id, species, mutation), or (id, full name, "Snap") for a snapped one
	"SpeedUp", -- (gain): a step on the treadmill
	"Bump", -- (position, kind: "Hit" or "Trap"): a bat hit a carrier, or a trap caught one
}

local FOLDER = "Remotes"

local Net = {}

local folder: Folder? = nil

local function getFolder(): Folder
	local cached = folder
	if cached then
		return cached
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER)
		local f: Folder = if existing and existing:IsA("Folder") then existing else Instance.new("Folder")
		f.Name = FOLDER
		for _, name in EVENTS do
			if not f:FindFirstChild(name) then
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = f
			end
		end
		f.Parent = ReplicatedStorage
		folder = f
		return f
	end
	local f = ReplicatedStorage:WaitForChild(FOLDER) :: Folder
	folder = f
	return f
end

function Net.event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), "Unknown remote " .. name)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

-- Creates every remote. Call once on the server before players join.
function Net.init()
	getFolder()
end

return Net
