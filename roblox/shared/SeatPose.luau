--!strict
-- Where a rider's hands and feet go on a floating seat (SeatModel): sitting cross-legged, the feet crossed in
-- front (each under the other leg's knee), the knees out to the sides, the hands resting on the knees.
-- RideClient bends the limbs onto these with RideIK. Pure CFrame math, so the offline tests check it.
--
-- Everything is measured in the hips' frame (the LowerTorso's: X right, Y up, -Z front) from the middle of
-- the hip joints, in units of a standard R15 leg, so it fits any avatar's size.

local SeatPose = {}

SeatPose.STANDARD_LEG = 1.92 -- a standard R15 leg, hip joint to sole
SeatPose.LIFT = 0.42 -- the hips this high above the seat's surface (the thighs lie on it), in legs
SeatPose.LEAN = -6 -- the back leans this much forward (degrees)

-- The sole of each foot, by side (Left is -X): the left foot under the right knee, a little in front
local SOLE = {
	Left = Vector3.new(0.12, -0.36, -0.98),
	Right = Vector3.new(-0.12, -0.28, -0.8),
}
local FOOT_YAW = 75 -- the feet point across, toward the other side
local FOOT_ROLL = 35 -- and lie on their outer edge, the soles turned up and back
local HAND_ABOVE_KNEE = 0.3 -- the hand's grip above the knee joint, in legs

-- The leg's target: where the sole goes, which way the knee points, and the foot's rotation (world)
function SeatPose.leg(hips: CFrame, side: string, scale: number): (Vector3, Vector3, CFrame)
	local s = if side == "Left" then -1 else 1
	local sole = hips:PointToWorldSpace(SOLE[side] * scale)
	local pole = hips:VectorToWorldSpace(Vector3.new(s, 0.3, -0.3))
	local foot = hips.Rotation * CFrame.Angles(0, math.rad(s * FOOT_YAW), 0) * CFrame.Angles(0, 0, math.rad(-s * FOOT_ROLL))
	return sole, pole, foot
end

-- The arm's target: the hand on top of its knee, the elbow out and back
function SeatPose.hand(hips: CFrame, knee: Vector3, side: string, scale: number): (Vector3, Vector3)
	local s = if side == "Left" then -1 else 1
	local target = knee + hips:VectorToWorldSpace(Vector3.new(-s * 0.1, HAND_ABOVE_KNEE, 0) * scale)
	local pole = hips:VectorToWorldSpace(Vector3.new(s * 0.8, -0.3, 0.6))
	return target, pole
end

return SeatPose
