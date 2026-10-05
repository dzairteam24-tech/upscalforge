--!strict
-- World Boss: a giant creature in the Hub every hour at :30 (UTC). Everyone in the server fights it
-- together. Rewards depend on how long YOU fought (measured in seconds of your own team power), not on
-- rank, so a new player who joins in gets the same reward as a strong one.

return {
	INTERVAL = 3600, -- seconds between bosses
	OFFSET = 1800, -- :30 past the hour
	WARNING = 60, -- server message this long before it comes
	LIFETIME = 180, -- seconds to defeat it before it escapes
	HEALTH_SECONDS = 60, -- health = everyone's team power x this
	MIN_HEALTH = 5000,
	FULL_SECONDS = 15, -- fight this long (in seconds of your team power) for the full reward
	MIN_SECONDS = 3, -- below this you get nothing
	-- Rewards: gems are base + perZone x your best zone
	GEMS_BASE = 25,
	GEMS_PER_ZONE = 5,
	TICKETS = 3,
	GOLDEN_KEY_CHANCE = 0.25,
	CARD_CHANCE = 0.1,
	RIFT_KEY_HALF_CHANCE = 0.2,
	VARIANTS = { "Crystal", "Lava", "Neon" }, -- how the boss looks (just for show)
}
