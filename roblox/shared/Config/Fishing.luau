--!strict
-- Fishing Pond (Hub corner): cast, wait for a bite, tap while the marker is in the green to reel in.
-- A good tap ("Perfect") doubles the chance of rare fish. Auto Fish is free but slower and never Perfect.
-- Coins are a few seconds of your team's farming, so fishing is a break, not a better farm.
-- Catch all 10 fish for the Angler title.

export type Fish = {
	id: string,
	name: string,
	rarity: string,
	icon: string,
}

export type Rarity = {
	id: string,
	weight: number,
	color: Color3,
	coinSeconds: number, -- coins = team power x this
	gems: number,
	ticketChance: number,
	elixirChance: number,
	elixirTiers: { number },
}

local rarities: { Rarity } = {
	{ id = "Common", weight = 60, color = Color3.fromRGB(200, 200, 200), coinSeconds = 1, gems = 0, ticketChance = 0, elixirChance = 0, elixirTiers = { 1, 1 } },
	{ id = "Uncommon", weight = 25, color = Color3.fromRGB(120, 220, 120), coinSeconds = 2, gems = 0, ticketChance = 0, elixirChance = 0, elixirTiers = { 1, 1 } },
	{ id = "Rare", weight = 10.5, color = Color3.fromRGB(91, 184, 245), coinSeconds = 5, gems = 1, ticketChance = 0.2, elixirChance = 0, elixirTiers = { 1, 1 } },
	{ id = "Epic", weight = 4, color = Color3.fromRGB(185, 120, 245), coinSeconds = 12, gems = 5, ticketChance = 0.5, elixirChance = 0.25, elixirTiers = { 1, 2 } },
	{ id = "Legendary", weight = 0.5, color = Color3.fromRGB(255, 200, 60), coinSeconds = 30, gems = 25, ticketChance = 1, elixirChance = 1, elixirTiers = { 2, 3 } },
}

local fish: { Fish } = {
	{ id = "Minnow", name = "Cube Minnow", rarity = "Common", icon = "🐟" },
	{ id = "Perch", name = "Pebble Perch", rarity = "Common", icon = "🐟" },
	{ id = "Guppy", name = "Bubble Guppy", rarity = "Common", icon = "🐠" },
	{ id = "Bass", name = "Block Bass", rarity = "Uncommon", icon = "🐟" },
	{ id = "Carp", name = "Coral Carp", rarity = "Uncommon", icon = "🐠" },
	{ id = "Pike", name = "Pixel Pike", rarity = "Rare", icon = "🐡" },
	{ id = "Trout", name = "Glass Trout", rarity = "Rare", icon = "🐠" },
	{ id = "Eel", name = "Lava Eel", rarity = "Epic", icon = "🐍" },
	{ id = "Koi", name = "Neon Koi", rarity = "Epic", icon = "🎏" },
	{ id = "Cubefish", name = "Golden Cubefish", rarity = "Legendary", icon = "👑" },
}

local raritiesById: { [string]: Rarity } = {}
for _, rarity in rarities do
	raritiesById[rarity.id] = rarity
end
local fishById: { [string]: Fish } = {}
for _, f in fish do
	fishById[f.id] = f
end

return {
	POND_OFFSET = Vector3.new(0, 0, 143), -- from the Hub center (south, between the leaderboards; see HubBuilder)
	POND_RADIUS = 20,
	REACH = 40, -- you must stand this close to the pond's middle to fish
	BITE_MIN = 2, -- seconds until a bite
	BITE_MAX = 6,
	AUTO_SLOWER = 2.5, -- Auto Fish waits this much longer, and gives no tickets
	MIN_CYCLE = 4, -- seconds between casts, however fast you reel
	REEL_WINDOW = 2.5, -- seconds to tap after the bite
	LATENCY = 0.6, -- extra time allowed for the network
	PERFECT_SLACK = 0.35, -- the server accepts a Perfect if the marker was in the green this long before it heard the tap
	PERFECT_LUCK = 2, -- rare fish weights x this on a Perfect
	MARKER_SPEED = 1.4, -- bar widths per second
	GREEN = 0.22, -- width of the green zone (0-1)
	TITLE = "F_Angler",
	rarities = rarities,
	raritiesById = raritiesById,
	fish = fish,
	fishById = fishById,
}
