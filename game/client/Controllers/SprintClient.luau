--!strict
-- Sprint: hold Shift (or the Sprint button on a phone, or the gamepad's left stick click) to run faster
-- (MoveService has the truth).

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local SprintClient = {}

function SprintClient.init()
	local remote = Net.event("Sprint")
	local holding = false
	local function set(on: boolean)
		if on ~= holding then
			holding = on
			remote:FireServer(on)
		end
	end
	ContextActionService:BindAction("Sprint", function(_, state)
		if state == Enum.UserInputState.Begin then
			set(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			set(false)
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("Sprint", "Sprint")
	ContextActionService:SetPosition("Sprint", UDim2.new(1, -170, 1, -75))
end

return SprintClient
