-- World Boss (Config/Boss): every hour at :30 a giant creature lands in the Hub and the whole server
-- fights it. It uses the same damage as coin sources (team power + taps), so nothing new to learn.
-- Rewards go to everyone who fought long enough for their own power, never just to the top players.
-- Clients read the schedule from ReplicatedStorage attributes: BossNext, BossEnds, BossSource.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossConfig = require(Shared.Config.Boss)
local Items = require(Shared.Config.Items)
local World1 = require(Shared.Config.World1)
local Boss = require(Shared.Logic.Boss)
local Format = require(Shared.Logic.Format)
local Loot = require(Shared.Logic.Loot)
local MapLayout = require(Shared.Logic.MapLayout)
local Unlocks = require(Shared.Logic.Unlocks)
local Net = require(Shared.Net)

local BreakableService = require(script.Parent.BreakableService)
local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

local BossService = {}

local rng = Random.new()
local active: BreakableService.Source? = nil
local nextAt = 0
local endsAt = 0
local warned = false
-- Each fighter's team power when they hit it last, to measure how long they fought
local powerSeen: { [Player]: number } = {}

local function publish()
	ReplicatedStorage:SetAttribute("BossNext", nextAt)
	ReplicatedStorage:SetAttribute("BossEnds", if active then endsAt else 0)
	ReplicatedStorage:SetAttribute("BossSource", if active then active.name else "")
end

local function hubPosition(): Vector3
	return MapLayout.center(0) + Vector3.new(0, 0, -12)
end

local function spawn()
	local total = 0
	for _, runtime in State.all() do
		total += runtime.power
	end
	local species = {}
	for id in World1.species do
		table.insert(species, id)
	end
	table.sort(species)
	local pet = {
		s = species[rng:NextInteger(1, #species)],
		v = BossConfig.VARIANTS[rng:NextInteger(1, #BossConfig.VARIANTS)],
		z = "Titan",
	}
	active = BreakableService.spawnSpecial(0, "Boss", pet, hubPosition(), Boss.health(total), BossConfig.LIFETIME)
	endsAt = os.time() + BossConfig.LIFETIME
	table.clear(powerSeen)
	GameService.notifyAll(("👹 The World Boss %s landed in the Hub! Everyone, fight it together!"):format(pet.s), "rare")
end

local function payOut(contributors: { [Player]: number }, defeated: boolean)
	local count = 0
	for player, damage in contributors do
		local data = DataService.get(player)
		local runtime = State.get(player)
		if not data or not runtime or not player.Parent then
			continue
		end
		local tier = Boss.tier(damage, math.max(powerSeen[player] or 0, runtime.power))
		if not tier then
			GameService.notify(player, "You didn't fight the boss long enough for a reward. Next time!", "info")
			continue
		end
		count += 1
		local reward = Boss.reward(tier, Unlocks.bestZone(data), defeated)
		data.gems += reward.gems
		data.tickets += reward.tickets
		local parts = { "💎 " .. reward.gems }
		if reward.tickets > 0 then
			table.insert(parts, "🎟️ " .. reward.tickets)
		end
		if defeated and tier == "full" then
			if rng:NextNumber() < BossConfig.GOLDEN_KEY_CHANCE then
				GameService.giveItem(player, "Key_Golden", 1, false)
				table.insert(parts, Items.byId.Key_Golden.name)
			end
			if Unlocks.has(data, "Cartridges") and rng:NextNumber() < BossConfig.CARD_CHANCE then
				local card = Loot.randomCartridge(1, 2, function()
					return rng:NextNumber()
				end)
				GameService.giveItem(player, card, 1, false)
				table.insert(parts, Items.byId[card].name)
			end
		end
		if defeated then
			GameService.progress(player, "Boss", 1)
		end
		local heading = if not defeated then "The boss escaped, but you fought well: " elseif tier == "full" then "Boss defeated! " else "Boss defeated (you joined late): "
		GameService.notify(player, heading .. table.concat(parts, ", "), "success")
		GameService.refresh(player)
	end
	return count
end

local function finish(defeated: boolean, contributors: { [Player]: number })
	local source = active
	active = nil
	endsAt = 0
	local count = payOut(contributors, defeated)
	if defeated then
		GameService.notifyAll(("👹 The World Boss was defeated by %d player%s!"):format(count, if count == 1 then "" else "s"), "rare")
	else
		GameService.notifyAll("👹 The World Boss escaped... Next one in an hour!", "info")
		if source then
			BreakableService.despawn(source)
		end
	end
	table.clear(powerSeen)
	publish()
end

local function step()
	local now = os.time()
	if active then
		local source = active :: BreakableService.Source
		-- Remember each fighter's power while they fight (the tier is measured against it)
		for player in source.contributors do
			local runtime = State.get(player)
			if runtime then
				powerSeen[player] = math.max(powerSeen[player] or 0, runtime.power)
			end
		end
		if source.alive and now >= endsAt then
			finish(false, source.contributors)
		end
		return
	end
	if not warned and now >= nextAt - BossConfig.WARNING and #Players:GetPlayers() > 0 then
		warned = true
		GameService.notifyAll(("👹 A World Boss lands in the Hub in %s!"):format(Format.time(math.max(0, nextAt - now))), "rare")
	end
	if now >= nextAt then
		if #Players:GetPlayers() > 0 then
			spawn()
		end
		nextAt = Boss.nextSpawn(now)
		warned = false
		publish()
	end
end

-- Free trip to the fight for everyone (the Teleport pass is for zones)
local function goToBoss(player: Player)
	local runtime = State.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not active or not runtime or not root or not State.throttle(runtime, "BossGo", 2) then
		return
	end
	root.CFrame = CFrame.new(hubPosition() + Vector3.new(0, 4, 22))
end

function BossService.init()
	-- In Studio the first boss comes after 45 seconds, so it can be tested without waiting for :30
	nextAt = if RunService:IsStudio() then os.time() + 45 else Boss.nextSpawn(os.time())
	publish()
	BreakableService.Broken:Connect(function(source, contributors)
		if source == active then
			-- Keep the damage dealt just before the last hit in the fight log
			for player in contributors do
				local runtime = State.get(player)
				if runtime then
					powerSeen[player] = math.max(powerSeen[player] or 0, runtime.power)
				end
			end
			finish(true, contributors)
		end
	end)
	Net.event("BossGo").OnServerEvent:Connect(goToBoss)
	Players.PlayerRemoving:Connect(function(player)
		powerSeen[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(step)
			if not ok then
				warn("[Boss] step error", err)
			end
		end
	end)
end

return BossService
