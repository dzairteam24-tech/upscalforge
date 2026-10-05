-- Paid memberships: game passes (VIP, Auto Tap, +2 Team Slots, Big Storage, Teleport, Extra Trip) and
-- Roblox Premium perks. Their effects are read from the player's
-- runtime by GameService (slots, storage, coins, auto tap) and ExpeditionService (trip slots).
-- Premium members also earn the game Premium Payouts while they play.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Products = require(Shared.Config.Products)
local MapLayout = require(Shared.Logic.MapLayout)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData

local MembershipService = {}

local function ownsPass(player: Player, passId: number): boolean
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	return ok and owns == true
end

local function apply(player: Player)
	local runtime = State.get(player)
	if not runtime then
		return
	end
	runtime.vip = runtime.passes.VIP == true
	GameService.refresh(player)
	GameService.refreshTitles(player)
end

local function load(player: Player)
	local runtime = State.get(player)
	if not runtime then
		return
	end
	for _, pass in Products.gamePasses do
		if pass.id ~= 0 and ownsPass(player, pass.id) then
			runtime.passes[pass.key] = true
		end
	end
	runtime.premium = player.MembershipType == Enum.MembershipType.Premium
	apply(player)
end

-- Teleport pass: jump to the middle of any unlocked zone (or the hub).
local function teleport(player: Player, zoneId: any)
	local runtime = State.get(player)
	local data = DataService.get(player)
	if not runtime or not data or type(zoneId) ~= "number" or not State.throttle(runtime, "Teleport", 2) then
		return
	end
	if not runtime.passes.Teleport then
		GameService.notify(player, "Get the Teleport pass to jump between zones", "error")
		return
	end
	if not data.unlockedZones[tostring(zoneId)] then
		GameService.notify(player, "Unlock that zone first", "error")
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.CFrame = CFrame.new(MapLayout.center(zoneId) + Vector3.new(0, 5, -12))
		runtime.target = nil
	end
end

function MembershipService.init()
	DataService.Loaded:Connect(function(player: Player, _data: PlayerData)
		load(player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local runtime = State.get(player)
		for _, pass in Products.gamePasses do
			if pass.id == passId and runtime then
				runtime.passes[pass.key] = true
				GameService.notify(player, ("%s is yours. Thanks!"):format(pass.name), "success")
				apply(player)
			end
		end
	end)

	Players.PlayerMembershipChanged:Connect(function(player)
		local runtime = State.get(player)
		if runtime then
			runtime.premium = player.MembershipType == Enum.MembershipType.Premium
			if runtime.premium then
				GameService.notify(player, "Premium perks on: coins +10%!", "success")
			end
			apply(player)
		end
	end)

	Net.event("Teleport").OnServerEvent:Connect(teleport)
end

return MembershipService
