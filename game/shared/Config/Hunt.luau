--!strict
-- Hunting in the Wild (reached from the Trips shop in town): four zones of wild creatures, each opening once the
-- player has hatched a creature from its first egg tier. Catching one is a timing game (Logic/Hunt): stop the
-- marker in the green; rarer creatures have a smaller green and a faster marker, better nets a bigger green.
-- A miss and the creature runs off. Wild eggs lie in the grass too, and now and then a shiny appears.

export type Zone = { id: string, name: string, tiers: { number }, need: number, color: Color3, theme: number }
export type Net = { id: string, name: string, icon: string, mult: number, share: number, min: number }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local ZONES: { Zone } = {
	-- `need`: the egg tier a player must have hatched from; `theme`: the props (Config/PropLooks zones)
	{ id = "Meadow", name = "Meadow", tiers = { 1, 2 }, need = 1, color = rgb(132, 200, 110), theme = 1 },
	{ id = "Forest", name = "Forest & Beach", tiers = { 3, 4 }, need = 3, color = rgb(84, 150, 84), theme = 3 },
	{ id = "Desert", name = "Cave & Desert", tiers = { 5, 6 }, need = 5, color = rgb(222, 190, 130), theme = 6 },
	{ id = "Snow", name = "Snow & Volcano", tiers = { 7, 8 }, need = 7, color = rgb(226, 238, 248), theme = 7 },
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
	PER_ZONE = 6, -- wild creatures roaming each zone
	RESPAWN = 20, -- seconds before a caught (or fled) one is replaced
	WALK_SPEED = 6,
	CATCH_RANGE = 14, -- how close a player must be to start catching
	GAME_TIME = 8, -- seconds to click before the creature gets bored and walks off
	COOLDOWN = 1.5, -- between two catches
	EGGS_PER_ZONE = 2, -- wild eggs lying in each zone...
	EGG_RESPAWN = 120, -- ...each replaced this long after it's picked up
	SHINY_EVERY = 300, -- a shiny (an Epic, Golden at least) appears this often...
	SHINY_STAYS = 120, -- ...for this long
	SHINY_MUTATION = "Golden",
}
