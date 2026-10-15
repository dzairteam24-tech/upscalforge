--!strict
-- Remote names in one place. The server creates them, the client waits for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- client -> server
	"RunStart", -- (stage): they start a stage from its beginning (its orbs are back)
	"Collect", -- (stage, index): picked up an orb
	"Smash", -- (stage): reached the wall of their furthest stage
	"Finish", -- (stage): ran through a stage they had already smashed
	"Crash", -- (stage, kind): hit an obstacle (just counted)
	"Buy", -- (upgrade key): with coins
	"BuyRobux", -- ("pass" or "product", key): the Robux shop (RobuxService)
	"Rebirth",
	"Daily", -- claim today's reward
	"Restart", -- go back to the start of their furthest stage
	"GuideDone", -- (step): the first-minutes guide has shown this far
	-- server -> client
	"Data", -- (snapshot: Logic/Snapshot)
	"Notify", -- (text, kind: "info", "good", "bad", "gold")
	"Smashed", -- (stage, coins): the wall broke
	"Teleported", -- (stage): the server moved them to the start of a stage
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
