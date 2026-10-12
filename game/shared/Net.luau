--!strict
-- Remote names in one place. The server creates them, the client waits for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- client -> server
	"SellCreature", -- (creature id): at the Sell stall
	"SellEgg", -- (egg key or tier, golden, all): one egg of the kind the player holds, or all of them
	"PlaceCreature", -- (id)
	"Store", -- (what: "egg", "golden" or "creature", egg key or id, all?): into the barn, in their own garden
	"Withdraw", -- (what, egg key or id, all?): out of the barn, in their own garden
	"TakeCreature", -- (id)
	"UseIncubator", -- (slot)
	"BuyIncubator",
	"SetEgg", -- (egg key or tier, golden): one the player holds, down on the grass in front of them
	"BuyPen",
	"BuyStorage",
	"BuyPasture",
	"BuyFood", -- (food id)
	"Feed",
	"Snap", -- (id): it and matching creatures snap into one (Config/Snap)
	"ClaimDaily", -- the egg for doing all of today's tasks
	"ClaimIndex", -- (egg tier): a complete Index page's reward
	"Mutate", -- (creature id): its mutation one step up at the Mutation Machine
	"BuyTrail", -- (trail id): buy it, or wear it if it's theirs (TrailService)
	"BuyRobux", -- ("FastHatch" or "HatchAll"): the Robux shop (RobuxService)
	"Sprint", -- (on)
	-- server -> client
	"Data", -- (snapshot)
	"Notify", -- (text, kind)
	"Hatched", -- (creature id, species, mutation, snap grade or nil)
	"SpeedUp", -- (gain): a step on the treadmill
	"Fx", -- (kind, position, color?): an effect everyone near sees and hears (client Effects)
	"Knocked", -- (push, hard): a bat hit this player: they fly back (and fall, on the knock-out hit)
	"HitMark", -- (target's character, hits, needed): the swinger's count over the one they hit
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
