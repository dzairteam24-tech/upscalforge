--!strict
-- Game-wide tuning values. Numbers match docs/game-design.md and are meant to be balanced in playtests.

local Constants = {
	-- Team and storage
	BASE_TEAM_SLOTS = 6,
	MAX_TEAM_SLOTS = 12,
	BASE_STORAGE = 100,

	-- Combat / collecting
	TICK_SECONDS = 0.25,
	TAP_COOLDOWN = 0.12,
	BASE_TAP_POWER = 1,
	TARGET_RANGE = 90,
	AUTO_TARGET_RANGE = 70,

	-- Combo: breaking a source within COMBO_WINDOW seconds keeps the combo alive.
	COMBO_WINDOW = 5,
	COMBO_STEPS = {
		{ at = 50, mult = 5 },
		{ at = 20, mult = 3 },
		{ at = 10, mult = 2 },
		{ at = 5, mult = 1.5 },
		{ at = 0, mult = 1 },
	},

	JACKPOT_CHANCE = 0.01,
	JACKPOT_MULT = 10,
	BASE_GEM_CHANCE = 0.01,

	-- Hatching
	HATCH_COOLDOWN = 0.6,
	EGG_RANGE = 16,
	GUARANTEED_GOLDEN_BY_HATCH = 5,

	-- Offline earnings
	BASE_OFFLINE_HOURS = 2,
	OFFLINE_EFFICIENCY = 0.25,

	-- Big and Titan base power multipliers (on top of species power)
	BIG_POWER_MULT = 3,
	TITAN_POWER_MULT = 10,

	-- Default element bonus when a variant is in its strong zone
	ELEMENT_BONUS = 2,

	-- Fusion
	FUSION_COST = 5,

	-- Reload (rebirth)
	RELOAD_COIN_MULT = 1.5,
	RELOAD_REQUIRED_ZONE = 10,

	-- Trading
	TRADE_MAX_PETS = 12,
	TRADE_LOCK_SECONDS = 3,
	TRADE_REQUEST_TIMEOUT = 30,
	TRADE_HISTORY_SIZE = 50,

	-- Data
	AUTOSAVE_SECONDS = 60,
	DATASTORE_NAME = "Cubelings_PlayerData_v1",
	SESSION_LOCK_SECONDS = 1800,
}

return Constants
