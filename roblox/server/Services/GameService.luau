-- The core loop: creatures collect coins from the player's target, combos, jackpots, zone progress,
-- Big/Titan periodic skills, offline earnings and what the client sees (currency, pets, titles).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Breakables = require(Shared.Config.Breakables)
local Constants = require(Shared.Config.Constants)
local Products = require(Shared.Config.Products)
local Upgrades = require(Shared.Config.Upgrades)
local World1 = require(Shared.Config.World1)
local Cosmetics = require(Shared.Config.Cosmetics)
local Items = require(Shared.Config.Items)
local Progression = require(Shared.Config.Progression)
local Bag = require(Shared.Logic.Bag)
local Boosts = require(Shared.Logic.Boosts)
local Combo = require(Shared.Logic.Combo)
local Gear = require(Shared.Logic.Gear)
local Loot = require(Shared.Logic.Loot)
local Effects = require(Shared.Logic.Effects)
local Format = require(Shared.Logic.Format)
local Inventory = require(Shared.Logic.Inventory)
local MapLayout = require(Shared.Logic.MapLayout)
local PetMath = require(Shared.Logic.PetMath)
local Achievements = require(Shared.Logic.Achievements)
local Expedition = require(Shared.Logic.Expedition)
local GemShop = require(Shared.Logic.GemShop)
local Events = require(Shared.Logic.Events)
local LiveEvent = require(Shared.Logic.LiveEvent)
local FirstClear = require(Shared.Logic.FirstClear)
local EventConfig = require(Shared.Config.Events)
local Reload = require(Shared.Logic.Reload)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local BreakableService = require(script.Parent.BreakableService)
local DataService = require(script.Parent.DataService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData

local GameService = {}

-- Fired for quest and pass progress: (player, event, amount). Events: Coins, Break, Hatch, Combo,
-- Fuse, Big, Guardian, Restore, Rift, Expedition, Reload, Golden, Pixel, Titan, BigCatch, Zone, Streak, Trade.
GameService.Progress = Signal.new() :: Signal.Signal<Player, string, number>
-- Fired for every creature hatched (species, variant), even auto-deleted ones
GameService.Hatched = Signal.new() :: Signal.Signal<Player, string, string>

function GameService.progress(player: Player, event: string, amount: number)
	GameService.Progress:Fire(player, event, amount)
end

-- Today's Pixel Rift zone (set by ProgressionService).
GameService.riftZone = 0
-- Rift Keys open a short extra rift: zone id -> os.clock() when it closes
GameService.keyRifts = {} :: { [number]: number }

-- True for the daily Pixel Rift zone and for zones with an open Rift Key rift.
function GameService.isRift(zoneId: number?): boolean
	if not zoneId then
		return false
	end
	if zoneId == GameService.riftZone then
		return true
	end
	local ends = GameService.keyRifts[zoneId]
	return ends ~= nil and os.clock() < ends
end

-- The running Live Event (LiveEventService sets it), or nil.
GameService.live = nil :: LiveEvent.Live?

function GameService.liveBonus(stat: string): number
	return LiveEvent.bonus(GameService.live, stat, os.time())
end

-- The running limited-time event, or nil. In Studio, Config/Events.TEST_EVENT forces one.
function GameService.event(): EventConfig.Event?
	local forced = if RunService:IsStudio() then EventConfig.TEST_EVENT else nil
	return Events.active(os.time(), forced)
end

-- Totems placed with gadgets: zone id -> stat -> os.clock() when it ends. Everyone in the zone gets +50%.
GameService.TOTEM_MULT = 1.5
local totems: { [number]: { [string]: number } } = {}

function GameService.placeTotem(zoneId: number, stat: string, seconds: number)
	totems[zoneId] = totems[zoneId] or {}
	totems[zoneId][stat] = math.max(totems[zoneId][stat] or 0, os.clock()) + seconds
end

function GameService.totem(zoneId: number?, stat: string): number
	local zone = if zoneId then totems[zoneId] else nil
	return if zone and (zone[stat] or 0) > os.clock() then GameService.TOTEM_MULT else 1
end

local function riftCoinMult(runtime: State.Runtime, zoneId: number?): number
	if GameService.isRift(zoneId) then
		return Progression.RIFT_COINS * Effects.get(runtime.effects, "RiftCoins")
	end
	return 1
end

local NotifyRemote = Net.event("Notify")
local DataRemote = Net.event("Data")
local CurrencyRemote = Net.event("Currency")
local BreakFx = Net.event("BreakFx")
local SkillFx = Net.event("SkillFx")
local OfflineRemote = Net.event("OfflineEarnings")

local petDisplay = Instance.new("Folder")
petDisplay.Name = "PetDisplay"
petDisplay.Parent = ReplicatedStorage

local rng = Random.new()
local lastValidPosition: { [Player]: CFrame } = {}
local hatchEggs: ((Player, number, number, number, string?) -> ())? = nil

---------------------------------------------------------------------------------------------------------------
-- Helpers

-- Short unique id for a new creature.
function GameService.newId(): string
	return string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 16)
end

function GameService.notify(player: Player, text: string, kind: string?)
	NotifyRemote:FireClient(player, text, kind or "info")
end

-- Tells everyone standing in a zone (totems and other zone events).
function GameService.notifyZone(zoneId: number, text: string, kind: string?)
	for player, runtime in State.all() do
		if runtime.zoneId == zoneId and player.Parent then
			GameService.notify(player, text, kind)
		end
	end
end

-- Whole server. Kept for the big moments only: Titans, Pixels, jackpots and Server Boosts.
function GameService.notifyAll(text: string, kind: string?)
	NotifyRemote:FireAllClients(text, kind or "info")
end

function GameService.maxSlots(player: Player): number
	local data = DataService.get(player)
	local runtime = State.get(player)
	local slots = Constants.BASE_TEAM_SLOTS + (if data then data.upgrades.TeamSlots or 0 else 0)
	if runtime and runtime.vip then
		slots += Products.VIP_EXTRA_SLOTS
	end
	if runtime and runtime.passes.TeamSlots then
		slots += Products.PASS_TEAM_SLOTS
	end
	-- Passes give slots sooner, never more than free players can reach: the Strongest Team board stays fair
	return math.min(Constants.MAX_TEAM_SLOTS, slots)
