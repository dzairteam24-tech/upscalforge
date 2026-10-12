--!strict
-- The barn: what a player carries (the eggs in their hotbar and the creatures not in the garden) can be stolen
-- outside their garden, so they take it home and keep it in the barn, safe, or hatch / set it down. Storing and
-- taking out only work inside their own garden: the only safe place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hatch = require(Shared.Logic.Hatch)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)

local StorageService = {}

-- Moves eggs between what's carried and what's in the barn
local function moveEggs(player: Player, golden: boolean, tier: any, all: any, into: boolean)
	local data = DataService.get(player)
	local egg = if type(tier) == "number" then Hatch.egg(tier) else nil
	if not data or not egg then
		return
	end
	local key = tostring(egg.tier)
	local from, to
	if into then
		from, to = if golden then data.golden else data.eggs, if golden then data.storedGolden else data.storedEggs
	else
		from, to = if golden then data.storedGolden else data.storedEggs, if golden then data.golden else data.eggs
	end
	local have = from[key] or 0
	if have <= 0 then
		return
	end
	local count = if all == true then have else 1
	from[key] = if have - count > 0 then have - count else nil
	to[key] = (to[key] or 0) + count
end

-- Moves one creature between the hotbar (carried) and the barn
local function moveCreature(player: Player, id: any, into: boolean)
	local data = DataService.get(player)
	if not data or type(id) ~= "string" or not data.creatures[id] then
		return
	end
	if table.find(data.placed, id) then
		IslandService.notify(player, "Take it out of the garden first", "error")
		return
	end
	data.stored[id] = if into then true else nil
end

local function handle(into: boolean)
	return function(player: Player, what: any, ref: any, all: any)
		if not IslandService.inOwnGarden(player) then
			IslandService.notify(player, "The barn is in your garden: go home first", "error")
			return
		end
		if what == "egg" or what == "golden" then
			moveEggs(player, what == "golden", ref, all, into)
		elseif what == "creature" then
			moveCreature(player, ref, into)
		else
			return
		end
		IslandService.push(player)
	end
end

function StorageService.init()
	Net.event("Store").OnServerEvent:Connect(handle(true))
	Net.event("Withdraw").OnServerEvent:Connect(handle(false))
end

return StorageService
