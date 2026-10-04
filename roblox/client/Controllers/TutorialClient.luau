-- First-time guide on the client: a banner with the current step and a glowing beam from the player
-- to the target (nearest coin pile, the zone 1 egg, or the next locked gate).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tutorial = require(Shared.Config.Tutorial)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Parent.UI.Theme)

local TutorialClient = {}

local LOCAL = Players.LocalPlayer

local function rootPart(): BasePart?
	local character = LOCAL.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nearest(parts: { Instance }, from: Vector3, filter: (BasePart) -> boolean): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, instance in parts do
		if instance:IsA("BasePart") and filter(instance) then
			local distance = (instance.Position - from).Magnitude
			if distance < bestDistance then
				best = instance
				bestDistance = distance
			end
		end
	end
	return best
end

local function findTarget(kind: string, from: Vector3): BasePart?
	if kind == "Breakable" then
		return nearest(CollectionService:GetTagged("Breakable"), from, function(part)
			return part:GetAttribute("Alive") ~= false and part:GetAttribute("ZoneId") == 1
		end)
	elseif kind == "Egg" then
		return nearest(CollectionService:GetTagged("EggStand"), from, function(part)
			return part:GetAttribute("ZoneId") == 1
		end)
	elseif kind == "Gate" then
		return nearest(CollectionService:GetTagged("Gate"), from, function(part)
			local a, b = part:GetAttribute("ZoneA"), part:GetAttribute("ZoneB")
			if type(a) ~= "number" or type(b) ~= "number" then
				return false
			end
			return Store.isUnlocked(a) ~= Store.isUnlocked(b)
		end)
	end
	return nil
end

function TutorialClient.init(gui: ScreenGui)
	local banner = Theme.frame({
		Name = "Guide",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(460, 58),
		BackgroundColor3 = Theme.bg,
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	Theme.corner(banner, 12)
	Theme.stroke(banner, Theme.gold, 2)
	local text = Theme.label({
		Text = "",
		Size = UDim2.new(1, -90, 1, -8),
		Position = UDim2.fromOffset(10, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
	})
	text.Parent = banner
	local skip = Theme.button({
		Text = "Skip",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(64, 36),
		BackgroundColor3 = Theme.card,
		MaxTextSize = 16,
	})
	skip.Parent = banner
	skip.Activated:Connect(function()
		Net.event("SkipTutorial"):FireServer()
	end)
	banner.Parent = gui

	-- Beam from the player to the target, and a bouncing arrow over the target
	local fromAttachment = Instance.new("Attachment")
	fromAttachment.Name = "GuideFrom"
	local anchor = Instance.new("Part")
	anchor.Name = "GuideTarget"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	local toAttachment = Instance.new("Attachment")
	toAttachment.Parent = anchor
	local beam = Instance.new("Beam")
	beam.Attachment0 = fromAttachment
	beam.Attachment1 = toAttachment
	beam.Color = ColorSequence.new(Theme.gold)
	beam.LightEmission = 1
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.FaceCamera = true
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureSpeed = 2
	beam.Transparency = NumberSequence.new(0.2)
	beam.Parent = anchor
	local arrow = Instance.new("BillboardGui")
	arrow.Size = UDim2.fromOffset(60, 60)
	arrow.AlwaysOnTop = true
	local arrowText = Instance.new("TextLabel")
	arrowText.BackgroundTransparency = 1
	arrowText.Size = UDim2.fromScale(1, 1)
	arrowText.Font = Enum.Font.FredokaOne
	arrowText.TextScaled = true
	arrowText.TextColor3 = Theme.gold
	arrowText.TextStrokeTransparency = 0.2
	arrowText.Text = "⬇"
	arrowText.Parent = arrow
	arrow.Parent = anchor

	task.spawn(function()
		while true do
			local data = Store.data
			local stepIndex: number = if data then data.tutorial or 0 else 0
			local step = Tutorial.steps[stepIndex]
			banner.Visible = step ~= nil
			local root = rootPart()
			local target = if step and root then findTarget(step.target, root.Position) else nil
			if step then
				text.Text = ("Step %d/%d · %s"):format(stepIndex, #Tutorial.steps, step.text)
			end
			if target and root then
				fromAttachment.Parent = root
				local top = target.Position + Vector3.new(0, target.Size.Y / 2 + 4 + math.abs(math.sin(os.clock() * 3)) * 1.5, 0)
				anchor.Position = top
				arrow.StudsOffset = Vector3.new(0, 2, 0)
				anchor.Parent = workspace
			else
				anchor.Parent = nil
				fromAttachment.Parent = nil
			end
			task.wait(if step then 0.05 else 1)
		end
	end)
end

return TutorialClient
