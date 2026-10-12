--!strict
-- Knocked down by a bat (StealService): the character is laid on its back on the ground for a moment, unable to
-- move, sliding a little the way the hit pushed it, then gets back up. A player's own client does it to their
-- character (Effects); the server does it to a Studio test bot (TestBotService). (Only switching the legs off,
-- PlatformStand alone, left it standing with its legs in the ground: an R15's legs don't collide.)

local Knockdown = {}

function Knockdown.fall(character: Model, push: Vector3, seconds: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	-- (the ground under them)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -14, 0), params)
	local ground = if hit then hit.Position.Y else root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	local flat = Vector3.new(push.X, 0, push.Z)
	local facing = if flat.Magnitude > 0.01 then -flat.Unit else root.CFrame.LookVector
	local yaw = CFrame.lookAt(Vector3.zero, Vector3.new(facing.X, 0, facing.Z))
	humanoid.PlatformStand = true
	-- (on their back, face up, feet toward where the hit came from)
	root.CFrame = CFrame.new(root.Position.X, ground + 1.2, root.Position.Z) * yaw * CFrame.Angles(math.rad(90), 0, 0)
	root.AssemblyLinearVelocity = flat * 0.5
	root.AssemblyAngularVelocity = Vector3.zero
	task.delay(seconds, function()
		if not humanoid.Parent or not root.Parent then
			return
		end
		root.CFrame = CFrame.new(root.Position + Vector3.new(0, 2.5, 0)) * yaw
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
end

return Knockdown
