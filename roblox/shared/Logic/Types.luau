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
	items: { [string]: number }, -- item id -> count
	boosts: { [string]: { [string]: number } }, -- stat -> multiplier -> seconds left
	daily: { streak: number, lastDay: number },
	quests: QuestBook,
	pass: PassState,
	guardians: { [string]: number }, -- zone id -> os.time() when its guardian can be fought again
	trails: { [string]: boolean },
	equippedTitle: string?,
	equippedTrail: string?,
}

export type Quest = {
	id: string, -- template id
	goal: number,
	progress: number,
	claimed: boolean,
}

export type QuestBook = {
	day: number, -- UTC day the daily quests belong to
	week: number, -- UTC week the weekly quests belong to
	daily: { Quest },
	weekly: { Quest },
}

export type PassState = {
	season: number,
	xp: number,
	premium: boolean,
	claimedFree: { [string]: boolean },
	claimedPremium: { [string]: boolean },
}

-- What the player rolls when hatching.
export type Roll = {
	s: string,
	v: string,
	z: string,
}

return {}
