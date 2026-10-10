-- For art/blender/seats.py's RIDE render: seats a standard R15 rig on a floating seat whose sitting surface is
-- arg 2 studs high (as the game draws it), poses it like RideClient (SeatPose + RideIK), and writes the
-- rider's blocks (game frame: studs, Y up, front -Z, origin on the ground under the seat's middle) to arg 1.
-- Run from the repo root:  lune run art/blender/seat_rider.luau out.json 1.55
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("../../tests/loader")
local Shared = Loader.root("game/shared", "Shared")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local RideIK = Loader.require(Shared.RideIK)
local SeatPose = Loader.require(Shared.SeatPose)
local TOP = tonumber(process.args[2]) or 1.55
local BACK = 0.45 -- the hips this far behind the seat's middle (RideClient SEAT_FORWARD)

local SCALE = 1
local function v(x, y, z) return Vector3.new(x, y, z) * SCALE end
local function c(x, y, z) return CFrame.new(v(x, y, z)) end
local size = { HumanoidRootPart = v(2, 2, 1), LowerTorso = v(2, 0.4, 1), UpperTorso = v(2, 1.6, 1), Head = v(1.2, 1.2, 1.2),
	UpperArm = v(1, 1.17, 1), LowerArm = v(1, 1.05, 1), Hand = v(1, 0.3, 1), UpperLeg = v(1, 1.22, 1), LowerLeg = v(1, 1.19, 1), Foot = v(1, 0.3, 1) }
local J = {
	Root = { "HumanoidRootPart", c(0, -0.8, 0), c(0, 0, 0), "LowerTorso" },
	Waist = { "LowerTorso", c(0, 0.2, 0), c(0, -0.8, 0), "UpperTorso" },
	Neck = { "UpperTorso", c(0, 0.8, 0), c(0, -0.5, 0), "Head" },
}
for _, side in { "Left", "Right" } do
	local s = if side == "Left" then -1 else 1
	J[side .. "Shoulder"] = { "UpperTorso", c(s * 1, 0.56, 0), c(-s * 0.5, 0.39, 0), side .. "UpperArm" }
	J[side .. "Elbow"] = { side .. "UpperArm", c(0, -0.33, 0), c(0, 0.26, 0), side .. "LowerArm" }
	J[side .. "Wrist"] = { side .. "LowerArm", c(0, -0.5, 0), c(0, 0.13, 0), side .. "Hand" }
	J[side .. "Hip"] = { "LowerTorso", c(s * 0.5, -0.2, 0), c(0, 0.42, 0), side .. "UpperLeg" }
	J[side .. "Knee"] = { side .. "UpperLeg", c(0, -0.41, 0), c(0, 0.29, 0), side .. "LowerLeg" }
	J[side .. "Ankle"] = { side .. "LowerLeg", c(0, -0.55, 0), c(0, 0.1, 0), side .. "Foot" }
end
local grip = c(0, -0.15, 0)
local sole = c(0, -0.15, 0)
local T = {}
for name in J do T[name] = CFrame.identity end

local legLen = (J.LeftHip[3]:Inverse() * J.LeftKnee[2]).Position.Magnitude
	+ (J.LeftKnee[3]:Inverse() * J.LeftAnkle[2] * J.LeftAnkle[3]:Inverse() * sole).Position.Magnitude
local k = legLen / SeatPose.STANDARD_LEG
local hipsRel = J.Root[2] * J.Root[3]:Inverse() * c(0, -0.2, 0)
local hipsAt = Vector3.new(0, TOP + SeatPose.LIFT * k, BACK)
local root = CFrame.new(hipsAt - hipsRel.Position)
local lower = root * J.Root[2] * J.Root[3]:Inverse()
local hips = CFrame.new(hipsAt) * lower.Rotation
T.Waist = CFrame.Angles(math.rad(SeatPose.LEAN), 0, 0)
local upper = lower * J.Waist[2] * T.Waist * J.Waist[3]:Inverse()
local function limb(parent, names, tip, target, pole)
	local a, b, cc = J[names[1]], J[names[2]], J[names[3]]
	local base = parent * a[2]
	local midRel = a[3]:Inverse() * b[2]
	local tipRel = b[3]:Inverse() * cc[2] * cc[3]:Inverse() * tip
	local first, second, reach = RideIK.solve(base, midRel, tipRel, target, pole)
	T[names[1]], T[names[2]] = first, second
	local lowerPart = base * first * a[3]:Inverse() * b[2] * second * b[3]:Inverse()
	return lowerPart, cc, (reach - target).Magnitude, (lowerPart * b[3]).Position
end
local miss = {}
for _, side in { "Left", "Right" } do
	local target, pole, foot = SeatPose.leg(hips, side, k)
	local shin, ankle, m1, knee = limb(lower, { side .. "Hip", side .. "Knee", side .. "Ankle" }, sole, target, pole)
	T[side .. "Ankle"] = RideIK.orient(shin, ankle[2], ankle[3], foot)
	local hand, epole = SeatPose.hand(hips, knee, side, k)
	local _, _, m2 = limb(upper, { side .. "Shoulder", side .. "Elbow", side .. "Wrist" }, grip, hand, epole)
	miss[side] = { m1, m2 }
end
local frames = { HumanoidRootPart = root }
local function solvePart(name)
	if frames[name] then return frames[name] end
	for jn, j in J do
		if j[4] == name then
			frames[name] = solvePart(j[1]) * j[2] * T[jn] * j[3]:Inverse()
			return frames[name]
		end
	end
end
local out = { parts = {} }
local colors = { Head = { 0.98, 0.8, 0.6 }, Hand = { 0.98, 0.8, 0.6 }, UpperTorso = { 0.9, 0.35, 0.35 }, UpperArm = { 0.9, 0.35, 0.35 }, LowerArm = { 0.98, 0.8, 0.6 }, Foot = { 0.1, 0.1, 0.1 } }
for name in pairs(J) do
	local part = J[name][4]
	local f = solvePart(part)
	local kind = string.gsub(string.gsub(part, "^Left", ""), "^Right", "")
	local col = colors[kind] or { 0.2, 0.25, 0.45 }
	local x, y, z = f.XVector, f.YVector, f.ZVector
	table.insert(out.parts, { n = "Rider_" .. part, p = { f.Position.X, f.Position.Y, f.Position.Z }, s = { size[kind].X, size[kind].Y, size[kind].Z }, c = col, r = { x.X, x.Y, x.Z, y.X, y.Y, y.Z, z.X, z.Y, z.Z } })
end
fs.writeFile(process.args[1], serde.encode("json", out))
print(("scale %.2f  leg miss L %.3f R %.3f  arm miss L %.3f R %.3f"):format(SCALE, miss.Left[1], miss.Right[1], miss.Left[2], miss.Right[2]))
