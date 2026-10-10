--!strict
-- Where everything is. The town is a small round plaza with the six shops round a fountain; the players'
-- islands float in a ring round it, each joined to the plaza by a bridge between two shops.

local IslandConfig = require(script.Parent.Parent.Config.Island)

local Layout = {
	TOWN_RADIUS = 64,
	SHOP_RADIUS = 42, -- the shops' middles
	ISLAND_DISTANCE = 160, -- from the town's middle to an island's
	ISLAND_SIZE = 60,
	BRIDGE_WIDTH = 18,
	CENTER = Vector3.new(0, 0, 0),
}

local SHOPS = 6

-- A frame at `at` (on the ground) turned about Y so its front (-Z) faces `target` (no lookAt: the same in
-- every runtime)
function Layout.facing(at: Vector3, target: Vector3): CFrame
	local d = target - at
	return CFrame.new(at) * CFrame.Angles(0, math.atan2(-d.X, -d.Z), 0)
end

-- A shop's spot (1..6), facing the fountain
function Layout.shop(index: number): CFrame
	local angle = math.rad((index - 1) * 360 / SHOPS)
	local at = Layout.CENTER + Vector3.new(math.sin(angle), 0, -math.cos(angle)) * Layout.SHOP_RADIUS
	return Layout.facing(at, Layout.CENTER)
end

-- An island's middle, facing the town (its front, -Z, toward the bridge). The islands sit between the shops.
function Layout.island(index: number): CFrame
	local angle = math.rad((index - 0.5) * 360 / IslandConfig.ISLANDS)
	local at = Layout.CENTER + Vector3.new(math.sin(angle), 0, -math.cos(angle)) * Layout.ISLAND_DISTANCE
	return Layout.facing(at, Layout.CENTER)
end

-- An incubator's spot on an island: a row along the front, nearest the bridge
function Layout.incubator(index: number, slot: number): Vector3
	local frame = Layout.island(index)
	local count = IslandConfig.INCUBATORS + #IslandConfig.INCUBATOR_PRICES
	local across = (slot - (count + 1) / 2) * 6.5
	return (frame * CFrame.new(across, 0, -(Layout.ISLAND_SIZE / 2 - 9))).Position
end

-- Where a creature living on the island stands (rows of four behind the incubators)
function Layout.pen(index: number, slot: number): Vector3
	local frame = Layout.island(index)
	local column = (slot - 1) % 4
	local row = (slot - 1) // 4
	return (frame * CFrame.new((column - 1.5) * 11, 0, -6 + row * 10)).Position
end

-- Whether a position is on an island (and which)
function Layout.islandAt(position: Vector3): number?
	for index = 1, IslandConfig.ISLANDS do
		local local_ = Layout.island(index):PointToObjectSpace(position)
		if math.abs(local_.X) <= Layout.ISLAND_SIZE / 2 and math.abs(local_.Z) <= Layout.ISLAND_SIZE / 2 then
			return index
		end
	end
	return nil
end

return Layout
