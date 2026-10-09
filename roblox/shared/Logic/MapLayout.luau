--!strict
-- Where things are on the map. Shared by the server (building, checks) and the client (gates, eggs).

local World1 = require(script.Parent.Parent.Config.World1)

-- The zones follow one winding path (Config/World1 grid), each touching the one before it through a short
-- gatehouse, so a player never walks an empty bridge. Every zone is laid out the same way, turned toward
-- its entrance: the base just inside the entrance (the egg and the stations), the coin sources filling the
-- rest, and the gate to the next zone on the far side, in sight from the base (like Pet Simulator 99).
local MapLayout = {
	PLATFORM = 120, -- each zone is a 120 x 120 square with rounded corners
	CORNER = 20, -- the corners' radius
	CELL = 132, -- PLATFORM + the 12-stud gatehouse between two zones
	HUB_SIZE = 400, -- the Hub is bigger than a zone: it's where everyone meets
	HUB_BRIDGE = 30, -- length of the bridge from the Hub to Spawn Meadow
	BRIDGE_WIDTH = 30, -- the openings between zones
	BASE_DEPTH = 40, -- how far the base reaches in from the entrance (no coin sources there)
	SOURCE_SPACING = 14, -- minimum distance between coin sources (the vault is 12 studs wide)
}

-- Width of a zone's square platform
function MapLayout.size(zoneId: number): number
	return if zoneId == 0 then MapLayout.HUB_SIZE else MapLayout.PLATFORM
end

function MapLayout.center(zoneId: number): Vector3
	if zoneId == 0 then
		-- South of Spawn Meadow (zone 1, at the origin), far enough for its bigger platform
		return Vector3.new(0, 0, MapLayout.PLATFORM / 2 + MapLayout.HUB_BRIDGE + MapLayout.HUB_SIZE / 2)
	end
	local zone = World1.zonesById[zoneId]
	return Vector3.new(zone.grid.X * MapLayout.CELL, 0, -zone.grid.Y * MapLayout.CELL)
end

-- The side a zone is entered from (toward the zone before it, or the Hub), as a flat unit axis
function MapLayout.entrance(zoneId: number): Vector3
	local zone = World1.zonesById[zoneId]
	local previous = zoneId - 1
	for _, other in zone.links do
		if other < zoneId then
			previous = other
		end
	end
	local delta = MapLayout.center(previous) - MapLayout.center(zoneId)
	if math.abs(delta.X) > math.abs(delta.Z) then
		return Vector3.new(math.sign(delta.X), 0, 0)
	end
	return Vector3.new(0, 0, math.sign(delta.Z))
end

-- A spot in a zone's base: `inward` studs in from the entrance edge, `across` to the right as you walk in
function MapLayout.basePoint(zoneId: number, inward: number, across: number): Vector3
	local e = MapLayout.entrance(zoneId)
	local right = Vector3.new(e.Z, 0, -e.X)
	return MapLayout.center(zoneId) + e * (MapLayout.PLATFORM / 2 - inward) + right * across
end

function MapLayout.eggPosition(zoneId: number): Vector3
	return MapLayout.basePoint(zoneId, 30, 0)
end

-- Zone id under a position, or nil when on a bridge / outside the map.
function MapLayout.zoneAt(position: Vector3): number?
	for _, zone in World1.zones do
		local half = MapLayout.size(zone.id) / 2 + 1
		local c = MapLayout.center(zone.id)
		if math.abs(position.X - c.X) <= half and math.abs(position.Z - c.Z) <= half then
			return zone.id
		end
	end
	return nil
end

-- Spots for coin sources. In a zone: a grid over the part beyond the base (the egg and the stations), its
-- spots picked in a shuffled order and nudged a little, so it fits every source and doesn't look lined up.
-- In the Hub: random spots round the middle.
function MapLayout.sourceSpots(zoneId: number, count: number, seed: number): { Vector3 }
	local center = MapLayout.center(zoneId)
	local spots: { Vector3 } = {}
	local span = MapLayout.PLATFORM / 2 - 16
	local state = seed
	local function rand(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
	if zoneId == 0 then
		local attempts = 0
		while #spots < count and attempts < count * 50 do
			attempts += 1
			local offset = Vector3.new((rand() * 2 - 1) * span, 0, (rand() * 2 - 1) * span)
			local crowded = offset.Magnitude < 10
			for _, other in spots do
				if (other - (center + offset)).Magnitude < MapLayout.SOURCE_SPACING then
					crowded = true
					break
				end
			end
			if not crowded then
				table.insert(spots, center + offset)
			end
		end
		return spots
	end
	local entrance = MapLayout.entrance(zoneId)
	local right = Vector3.new(entrance.Z, 0, -entrance.X)
	local near = MapLayout.PLATFORM / 2 - MapLayout.BASE_DEPTH - 4 -- the grid's edge toward the base
	local columns, rows = 7, 5
	local pitchAcross = 2 * span / (columns - 1)
	local pitchDeep = (span + near) / (rows - 1)
	local jitter = (math.min(pitchAcross, pitchDeep) - MapLayout.SOURCE_SPACING) / 2
	local corner = MapLayout.PLATFORM / 2 - MapLayout.CORNER
	local cells: { Vector3 } = {}
	for column = 0, columns - 1 do
		for row = 0, rows - 1 do
			local offset = right * (-span + column * pitchAcross) + entrance * (near - row * pitchDeep)
			-- (not out in the rounded corners)
			local cx, cz = math.max(math.abs(offset.X) - corner, 0), math.max(math.abs(offset.Z) - corner, 0)
			if math.sqrt(cx * cx + cz * cz) <= MapLayout.CORNER - 16 then
				table.insert(cells, offset)
			end
		end
	end
	for i = #cells, 2, -1 do
		local j = 1 + math.floor(rand() * i)
		cells[i], cells[j] = cells[j], cells[i]
	end
	for i = 1, math.min(count, #cells) do
		local nudge = Vector3.new((rand() * 2 - 1) * jitter, 0, (rand() * 2 - 1) * jitter)
		table.insert(spots, center + cells[i] + nudge)
	end
	return spots
end

return MapLayout
