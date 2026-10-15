--!strict
-- Driving: while this player sits in their tractor's seat, the seat's throttle and steer (keyboard or thumbstick)
-- set how fast it goes and turns; it speeds up and slows down smoothly. Also hides this player's own "Trade"
-- prompt (it's for the others).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TractorController = {}

local LOCAL = Players.LocalPlayer
TractorController.TOP = 70 -- studs a second, flat out
TractorController.BACK = 25 -- in reverse
TractorController.TURN = 1.7 -- radians a second
TractorController.GRIP = 2.2 -- how quickly it gets to the speed asked for

local speed = 0

-- One frame of driving (dt seconds). Returns whether they're driving
function TractorController.drive(dt: number): boolean
	local character = LOCAL.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") or seat.Name ~= "DriverSeat" then
		speed = 0
		return false
	end
	local model = seat.Parent :: Model
	local base = model.PrimaryPart
	local move = base and base:FindFirstChild("Move") :: LinearVelocity?
	local turn = base and base:FindFirstChild("Turn") :: AngularVelocity?
	if not base or not move or not turn then
		return false
	end
	local throttle, steer = seat.ThrottleFloat, seat.SteerFloat
	local target = if throttle >= 0 then throttle * TractorController.TOP else throttle * TractorController.BACK
	speed += (target - speed) * math.min(1, dt * TractorController.GRIP)
	local look = base.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	move.PlaneVelocity = Vector2.new(flat.X * speed, flat.Z * speed)
	-- (it turns more the faster it goes, and the other way in reverse, like a real one)
	local grip = math.clamp(math.abs(speed) / 12, 0, 1)
	turn.AngularVelocity = Vector3.new(0, -steer * TractorController.TURN * grip * (if speed < 0 then -1 else 1), 0)
	return true
end

local function hideOwnPrompt(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local prompt = root and root:WaitForChild("TradePrompt", 10)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
end

function TractorController.init()
	RunService.RenderStepped:Connect(TractorController.drive)
	LOCAL.CharacterAdded:Connect(hideOwnPrompt)
	if LOCAL.Character then
		task.spawn(hideOwnPrompt, LOCAL.Character)
	end
end

return TractorController
