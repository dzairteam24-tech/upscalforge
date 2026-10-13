--!strict
-- The first minutes: a glowing line from the player to what to do next, a word over it, and one line at the top
-- of the screen. Dig the first cube; keep digging for gems; when the backpack fills, go and sell; then buy the
-- first shovel. After that it's gone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Config.Gear)
local Layout = require(Shared.Logic.Layout)
local MineConfig = require(Shared.Config.Mine)

local Store = require(script.Parent.Parent.Store)

local Guide = {}

local LOCAL = Players.LocalPlayer
local NEAR = 12 -- studs: close enough, the line goes away (the word stays)

local function stand(name: string): BasePart?
	local town = workspace:FindFirstChild("Town")
	local found = town and town:FindFirstChild(name)
	return if found and found:IsA("BasePart") then found else nil
end

-- Where to go: the point, the word over it, and the line at the top of the screen (nothing: no guide)
local function step(): (Vector3?, string, string)
	local data = Store.data
	local plot = LOCAL:GetAttribute("Plot")
	if not data or type(plot) ~= "number" then
		return nil, "", ""
	end
	if data.stats.sold >= 1 and data.shovel > 1 then
		return nil, "", ""
	end
	if data.stats.dug == 0 then
		return Layout.cellCenter(plot, MineConfig.TUTORIAL.x, 1, MineConfig.TUTORIAL.z) + Vector3.new(0, 4, 0), "Dig here!", "Stand on the glowing spot and hold DIG (look down to dig under you)"
	end
	if data.stats.sold == 0 then
		if data.used >= math.max(4, data.capacity // 2) then
			local sell = stand("SellStand")
			return if sell then sell.Position + Vector3.new(0, 6, 0) else nil, "Sell here!", "Your backpack is filling: take your gems to the Sell stand in town (the Town button)"
		end
		return nil, "", "Keep digging: the sparkly cubes hold gems"
	end
	local price = Gear.SHOVELS[2].price
	if data.coins >= price then
		local shop = stand("ShopStand")
		return if shop then shop.Position + Vector3.new(0, 6, 0) else nil, "Buy a shovel!", "You can afford the Stone Shovel: it digs faster and deeper"
	end
	return nil, "", ("Dig and sell until you have %d coins for the Stone Shovel"):format(price)
end

function Guide.init(screen: ScreenGui)
	local beam = Instance.new("Beam")
	beam.FaceCamera = true
	beam.Width0, beam.Width1 = 0.8, 0.8
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 215, 80))
	beam.Transparency = NumberSequence.new(0.2)
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Static
	beam.TextureLength = 3
	beam.TextureSpeed = 2

	local marker = Instance.new("Part")
	marker.Name = "GuideMarker"
	marker.Size = Vector3.one
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	local to = Instance.new("Attachment")
	to.Parent = marker
	local from = Instance.new("Attachment")
	beam.Attachment0, beam.Attachment1 = from, to

	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromScale(9, 2)
	label.AlwaysOnTop = true
	label.MaxDistance = 600
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.fromRGB(255, 225, 100)
	text.TextStrokeTransparency = 0.2
	text.Parent = label
	label.Adornee = marker
	label.Parent = marker

	local line = Instance.new("TextLabel")
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0, 56)
	line.Size = UDim2.new(0.62, 0, 0, 28)
	line.BackgroundTransparency = 1
	line.TextScaled = true
	line.Font = Enum.Font.FredokaOne
	line.TextColor3 = Color3.fromRGB(255, 225, 100)
	line.TextStrokeColor3 = Color3.fromRGB(28, 24, 40)
	line.TextStrokeTransparency = 0
	line.Parent = screen

	task.spawn(function()
		while true do
			local root = LOCAL.Character and LOCAL.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local target, words, says = step()
			if target and root then
				marker.Position = target
				marker.Parent = workspace
				from.Parent = root
				text.Text = words
				beam.Parent = if (root.Position - target).Magnitude > NEAR then root else nil
			else
				marker.Parent = nil
				beam.Parent = nil
				from.Parent = nil
			end
			line.Text = says
			line.Visible = says ~= ""
			task.wait(0.25)
		end
	end)
end

return Guide
