--!strict
-- Redeemable codes: post them on the game page, Discord and socials. Each code works once per player.
-- Codes are free rewards, so they follow the same rule as everything else: no creatures, no Robux items.
-- `ends` is optional (UTC, see Events.utc). Codes are case-insensitive.

local Events = require(script.Parent.Events)
local Progression = require(script.Parent.Progression)

export type Code = {
	code: string, -- upper case
	reward: Progression.Reward,
	ends: number?,
}

local list: { Code } = {
	{ code = "RELEASE", reward = { gems = 100, items = { { id = "Elixir_Coins_2", amount = 2 } } } },
	{ code = "CUBES", reward = { tickets = 5, items = { { id = "Elixir_Luck_2", amount = 1 } } } },
	{ code = "SPOOKY", reward = { gems = 150 }, ends = Events.utc(2026, 11, 7) },
}

local byCode: { [string]: Code } = {}
for _, entry in list do
	byCode[entry.code] = entry
end

-- Trims spaces and ignores case, so "  release " works.
local function normalize(text: string): string
	return (string.upper((string.gsub(text, "%s+", ""))))
end

return {
	list = list,
	byCode = byCode,
	normalize = normalize,
	MAX_LENGTH = 30,
}
