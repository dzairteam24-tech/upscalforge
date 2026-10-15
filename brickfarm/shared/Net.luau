--!strict
-- Remote names in one place. The server creates them, the client waits for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- client -> server
	"Tile", -- (tileIndex, cropKey?): plant the crop on an empty tile of their farm, or harvest a ready one
	"BuySeeds", -- (cropKey, amount)
	"Sell", -- (cropKey or "all"): sell from the barn (they must be at it)
	"Expand", -- buy the next tile of land
	"GuideDone", -- (step): the first-minutes guide has shown this far
	-- server -> client
	"Data", -- (snapshot: Logic/Snapshot)
	"Notify", -- (text, kind: "info", "good", "bad", "gold")
	"Harvested", -- (tileIndex, cropKey, amount, xp): for the effect
	"LevelUp", -- (level, unlocked crop keys)
	"OpenBarn", -- the barn's prompt was used
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
