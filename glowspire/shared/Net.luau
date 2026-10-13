--!strict
-- Remote names. The server creates them, the client waits for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"Finish", -- client -> server: (preset key, tap times): a run that just ended
	"Result", -- server -> client: (layers, perfects, tier or nil, best layers)
}

local Net = {}

local function folder(): Folder
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
		if not f then
			local made = Instance.new("Folder")
			made.Name = "Remotes"
			for _, name in EVENTS do
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = made
			end
			made.Parent = ReplicatedStorage
			f = made
		end
		return f :: Folder
	end
	return ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), "Unknown remote " .. name)
	return folder():WaitForChild(name) :: RemoteEvent
end

return Net
