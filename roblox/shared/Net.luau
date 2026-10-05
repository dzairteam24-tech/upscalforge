-- Remote names in one place. The server creates them, the client waits for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- client -> server
	"ToggleAuto",
	"Hatch",
	"EquipPet",
	"UnequipPet",
	"EquipBest",
	"LockPet",
	"DeletePets",
	"FusePets",
	"BuyUpgrade",
	"UnlockZone",
	"SetSetting",
	"TradeRequest",
	"TradeRespond",
	"TradeOffer",
	"TradeReady",
	"TradeConfirm",
	"TradeCancel",
	"UseItem",
	"MergeItems",
	"MixItems",
	"WatchAd",
	"ClaimDaily",
	"ClaimQuest",
	"ClaimPass",
	"EquipCosmetic",
	"EquipCartridge",
	"UnequipCartridge",
	"Reload",
	"StartExpedition",
	"ClaimExpedition",
	"ClaimGift",
	"SkipTutorial",
	"ApplySticker",
	"RemoveSticker",
	"SpinWheel",
	"BuyProduct",
	"BuyGemItem",
	"BoothClaim",
	"BoothRelease",
	"BoothList",
	"BoothUnlist",
	"BoothBuy",
	"ClanCreate",
	"ClanJoin",
	"ClanLeave",
	"ClanRequest",
	"EventBuy",
	"Teleport",
	-- server -> client
	"Data",
	"Currency",
	"Notify",
	"HatchResult",
	"BreakFx",
	"SkillFx",
	"TradeIncoming",
	"TradeState",
	"TradeClosed",
	"OfflineEarnings",
	"WheelResult",
	"ClanData",
}

local FOLDER_NAME = "Remotes"

local Net = {}

local cached: Folder? = nil

local function getFolder(): Folder
	if cached then
		return cached
	end
	local result: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			result = existing
		else
			result = Instance.new("Folder")
			result.Name = FOLDER_NAME
		end
		for _, name in EVENTS do
			if not result:FindFirstChild(name) then
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = result
			end
		end
		result.Parent = ReplicatedStorage
	else
		result = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	cached = result
	return result
end

function Net.event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), "Unknown remote " .. name)
	local remote = getFolder():WaitForChild(name)
	return remote :: RemoteEvent
end

-- Creates every remote. Call once on the server before players join.
function Net.init()
	getFolder()
end

return Net
