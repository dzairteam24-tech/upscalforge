--!strict
-- Big creatures that roam zones, and zone guardians (Titans) that appear at 100% restoration.
-- Coins inside them scale with the zone's restore goal, so a fight lasts about the same at every zone.

return {
	-- Big
	BIG_INTERVAL = 600, -- seconds between Bigs in a zone (shortened by BigSpawn skills and Hunter elixirs)
	BIG_MIN_INTERVAL = 60,
	BIG_LIFETIME = 180, -- it runs away after this
	BIG_COINS = 0.05, -- x zone restore goal
	BIG_CATCH_CHANCE = 0.1, -- per player who helped, x BigSpawn skill, capped below
	BIG_CATCH_CAP = 0.5,

	-- Guardian
	GUARDIAN_COOLDOWN = 4 * 3600,
	GUARDIAN_LIFETIME = 300,
	GUARDIAN_COINS = 0.5, -- x zone restore goal
	GUARDIAN_TAME_CHANCE = 0.005,
	GUARDIAN_GEMS = 25, -- x zone id
}
