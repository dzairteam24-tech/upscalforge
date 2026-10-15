--!strict
-- A small seeded random generator (Park-Miller), the same on the server and on every phone: the course is built
-- from a stage's number alone, so everyone agrees where every orb and obstacle is.

export type Rng = { state: number }

local Rng = {}

local MOD = 2147483647

function Rng.new(seed: number): Rng
	local s = math.floor(math.abs(seed)) % (MOD - 1) + 1
	return { state = s }
end

-- 0 <= x < 1
function Rng.float(r: Rng): number
	r.state = (r.state * 48271) % MOD
	return (r.state - 1) / (MOD - 1)
end

function Rng.range(r: Rng, a: number, b: number): number
	return a + (b - a) * Rng.float(r)
end

-- a whole number from a to b, both included
function Rng.int(r: Rng, a: number, b: number): number
	return a + math.floor(Rng.float(r) * (b - a + 1))
end

function Rng.pick(r: Rng, list: { any }): any
	return list[Rng.int(r, 1, #list)]
end

return Rng
