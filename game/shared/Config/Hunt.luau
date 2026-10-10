--!strict
-- Hunting: wild creatures come out of the den at the far end of the street and walk down the carpet in its
-- middle, past every garden, until they go into the burrow by the shops. Anyone can catch one as it passes, if
-- they've hatched a creature from its kind's first egg tier. Catching is a timing game (Logic/Hunt): stop the
-- marker in the green; rarer creatures have a smaller green and a faster marker, better nets (the Net Shop) a
-- bigger green. A miss and the creature runs off. Now and then a shiny walks by.

export type Zone = { id: string, name: string, tiers: { number }, need: number, weight: number }
export type Net = { id: string, name: string, icon: string, mult: number, share: number, min: number }

local ZONES: { Zone } = {
	-- The kinds of wild creatures (their egg tiers); `need`: the egg tier a player must have hatched from to catch
	-- one; `weight`: how often this kind comes out
	{ id = "Meadow", name = "Meadow", tiers = { 1, 2 }, need = 1, weight = 50 },
	{ id = "Forest", name = "Forest & Beach", tiers = { 3, 4 }, need = 3, weight = 25 },
	{ id = "Desert", name = "Cave & Desert", tiers = { 5, 6 }, need = 5, weight = 15 },
	{ id = "Snow", name = "Snow & Volcano", tiers = { 7, 8 }, need = 7, weight = 10 },
}

local NETS: { Net } = {
	-- `share` of the price of the player's best egg (Logic/Hunt.netPrice), at least `min`; the basic net is free
	{ id = "Basic", name = "Net", icon = "🥅", mult = 1, share = 0, min = 0 },
	{ id = "Silver", name = "Silver Net", icon = "🥈", mult = 1.5, share = 0.3, min = 100 },
	{ id = "Gold", name = "Gold Net", icon = "🥇", mult = 2.2, share = 1.5, min = 500 },
}
local netById: { [string]: Net } = {}
for _, net in NETS do
	netById[net.id] = net
end

return {
	ZONES = ZONES,
	NETS = NETS,
	netById = netById,
	-- The timing game per rarity: the green's width (a share of the bar) and the marker's speed (bars a second)
	BAR = {
		Common = { width = 0.3, speed = 0.6 },
		Uncommon = { width = 0.22, speed = 0.75 },
		Rare = { width = 0.15, speed = 0.9 },
		Epic = { width = 0.1, speed = 1.1 },
		Legendary = { width = 0.07, speed = 1.3 },
	} :: { [string]: { width: number, speed: number } },
	MAX_WIDTH = 0.8,
	SPAWN_EVERY = 3, -- a wild creature comes out of the den this often...
	MAX_OUT = 24, -- ...while there are fewer than this on the carpet
	WALK_SPEED = 5,
	CATCH_RANGE = 14, -- how close a player must be to start catching
	GAME_TIME = 8, -- seconds to click before the creature gets bored and walks on
	COOLDOWN = 1.5, -- between two catches
	SHINY_EVERY = 300, -- a shiny (an Epic, Golden at least) comes out this often
	SHINY_MUTATION = "Golden",
}
