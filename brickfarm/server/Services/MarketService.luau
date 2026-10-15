--!strict
-- Farmers and their neighbours: the town's orders board, each farm's stand (its farmer stocks it, visitors buy,
-- the coins reach the farmer wherever they are), and trades between two farmers standing together. Every step is
-- checked against the rules (Logic/Orders, Logic/Stand, Logic/Trade) and against where the players really are.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crops = require(Shared.Config.Crops)
local Format = require(Shared.Logic.Format)
local Layout = require(Shared.Logic.Layout)
local Net = require(Shared.Net)
local Orders = require(Shared.Logic.Orders)
local Stand = require(Shared.Logic.Stand)
local Trade = require(Shared.Logic.Trade)

local DataService = require(script.Parent.DataService)

local MarketService = {}

MarketService.NEAR_BOARD = 24 -- studs from the orders board to hand an order in
MarketService.NEAR_STAND = 20 -- studs from a stand to buy from it
MarketService.NEAR_TRADE = 30 -- studs between two farmers who trade

local rng = Random.new()
local function rand(a: number, b: number): number
	return rng:NextInteger(a, b)
end

-- (who owns which farm: FarmService)
local farmOf: (Player) -> number? = function()
	return nil
end
local ownerOf: (number) -> Player? = function()
	return nil
end
local onLevel: (Player, number) -> () = function() end

local sessions: { [Player]: Trade.Session } = {}
local asks: { [Player]: { from: Player, at: number } } = {} -- (who asked them, and when)

local function notify(player: Player, text: string, kind: string)
	Net.event("Notify"):FireClient(player, text, kind)
end

