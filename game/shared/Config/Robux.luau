--!strict
-- What Robux buy (docs/vision.md: time, comfort and looks only; never eggs, luck, creatures, coins or speed).
-- Each one is made on the Roblox website (the game's Monetization page: a game pass or a developer product) and
-- its id pasted here; until then (id 0) the shop shows it as coming soon.

export type Item = { id: number, price: number, icon: string, name: string, text: string }

return {
	-- Game passes (bought once, kept)
	FAST_HATCH = { id = 0, price = 199, icon = "⏩", name = "Fast Hatch", text = "Every egg hatches ×2 faster, forever" } :: Item,
	-- Developer products (bought each time)
	HATCH_ALL = { id = 0, price = 49, icon = "🐣", name = "Hatch All Now", text = "Every egg in your garden ready to hatch, right now" } :: Item,
	-- Floating seats (looks only: every seat rides the same): developer product ids by seat name (Config/SeatLooks)
	SEAT_PRICE = 99,
	SEATS = {} :: { [string]: number },
}
