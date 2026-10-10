--!strict
-- The catching game on this screen (Logic/Hunt): a bar with its green and a marker sweeping along it; a click
-- (or tap, or Space) stops it and sends the moment to the server, which decides.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HuntConfig = require(Shared.Config.Hunt)
local Hunt = require(Shared.Logic.Hunt)
local Net = require(Shared.Net)

local Theme = require(script.Parent.Parent.UI.Theme)

local HuntClient = {}

function HuntClient.mount(gui: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "CatchGame"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -40)
	panel.Size = UDim2.fromOffset(440, 150)
	panel.BackgroundColor3 = Theme.panel
	panel.Visible = false
	Theme.round(panel, 16)
	Theme.stroke(panel, Theme.gold, 3)
	panel.Parent = gui
	local title = Theme.text(panel, { Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 6) })
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -40, 0, 30)
	bar.Position = UDim2.fromOffset(20, 42)
	bar.BackgroundColor3 = Theme.card
	Theme.round(bar, 8)
	bar.Parent = panel
	local green = Instance.new("Frame")
	green.BackgroundColor3 = Theme.green
	green.Size = UDim2.fromScale(0.2, 1)
	Theme.round(green, 6)
	green.Parent = bar
	local marker = Instance.new("Frame")
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.new(0, 6, 1, 14)
	marker.BackgroundColor3 = Color3.new(1, 1, 1)
	Theme.stroke(marker, Color3.fromRGB(40, 36, 54), 2)
	marker.Parent = bar

	local current: { id: string, start: number, speed: number, ends: number }? = nil
	local function close()
		current = nil
		panel.Visible = false
		ContextActionService:UnbindAction("Catch")
	end
	local function click()
		local game_ = current
		if not game_ or workspace:GetServerTimeNow() < game_.start then
			return
		end
		Net.event("CatchTry"):FireServer(game_.id, workspace:GetServerTimeNow())
		close()
	end
	local button = Theme.button(panel, "CATCH!", Theme.green, click)
	button.Size = UDim2.new(0.5, 0, 0, 44)
	button.Position = UDim2.new(0.25, 0, 0, 92)

	Net.event("CatchGame").OnClientEvent:Connect(function(id, start, speed, center, width, netId)
		local net = HuntConfig.netById[netId] or HuntConfig.NETS[1]
		current = { id = id, start = start, speed = speed, ends = start + HuntConfig.GAME_TIME }
		title.Text = ("%s Stop the marker in the green!"):format(net.icon)
		green.Position = UDim2.fromScale(center - width / 2, 0)
		green.Size = UDim2.fromScale(width, 1)
		panel.Visible = true
		ContextActionService:BindAction("Catch", function(_, state)
			if state == Enum.UserInputState.Begin then
				click()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	end)
	RunService.RenderStepped:Connect(function()
		local game_ = current
		if not game_ then
			return
		end
		local now = workspace:GetServerTimeNow()
		if now > game_.ends then
			close()
			return
		end
		marker.Position = UDim2.fromScale(Hunt.marker(now - game_.start, game_.speed), 0.5)
	end)
end

return HuntClient
