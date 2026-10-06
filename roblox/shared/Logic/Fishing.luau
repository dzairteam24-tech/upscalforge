--!strict
-- Fishing rules shared by the server (rolls and rewards) and the client (the timing bar).

local Config = require(script.Parent.Parent.Config.Fishing)

export type FishingData = { caught: { [string]: number }, total: number }

local Fishing = {}

-- Seconds until a bite. `r` is a 0-1 random number.
function Fishing.biteDelay(r: number, auto: boolean): number
	local delay = Config.BITE_MIN + r * (Config.BITE_MAX - Config.BITE_MIN)
	return if auto then delay * Config.AUTO_SLOWER else delay
end

-- Rarity weights; a Perfect multiplies everything above Common.
function Fishing.weights(perfect: boolean): { [string]: number }
	local weights = {}
	for _, rarity in Config.rarities do
		weights[rarity.id] = if perfect and rarity.id ~= "Common" then rarity.weight * Config.PERFECT_LUCK else rarity.weight
	end
	return weights
end

-- Picks a fish. `rng` returns 0-1.
function Fishing.roll(perfect: boolean, rng: () -> number): Config.Fish
	local weights = Fishing.weights(perfect)
	local total = 0
	for _, rarity in Config.rarities do
		total += weights[rarity.id]
	end
	local pick = rng() * total
	local chosen = Config.rarities[1].id
	for _, rarity in Config.rarities do
		pick -= weights[rarity.id]
		if pick < 0 then
			chosen = rarity.id
			break
		end
	end
	local options = {}
	for _, f in Config.fish do
		if f.rarity == chosen then
			table.insert(options, f)
		end
	end
	return options[math.clamp(math.floor(rng() * #options) + 1, 1, #options)]
end

-- Where the marker is on the bar (0-1) `t` seconds after the bite: it bounces back and forth.
function Fishing.marker(t: number): number
	local x = (t * Config.MARKER_SPEED) % 2
	return if x <= 1 then x else 2 - x
end

-- The green zone is in the middle of the bar.
function Fishing.isPerfect(position: number): boolean
	return math.abs(position - 0.5) <= Config.GREEN / 2
end

-- The server's check of a Perfect: the marker must have been in the green at some moment between
-- `sinceBite - PERFECT_SLACK` (the tap travelled over the network) and `sinceBite`.
function Fishing.perfectPlausible(sinceBite: number): boolean
	local from = math.max(0, sinceBite - Config.PERFECT_SLACK)
	local t = from
	while t <= sinceBite do
		if Fishing.isPerfect(Fishing.marker(t)) then
			return true
		end
		t += 0.01
	end
	return Fishing.isPerfect(Fishing.marker(sinceBite))
end

-- The reel counts if it comes after the bite and before the window (plus network time) closes.
function Fishing.inTime(sinceBite: number): boolean
	return sinceBite >= 0 and sinceBite <= Config.REEL_WINDOW + Config.LATENCY
end

function Fishing.reward(f: Config.Fish, power: number, auto: boolean, rng: () -> number): { coins: number, gems: number, tickets: number, elixir: { number }? }
	local rarity = Config.raritiesById[f.rarity]
	local ticketRoll = rng()
	return {
		coins = math.floor(math.max(1, power) * rarity.coinSeconds),
		gems = rarity.gems,
		tickets = if not auto and ticketRoll < rarity.ticketChance then 1 else 0,
		elixir = if rng() < rarity.elixirChance then rarity.elixirTiers else nil,
	}
end

-- Adds a catch. Returns true for a new kind, and true when this catch completed the collection.
function Fishing.record(data: FishingData, fishId: string): (boolean, boolean)
	local isNew = (data.caught[fishId] or 0) == 0
	data.caught[fishId] = (data.caught[fishId] or 0) + 1
	data.total += 1
	return isNew, isNew and Fishing.kinds(data) == #Config.fish
end

function Fishing.kinds(data: FishingData): number
	local n = 0
	for _, f in Config.fish do
		if (data.caught[f.id] or 0) > 0 then
			n += 1
		end
	end
	return n
end

return Fishing
