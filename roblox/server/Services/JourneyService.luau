-- The Journey (Config/Journey): Professor Cubo's quest line. Steps count progress events and are claimed in
-- the Quests window; the Professor in the town opens it and says the current line.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local JourneyConfig = require(Shared.Config.Journey)
local Journey = require(Shared.Logic.Journey)
local Unlocks = require(Shared.Logic.Unlocks)
local Types = require(Shared.Logic.Types)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local ProgressionService = require(script.Parent.ProgressionService)
local State = require(script.Parent.State)

local JourneyService = {}

local function already(data: Types.PlayerData): { [string]: number }
	return {
		Zone = Unlocks.bestZone(data),
		Reload = data.reloads or 0,
		Combo = data.stats.bestCombo or 0,
	}
end

local function onProgress(player: Player, event: string, amount: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	local step = Journey.current(data.journey)
	if Journey.onEvent(data.journey, event, amount) then
		GameService.notify(player, "📖 Journey step done! Claim it in Quests.", "success")
		GameService.refresh(player)
	elseif step and step.event == event then
		GameService.markDirty(player) -- so the progress bar moves
	end
end

local function claim(player: Player)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or not State.throttle(runtime, "ClaimJourney", 0.5) then
		return
	end
	local step = Journey.current(data.journey)
	if not step or not Journey.isDone(data.journey) then
		return
	end
	local summary = ProgressionService.grant(player, step.reward)
	Journey.advance(data.journey, already(data))
	local nextStep = Journey.current(data.journey)
	if nextStep then
		GameService.notify(player, ("📖 %s: %s"):format(JourneyConfig.NPC_NAME, summary), "success")
	else
		GameService.notify(player, "📖 You finished the Journey! You're a Valley Hero. " .. summary, "rare")
	end
	GameService.refresh(player)
end

function JourneyService.init()
	GameService.Progress:Connect(onProgress)
	DataService.Loaded:Connect(function(player, data)
		-- A "max" step can already be true (an old save, or a zone opened another way)
		local step = Journey.current(data.journey)
		if step and step.max then
			data.journey.progress = math.max(data.journey.progress, already(data)[step.event] or 0)
		end
	end)
	Net.event("ClaimJourney").OnServerEvent:Connect(claim)
end

return JourneyService
