--!strict
-- Robux: the passes and developer products in Config/Passes. They only buy convenience: nothing here can't also
-- be earned for free. Each id is pasted into Config/Passes after the pass or product is made in Creator Hub;
-- an id of 0 isn't set up yet, and in Studio the shop then gives the thing for free so it can be tried.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Multiplier = require(Shared.Logic.Multiplier)
local Net = require(Shared.Net)
local PassConfig = require(Shared.Config.Passes)

local DataService = require(script.Parent.DataService)

local RobuxService = {}

local MAX_RECEIPTS = 100

local function notify(player: Player, text: string, kind: string)
	Net.event("Notify"):FireClient(player, text, kind)
end

local function passByKey(key: any): PassConfig.Pass?
	for _, pass in PassConfig.PASSES do
		if pass.key == key then
			return pass
		end
	end
	return nil
end

local function productByKey(key: any): PassConfig.Product?
	for _, product in PassConfig.PRODUCTS do
		if product.key == key then
			return product
		end
	end
	return nil
end

function RobuxService.grantPass(player: Player, pass: PassConfig.Pass)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.passes[pass.key] = true
	notify(player, "You got " .. pass.name .. "!", "Legendary")
	DataService.push(player)
end

-- `perMinute`: what the player earns by hand a minute (the income packs are worth that many minutes of it)
function RobuxService.grantProduct(player: Player, product: PassConfig.Product, perMinute: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	local now = os.time()
	if product.boostMinutes then
		data.boostUntil = math.max(now, data.boostUntil) + product.boostMinutes * 60
		notify(player, ("Double coins for %d minutes!"):format(product.boostMinutes), "Legendary")
	end
	if product.incomeMinutes then
		local coins = math.max(200, math.floor(product.incomeMinutes * perMinute * Multiplier.sell(data, now)))
		data.coins += coins
		notify(player, ("+%d coins"):format(coins), "Legendary")
	end
	DataService.push(player)
end

-- The player asked for something in the Store: ask Roblox to charge them (or, in Studio with no id yet, give it)
function RobuxService.request(player: Player, kind: any, key: any, perMinute: number)
	local pass = if kind == "pass" then passByKey(key) else nil
	local product = if kind == "product" then productByKey(key) else nil
	if not pass and not product then
		return
	end
	local id = if pass then pass.id else (product :: PassConfig.Product).id
	if id ~= 0 then
		local ok, err = pcall(function()
			if pass then
				MarketplaceService:PromptGamePassPurchase(player, id)
			else
				MarketplaceService:PromptProductPurchase(player, id)
			end
		end)
		if not ok then
			warn("[Robux] Couldn't prompt: " .. tostring(err))
		end
		return
	end
	if RunService:IsStudio() then
		if pass then
			RobuxService.grantPass(player, pass)
		else
			RobuxService.grantProduct(player, product :: PassConfig.Product, perMinute)
		end
	else
		notify(player, "Not available yet", "bad")
	end
end

-- Roblox says a developer product was bought: pay it exactly once (the receipt is remembered)
function RobuxService.process(userId: number, productId: number, purchaseId: string, perMinute: (Player) -> number): boolean
	local player = Players:GetPlayerByUserId(userId)
	local data = if player then DataService.get(player) else nil
	if not player or not data then
		return false -- (not processed: Roblox will ask again)
	end
	if table.find(data.receipts, purchaseId) then
		return true
	end
	local found: PassConfig.Product? = nil
	for _, product in PassConfig.PRODUCTS do
		if product.id ~= 0 and product.id == productId then
			found = product
		end
	end
	if not found then
		return false
	end
	RobuxService.grantProduct(player, found, perMinute(player))
	table.insert(data.receipts, purchaseId)
	while #data.receipts > MAX_RECEIPTS do
		table.remove(data.receipts, 1)
	end
	DataService.save(player)
	return true
end

-- `perMinute(player)`: their income by hand (EconomyService). `ready(player, data)`: called once their passes are
-- known (the drone's earnings depend on one)
function RobuxService.init(perMinute: (Player) -> number, ready: (Player, any) -> ())
	Net.event("BuyRobux").OnServerEvent:Connect(function(player, kind, key)
		RobuxService.request(player, kind, key, perMinute(player))
	end)
	-- Which passes they own: asked of Roblox each time they join (a refund takes it away)
	DataService.onLoaded(function(player, data)
		for _, pass in PassConfig.PASSES do
			if pass.id ~= 0 then
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
				end)
				if ok then
					data.passes[pass.key] = owns == true
				end
			end
		end
		DataService.push(player)
		ready(player, data)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, bought: boolean)
		if not bought then
			return
		end
		for _, pass in PassConfig.PASSES do
			if pass.id ~= 0 and pass.id == passId then
				RobuxService.grantPass(player, pass)
			end
		end
	end)
	MarketplaceService.ProcessReceipt = function(info: any)
		local ok = RobuxService.process(info.PlayerId, info.ProductId, tostring(info.PurchaseId), function(player)
			local data = DataService.get(player)
			if not data then
				return 0
			end
			return perMinute(player)
		end)
		return if ok then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

return RobuxService
