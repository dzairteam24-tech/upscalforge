--!strict
-- Robux purchases (Config/Robux): the Fast Hatch game pass (checked when a player joins, and when they buy it),
-- and the Hatch All Now product. Players ask for one with the BuyRobux remote; Roblox shows the
-- purchase prompt and calls ProcessReceipt once it's paid.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Robux = require(Shared.Config.Robux)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)

local RobuxService = {}

local function checkPass(player: Player)
	if Robux.FAST_HATCH.id == 0 then
		return
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Robux.FAST_HATCH.id)
	end)
	if ok and owns then
		IslandService.setFast(player, true)
	end
end

-- The player asks to buy something: "FastHatch" or "HatchAll"
local function buy(player: Player, what: any)
	if type(what) ~= "string" then
		return
	end
	if what == "FastHatch" and Robux.FAST_HATCH.id ~= 0 then
		MarketplaceService:PromptGamePassPurchase(player, Robux.FAST_HATCH.id)
	elseif what == "HatchAll" and Robux.HATCH_ALL.id ~= 0 then
		MarketplaceService:PromptProductPurchase(player, Robux.HATCH_ALL.id)
	else
		IslandService.notify(player, "Coming soon! 🛠️", "info")
	end
end

-- Gives what a paid product buys; Roblox keeps asking until this says it's granted
local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = player and DataService.get(player)
	if not player or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = receipt.ProductId
	if id == Robux.HATCH_ALL.id then
		IslandService.hatchAll(player)
		IslandService.notify(player, "🐣 Every egg in your garden is ready to hatch!", "success")
		IslandService.push(player)
	else
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService.save(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function RobuxService.init()
	Net.event("BuyRobux").OnServerEvent:Connect(buy)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
		if bought and passId == Robux.FAST_HATCH.id then
			IslandService.setFast(player, true)
			IslandService.notify(player, "⏩ Fast Hatch! Your eggs hatch twice as fast", "success")
		end
	end)
	DataService.onLoaded(function(player)
		checkPass(player)
	end)
end

return RobuxService
