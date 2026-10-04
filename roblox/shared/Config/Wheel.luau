--!strict
-- Lucky Spin: one free spin a day, then spins for tickets or a video. The chances are shown in the game.

export type Slice = {
	id: string,
	label: string,
	weight: number,
	color: Color3,
}

local slices: { Slice } = {
	{ id = "Coins", label = "🪙 Coins", weight = 28, color = Color3.fromRGB(245, 197, 66) },
	{ id = "Elixir", label = "🧪 Elixir", weight = 20, color = Color3.fromRGB(80, 200, 120) },
	{ id = "Gems", label = "💎 25 Gems", weight = 15, color = Color3.fromRGB(120, 220, 255) },
	{ id = "KeyHalf", label = "🗝️ Key half", weight = 10, color = Color3.fromRGB(91, 184, 245) },
	{ id = "Tickets", label = "🎟️ 5 Tickets", weight = 8, color = Color3.fromRGB(255, 140, 90) },
	{ id = "Sticker", label = "⭐ Sticker", weight = 8, color = Color3.fromRGB(255, 215, 80) },
	{ id = "Gadget", label = "💣 Gadget", weight = 6, color = Color3.fromRGB(229, 83, 75) },
	{ id = "Eggs", label = "🥚 3 lucky eggs", weight = 4, color = Color3.fromRGB(180, 255, 140) },
	{ id = "Jackpot", label = "👑 JACKPOT", weight = 1, color = Color3.fromRGB(185, 140, 255) },
}

return {
	slices = slices,
	TICKET_COST = 5,
	JACKPOT_RIDE = "PixelBoard",
	JACKPOT_GEMS_IF_OWNED = 250,
}