local function positionOf(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.CFrame.Position else nil
end

local function near(player: Player, at: Vector3, distance: number): boolean
	local p = positionOf(player)
	return p ~= nil and (p - at).Magnitude <= distance
end

local function nameOf(player: Player): string
	return player.DisplayName or player.Name
end

-- Orders -------------------------------------------------------------------------------------------------------

function MarketService.deliver(player: Player, i: any): boolean
	local data = DataService.get(player)
	if not data or not near(player, Layout.board().Position, MarketService.NEAR_BOARD) then
		return false
	end
	local before = data.xp
	local coins, xp = Orders.deliver(data, i, rand)
	if not coins then
		if xp == "crops" then
			notify(player, "You don't have all of those yet", "bad")
		end
		return false
	end
	notify(player, ("Order done! +%s coins, +%d XP"):format(Format.short(coins), xp :: number), "gold")
	onLevel(player, before)
	DataService.push(player)
	return true
end

function MarketService.swap(player: Player, i: any): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	local ok, why = Orders.swap(data, i, os.time(), rand)
	if not ok then
		if why == "wait" then
			notify(player, ("You can swap an order again in %s"):format(Format.clock(data.swapAt - os.time())), "bad")
		end
		return false
	end
	DataService.push(player)
	return true
end

-- Stands -------------------------------------------------------------------------------------------------------

-- Shows a stand's stock on its counter: a little crate of each crop
function MarketService.showStand(index: number, stand: { [string]: Stand.Lot }?)
	local village = workspace:FindFirstChild("Village")
	local farm = village and village:FindFirstChild("Farm" .. index)
	local model = farm and farm:FindFirstChild("Stand")
	if not model then
		return
	end
	local old = model:FindFirstChild("Goods")
	if old then
		old:Destroy()
	end
	local goods = Instance.new("Folder")
	goods.Name = "Goods"
	local slot = 0
	for _, crop in Crops.LIST do
		local lot = stand and stand[crop.key]
		if lot and lot.n > 0 then
			local at = Layout.stand(index) * CFrame.new(-3.6 + slot * 1.45, 3.75, 0)
			local crate = Instance.new("Part")
			crate.Name = "Crate"
			crate.Anchored = true
			crate.CanCollide = false
			crate.Size = Vector3.new(1.3, 0.7, 1.3)
			crate.CFrame = at
			crate.Color = Color3.fromRGB(160, 110, 70)
			crate.Material = Enum.Material.Plastic
			crate.Parent = goods
			local heap = Instance.new("Part")
			heap.Name = "Heap"
			heap.Anchored = true
			heap.CanCollide = false
			heap.Size = Vector3.new(1, 0.5, 1)
			heap.CFrame = at * CFrame.new(0, 0.5, 0)
			heap.Color = crop.fruit
			heap.Material = Enum.Material.Plastic
			heap.TopSurface = Enum.SurfaceType.Studs
			heap.Parent = goods
			slot += 1
		end
	end
	goods.Parent = model
end

local function refreshStand(index: number)
	local owner = ownerOf(index)
	local data = owner and DataService.get(owner)
	MarketService.showStand(index, if data then data.stand else nil)
end

-- A stand's prompt: its own farmer manages it, anyone else shops
function MarketService.openStand(player: Player, index: number)
	local owner = ownerOf(index)
	local data = owner and DataService.get(owner)
	if not owner or not data then
		notify(player, "Nobody farms here right now", "info")
		return
	end
	Net.event("OpenStand"):FireClient(player, index, nameOf(owner), data.stand, owner == player)
end

function MarketService.put(player: Player, key: any, n: any, price: any): boolean
	local data = DataService.get(player)
	local index = farmOf(player)
	if not data or not index then
		return false
	end
	local ok, why = Stand.put(data, key, n, price)
	if not ok then
		notify(player, if why == "full" then "Your stand is full" elseif why == "barn" then "Not that many in your barn" else "Can't put that out", "bad")
		return false
	end
	refreshStand(index)
	DataService.push(player)
	Net.event("OpenStand"):FireClient(player, index, nameOf(player), data.stand, true)
	return true
end

function MarketService.take(player: Player, key: any): boolean
	local data = DataService.get(player)
	local index = farmOf(player)
	if not data or not index or not Stand.take(data, key) then
		return false
	end
	refreshStand(index)
	DataService.push(player)
	Net.event("OpenStand"):FireClient(player, index, nameOf(player), data.stand, true)
	return true
end

function MarketService.buy(player: Player, index: any, key: any, n: any): boolean
	if type(index) ~= "number" then
		return false
	end
	local owner = ownerOf(index)
	local buyer = DataService.get(player)
	local seller = owner and DataService.get(owner)
	if not owner or not buyer or not seller or owner == player then
		return false
	end
	if not near(player, Layout.stand(index).Position, MarketService.NEAR_STAND) then
		return false
	end
	local cost, why = Stand.buy(seller, buyer, key, n)
	if not cost then
		notify(player, if why == "coins" then "Not enough coins" elseif why == "stock" then "Not that many left" else "Can't buy that", "bad")
		return false
	end
	local crop = Crops.byKey[key]
	notify(player, ("Bought %d %s for %s coins"):format(n, crop.name, Format.short(cost)), "good")
	notify(owner, ("%s bought %d %s from your stand: +%s coins!"):format(nameOf(player), n, crop.name, Format.short(cost)), "gold")
	refreshStand(index)
	DataService.push(player)
	DataService.push(owner)
	Net.event("OpenStand"):FireClient(player, index, nameOf(owner), seller.stand, false)
	return true
end

-- Trades -------------------------------------------------------------------------------------------------------

local function other(session: Trade.Session, player: Player): Player
	return if session.a == player then session.b else session.a
end

local function sendState(session: Trade.Session)
	for _, p in { session.a, session.b } do
		local o = other(session, p)
		Net.event("TradeState"):FireClient(p, {
			with = nameOf(o),
			mine = session.offers[p],
			theirs = session.offers[o],
			myReady = session.ready[p] == true,
			theirReady = session.ready[o] == true,
		})
	end
end

local function endTrade(session: Trade.Session, why: string?)
	for _, p in { session.a, session.b } do
		if sessions[p] == session then
			sessions[p] = nil
			Net.event("TradeState"):FireClient(p, nil)
			if why then
				notify(p, why, "info")
			end
		end
	end
end

function MarketService.ask(player: Player, userId: any)
	if type(userId) ~= "number" or sessions[player] then
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player or sessions[target] then
		return
	end
	local here = positionOf(player)
	if not here or not near(target, here, MarketService.NEAR_TRADE) then
		notify(player, "Get closer to trade", "bad")
		return
	end
	asks[target] = { from = player, at = os.clock() }
	Net.event("TradeAsked"):FireClient(target, player.UserId, nameOf(player))
	notify(player, ("Asked %s to trade..."):format(nameOf(target)), "info")
end

function MarketService.answer(player: Player, userId: any, accept: any)
	local ask = asks[player]
	asks[player] = nil
	if not ask or ask.from.UserId ~= userId or os.clock() - ask.at > 30 then
		return
	end
	local from = ask.from
	if not accept then
		notify(from, ("%s said no thanks"):format(nameOf(player)), "info")
		return
	end
	if sessions[player] or sessions[from] or not DataService.get(from) then
		return
	end
	local here = positionOf(player)
	if not here or not near(from, here, MarketService.NEAR_TRADE) then
		notify(player, "Too far apart to trade", "bad")
		return
	end
	local session = Trade.new(from, player)
	sessions[from] = session
	sessions[player] = session
	sendState(session)
end

function MarketService.offer(player: Player, items: any, coins: any)
	local session = sessions[player]
	local data = DataService.get(player)
	if not session or not data then
		return
	end
	local ok, why = Trade.offer(session, player, items, coins, data)
	if not ok then
		notify(player, if why == "short" then "You don't have all of that" else "Can't offer that", "bad")
	end
	sendState(session)
end

function MarketService.ready(player: Player, ready: any)
	local session = sessions[player]
	if not session then
		return
	end
	Trade.setReady(session, player, ready == true)
	if Trade.bothReady(session) then
		local a, b = session.a, session.b
		local dataA, dataB = DataService.get(a), DataService.get(b)
		local pa = positionOf(a)
		if not dataA or not dataB or not pa or not near(b, pa, MarketService.NEAR_TRADE + 10) then
			endTrade(session, "The trade was called off (too far apart)")
			return
		end
		local done = Trade.complete(session, dataA, dataB)
		if done then
			DataService.push(a)
			DataService.push(b)
			DataService.save(a)
			DataService.save(b)
			endTrade(session, "Trade done!")
			return
		end
	end
	sendState(session)
end

function MarketService.cancel(player: Player)
	local session = sessions[player]
	if session then
		endTrade(session, ("%s called the trade off"):format(nameOf(player)))
	end
end

-- (for the tests)
function MarketService.session(player: Player): Trade.Session?
	return sessions[player]
end

-- A "Trade" prompt over each farmer, for the others to use (each phone hides its own)
local function addTradePrompt(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TradePrompt"
		prompt.ActionText = "Trade"
		prompt.ObjectText = character.Name
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 10
		prompt.KeyboardKeyCode = Enum.KeyCode.T
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
	end
end

-- `farm(player)` and `owner(index)`: who farms where (FarmService); `level(player, xpBefore)`: tells them of a
-- new level if an order brought one
function MarketService.init(farm: (Player) -> number?, owner: (number) -> Player?, level: (Player, number) -> ())
	farmOf, ownerOf, onLevel = farm, owner, level
	Net.event("Deliver").OnServerEvent:Connect(MarketService.deliver)
	Net.event("SwapOrder").OnServerEvent:Connect(MarketService.swap)
	Net.event("StandPut").OnServerEvent:Connect(MarketService.put)
	Net.event("StandTake").OnServerEvent:Connect(MarketService.take)
	Net.event("StandBuy").OnServerEvent:Connect(MarketService.buy)
	Net.event("TradeAsk").OnServerEvent:Connect(MarketService.ask)
	Net.event("TradeAnswer").OnServerEvent:Connect(MarketService.answer)
	Net.event("TradeOffer").OnServerEvent:Connect(MarketService.offer)
	Net.event("TradeReady").OnServerEvent:Connect(MarketService.ready)
	Net.event("TradeCancel").OnServerEvent:Connect(MarketService.cancel)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name == "OrdersPrompt" then
			Net.event("OpenOrders"):FireClient(player)
		elseif prompt.Name == "StandPrompt" then
			local farmModel = prompt:FindFirstAncestorWhichIsA("Model")
			while farmModel and not farmModel:GetAttribute("Index") do
				farmModel = farmModel:FindFirstAncestorWhichIsA("Model")
			end
			if farmModel then
				MarketService.openStand(player, farmModel:GetAttribute("Index") :: number)
			end
		elseif prompt.Name == "TradePrompt" then
			local character = prompt:FindFirstAncestorWhichIsA("Model")
			local target = character and Players:GetPlayerFromCharacter(character)
			if target then
				MarketService.ask(player, target.UserId)
			end
		end
	end)
	DataService.onLoaded(function(player, data)
		Orders.fill(data, rand)
		local index = farm(player)
		if index then
			MarketService.showStand(index, data.stand)
		end
	end)
	DataService.onLeaving(function(player)
		local session = sessions[player]
		if session then
			endTrade(session, "The trade was called off")
		end
		asks[player] = nil
		local index = farm(player)
		if index then
			MarketService.showStand(index, nil)
		end
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(addTradePrompt)
		if player.Character then
			task.spawn(addTradePrompt, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return MarketService
