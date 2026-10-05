--!strict
-- Clans: up to 20 players across servers. Members earn weekly points by playing; the best clans of the
-- week get gems and a title.

return {
	CREATE_COST = 500, -- gems
	MAX_MEMBERS = 20,
	NAME_MIN = 3,
	NAME_MAX = 16,
	TAG_MIN = 2,
	TAG_MAX = 4,
	-- Weekly points per progress event
	POINTS = {
		Break = 1,
		Hatch = 1, -- per egg
		Big = 10,
		Guardian = 50,
		Restore = 100,
		Expedition = 5,
	} :: { [string]: number },
	-- Weekly rewards for every member, by the clan's rank
	REWARDS = {
		{ upTo = 1, gems = 500 },
		{ upTo = 3, gems = 300 },
		{ upTo = 10, gems = 150 },
	},
	REWARD_TITLE = "C_TopClan",
}