end

-- Trip slots from the Extra Trip pass.
function GameService.extraTripSlots(player: Player): number
	local runtime = State.get(player)
	if not runtime then
		return 0
	end
	return if runtime.passes.TripSlot then Products.PASS_TRIP_SLOTS else 0
end

function GameService.capacity(player: Player): number
	local data = DataService.get(player)
	if not data then
		return Constants.BASE_STORAGE
	end
	local _, perks = Achievements.forData(data)
	local runtime = State.get(player)
	local pass = if runtime and runtime.passes.Storage then Products.PASS_STORAGE else 0
	return Constants.BASE_STORAGE
		+ Upgrades.storageBonus(data.upgrades.Storage or 0)
		+ perks.storage
		+ pass
		+ GemShop.storageBonus(data.gemShop)
end

function GameService.luck(player: Player): number
	local runtime = State.get(player)
	if not runtime then
		return 1
	end
	local data = DataService.get(player)
	local saved = if data then Boosts.active(data.boosts, "Luck") else 1
	return Effects.get(runtime.effects, "Luck")
		* State.boost(runtime, "Luck", os.clock())
		* saved
		* Gear.get(runtime.gear, "Luck")
		* GameService.totem(runtime.zoneId, "Luck")
		* GameService.liveBonus("Luck")
		* (if data then FirstClear.luckMult(data.clears) else 1)
end

-- Extra multiplier per variant for hatching: skills plus the saved Pixel boost.
function GameService.variantChance(player: Player, eggZone: number?): { [string]: number }
	local runtime = State.get(player)
	local data = DataService.get(player)
	local chances = if runtime then table.clone(runtime.effects.variantChance) else {}
	if data then
		chances.Pixel = (chances.Pixel or 1) * Boosts.active(data.boosts, "Pixel")
		if runtime then
			chances.Pixel *= Gear.get(runtime.gear, "Pixel")
		end
	end
	if GameService.isRift(eggZone) then
		chances.Pixel = (chances.Pixel or 1) * Progression.RIFT_PIXEL_CHANCE
	end
	chances.Pixel = (chances.Pixel or 1) * GameService.liveBonus("Pixel")
	return chances
end

