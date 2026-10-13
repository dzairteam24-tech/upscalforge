--!strict
-- What's in each cube of a player's mine, the same every time for the same seed: which cubes hold a gem (and
-- which kind), and a little shade so the cubes aren't all one color. Pure maths, no engine.

local Gem = require(script.Parent.Gem)
local MineConfig = require(script.Parent.Parent.Config.Mine)

local MineGen = {}

-- A steady pseudo-random number in [0, 1) for a cube and a channel
local function hash(seed: number, x: number, l: number, z: number, channel: number): number
	local v = math.sin(seed * 12.9898 + x * 78.233 + l * 37.719 + z * 11.135 + channel * 51.17) * 43758.5453
	return v - math.floor(v)
end

-- The zone (Dirt, Stone, Deep) a layer is in
function MineGen.zone(layer: number): any
	local found = MineConfig.ZONES[1]
	for _, zone in MineConfig.ZONES do
		if layer >= zone.from then
			found = zone
		end
	end
	return found
end

-- How much damage a cube takes to break
function MineGen.hp(layer: number): number
	local zone = MineGen.zone(layer)
	return math.floor(zone.hp + zone.perLayer * (layer - zone.from) + 0.5)
end

-- The gem kind in a cube, or nil
function MineGen.gemAt(seed: number, x: number, l: number, z: number): string?
	if hash(seed, x, l, z, 1) >= MineConfig.GEM_CHANCE then
		return nil
	end
	-- (the kind: its own steady number, fed to Gem.pick like a random source)
	local pick = { NextNumber = function(_self: any): number return hash(seed, x, l, z, 2) end }
	return Gem.pick(l, pick)
end

-- 0..1: a cube's shade
function MineGen.shade(seed: number, x: number, l: number, z: number): number
	return hash(seed, x, l, z, 3)
end

return MineGen
