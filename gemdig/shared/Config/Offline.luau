--!strict
-- The drone: it keeps mining while the player is away, and pays out when they come back.

return {
	FREE_HOURS = 2, -- how long it works for free...
	PASS_HOURS = 12, -- ...and with the Long Offline Miner pass
	RATE = 0.25, -- of what the player earns digging by hand
	MIN_AWAY = 120, -- seconds: shorter than this, no report
}
