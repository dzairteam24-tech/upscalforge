--!strict
-- Systems open one by one as the player reaches zones, so a new player isn't buried in buttons.
-- The zone counts once reached: a Reload doesn't lock anything again.

export type Unlock = { feature: string, zone: number, label: string, text: string }

local list: { Unlock } = {
	{ feature = "Trips", zone = 2, label = "🧭 Trips", text = "Send creatures you don't use on trips for loot" },
	{ feature = "Cartridges", zone = 3, label = "🃏 Boost Cards", text = "Cards that give permanent bonuses while equipped" },
	{ feature = "Spin", zone = 3, label = "🎰 Lucky Spin", text = "A free spin every day" },
	{ feature = "Stickers", zone = 4, label = "⭐ Stickers", text = "Stick them on creatures for bonuses" },
	{ feature = "Gadgets", zone = 4, label = "💣 Gadgets", text = "One-use tools: bombs, totems, coin rain" },
	{ feature = "Clans", zone = 3, label = "🛡️ Clans", text = "Team up with friends and climb the weekly clan board" },
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
