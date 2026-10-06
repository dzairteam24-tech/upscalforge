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
	BIG_PITY = 10, -- the 10th try in a row is a sure catch

	-- Guardian
	GUARDIAN_COOLDOWN = 4 * 3600,
	GUARDIAN_LIFETIME = 300,
	GUARDIAN_COINS = 0.5, -- x zone restore goal
	-- About 200 guardian wins per Titan on average (several days of play), so Titans stay rare
	GUARDIAN_TAME_CHANCE = 0.001,
	TITAN_PITY = 500, -- the 500th guardian in a row is a sure tame
	TITAN_PITY_STEP = 0.00005, -- +0.005% tame chance after every miss
	GUARDIAN_GEMS = 10, -- x zone id (first clears give more)
}
