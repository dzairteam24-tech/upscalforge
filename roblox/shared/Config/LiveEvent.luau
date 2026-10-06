--!strict
-- Live Events ("Admin Abuse" in other games): the developer starts a short boost for every server at
-- once, so everyone joins at the same time. Real numbers only, and never more than these caps.
-- Start one in chat:  /live luck 3 30   (stat, multiplier, minutes)   ·   /live stop
-- Luck never changes Legendary odds (the Legendary Egg ignores luck).

return {
	-- Who may start one (the game's owner and Studio are always allowed). Add Roblox user ids here.
	ADMINS = {} :: { number },
	-- stat -> the highest multiplier allowed
	STATS = {
		Luck = 5,
		Coins = 5,
		Gem = 3,
		Pixel = 5, -- Pixel variant chance
	} :: { [string]: number },
	MAX_MINUTES = 60,
	DEFAULT_MINUTES = 30,
}
