--!strict
-- On their own treadmill (in front of their garden), the player runs by themselves: their character runs in place
-- toward the treadmill's far end (where an invisible wall keeps them on it) for as long as they don't steer
-- themselves; steering walks them off. WildService counts the seconds they spend on it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("Layout"))

local TreadmillClient = {}

local LOCAL = Players.LocalPlayer

-- The player's own steering, from Roblox's control module (zero when they don't touch the controls)
local controls: any = nil
local function steering(): Vector3
	if not controls then
		local ok, module = pcall(function()
			local scripts = LOCAL:WaitForChild("PlayerScripts")
			return (require :: any)(scripts:WaitForChild("PlayerModule")):GetControls()
		end)
		controls = if ok then module else false
	end
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			return vector
		end
	end
	return Vector3.zero
end

local function onTreadmill(root: BasePart): CFrame?
	local index = LOCAL:GetAttribute("Island")
	if type(index) ~= "number" then
		return nil
	end
	local mill = Layout.garden(index) * CFrame.new(Layout.TREADMILL)
	local inside = mill:PointToObjectSpace(root.Position)
	if math.abs(inside.X) <= 5.5 and math.abs(inside.Z) <= 2.7 and inside.Y < 8 then
		return mill
	end
	return nil
end

function TreadmillClient.init()
	-- (after the controls have set the character's movement for this frame)
	RunService:BindToRenderStep("Treadmill", Enum.RenderPriority.Character.Value + 1, function()
		local character = LOCAL.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			return
		end
		local mill = onTreadmill(root)
		if mill and steering().Magnitude < 0.1 then
			humanoid:Move(mill.RightVector, false)
		end
	end)
end

return TreadmillClient
