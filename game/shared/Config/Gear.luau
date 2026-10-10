--!strict
-- The Gear Shop (GearService): the bat every player holds, upgraded with coins (never Robux). Hitting a player who
-- carries an egg (from the Wild or the Heist) knocks it out of their hands after enough hits: more when
-- they have a better bat than you, fewer when yours is better (Logic/Gear), so a new player can't take an egg
-- from a strong one with a hit. Players carrying nothing aren't touched: the bat is only for eggs.

export type Bat = { name: string, price: number, color: Color3, material: Enum.Material }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local BATS: { Bat } = {
	{ name = "Stick", price = 0, color = rgb(150, 105, 70), material = Enum.Material.Wood },
	{ name = "Wooden Bat", price = 1500, color = rgb(205, 150, 90), material = Enum.Material.Wood },
	{ name = "Iron Bat", price = 15000, color = rgb(170, 175, 185), material = Enum.Material.Metal },
	{ name = "Gold Bat", price = 150000, color = rgb(255, 200, 60), material = Enum.Material.Foil },
	{ name = "Diamond Bat", price = 1500000, color = rgb(120, 220, 255), material = Enum.Material.Glass },
	{ name = "Lava Bat", price = 15000000, color = rgb(255, 100, 40), material = Enum.Material.Neon },
	{ name = "Cosmic Bat", price = 150000000, color = rgb(150, 90, 255), material = Enum.Material.Neon },
}

return {
	BATS = BATS,
	HITS = 2, -- hits that knock an egg out of a player with the same bat as yours...
	MAX_HITS = 10, -- ...one more for each level their bat is above yours (one less below), from 1 up to this
	COMBO = 4, -- seconds: hits further apart than this start over
	RANGE = 9, -- studs: how close the one hit must be
	COOLDOWN = 0.6, -- seconds between two swings

	-- Traps: bought at the Gear Shop, set down in the Wild. A player carrying an egg who steps on someone else's
	-- trap is stuck there for a moment (the guardian, or a bat, catches up)
	TRAP_PRICE = 2500,
	TRAP_MAX_HELD = 10,
	TRAP_MAX_SET = 3, -- set at once, per player
	TRAP_TIME = 90, -- seconds a set trap lasts
	TRAP_STUCK = 3, -- seconds stuck
	TRAP_RANGE = 3.5,
}
