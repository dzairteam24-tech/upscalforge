--!strict
-- Two-bone inverse kinematics for the rider's arms and legs (RideClient): bends a limb's two joints
-- (shoulder and elbow, or hip and knee) so its end (the hand's grip, the foot's sole) lands on a target,
-- whatever the avatar's size. Pure CFrame math on the joints' frames, so the offline tests check it.
--
-- A joint turns its child part through its Transform: child = parent * C0 * Transform * C1:Inverse() (a
-- Motor6D; an AnimationConstraint is the same with its attachments' CFrames for C0 and C1).

local RideIK = {}

-- The rotation that turns direction a onto direction b by the shortest way
function RideIK.between(a: Vector3, b: Vector3): CFrame
	local ua, ub = a.Unit, b.Unit
	local axis = ua:Cross(ub)
	local s = axis.Magnitude
	local c = ua:Dot(ub)
	if s < 1e-6 then
		if c > 0 then
			return CFrame.identity
		end
		-- Opposite: half a turn about any axis square to a
		local other = if math.abs(ua.X) < 0.9 then Vector3.xAxis else Vector3.yAxis
		return CFrame.fromAxisAngle(ua:Cross(other).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis / s, math.atan2(s, c))
end

-- Solves a limb.
--   base:   the first joint's pivot in the world, before its Transform (parent part * C0)
--   midRel: from the first joint's pivot to the second joint's pivot, at rest (C1a:Inverse() * C0b)
--   tipRel: from the second joint's pivot to the limb's end, at rest (C1b:Inverse() * ... * the end)
--   target: where the end should go (world); pole: which way the middle joint should point (world)
-- Returns the two joints' Transforms (rotations), and where the end lands: the target, or as close as
-- the limb reaches.
function RideIK.solve(base: CFrame, midRel: CFrame, tipRel: CFrame, target: Vector3, pole: Vector3): (CFrame, CFrame, Vector3)
	local v1 = midRel.Position
	local v2 = tipRel.Position
	local l1, l2 = v1.Magnitude, v2.Magnitude
	local origin = base.Position
	local toTarget = target - origin
	local dir = if toTarget.Magnitude > 1e-6 then toTarget.Unit else -base.UpVector
	local d = math.clamp(toTarget.Magnitude, math.abs(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	-- The middle joint: on the circle where both bones meet, on the pole's side
	local side = pole - dir * pole:Dot(dir)
	if side.Magnitude < 1e-6 then
		side = dir:Cross(if math.abs(dir.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis)
	end
	side = side.Unit
	local a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
	local h = math.sqrt(math.max(l1 * l1 - a * a, 0))
	local middle = origin + dir * a + side * h
	local reach = origin + dir * d

	local first = RideIK.between(v1, base:VectorToObjectSpace(middle - origin))
	local second = base * first * midRel
	local secondT = RideIK.between(v2, second:VectorToObjectSpace(reach - middle))
	return first, secondT, reach
end

-- The Transform that turns a joint's child to `wanted` (world rotation), given the parent's world frame:
-- child = parent * C0 * T * C1:Inverse()  =>  T = (parent * C0):Inverse() * wanted * C1
function RideIK.orient(parent: CFrame, c0: CFrame, c1: CFrame, wanted: CFrame): CFrame
	return ((parent * c0):Inverse() * wanted * c1).Rotation
end

return RideIK