-- Adds a saved timed boost (elixirs, ads) and tells the client.
function GameService.addBoost(player: Player, stat: string, mult: number, seconds: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	Boosts.add(data.boosts, stat, mult, seconds, Items.BOOST_CAP_SECONDS)
	if stat == "Speed" then
		GameService.refresh(player)
	end
	GameService.markDirty(player)
end

function GameService.giveItem(player: Player, itemId: string, amount: number, announce: boolean?)
	local data = DataService.get(player)
	local item = Items.byId[itemId]
	if not data or not item then
		return
	end
	Bag.add(data.items, itemId, amount)
	GameService.markDirty(player)
	if announce then
		NotifyRemote:FireClient(player, ("Found %s%s!"):format(item.name, if amount > 1 then " x" .. amount else ""), "success")
	end
end

function GameService.markDirty(player: Player)
	local runtime = State.get(player)
	if runtime then
		runtime.dirtyData = true
	end
end

-- MembershipService registers how to read game passes and Premium; it runs before the first refresh,
-- so pass slots and VIP perks count from the start (avoids a require cycle).
local passLoader: ((Player) -> ())? = nil
function GameService.setPassLoader(fn: (Player) -> ())
	passLoader = fn
end

-- Lets PetService register the hatch function used by EggDrop skills (avoids a require cycle).
function GameService.setHatcher(fn: (Player, number, number, number, string?) -> ())
	hatchEggs = fn
end

-- Free eggs (ad rewards, daily rewards): from the zone the player stands in, or their best unlocked egg.
function GameService.grantFreeEggs(player: Player, count: number, luck: number?, minVariant: string?)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or not hatchEggs then
		return
	end
	local zone = if runtime.zoneId then World1.zonesById[runtime.zoneId] else nil
	local zoneId = 1
	if zone and zone.eggPrice > 0 then
		zoneId = zone.id
	else
		for _, candidate in World1.zones do
			if candidate.eggPrice > 0 and data.unlockedZones[tostring(candidate.id)] then
				zoneId = candidate.id
			end
		end
	end
	hatchEggs(player, zoneId, count, luck or 1, minVariant)
end


-- Permanent coin multiplier from Reloads (x1.5 each).
function GameService.reloadMult(data: PlayerData): number
	return Reload.coinMult(data.reloads or 0)
end

function GameService.tapPower(runtime: State.Runtime, data: PlayerData): number
	return (Constants.BASE_TAP_POWER + runtime.power * Upgrades.tapShare(data.upgrades.TapPower or 0))
		* Gear.get(runtime.gear, "Tap")
end

local function zoneElement(zoneId: number?): string
	local zone = if zoneId then World1.zonesById[zoneId] else nil
	return if zone then zone.element else "Neutral"
end

-- Recomputes effects, power, the visible team and walk speed after anything changes.
function GameService.refresh(player: Player)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime then
		return
	end
	Inventory.sanitize(data, GameService.maxSlots(player))
	runtime.effects = Effects.collect(data.pets, data.equipped)
	runtime.gear = Gear.compute(data.cartridges)

	-- Pets others can see
	local folder = petDisplay:FindFirstChild(tostring(player.UserId))
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = tostring(player.UserId)
		folder.Parent = petDisplay
	end
	local wanted: { [string]: string } = {}
	for _, petId in data.equipped do
		local pet = data.pets[petId]
		if pet then
			wanted[petId] = ("%s|%s|%s|%s"):format(pet.s, pet.v, pet.z, pet.st or "")
		end
	end
	for _, child in (folder :: Folder):GetChildren() do
		if not wanted[child.Name] then
			child:Destroy()
		end
	end
	-- Cubeling Ride: the strongest creature in the team carries the player. Clients draw it (RideClient)
	-- and hide it from the followers; the character stands higher while there is one to ride.
	local rideDef = if data.equippedRide and data.rides[data.equippedRide] then Cosmetics.rideById[data.equippedRide] else nil
	local ridePetId = ""
	if rideDef and rideDef.style == "creature" then
		local bestPower = -1
		for _, petId in data.equipped do
			local pet = data.pets[petId]
			if pet and wanted[petId] then
				local petPower = PetMath.basePower(pet)
				if petPower > bestPower then
					ridePetId, bestPower = petId, petPower
				end
			end
		end
	end
	local wasRiding = (player:GetAttribute("RidePetId") or "") ~= ""
	if player:GetAttribute("RidePetId") ~= ridePetId then
		player:SetAttribute("RidePetId", ridePetId)
		player:SetAttribute("RidePet", if ridePetId ~= "" then wanted[ridePetId] else "")
		if wasRiding ~= (ridePetId ~= "") then
			GameService.refreshTitles(player) -- stand higher or lower
		end
	end

	for petId, value in wanted do
		local existing = (folder :: Folder):FindFirstChild(petId) :: StringValue?
		if not existing then
			local sv = Instance.new("StringValue")
			sv.Name = petId
			sv.Value = value
			sv.Parent = folder
		elseif existing.Value ~= value then
			existing.Value = value
		end
	end

	-- Walk speed
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local speed = 16 * Upgrades.walkSpeedMult(data.upgrades.WalkSpeed or 0)
		if data.equippedRide and data.rides[data.equippedRide] then
			speed *= Cosmetics.RIDE_SPEED
		end
		speed *= math.min(3, Effects.get(runtime.effects, "Speed") * Boosts.active(data.boosts, "Speed") * Gear.get(runtime.gear, "Speed"))
		humanoid.WalkSpeed = speed
	end

	runtime.dirtyData = true
end

local function computePower(runtime: State.Runtime, data: PlayerData, now: number)
	local boosts = {
		Power = State.boost(runtime, "Power", now) * Boosts.active(data.boosts, "Power") * Gear.get(runtime.gear, "Power"),
		Element = if State.boost(runtime, "Element", now) > 1 then State.boost(runtime, "Element", now) else nil,
		CloneCount = if State.boost(runtime, "Clone", now) > 1 then State.boost(runtime, "Clone", now) else nil,
	}
	runtime.power = PetMath.teamPower(data.pets, data.equipped, zoneElement(runtime.zoneId), runtime.effects, boosts)
end

local function comboActive(runtime: State.Runtime, now: number): boolean
	local hold = Effects.get(runtime.effects, "ComboHold") + Gear.get(runtime.gear, "ComboHold")
	return now - runtime.lastBreak <= Constants.COMBO_WINDOW + hold
end

local function coinMultiplier(
	runtime: State.Runtime,
	data: PlayerData,
	kind: Breakables.BreakableKind?,
	now: number,
	zoneId: number?,
	noCombo: boolean?
): number
	local mult = Upgrades.coinMult(data.upgrades.CoinMult or 0) * riftCoinMult(runtime, zoneId)
	mult *= Effects.get(runtime.effects, "Coins")
	mult *= State.boost(runtime, "Coins", now)
	mult *= Boosts.active(data.boosts, "Coins")
	mult *= Gear.get(runtime.gear, "Coins")
	mult *= GameService.reloadMult(data)
	mult *= GameService.totem(zoneId, "Coins")
	mult *= Events.bonus(GameService.event(), "Coins")
	mult *= GameService.liveBonus("Coins")
	mult *= FirstClear.coinMult(data.clears)
	if runtime.premium then
		mult *= Products.PREMIUM_COINS
	end
	if kind and kind.isPile then
		mult *= Effects.get(runtime.effects, "Pile")
	end
	if kind and kind.isChest then
		mult *= Effects.get(runtime.effects, "Chest") * Gear.get(runtime.gear, "Chest")
	end
	if not noCombo and not runtime.auto and runtime.combo > 0 then
		mult *= Combo.multiplier(runtime.combo)
	end
	return mult
end

-- Adds coins and zone progress. `raw` is the amount before multipliers (used for zone progress).
function GameService.addCoins(player: Player, amount: number, zoneId: number?, raw: number?)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or amount <= 0 then
		return
	end
	data.coins += amount
	-- The Coins leaderboard leaves out timed boosts (bought, watched or from elixirs) and Premium,
	-- so it can't be bought: it ranks what you earn by playing. Creature skills still count.
	local timed = Boosts.active(data.boosts, "Coins")
	if runtime.premium then
		timed *= Products.PREMIUM_COINS
	end
	data.stats.boardCoins = (data.stats.boardCoins or data.stats.coinsEarned or 0) + amount / timed
	data.stats.coinsEarned = (data.stats.coinsEarned or 0) + amount
	GameService.progress(player, "Coins", amount)
	if zoneId and zoneId > 0 then
		local zone = World1.zonesById[zoneId]
		local key = tostring(zoneId)
		local before = data.zoneProgress[key] or 0
		local progress = before + (raw or amount) * Effects.get(runtime.effects, "Restore")
		data.zoneProgress[key] = progress
		if zone.restoreGoal > 0 and before < zone.restoreGoal and progress >= zone.restoreGoal then
			GameService.notify(player, zone.name .. " is fully restored! +10% offline earnings", "success")
			GameService.progress(player, "Restore", 1)
			runtime.dirtyData = true
		end
	end
end

-- Coins from rewards (keys, trips): raw amount with the player's coin multipliers applied, except the combo.
function GameService.rewardCoins(player: Player, raw: number, zoneId: number?): number
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime then
		return 0
	end
	local gained = raw * coinMultiplier(runtime, data, nil, os.clock(), zoneId, true)
	GameService.addCoins(player, gained, zoneId, raw)
	return gained
end

-- Takes coins from a source for the player, with all multipliers applied.
function GameService.collectFrom(player: Player, source: BreakableService.Source, rawAmount: number): number
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime then
		return 0
	end
	local taken = BreakableService.collect(source, player, rawAmount)
	if taken <= 0 then
		return 0
	end
	local gained = taken * coinMultiplier(runtime, data, source.kind, os.clock(), source.zoneId)
	GameService.addCoins(player, gained, source.zoneId, taken)
	return gained
end

local function restoredZones(data: PlayerData): number
	local count = 0
	for _, zone in World1.zones do
		if zone.restoreGoal > 0 and (data.zoneProgress[tostring(zone.id)] or 0) >= zone.restoreGoal then
			count += 1
		end
	end
	return count
end

---------------------------------------------------------------------------------------------------------------
-- Breaking

BreakableService.Broken:Connect(function(source: BreakableService.Source, contributors: { [Player]: number })
	local now = os.clock()
	local instantRespawn = false
	for player, share in contributors do
		local runtime = State.get(player)
		local data = DataService.get(player)
		if not runtime or not data or not player.Parent then
			continue
		end

		if not runtime.auto then
			runtime.combo = if comboActive(runtime, now) then runtime.combo + 1 else 1
			runtime.lastBreak = now
			GameService.progress(player, "Combo", runtime.combo)
		end
		GameService.progress(player, "Break", 1)
		if GameService.isRift(source.zoneId) then
			GameService.progress(player, "Rift", 1)
		end

		local mult = coinMultiplier(runtime, data, source.kind, now, source.zoneId)
		local bonus = 0
		local jackpotChance = Constants.JACKPOT_CHANCE
				* Effects.get(runtime.effects, "Jackpot")
				* State.boost(runtime, "Jackpot", now)
			+ Gear.get(runtime.gear, "Jackpot")
		local jackpot = rng:NextNumber() < math.min(1, jackpotChance)
		if jackpot then
			bonus += share * (Constants.JACKPOT_MULT - 1) * mult
		end
		local golden = rng:NextNumber()
			< Effects.get(runtime.effects, "GoldenSources") + Gear.get(runtime.gear, "GoldenSources")
		if golden then
			bonus += share * 9 * mult
		end
		if bonus > 0 then
			GameService.addCoins(player, bonus, source.zoneId, 0)
		end

		local gemChance = (Constants.BASE_GEM_CHANCE + Effects.get(runtime.effects, "Gem"))
			* Boosts.active(data.boosts, "Gem")
			* Gear.get(runtime.gear, "Gem")
			* Effects.get(runtime.effects, "GemMult")
			* Events.bonus(GameService.event(), "Gem")
			* GameService.liveBonus("Gem")
		if rng:NextNumber() < gemChance then
			data.gems += math.max(1, source.zoneId)
		end

		-- A guardian's loot only goes to players whose fight counts (not on their 4h cooldown)
		local special = source.special
		local lootAllowed = not (special and special.type == "Guardian" and not special.eligible[player])
		if lootAllowed then
			for _, drop in Loot.rollAll(source.kind.id, source.zoneId, function()
				return rng:NextNumber()
			end) do
				GameService.giveItem(player, drop, 1, true)
			end
		end

		if Effects.get(runtime.effects, "InstantRespawn") > 0 or State.boost(runtime, "Respawn", now) > 1 then
			instantRespawn = true
		end

		BreakFx:FireClient(player, source.part.Position, share * mult + bonus, jackpot, golden)

		if runtime.target == source.name then
			runtime.target = nil
		end
	end
	-- Bigs and guardians are removed by HuntService instead of coming back
	if not source.special then
		BreakableService.respawn(source, if instantRespawn then 0.5 else source.kind.respawn)
	end
end)

---------------------------------------------------------------------------------------------------------------
-- Big and Titan periodic skills

local function center(player: Player, runtime: State.Runtime): Vector3?
	if runtime.target then
		local source = BreakableService.get(runtime.target)
		if source then
			return source.part.Position
		end
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position else nil
end

local function runPeriodic(player: Player, runtime: State.Runtime, data: PlayerData, entry: Effects.PeriodicEntry, now: number)
	local spec = entry.spec
	local zoneId = runtime.zoneId
	local zone = if zoneId then World1.zonesById[zoneId] else nil
	local inPlayZone = zone ~= nil and zone.id > 0
	local kind = spec.kind
	local showFx = true

	if kind == "Strike" or kind == "Wave" or kind == "Smash" then
		if not inPlayZone then
			return
		end
		local alive = BreakableService.aliveInZone(zoneId :: number)
		local picked = {}
		if kind == "Wave" then
			for _, source in alive do
				if not spec.onlyKind or source.kind.id == spec.onlyKind then
					table.insert(picked, source)
				end
			end
		elseif kind == "Smash" then
			local biggest = nil
			for _, source in alive do
				if not biggest or source.coinsMax > biggest.coinsMax then
					biggest = source
				end
			end
			if biggest then
				table.insert(picked, biggest)
			end
		else
			local count = spec.count or math.floor(#alive * (spec.fraction or 0))
			for _ = 1, math.min(count, #alive) do
				table.insert(picked, table.remove(alive, rng:NextInteger(1, #alive)))
			end
		end
		for _, source in picked do
			GameService.collectFrom(player, source, source.coinsLeft)
		end
		showFx = #picked > 0
	elseif kind == "Area" or kind == "Drain" then
		if not inPlayZone then
			return
		end
		local pet = data.pets[entry.petId]
		local petPower = if pet then PetMath.basePower(pet) else 0
		local pos = center(player, runtime)
		for _, source in BreakableService.aliveInZone(zoneId :: number) do
			if kind == "Drain" then
				GameService.collectFrom(player, source, source.coinsMax * (spec.fraction or 0))
			elseif pos and (source.part.Position - pos).Magnitude <= (spec.radius or 30) then
				GameService.collectFrom(player, source, petPower * (spec.damageMult or 1))
			end
		end
		if kind == "Drain" then
			return -- runs every second, no popup
		end
	elseif kind == "Boost" then
		local stat = spec.stat or "Coins"
		State.addBoost(runtime, stat, spec.mult or 1, spec.duration or 10, now)
	elseif kind == "CloneArmy" then
		State.addBoost(runtime, "Clone", spec.count or 1, spec.duration or 10, now)
	elseif kind == "Rain" then
		local scale = if zone and zone.id > 0 then zone.scale else 1
		local raw = (spec.chests or 1) * Breakables.byId.Chest.coins * scale
		GameService.addCoins(player, raw * coinMultiplier(runtime, data, nil, now, zoneId), zoneId, raw)
	elseif kind == "GemRain" then
		data.gems += (spec.amount or 1) * math.max(1, zoneId or 1)
	elseif kind == "ComboAdd" then
		runtime.combo += spec.amount or 1
		runtime.lastBreak = now
	elseif kind == "EggDrop" then
		local eggZone = if zone and zone.eggPrice > 0 then zone.id else 1
		if hatchEggs then
			hatchEggs(player, eggZone, spec.count or 1, spec.luck or 1, spec.minVariant)
		end
	end

	local pet = data.pets[entry.petId]
	if pet and showFx then
		SkillFx:FireClient(player, kind, pet.s, pet.z, center(player, runtime))
	end
end

---------------------------------------------------------------------------------------------------------------
-- Player lifecycle

local function applyTitles(player: Player, character: Model)
	local data = DataService.get(player)
	local runtime = State.get(player)
	local head = character:WaitForChild("Head", 10) :: BasePart?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not head or not root or not data or not runtime then
		return
	end

	-- Title: the equipped one, or VIP / Supporter by default
	local old = head:FindFirstChild("Titles")
	if old then
		old:Destroy()
	end
	local title: Cosmetics.Title? = nil
	if data.equippedTitle and data.titles[data.equippedTitle] then
		title = Cosmetics.titleById[data.equippedTitle]
	elseif runtime.vip then
		title = Cosmetics.titleById.VIP
	elseif data.titles.Supporter then
		title = Cosmetics.titleById.Supporter
	end
	-- Rank badge on top, title under it
	local rank = Achievements.forData(data)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Titles"
	gui.Size = UDim2.fromOffset(220, if title then 50 else 22)
	gui.StudsOffset = Vector3.new(0, if title then 3 else 2.4, 0)
	gui.MaxDistance = 80
	local rankLabel = Instance.new("TextLabel")
	rankLabel.Size = UDim2.new(1, 0, 0, 20)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Font = Enum.Font.FredokaOne
	rankLabel.TextScaled = true
	rankLabel.TextColor3 = Color3.fromRGB(255, 225, 120)
	rankLabel.TextStrokeTransparency = 0.3
	rankLabel.Text = "⭐ " .. rank .. (if runtime.clanTag then (" [%s]"):format(runtime.clanTag) else "")
	rankLabel.Parent = gui
	if title then
		local textLabel = Instance.new("TextLabel")
		textLabel.Position = UDim2.fromOffset(0, 20)
		textLabel.Size = UDim2.new(1, 0, 0, 30)
		textLabel.BackgroundTransparency = 1
		textLabel.Font = Enum.Font.FredokaOne
		textLabel.TextScaled = true
		textLabel.TextColor3 = title.color
		textLabel.TextStrokeTransparency = 0.2
		textLabel.Text = title.text
		textLabel.Parent = gui
	end
	gui.Parent = head

	-- Ride: welded under the feet; the character floats a little higher while riding
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local oldRide = character:FindFirstChild("Ride")
	if oldRide then
		oldRide:Destroy()
	end
	local baseHip = character:GetAttribute("BaseHipHeight")
	if humanoid and typeof(baseHip) ~= "number" then
		baseHip = humanoid.HipHeight
		character:SetAttribute("BaseHipHeight", baseHip)
	end
	local rideDef = if data.equippedRide and data.rides[data.equippedRide] then Cosmetics.rideById[data.equippedRide] else nil
	local onCreature = rideDef ~= nil and rideDef.style == "creature"
	-- A floating seat: clients draw it under the player and pose them on it (RideClient), so nothing is welded
	local onSeat = rideDef ~= nil and rideDef.style == "seat"
	player:SetAttribute("RideSeat", if onSeat and rideDef then rideDef.seat or "" else "")
	if humanoid and typeof(baseHip) == "number" then
		-- On a creature the player sits on its saddle (RideClient plays the sit pose). R6 legs aren't part of HipHeight, so they come off. Nothing to
		-- sit on with an empty team.
		local riding = (player:GetAttribute("RidePetId") or "") ~= ""
		local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else 0
		if onCreature and riding then
			humanoid.HipHeight = math.max(baseHip, Cosmetics.RIDE_HIP - legs)
		elseif onSeat then
			humanoid.HipHeight = Cosmetics.SEAT_HIP - legs
		else
			humanoid.HipHeight = baseHip + (if rideDef and not onCreature then 0.6 else 0)
		end
		if rideDef and not onCreature and not onSeat then
			local ride = Instance.new("Model")
			ride.Name = "Ride"
			local footY = -(root.Size.Y / 2 + baseHip + 0.6) + 0.2
			local function piece(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
				local p = Instance.new("Part")
				p.Size = size
				p.Color = color
				p.Material = material
				p.Shape = shape or Enum.PartType.Block
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Massless = true
				p.CFrame = root.CFrame * offset
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = p
				weld.Parent = p
				p.Parent = ride
			end
			if rideDef.style == "cloud" then
				for i, x in { -1.1, 0, 1.1 } do
					piece(Vector3.one * (if i == 2 then 2.4 else 1.9), CFrame.new(x, footY, 0.2 * i - 0.4), rideDef.color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
				end
			else
				piece(Vector3.new(2.4, 0.25, 5), CFrame.new(0, footY, 0), rideDef.color, Enum.Material.SmoothPlastic)
				piece(Vector3.new(2.5, 0.08, 5.1), CFrame.new(0, footY - 0.16, 0), rideDef.glow, Enum.Material.Neon)
			end
			ride.Parent = character
		end
	end

	-- Trail
	for _, name in { "CosmeticTrail", "TrailTop", "TrailBottom" } do
		local existing = root:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	local trailDef = if data.equippedTrail and data.trails[data.equippedTrail]
		then Cosmetics.trailById[data.equippedTrail]
		else nil
	if trailDef then
		local top = Instance.new("Attachment")
		top.Name = "TrailTop"
		top.Position = Vector3.new(0, 0.9, 0)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Name = "TrailBottom"
		bottom.Position = Vector3.new(0, -0.9, 0)
		bottom.Parent = root
		local keypoints = {}
		for i, color in trailDef.colors do
			table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #trailDef.colors - 1), color))
		end
		if #keypoints == 1 then
			table.insert(keypoints, ColorSequenceKeypoint.new(1, trailDef.colors[1]))
		end
		local trail = Instance.new("Trail")
		trail.Name = "CosmeticTrail"
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Color = ColorSequence.new(keypoints)
		trail.Lifetime = 0.6
		trail.LightEmission = 0.4
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.Parent = root
	end

	-- Aura: particles around the character
	local oldAura = character:FindFirstChild("Aura")
	if oldAura then
		oldAura:Destroy()
	end
	local auraDef = if data.equippedAura and data.auras[data.equippedAura] then Cosmetics.auraById[data.equippedAura] else nil
	if auraDef then
		-- An invisible part gives the particles a shape to come out of (an attachment is a single point)
		local holder = Instance.new("Part")
		holder.Name = "Aura"
		holder.Transparency = 1
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Massless = true
		holder.Size = Vector3.new(3.5, 4.5, 3.5)
		local auraOffset = Vector3.zero
		local first = auraDef.colors[1]
		local last = auraDef.colors[#auraDef.colors]
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(first, last)
		emitter.LightEmission = 0.6
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		emitter.Shape = Enum.ParticleEmitterShape.Cylinder
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		emitter.LockedToPart = false
		if auraDef.style == "flame" then
			emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
			emitter.Lifetime = NumberRange.new(0.5, 0.9)
			emitter.Speed = NumberRange.new(0.5, 1.5)
			emitter.Acceleration = Vector3.new(0, 6, 0)
			emitter.Rate = 30
			holder.Size = Vector3.new(3, 1, 3)
			auraOffset = Vector3.new(0, -2.2, 0)
		elseif auraDef.style == "cubes" then
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Size = NumberSequence.new(0.35)
			emitter.Lifetime = NumberRange.new(1, 1.6)
			emitter.Speed = NumberRange.new(0.3, 0.8)
			emitter.RotSpeed = NumberRange.new(-90, 90)
			emitter.Acceleration = Vector3.new(0, 1.5, 0)
			emitter.Rate = 14
		elseif auraDef.style == "ring" then
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Shape = Enum.ParticleEmitterShape.Disc
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) })
			emitter.Lifetime = NumberRange.new(0.8, 1.2)
			emitter.Speed = NumberRange.new(0.2, 0.4)
			emitter.Acceleration = Vector3.new(0, 2, 0)
			emitter.Rate = 24
			holder.Size = Vector3.new(5, 0.2, 5)
			auraOffset = Vector3.new(0, -2.8, 0)
		else -- sparkle
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
			emitter.Lifetime = NumberRange.new(0.8, 1.4)
			emitter.Speed = NumberRange.new(0.2, 0.6)
			emitter.Acceleration = Vector3.new(0, 1, 0)
			emitter.Rate = 16
		end
		emitter.Parent = holder
		holder.CFrame = root.CFrame * CFrame.new(auraOffset)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = holder
		weld.Parent = holder
		holder.Parent = character
	end
end

function GameService.refreshTitles(player: Player)
	if player.Character then
		task.spawn(applyTitles, player, player.Character)
	end
end

local function giveOfflineEarnings(player: Player, data: PlayerData, runtime: State.Runtime)
	if data.lastSeen <= 0 or data.lastPower <= 0 then
		return
	end
	local elapsed = os.time() - data.lastSeen
	if elapsed < 60 then
		return
	end
	local hours = Upgrades.offlineHours(data.upgrades.OfflineTime or 0, Constants.BASE_OFFLINE_HOURS)
	if runtime.vip then
		hours += Products.VIP_EXTRA_OFFLINE_HOURS
	end
	hours += Gear.get(runtime.gear, "OfflineHours")
	local seconds = math.min(elapsed, hours * 3600)
	local coins = data.lastPower
		* seconds
		* Constants.OFFLINE_EFFICIENCY
		* Effects.get(runtime.effects, "Offline")
		* Gear.get(runtime.gear, "Offline")
		* GameService.reloadMult(data)
		* (1 + 0.1 * restoredZones(data))
	if coins > 0 then
		data.coins += coins
		OfflineRemote:FireClient(player, coins, seconds)
	end
end

local function leaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("StringValue")
	coins.Name = "Coins"
	coins.Value = "0"
	coins.Parent = stats
	local power = Instance.new("StringValue")
	power.Name = "Power"
	power.Value = "0"
	power.Parent = stats
	stats.Parent = player
end

-- New players start with a small team so the first seconds are already fun.
local STARTER_PETS = { "Cubby", "Cubby", "Kitty" }
local STARTER_COINS = 100

local function giveStarterPack(player: Player, data: PlayerData)
	if data.flags.starterGiven then
		return
	end
	data.flags.starterGiven = true
	for _, speciesId in STARTER_PETS do
		Inventory.add(data, { s = speciesId, v = "Normal", z = "Normal" }, GameService.newId)
	end
	data.coins += STARTER_COINS
	Inventory.equipBest(data, GameService.maxSlots(player))
end

local function onLoaded(player: Player, data: PlayerData)
	local runtime = State.create(player)
	-- Auto farm picks up where it was after a rejoin (an AFK kick, a server restart)
	runtime.auto = data.settings.autoFarm == true
	-- Passes first: the team size (VIP, Team Slots) and VIP offline hours depend on them
	if passLoader then
		local ok, err = pcall(passLoader :: (Player) -> (), player)
		if not ok then
			warn("[Game] pass check failed", err)
		end
		if not player.Parent or State.get(player) ~= runtime then
			return
		end
	end
	giveStarterPack(player, data)
	-- Everyone can ride their strongest creature, and sit on the meadow's seat, from the start
	data.rides = data.rides or {}
	for _, id in Cosmetics.RIDE_STARTERS do
		data.rides[id] = true
	end
	leaderstats(player)
	GameService.refresh(player)
	giveOfflineEarnings(player, data, runtime)
	player.CharacterAdded:Connect(function(character)
		GameService.refresh(player)
		applyTitles(player, character)
	end)
	if player.Character then
		GameService.refresh(player)
		task.spawn(applyTitles, player, player.Character)
	end
end

-- Runs before the final save so offline earnings use the team the player left with.
-- Doesn't use the runtime state: it may already be gone when the player leaves.
local function storeLastPower(_player: Player, data: PlayerData)
	data.lastPower = PetMath.teamPower(data.pets, data.equipped, "Neutral", Effects.collect(data.pets, data.equipped))
end

local function onRemoving(player: Player)
	local folder = petDisplay:FindFirstChild(tostring(player.UserId))
	if folder then
		folder:Destroy()
	end
	lastValidPosition[player] = nil
	State.remove(player)
end

---------------------------------------------------------------------------------------------------------------
-- Main loop

local function snapshot(player: Player, data: PlayerData): { [string]: any }
	local rank, perks = Achievements.forData(data)
	return {
		coins = data.coins,
		gems = data.gems,
		pets = data.pets,
		equipped = data.equipped,
		unlockedZones = data.unlockedZones,
		zoneProgress = data.zoneProgress,
		upgrades = data.upgrades,
		stats = data.stats,
		titles = data.titles,
		settings = data.settings,
		items = data.items,
		boosts = data.boosts,
		daily = data.daily,
		quests = data.quests,
		pass = data.pass,
		guardians = data.guardians,
		clears = data.clears,
		fishing = data.fishing,
		trails = data.trails,
		equippedTitle = data.equippedTitle,
		equippedTrail = data.equippedTrail,
		cartridges = data.cartridges,
		loadouts = data.loadouts,
		cartridgeSlots = Gear.slots(data.reloads, perks.cartridgeSlots),
		gearSets = (State.get(player) :: State.Runtime).gear.sets,
		reloads = data.reloads,
		reloadMult = GameService.reloadMult(data),
		canReload = (Reload.canReload(data)),
		nextReloadMult = Reload.coinMult(data.reloads + 1),
		nextCartridgeSlots = Gear.slots(data.reloads + 1, perks.cartridgeSlots),
		expeditions = data.expeditions,
		expeditionSlots = Expedition.slots(data.reloads, perks.tripSlots + GameService.extraTripSlots(player)),
		nextExpeditionSlots = Expedition.slots(data.reloads + 1, perks.tripSlots + GameService.extraTripSlots(player)),
		passes = (State.get(player) :: State.Runtime).passes,
		premium = (State.get(player) :: State.Runtime).premium,
		achievements = data.achievements,
		index = data.index,
		rank = rank,
		tutorial = data.tutorial,
		tickets = data.tickets,
		gemShop = data.gemShop,
		events = data.events,
		bounty = data.bounty,
		journey = data.journey,
		arcade = data.arcade,
		gifts = data.gifts,
		wheel = data.wheel,
		rides = data.rides,
		equippedRide = data.equippedRide,
		auras = data.auras,
		equippedAura = data.equippedAura,
		hatchFx = data.hatchFx,
		equippedHatchFx = data.equippedHatchFx,
		ads = data.ads,
		playtime = data.playtime,
		maxSlots = GameService.maxSlots(player),
		capacity = GameService.capacity(player),
	}
end

local function questProgressList(quests: { Types.Quest }): { number }
	local out = {}
	for i, quest in quests do
		out[i] = quest.progress
	end
	return out
end

local function tickPlayer(player: Player, runtime: State.Runtime, data: PlayerData, now: number, dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	-- Zone tracking and gate enforcement
	local zoneId = MapLayout.zoneAt(root.Position)
	if zoneId and not data.unlockedZones[tostring(zoneId)] then
		local back = lastValidPosition[player] or CFrame.new(MapLayout.center(0) + Vector3.new(0, 5, 20))
		root.CFrame = back
		GameService.notify(player, "Unlock this zone at its gate first", "error")
		return
	end
	if zoneId then
		lastValidPosition[player] = root.CFrame
	end
	if zoneId ~= runtime.zoneId and zoneId ~= nil then
		runtime.zoneId = zoneId
		if runtime.target then
			local source = BreakableService.get(runtime.target)
			if source and source.zoneId ~= zoneId then
				runtime.target = nil
			end
		end
	end

	if not comboActive(runtime, now) then
		runtime.combo = 0
	end

	computePower(runtime, data, now)

	-- Pick a target
	local source = if runtime.target then BreakableService.get(runtime.target) else nil
	local range = math.max(Constants.TARGET_RANGE, Constants.AUTO_TARGET_RANGE * Effects.get(runtime.effects, "Magnet"))
	if source and (not source.alive or (source.part.Position - root.Position).Magnitude > range) then
		source = nil
		runtime.target = nil
	end
	-- Auto mode picks the next source; Magnet skills do it in manual mode too, in a wider radius
	local magnet = Effects.get(runtime.effects, "Magnet")
	-- In the Hub (zone 0) the only target is the World Boss
	if not source and (runtime.auto or magnet > 1) and runtime.zoneId and runtime.zoneId >= 0 then
		source = BreakableService.nearest(runtime.zoneId, root.Position, Constants.AUTO_TARGET_RANGE * magnet)
		runtime.target = if source then source.name else nil
	end
	player:SetAttribute("Target", runtime.target or "")

	if source and #data.equipped > 0 then
		GameService.collectFrom(player, source, runtime.power * dt)
	end
	-- Auto Tap cartridge: two taps per second without clicking
	if source and (Gear.get(runtime.gear, "AutoTap") > 0 or runtime.passes.AutoTap) and now - runtime.lastTap >= 0.5 then
		runtime.lastTap = now
		GameService.collectFrom(player, source, GameService.tapPower(runtime, data))
	end
end

local function onClick(player: Player, part: BasePart)
	local runtime = State.get(player)
	local data = DataService.get(player)
	local source = BreakableService.get(part.Name)
	if not runtime or not data or not source or not source.alive then
		return
	end
	local zoneKey = tostring(source.zoneId)
	if not data.unlockedZones[zoneKey] then
		return
	end
	runtime.target = source.name
	player:SetAttribute("Target", source.name)
	-- Tapping hits too, so playing actively beats AFK
	local now = os.clock()
	if now - runtime.lastTap >= Constants.TAP_COOLDOWN then
		runtime.lastTap = now
		GameService.collectFrom(player, source, GameService.tapPower(runtime, data))
	end
end

function GameService.init()
	DataService.Loaded:Connect(onLoaded)
	DataService.onBeforeRelease(storeLastPower)
	Players.PlayerRemoving:Connect(onRemoving)

	-- Clicking a source (works on touch too)
	BreakableService.setClickHandler(onClick)

	Net.event("ToggleAuto").OnServerEvent:Connect(function(player, enabled)
		local runtime = State.get(player)
		local data = DataService.get(player)
		if runtime and data and type(enabled) == "boolean" then
			runtime.auto = enabled
			data.settings.autoFarm = enabled
			GameService.markDirty(player)
			if enabled then
				runtime.combo = 0
			end
		end
	end)

	Net.event("SetSetting").OnServerEvent:Connect(function(player, key, value)
		local data = DataService.get(player)
		if not data or type(value) ~= "boolean" then
			return
		end
		local allowed = {
			allowTrades = true,
			autoEquipBest = true,
			lowEnd = true,
			sfx = true,
			music = true,
			autoDeleteNormal = true,
			autoDeleteGolden = true,
			autoHatch = true,
			quickHatch = true,
			calmEffects = true,
		}
		if type(key) == "string" and allowed[key] then
			data.settings[key] = value
			GameService.markDirty(player)
		end
	end)

	-- Collecting
	task.spawn(function()
		local dt = Constants.TICK_SECONDS
		while true do
			task.wait(dt)
			local now = os.clock()
			for player, runtime in State.all() do
				local data = DataService.get(player)
				if data then
					local ok, err = pcall(tickPlayer, player, runtime, data, now, dt)
					if not ok then
						warn("[Game] tick error", err)
					end
				end
			end
		end
	end)

	-- Skills, currency and data pushes
	task.spawn(function()
		local lastSkill = 0
		while true do
			task.wait(0.25)
			local now = os.clock()
			local runSkills = now - lastSkill >= 1
			if runSkills then
				lastSkill = now
			end
			for player, runtime in State.all() do
				local data = DataService.get(player)
				if not data then
					continue
				end
				if runSkills then
					local changed = Boosts.tick(data.boosts, 1)
					if table.find(changed, "Speed") then
						GameService.refresh(player)
					end
					if runtime.gear.fighter then
						local due = runtime.timers["gear:Fighter"]
						if not due then
							runtime.timers["gear:Fighter"] = now + Gear.FIGHTER_EVERY
						elseif now >= due then
							runtime.timers["gear:Fighter"] = now + Gear.FIGHTER_EVERY
							State.addBoost(runtime, "Power", Gear.FIGHTER_MULT, Gear.FIGHTER_DURATION, now)
						end
					end
					for _, entry in runtime.effects.periodic do
						local due = runtime.timers[entry.key]
						if not due then
							runtime.timers[entry.key] = now + entry.spec.every
						elseif now >= due then
							runtime.timers[entry.key] = now + entry.spec.every
							local ok, err = pcall(runPeriodic, player, runtime, data, entry, now)
							if not ok then
								warn("[Game] skill error", err)
							end
						end
					end
				end

				local zone = if runtime.zoneId then World1.zonesById[runtime.zoneId] else nil
				local progress = 0
				if zone and zone.restoreGoal > 0 then
					progress = math.min(1, (data.zoneProgress[tostring(zone.id)] or 0) / zone.restoreGoal)
				end
				local boosts = {}
				for stat, boost in runtime.boosts do
					if boost.untilTime > now and stat ~= "Respawn" then
						boosts["Skill " .. stat] = { mult = boost.mult, left = boost.untilTime - now }
					end
				end
				for stat, boost in Boosts.summary(data.boosts) do
					boosts[stat] = { mult = boost.mult, left = boost.left }
				end
				CurrencyRemote:FireClient(player, {
					coins = data.coins,
					gems = data.gems,
					power = runtime.power,
					combo = if runtime.auto then 0 else runtime.combo,
					comboMult = if runtime.auto then 1 else Combo.multiplier(runtime.combo),
					zoneId = runtime.zoneId,
					zoneProgress = progress,
					auto = runtime.auto,
					boosts = boosts,
					rift = GameService.riftZone,
					questProgress = {
						daily = questProgressList(data.quests.daily),
						weekly = questProgressList(data.quests.weekly),
					},
				})
				local stats = player:FindFirstChild("leaderstats")
				if stats then
					(stats:FindFirstChild("Coins") :: StringValue).Value = Format.abbrev(data.coins);
					(stats:FindFirstChild("Power") :: StringValue).Value = Format.abbrev(runtime.power)
				end
				if runtime.dirtyData then
					runtime.dirtyData = false
					DataRemote:FireClient(player, snapshot(player, data))
				end
			end
		end
	end)
end

return GameService
