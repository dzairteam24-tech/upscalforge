--!strict
-- Where the stages are in the world. The course runs along -Z: stage 1 starts at z = 0; a stage is its length of
-- lane, then the wall of cubes, then a gap, then the next stage.

local CourseConfig = require(script.Parent.Parent.Config.Course)
local Economy = require(script.Parent.Economy)

local Layout = {}

local starts: { [number]: number } = {}
do
	local z = 0
	for k = 1, CourseConfig.STAGES + 1 do
		starts[k] = z
		z -= Economy.stageLength(k) + CourseConfig.WALL_THICK + CourseConfig.GAP
	end
end

-- The world z where stage k starts
function Layout.startZ(stage: number): number
	return starts[stage] or starts[CourseConfig.STAGES + 1]
end

-- The world position of a stage's lane position and distance (on the floor)
function Layout.toWorld(stage: number, x: number, d: number): Vector3
	return Vector3.new(x, 0, Layout.startZ(stage) - d)
end

-- Which stage a world z is in, and how far along it (clamped to the stage's own run, wall and gap included)
function Layout.fromZ(z: number): (number, number)
	for k = CourseConfig.STAGES, 1, -1 do
		if z <= starts[k] then
			return k, starts[k] - z
		end
	end
	return 1, starts[1] - z
end

-- Where a runner starts a stage: in the middle, a little way in
function Layout.spawn(stage: number): Vector3
	return Layout.toWorld(stage, 0, 6) + Vector3.new(0, 4, 0)
end

return Layout
