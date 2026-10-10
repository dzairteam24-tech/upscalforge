--!strict
-- Sprint: hold Shift (or the Sprint button on a phone, or the gamepad's left stick click) to run faster while
-- the stamina lasts (MoveService has the truth); a bar under the screen shows what's left.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local SprintClient = {}

local LOCAL = Players.LocalPlayer

function SprintClient.init(gui: ScreenGui)
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

	-- The stamina bar: shown while it isn't full
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -16)
	frame.Size = UDim2.fromOffset(220, 12)
	frame.BackgroundColor3 = Color3.fromRGB(40, 36, 54)
	frame.BackgroundTransparency = 0.3
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 255)
	corner:Clone().Parent = fill
	fill.Parent = frame
	frame.Parent = gui
	local function update()
		local value = LOCAL:GetAttribute("Stamina")
		local left = if type(value) == "number" then value else 1
		fill.Size = UDim2.fromScale(left, 1)
		fill.BackgroundColor3 = if left < 0.3 then Color3.fromRGB(240, 110, 90) else Color3.fromRGB(90, 220, 255)
		frame.Visible = left < 1
	end
	LOCAL:GetAttributeChangedSignal("Stamina"):Connect(update)
	update()
end

return SprintClient
