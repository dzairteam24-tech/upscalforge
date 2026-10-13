--!strict
-- Digging: hold the mouse (or a finger) on a cube of your own mine to swing the shovel at it. The cube under the
-- pointer is outlined; the server decides what happens (reach, cooldown, what falls out).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MineConfig = require(Shared.Config.Mine)
local Net = require(Shared.Net)

local DigController = {}

local LOCAL = Players.LocalPlayer
local SEND_EVERY = 0.07 -- seconds (the server enforces the shovel's own cooldown)

function DigController.init()
	local holding = false
	local pointer: Vector2? = nil -- where the finger is, when there is no mouse
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = workspace

	local function point(): Vector2
		if pointer then
			return pointer
		end
		return UserInputService:GetMouseLocation()
	end

	-- The cube of my mine under the pointer, if one is within reach
	local function target(): BasePart?
		local camera = workspace.CurrentCamera
		local character = LOCAL.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not camera or not character or not root then
			return nil
		end
		local at = point()
		local ray = camera:ViewportPointToRay(at.X, at.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
		local hit = result and result.Instance
		if hit and hit.Name == "Block" and hit:GetAttribute("Owner") == LOCAL.UserId and (hit.Position - root.Position).Magnitude <= MineConfig.REACH + MineConfig.CELL then
			return hit
		end
		return nil
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = true
			pointer = nil
		elseif input.UserInputType == Enum.UserInputType.Touch then
			holding = true
			local inset = GuiService:GetGuiInset()
			pointer = Vector2.new(input.Position.X, input.Position.Y) + inset
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and holding then
			local inset = GuiService:GetGuiInset()
			pointer = Vector2.new(input.Position.X, input.Position.Y) + inset
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holding = false
			pointer = nil
		end
	end)

	local last = 0
	RunService.Heartbeat:Connect(function()
		local block = target()
		highlight.Adornee = block
		if holding and block and os.clock() - last >= SEND_EVERY then
			last = os.clock()
			Net.event("Dig"):FireServer(block:GetAttribute("X"), block:GetAttribute("L"), block:GetAttribute("Z"))
		end
	end)
end

return DigController
