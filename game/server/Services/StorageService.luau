--!strict
-- The barn: where a player keeps the eggs and creatures they don't need in their hotbar (eggs brought home are
-- safe either way: only an egg on its way home can be stolen, StealService). Storing and taking out only work
-- inside their own garden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hatch = require(Shared.Logic.Hatch)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)

local StorageService = {}

-- Moves eggs between what's carried and what's in the barn (ref: their key, Logic/Hatch.key, or a tier)
local function moveEggs(player: Player, golden: boolean, ref: any, all: any, into: boolean)
	local data = DataService.get(player)
	local key = if type(ref) == "number" then tostring(ref) elseif type(ref) == "string" then ref else nil
	local tier = if key then Hatch.parse(key) else nil
	if not data or not key or not tier or not Hatch.egg(tier) then
		return
	end
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
