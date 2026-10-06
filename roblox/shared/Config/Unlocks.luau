--!strict
-- Systems open one by one as the player reaches zones, so a new player isn't buried in buttons.
-- The zone counts once reached: a Reload doesn't lock anything again.

export type Unlock = { feature: string, zone: number, label: string, text: string }

local list: { Unlock } = {
	-- About one new system every zone, so the first half hour stays about the core loop
	{ feature = "Boss", zone = 2, label = "👹 World Boss", text = "Every hour a boss lands in the Hub. Fight it with everyone!" },
	{ feature = "Trips", zone = 3, label = "🧭 Trips", text = "Send creatures you don't use on trips for loot" },
	{ feature = "Cartridges", zone = 4, label = "🃏 Boost Cards", text = "Cards that give permanent bonuses while equipped" },
	{ feature = "Spin", zone = 4, label = "🎰 Lucky Spin", text = "A free spin every day" },
	{ feature = "Clans", zone = 5, label = "🛡️ Clans", text = "Team up with friends and climb the weekly clan board" },
	{ feature = "Stickers", zone = 6, label = "⭐ Stickers", text = "Stick them on creatures for bonuses" },
	{ feature = "Gadgets", zone = 7, label = "💣 Gadgets", text = "One-use tools: bombs, totems, coin rain" },
	{ feature = "Reload", zone = 10, label = "🔄 Reload", text = "Start again with coins x1.5 forever" },
}

local byFeature: { [string]: Unlock } = {}
for _, unlock in list do
	byFeature[unlock.feature] = unlock
end

return {
	list = list,
	byFeature = byFeature,
}
