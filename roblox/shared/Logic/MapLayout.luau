--!strict
-- Where things are on the map. Shared by the server (building, checks) and the client.
-- The world is the Hub (the town) with the Egg Garden north of it, the Trading Plaza east and the Nest field
-- west (WorldBuilder places those from the Hub); the zones of Config/World1 are egg tiers, not places.

local MapLayout = {
	HUB_SIZE = 400, -- the Hub: where everyone meets
	HUB_BRIDGE = 30, -- length of the bridge from the Hub to the Egg Garden
	BRIDGE_WIDTH = 30,
}

local HUB_CENTER = Vector3.new(0, 0, 290)

-- Width of the Hub's square island
function MapLayout.size(_zoneId: number): number
	return MapLayout.HUB_SIZE
end

-- The Hub's middle (every zone id gives the Hub: the zones are no places any more)
function MapLayout.center(_zoneId: number): Vector3
	return HUB_CENTER
end

-- Whether a position is on the Hub's island
function MapLayout.inHub(position: Vector3): boolean
	local half = MapLayout.HUB_SIZE / 2 + 1
	return math.abs(position.X - HUB_CENTER.X) <= half and math.abs(position.Z - HUB_CENTER.Z) <= half
end

return MapLayout
