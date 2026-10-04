--!strict
-- Shared data shapes.

-- A creature the player owns. Short keys keep DataStore entries small.
export type Pet = {
	s: string, -- species id
	v: string, -- variant id
	z: string, -- size id
	lk: boolean?, -- locked (cannot be deleted, fused or traded)
}

export type PetMap = { [string]: Pet }

export type PlayerData = {
	version: number,
	coins: number,
	gems: number,
	pets: PetMap,
	equipped: { string },
	unlockedZones: { [string]: boolean },
	zoneProgress: { [string]: number },
	upgrades: { [string]: number },
	stats: { [string]: number },
	flags: { [string]: boolean },
	purchases: { [string]: boolean },
	titles: { [string]: boolean },
	tradeHistory: { any },
	settings: { [string]: any },
	lastSeen: number,
	lastPower: number,
}

-- What the player rolls when hatching.
export type Roll = {
	s: string,
	v: string,
	z: string,
}

return {}
