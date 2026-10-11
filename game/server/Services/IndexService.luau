--!strict
-- The Index's rewards (Config/Index, Logic/Index): a player who has hatched every creature of an egg claims that
-- page's coins and speed, once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Index = require(Shared.Logic.Index)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)
local WildService = require(script.Parent.WildService)

local IndexService = {}

local function claim(player: Player, tier: any)
	local data = DataService.get(player)
	if not data or type(tier) ~= "number" then
		return
	end
	local reward = Index.claimable(data.index, data.indexClaimed, tier)
	if not reward then
		return
	end
	data.indexClaimed[tostring(tier)] = true
	data.coins += reward.coins
	data.power += reward.power
	WildService.applySpeed(player)
	local egg = Hatch.egg(tier)
	IslandService.notify(player, ("📖 %s page complete! +🪙 %s and +⚡ %s"):format(if egg then egg.name else "Index", Format.abbrev(reward.coins), Format.abbrev(reward.power)), "rare")
	IslandService.push(player)
end

function IndexService.init()
	Net.event("ClaimIndex").OnServerEvent:Connect(claim)
end

return IndexService
