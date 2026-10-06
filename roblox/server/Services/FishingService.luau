-- Fishing Pond (Config/Fishing). The server decides when a fish bites and checks the reel came in time.
-- Flow: FishCast -> (server waits) FishBite to the client -> FishReel(perfect) -> FishResult.
-- Auto Fish: the server reels by itself after a bite and casts again, as long as you stay at the pond.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local FishingConfig = require(Shared.Config.Fishing)
local Fishing = require(Shared.Logic.Fishing)
local Format = require(Shared.Logic.Format)
local Loot = require(Shared.Logic.Loot)
local MapLayout = require(Shared.Logic.MapLayout)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

local FishingService = {}

type Cast = { id: number, bite: number?, auto: boolean }

local rng = Random.new()
local casts: { [Player]: Cast } = {}
local autoOn: { [Player]: boolean? } = {}
local lastCast: { [Player]: number } = {}
local nextId = 0

local function rand(): number
	return rng:NextNumber()
end

function FishingService.pondCenter(): Vector3
	return MapLayout.center(0) + FishingConfig.POND_OFFSET
end

local function atPond(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local offset = root.Position - FishingService.pondCenter()
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= FishingConfig.REACH
end

local cast: (Player) -> ()

local function setAuto(player: Player, on: boolean)
	autoOn[player] = if on then true else nil
	Net.event("FishAuto"):FireClient(player, on)
end

local function catch(player: Player, perfect: boolean, auto: boolean)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime then
		return
	end
	local fish = Fishing.roll(perfect, rand)
	local reward = Fishing.reward(fish, runtime.power, auto, rand)
	local isNew, complete = Fishing.record(data.fishing, fish.id)
	GameService.addCoins(player, reward.coins, nil)
	data.gems += reward.gems
	data.tickets += reward.tickets
	local parts = { "💰 " .. Format.abbrev(reward.coins) }
	if reward.gems > 0 then
		table.insert(parts, "💎 " .. reward.gems)
	end
	if reward.tickets > 0 then
		table.insert(parts, "🎟️ " .. reward.tickets)
	end
	if reward.elixir then
		local tiers = reward.elixir :: { number }
		local elixir = Loot.randomElixir(tiers[1], tiers[2], rand)
		GameService.giveItem(player, elixir, 1, false)
		table.insert(parts, "🧪 Elixir")
	end
	if complete and not data.titles[FishingConfig.TITLE] then
		data.titles[FishingConfig.TITLE] = true
		local title = Cosmetics.titleById[FishingConfig.TITLE]
		GameService.notify(player, ("🎣 Fish Index complete! Title: %s"):format(if title then title.text else "Angler"), "rare")
	end
	if fish.rarity == "Legendary" then
		GameService.notifyAll(("🎣 %s caught a %s!"):format(player.DisplayName, fish.name), "rare")
	end
	GameService.progress(player, "Fish", 1)
	GameService.markDirty(player)
	GameService.refresh(player)
	Net.event("FishResult"):FireClient(player, fish.id, perfect, isNew, table.concat(parts, " · "))
end

-- Ends the current cast. A new one starts after a short pause when Auto Fish is on.
local function done(player: Player)
	casts[player] = nil
	if autoOn[player] then
		task.delay(1.5, function()
			if autoOn[player] and not casts[player] and player.Parent then
				cast(player)
			end
		end)
	end
end

cast = function(player: Player)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or casts[player] then
		return
	end
	if not atPond(player) then
		GameService.notify(player, "Stand next to the Fishing Pond to fish", "error")
		setAuto(player, false)
		return
	end
	nextId += 1
	-- Casting again right away just waits longer for the bite: one catch per MIN_CYCLE at most
	local early = math.max(0, FishingConfig.MIN_CYCLE - (os.clock() - (lastCast[player] or -math.huge)))
	lastCast[player] = os.clock()
	local auto = autoOn[player] == true
	local current: Cast = { id = nextId, bite = nil, auto = auto }
	casts[player] = current
	Net.event("FishCast"):FireClient(player)
	task.delay(early + Fishing.biteDelay(rand(), auto), function()
		if casts[player] ~= current then
			return
		end
		current.bite = os.clock()
		Net.event("FishBite"):FireClient(player, auto)
		if auto then
			task.delay(0.8, function()
				if casts[player] == current then
					catch(player, false, true)
					done(player)
				end
			end)
			return
		end
		task.delay(FishingConfig.REEL_WINDOW + FishingConfig.LATENCY + 0.1, function()
			if casts[player] == current then
				Net.event("FishResult"):FireClient(player, nil, false, false, "It got away!")
				done(player)
			end
		end)
	end)
end

local function reel(player: Player, perfect: any)
	local current = casts[player]
	if not current or current.auto then
		return
	end
	if not current.bite then
		Net.event("FishResult"):FireClient(player, nil, false, false, "Too early! The fish swam off.")
		done(player)
		return
	end
	local sinceBite = os.clock() - (current.bite :: number)
	if not Fishing.inTime(sinceBite) then
		return -- the timeout above handles it
	end
	-- The client says Perfect; the server checks the marker could really have been in the green
	catch(player, perfect == true and Fishing.perfectPlausible(sinceBite), false)
	done(player)
end

function FishingService.init()
	Net.event("FishCast").OnServerEvent:Connect(function(player)
		local runtime = State.get(player)
		-- Auto Fish casts by itself
		if runtime and not autoOn[player] and State.throttle(runtime, "FishCast", 0.5) then
			cast(player)
		end
	end)
	Net.event("FishReel").OnServerEvent:Connect(reel)
	Net.event("FishAuto").OnServerEvent:Connect(function(player, on: any)
		local runtime = State.get(player)
		-- Turning it off always works (closing the window right after turning it on)
		if not runtime or (on == true and not State.throttle(runtime, "FishAuto", 0.5)) then
			return
		end
		setAuto(player, on == true)
		if on == true and not casts[player] then
			cast(player)
		end
	end)
	-- Auto Fish stops when you walk away
	task.spawn(function()
		while true do
			task.wait(2)
			for player in autoOn do
				if not player.Parent or not atPond(player) then
					if player.Parent then
						setAuto(player, false)
						GameService.notify(player, "Auto Fish stopped: you left the pond", "info")
					else
						autoOn[player] = nil
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		casts[player] = nil
		autoOn[player] = nil
		lastCast[player] = nil
	end)
end

return FishingService
