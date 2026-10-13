--!strict
-- Digging, three ways: the big DIG button (or the E key): digs the cube below you when the camera looks down,
-- otherwise the one in front of you, so one thumb is enough on a phone; or hold the mouse on a cube of your own
-- mine; or, with the Auto Dig pass, switch Auto on and it keeps digging for you. The cube it will dig is
-- outlined. The server decides what happens (reach, cooldown, what falls out).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Config.Gear)
local MineConfig = require(Shared.Config.Mine)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Parent.UI.Ui)

local DigController = {}

local LOCAL = Players.LocalPlayer
local LOOK_DOWN = -0.3 -- the camera pitch (its look vector's Y) below which "dig down" is meant
local REACH = MineConfig.REACH + MineConfig.CELL

-- `openStore`: shown when someone taps Auto without the pass
function DigController.init(screen: ScreenGui, openStore: () -> ())
	local holding = false
	local mode = "smart" -- "smart" (the button, E) or "pointer" (the mouse on a cube)
	local pointer: Vector2? = nil -- where a finger is, for pointer mode
	local autoOn = false
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = workspace

	local function mine(hit: Instance?): BasePart?
		if hit and hit:IsA("BasePart") and hit.Name == "Block" and hit:GetAttribute("Owner") == LOCAL.UserId then
			return hit
		end
		return nil
	end

	local function params(): RaycastParams?
		local character = LOCAL.Character
		if not character then
			return nil
		end
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.FilterDescendantsInstances = { character }
		return p
	end

	-- The cube of my mine under the mouse or finger, within reach
	local function pointerTarget(): BasePart?
		local camera = workspace.CurrentCamera
		local root = LOCAL.Character and LOCAL.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local rp = params()
		if not camera or not root or not rp then
			return nil
		end
		local at = pointer or UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(at.X, at.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 200, rp)
		local block = mine(result and result.Instance)
		if block and (block.Position - root.Position).Magnitude <= REACH then
			return block
		end
		return nil
	end

	-- The cube the DIG button would dig: below you when looking down, else in front of you (else below)
	local function smartTarget(): BasePart?
		local camera = workspace.CurrentCamera
		local root = LOCAL.Character and LOCAL.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local rp = params()
		if not camera or not root or not rp then
			return nil
		end
		local function cast(origin: Vector3, direction: Vector3): BasePart?
			local result = workspace:Raycast(origin, direction * 9, rp)
			return mine(result and result.Instance)
		end
		local look = camera.CFrame.LookVector
		if look.Y < LOOK_DOWN then
			local below = cast(root.Position, Vector3.new(0, -1, 0))
			if below then
				return below
			end
		end
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			flat = flat.Unit
			local ahead = cast(root.Position, flat) or cast(root.Position - Vector3.new(0, 2.5, 0), flat)
			if ahead then
				return ahead
			end
		end
		return cast(root.Position, Vector3.new(0, -1, 0))
	end

	-- The DIG button, bottom right, and the Auto switch above it
	local dig = Ui.button(screen, "DIG", UDim2.fromOffset(110, 110), UDim2.new(1, -250, 1, -170), Color3.fromRGB(240, 150, 40), function() end)
	dig.AnchorPoint = Vector2.new(0, 0)
	Ui.round(dig, 55)
	dig.AutoButtonColor = false
	dig.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holding = true
			mode = "smart"
			dig.BackgroundColor3 = Color3.fromRGB(255, 190, 70)
		end
	end)
	dig.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holding = false
			dig.BackgroundColor3 = Color3.fromRGB(240, 150, 40)
		end
	end)
	local auto: TextButton
	local function refreshAuto()
		local data = Store.data
		local owned = data ~= nil and data.passes ~= nil and data.passes.AutoDig == true
		if not owned then
			autoOn = false
		end
		auto.Text = if owned then (if autoOn then "Auto: ON" else "Auto: off") else "Auto (pass)"
		auto.BackgroundColor3 = if autoOn then Ui.green else Ui.gray
	end
	auto = Ui.button(screen, "Auto (pass)", UDim2.fromOffset(110, 36), UDim2.new(1, -250, 1, -212), Ui.gray, function()
		local data = Store.data
		if data and data.passes and data.passes.AutoDig then
			autoOn = not autoOn
			refreshAuto()
		else
			openStore()
		end
	end)
	Store.onChanged(refreshAuto)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = true
			mode = "pointer"
			pointer = nil
		elseif input.UserInputType == Enum.UserInputType.Touch then
			-- (a finger on the world, not on a button: aim at what it touches)
			holding = true
			mode = "pointer"
			pointer = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
		elseif input.KeyCode == Enum.KeyCode.E then
			holding = true
			mode = "smart"
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and holding and mode == "pointer" then
			pointer = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and mode == "pointer" then
			holding = false
			pointer = nil
		elseif input.UserInputType == Enum.UserInputType.Touch and mode == "pointer" then
			holding = false
			pointer = nil
		elseif input.KeyCode == Enum.KeyCode.E then
			holding = false
		end
	end)

	local last = 0
	RunService.Heartbeat:Connect(function()
		local active = holding or autoOn
		if not active then
			highlight.Adornee = smartTarget() -- (what DIG would dig, so you can aim)
			return
		end
		local block = if holding and mode == "pointer" then pointerTarget() else smartTarget()
		highlight.Adornee = block
		if not block then
			return
		end
		-- (about as often as the shovel can swing: no more events than the server would take)
		local data = Store.data
		local shovel = Gear.SHOVELS[(data and data.shovel) or 1] or Gear.SHOVELS[1]
		if os.clock() - last >= shovel.cooldown * 0.9 then
			last = os.clock()
			Net.event("Dig"):FireServer(block:GetAttribute("X"), block:GetAttribute("L"), block:GetAttribute("Z"))
		end
	end)
end

return DigController
