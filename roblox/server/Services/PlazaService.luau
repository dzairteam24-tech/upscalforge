-- Trading Plaza: a player claims a booth and lists creatures for gems; others buy them right away.
-- Safety: the buyer sends the price they saw, so a seller can't raise it at the last second, and the
-- creature must still be exactly the one listed. A 5% tax on sales keeps gems flowing out of the game.
-- Booths are free again when their owner leaves.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Format = require(Shared.Logic.Format)
local Inventory = require(Shared.Logic.Inventory)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

type Pet = Types.Pet

local PlazaService = {}

local MAX_LISTINGS = 6
local TAX = 0.05
local MAX_PRICE = 1e9

type Listing = { id: string, price: number, s: string, v: string, z: string, st: string? }
type Booth = { part: BasePart, owner: Player?, listings: { Listing } }

local booths: { [number]: Booth } = {}

local function newId(): string
	return string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 16)
end

local function boothOf(player: Player): (number?, Booth?)
	for id, booth in booths do
		if booth.owner == player then
			return id, booth
		end
	end
	return nil, nil
end

-- Mirrors a booth to clients through attributes, and updates its sign.
local function publish(booth: Booth)
	local part = booth.part
	part:SetAttribute("Owner", if booth.owner then booth.owner.UserId else 0)
	part:SetAttribute("OwnerName", if booth.owner then booth.owner.DisplayName else "")
	part:SetAttribute("Listings", HttpService:JSONEncode(booth.listings))
	local gui = part:FindFirstChildOfClass("BillboardGui")
	local text = gui and gui:FindFirstChild("Text") :: TextLabel?
	if text then
		text.Text = if booth.owner
			then ("🏪 %s\n%d for sale"):format(booth.owner.DisplayName, #booth.listings)
			else "Free booth"
	end
end

local function release(player: Player)
	local _, booth = boothOf(player)
	if booth then
		booth.owner = nil
		booth.listings = {}
		publish(booth)
	end
end

local function claim(player: Player, boothId: any)
	local runtime = State.get(player)
	local booth = type(boothId) == "number" and booths[boothId] or nil
	if not runtime or not booth or not State.throttle(runtime, "Booth", 0.5) then
		return
	end
	if booth.owner then
		GameService.notify(player, "That booth is taken", "error")
		return
	end
	release(player)
	booth.owner = player
	booth.listings = {}
	publish(booth)
	GameService.notify(player, "Your booth! Tap it again to put creatures up for sale.", "success")
end

local function list(player: Player, petId: any, price: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	local _, booth = boothOf(player)
	if not data or not runtime or not booth or type(petId) ~= "string" or type(price) ~= "number" then
		return
	end
	if not State.throttle(runtime, "Booth", 0.3) then
		return
	end
	price = math.floor(price)
	if price < 1 or price > MAX_PRICE or price ~= price then
		GameService.notify(player, "Pick a price between 1 and 1B gems", "error")
		return
	end
	local pet = data.pets[petId]
	if not pet then
		return
	end
	if pet.lk or pet.ex then
		GameService.notify(player, "Locked creatures and creatures on a trip can't be sold", "error")
		return
	end
	if #booth.listings >= MAX_LISTINGS then
		GameService.notify(player, ("A booth holds %d creatures"):format(MAX_LISTINGS), "error")
		return
	end
	for _, listing in booth.listings do
		if listing.id == petId then
			return
		end
	end
	table.insert(booth.listings, { id = petId, price = price, s = pet.s, v = pet.v, z = pet.z, st = pet.st })
	publish(booth)
end

local function unlist(player: Player, petId: any)
	local _, booth = boothOf(player)
	if not booth or type(petId) ~= "string" then
		return
	end
	for index, listing in booth.listings do
		if listing.id == petId then
			table.remove(booth.listings, index)
			publish(booth)
			return
		end
	end
end

local function record(data: Types.PlayerData, player: Player, other: string, gave: { any }, got: { any })
	table.insert(data.tradeHistory, 1, { t = os.time(), with = other, gave = gave, got = got })
	while #data.tradeHistory > Constants.TRADE_HISTORY_SIZE do
		table.remove(data.tradeHistory)
	end
	data.stats.trades = (data.stats.trades or 0) + 1
	GameService.progress(player, "Trade", 1)
end

local function buy(player: Player, boothId: any, petId: any, seenPrice: any)
	local runtime = State.get(player)
	local buyerData = DataService.get(player)
	local booth = type(boothId) == "number" and booths[boothId] or nil
	if not runtime or not buyerData or not booth or type(petId) ~= "string" or type(seenPrice) ~= "number" then
		return
	end
	if not State.throttle(runtime, "BoothBuy", 0.5) then
		return
	end
	local seller = booth.owner
	local sellerData = seller and DataService.get(seller)
	if not seller or not sellerData or seller == player then
		return
	end
	local index, listing = nil, nil
	for i, entry in booth.listings do
		if entry.id == petId then
			index, listing = i, entry
		end
	end
	if not index or not listing then
		GameService.notify(player, "That creature isn't for sale any more", "error")
		return
	end
	if listing.price ~= seenPrice then
		GameService.notify(player, "The price changed. Check it again before buying.", "error")
		return
	end
	local pet = sellerData.pets[petId]
	-- Must be exactly the creature that was listed
	if not pet or pet.s ~= listing.s or pet.v ~= listing.v or pet.z ~= listing.z or pet.st ~= listing.st or pet.lk or pet.ex then
		table.remove(booth.listings, index)
		publish(booth)
		GameService.notify(player, "That creature isn't for sale any more", "error")
		return
	end
	if buyerData.gems < listing.price then
		GameService.notify(player, "Not enough gems", "error")
		return
	end
	if Inventory.count(buyerData) >= GameService.capacity(player) then
		GameService.notify(player, "Your storage is full", "error")
		return
	end

	local moved = Inventory.remove(sellerData, petId) :: Pet
	Inventory.add(buyerData, { s = moved.s, v = moved.v, z = moved.z, st = moved.st }, newId)
	local earned = math.floor(listing.price * (1 - TAX))
	buyerData.gems -= listing.price
	sellerData.gems += earned
	table.remove(booth.listings, index)
	publish(booth)

	local summary = { { s = moved.s, v = moved.v, z = moved.z } }
	record(buyerData, player, seller.DisplayName, {}, summary)
	record(sellerData, seller, player.DisplayName, summary, {})
	GameService.notify(player, ("You bought a %s %s for 💎 %s!"):format(moved.v, moved.s, Format.abbrev(listing.price)), "success")
	GameService.notify(seller, ("%s bought your %s %s: +💎 %s"):format(player.DisplayName, moved.v, moved.s, Format.abbrev(earned)), "success")
	GameService.refresh(player)
	GameService.refresh(seller)
	-- Save both now, like a trade, so a crash can't undo one side only
	task.spawn(DataService.save, player, false)
	task.spawn(DataService.save, seller, false)
end

function PlazaService.init()
	for _, part in CollectionService:GetTagged("Booth") do
		local id = part:GetAttribute("BoothId")
		if part:IsA("BasePart") and type(id) == "number" then
			booths[id] = { part = part, owner = nil, listings = {} }
			publish(booths[id])
		end
	end
	Net.event("BoothClaim").OnServerEvent:Connect(claim)
	Net.event("BoothRelease").OnServerEvent:Connect(release)
	Net.event("BoothList").OnServerEvent:Connect(list)
	Net.event("BoothUnlist").OnServerEvent:Connect(unlist)
	Net.event("BoothBuy").OnServerEvent:Connect(buy)
	Players.PlayerRemoving:Connect(release)
	task.spawn(function()
		while true do
			task.wait(5)
			for _, booth in booths do
				if booth.owner then
					pcall(PlazaService.sweep, booth.owner)
				end
			end
		end
	end)
end

-- Listings are kept in sync when a creature leaves its owner some other way (deleted, fused, traded).
function PlazaService.sweep(player: Player)
	local data = DataService.get(player)
	local _, booth = boothOf(player)
	if not data or not booth then
		return
	end
	local kept = {}
	for _, listing in booth.listings do
		if data.pets[listing.id] then
			table.insert(kept, listing)
		end
	end
	if #kept ~= #booth.listings then
		booth.listings = kept
		publish(booth)
	end
end

return PlazaService
