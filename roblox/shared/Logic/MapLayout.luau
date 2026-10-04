--!strict
-- Where things are on the map. Shared by the server (building, checks) and the client (gates, eggs).

local World1 = require(script.Parent.Parent.Config.World1)

local MapLayout = {
	CELL = 170,
	PLATFORM = 130,
	BRIDGE_WIDTH = 24,
	SOURCE_SPACING = 14, -- minimum distance between coin sources (the vault is 12 studs wide)
}

function MapLayout.center(zoneId: number): Vector3
	local zone = World1.zonesById[zoneId]
	return Vector3.new(zone.grid.X * MapLayout.CELL, 0, -zone.grid.Y * MapLayout.CELL)
end

function MapLayout.eggPosition(zoneId: number): Vector3
	return MapLayout.center(zoneId) + Vector3.new(0, 0, 30)
end

-- Zone id under a position, or nil when on a bridge / outside the map.
function MapLayout.zoneAt(position: Vector3): number?
	local half = MapLayout.PLATFORM / 2 + 1
	for _, zone in World1.zones do
		local c = MapLayout.center(zone.id)
		if math.abs(position.X - c.X) <= half and math.abs(position.Z - c.Z) <= half then
			return zone.id
		end
	end
	return nil
end

-- Spots for coin sources: a jittered grid that keeps the middle (egg area) and edges free.
function MapLayout.sourceSpots(zoneId: number, count: number, seed: number): { Vector3 }
	local center = MapLayout.center(zoneId)
	local spots: { Vector3 } = {}
	local span = MapLayout.PLATFORM / 2 - 16
	local state = seed
	local function rand(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
	local attempts = 0
	while #spots < count and attempts < count * 50 do
		attempts += 1
		local x = (rand() * 2 - 1) * span
		local z = (rand() * 2 - 1) * span
		local offset = Vector3.new(x, 0, z)
		local nearEgg = (offset - Vector3.new(0, 0, 30)).Magnitude < 16
		local nearCenter = offset.Magnitude < 10
		local crowded = false
		for _, other in spots do
			if (other - (center + offset)).Magnitude < MapLayout.SOURCE_SPACING then
				crowded = true
				break
			end
		end
		if not nearEgg and not nearCenter and not crowded then
			table.insert(spots, center + offset)
		end
	end
	return spots
end

return MapLayout
