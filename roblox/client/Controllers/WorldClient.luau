-- Client-side world: gates open per player, zones regain color as they're restored, source health bars,
-- booth prompts, coin and skill effects.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World1 = require(Shared.Config.World1)
local Format = require(Shared.Logic.Format)
local MapLayout = require(Shared.Logic.MapLayout)
local Reload = require(Shared.Logic.Reload)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Notify = require(script.Parent.Parent.UI.Notify)
local Windows = require(script.Parent.Parent.UI.Windows)
local BoothPanel = require(script.Parent.Parent.UI.BoothPanel)

local WorldClient = {}

local LOCAL = Players.LocalPlayer
local GREY = Color3.fromRGB(150, 152, 158)

---------------------------------------------------------------------------------------------------------------
-- Gates

local gatePrompts: { [BasePart]: ProximityPrompt } = {}

local function updateGate(gate: BasePart)
	local a, b = gate:GetAttribute("ZoneA"), gate:GetAttribute("ZoneB")
	if type(a) ~= "number" or type(b) ~= "number" then
		return
	end
	local openA, openB = Store.isUnlocked(a), Store.isUnlocked(b)
	local open = openA and openB
	gate.CanCollide = not open
	gate.Transparency = if open then 1 else 0.2
	local locked = if openA then b else a
	local zone = World1.zonesById[locked]
	local gui = gate:FindFirstChildOfClass("BillboardGui")
	local text = gui and gui:FindFirstChild("Text") :: TextLabel?
	if text then
		text.Text = if open then "" else ("🔒 %s\n🪙 %s"):format(zone.name, Format.abbrev(zone.gateCost))
	end
	local prompt = gatePrompts[gate]
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Unlock"
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0.3
		prompt.Parent = gate
		gatePrompts[gate] = prompt
	end
	local reachable = openA or openB
	prompt.Enabled = not open and reachable
	prompt.ObjectText = ("%s · 🪙 %s"):format(zone.name, Format.abbrev(zone.gateCost))
	prompt:SetAttribute("UnlockZone", locked)
end

local function updateGates()
	for _, gate in CollectionService:GetTagged("Gate") do
		if gate:IsA("BasePart") then
			updateGate(gate)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Zone colors: grey until restored

local function tintZones()
	local data = Store.data
	local worldFolder = workspace:FindFirstChild("World")
	if not data or not worldFolder then
		return
	end
	for _, zone in World1.zones do
		local model = worldFolder:FindFirstChild("Zone_" .. zone.id)
		if not model then
			continue
		end
		local amount = 1
		if zone.restoreGoal > 0 then
			local progress = math.min(1, (data.zoneProgress[tostring(zone.id)] or 0) / zone.restoreGoal)
			amount = 0.25 + 0.75 * progress
		end
		for _, part in model:GetChildren() do
			local base = part:GetAttribute("BaseColor")
			if part:IsA("BasePart") and typeof(base) == "Color3" then
				part.Color = GREY:Lerp(base, amount)
			end
		end
	end
end

-- Every Reload paints the world in a new palette.
local function tintWorld()
	local data = Store.data
	if not data then
		return
	end
	local effect = Lighting:FindFirstChild("ReloadTint") :: ColorCorrectionEffect?
	if not effect then
		local created = Instance.new("ColorCorrectionEffect")
		created.Name = "ReloadTint"
		created.Parent = Lighting
		effect = created
	end
	local reloads: number = data.reloads or 0
	local goal = Reload.tint(reloads)
	local target = effect :: ColorCorrectionEffect
	if target.TintColor ~= goal then
		TweenService:Create(target, TweenInfo.new(2), {
			TintColor = goal,
			Saturation = math.min(0.3, reloads * 0.05),
		}):Play()
	end
end

---------------------------------------------------------------------------------------------------------------
-- Source health bars

local function bindBreakable(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local gui = part:FindFirstChild("Info")
	local coins = gui and gui:FindFirstChild("Coins") :: TextLabel?
	local fill = gui and gui:FindFirstChild("Bar") and (gui :: any).Bar:FindFirstChild("Fill") :: Frame?
	local function update()
		local left = part:GetAttribute("CoinsLeft") or 0
		local max = part:GetAttribute("CoinsMax") or 1
		if coins then
			coins.Text = "🪙 " .. Format.abbrev(left)
		end
		if fill then
			fill.Size = UDim2.fromScale(math.clamp(left / math.max(max, 1), 0, 1), 1)
		end
	end
	part:GetAttributeChangedSignal("CoinsLeft"):Connect(update)
	update()
end

---------------------------------------------------------------------------------------------------------------
-- Effects

local fxFolder = Instance.new("Folder")
fxFolder.Name = "Fx"

local function floatingText(position: Vector3, text: string, color: Color3, size: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, size)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = anchor
	anchor.Parent = fxFolder
	TweenService:Create(anchor, TweenInfo.new(1.1), { Position = position + Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.2, function()
		anchor:Destroy()
	end)
end

local function coinBurst(position: Vector3, count: number)
	if Store.lowEnd() then
		return
	end
	local character = LOCAL.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _ = 1, count do
		local coin = Instance.new("Part")
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.3, 1.2, 1.2)
		coin.Color = Color3.fromRGB(255, 205, 60)
		coin.Material = Enum.Material.Neon
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		local start = position + Vector3.new(math.random(-20, 20) / 10, 1, math.random(-20, 20) / 10)
		coin.Position = start
		coin.Parent = fxFolder
		local peak = start + Vector3.new(math.random(-30, 30) / 10, 4, math.random(-30, 30) / 10)
		local up = TweenService:Create(coin, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = peak })
		up:Play()
		up.Completed:Connect(function()
			local goal = if root then root.Position else peak
			local fly = TweenService:Create(coin, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = goal,
				Size = Vector3.new(0.1, 0.4, 0.4),
			})
			fly:Play()
			fly.Completed:Connect(function()
				coin:Destroy()
			end)
		end)
	end
end

local function ring(position: Vector3, color: Color3)
	if Store.lowEnd() then
		return
	end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.3
	p.Size = Vector3.new(0.4, 4, 4)
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(0.6), { Size = Vector3.new(0.4, 60, 60), Transparency = 1 }):Play()
	task.delay(0.65, function()
		p:Destroy()
	end)
end

local SKILL_COLORS = {
	Strike = Color3.fromRGB(120, 200, 255),
	Wave = Color3.fromRGB(80, 160, 255),
	Smash = Color3.fromRGB(255, 120, 60),
	Area = Color3.fromRGB(255, 200, 80),
	Boost = Color3.fromRGB(255, 90, 200),
	Rain = Color3.fromRGB(255, 215, 80),
	GemRain = Color3.fromRGB(120, 230, 255),
	EggDrop = Color3.fromRGB(180, 255, 140),
	ComboAdd = Color3.fromRGB(255, 140, 60),
	CloneArmy = Color3.fromRGB(190, 160, 255),
	Drain = Color3.fromRGB(150, 255, 120),
}

---------------------------------------------------------------------------------------------------------------

-- A floating purple sign over today's Pixel Rift zone.
local riftMarker: BasePart? = nil
local function updateRift()
	local zoneId = ReplicatedStorage:GetAttribute("RiftZone")
	if riftMarker then
		riftMarker:Destroy()
		riftMarker = nil
	end
	if type(zoneId) ~= "number" or not World1.zonesById[zoneId] then
		return
	end
	local marker = Instance.new("Part")
	marker.Name = "RiftMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.Shape = Enum.PartType.Cylinder
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(142, 91, 217)
	marker.Transparency = 0.55
	marker.Size = Vector3.new(0.6, MapLayout.PLATFORM - 10, MapLayout.PLATFORM - 10)
	marker.CFrame = CFrame.new(MapLayout.center(zoneId) + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(320, 60)
	gui.StudsOffset = Vector3.new(0, 34, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 600
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(210, 170, 255)
	label.TextStrokeTransparency = 0.2
	label.Text = "🟪 PIXEL RIFT"
	label.Parent = gui
	gui.Parent = marker
	marker.Parent = fxFolder
	riftMarker = marker
end

function WorldClient.init()
	fxFolder.Parent = workspace
	ReplicatedStorage:GetAttributeChangedSignal("RiftZone"):Connect(updateRift)
	updateRift()

	Store.DataChanged:Connect(function()
		updateGates()
		tintZones()
		tintWorld()
	end)
	CollectionService:GetInstanceAddedSignal("Gate"):Connect(function(gate)
		if gate:IsA("BasePart") then
			updateGate(gate)
		end
	end)
	updateGates()

	for _, part in CollectionService:GetTagged("Breakable") do
		bindBreakable(part)
	end
	CollectionService:GetInstanceAddedSignal("Breakable"):Connect(bindBreakable)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local boothId = prompt:GetAttribute("BoothId")
		if type(boothId) == "number" then
			BoothPanel.use(boothId)
			return
		end
		local ui = prompt:GetAttribute("OpenUI")
		if type(ui) == "string" then
			Windows.open(ui)
			return
		end
		local zoneId = prompt:GetAttribute("UnlockZone")
		if type(zoneId) == "number" then
			Net.event("UnlockZone"):FireServer(zoneId)
		end
	end)

	Net.event("Notify").OnClientEvent:Connect(function(text: string, kind: string)
		Notify.show(text, kind, if kind == "rare" then 5 else 3)
	end)

	Net.event("BreakFx").OnClientEvent:Connect(function(position: Vector3, coins: number, jackpot: boolean, golden: boolean)
		coinBurst(position, if jackpot then 14 else 5)
		if Store.lowEnd() and not jackpot and not golden then
			return
		end
		local color = if jackpot then Color3.fromRGB(255, 90, 200) elseif golden then Color3.fromRGB(255, 215, 80) else Color3.fromRGB(255, 235, 140)
		local prefix = if jackpot then "JACKPOT! +" elseif golden then "GOLD! +" else "+"
		floatingText(position + Vector3.new(0, 3, 0), prefix .. Format.abbrev(coins), color, if jackpot then 60 else 36)
	end)

	Net.event("SkillFx").OnClientEvent:Connect(function(kind: string, speciesId: string, size: string, _text: string, position: Vector3?)
		local color = SKILL_COLORS[kind] or Color3.new(1, 1, 1)
		if position then
			ring(position, color)
			floatingText(position + Vector3.new(0, 8, 0), ("%s %s: %s!"):format(size, speciesId, kind), color, 40)
		end
	end)

	Net.event("OfflineEarnings").OnClientEvent:Connect(function(coins: number, seconds: number)
		Notify.show(("Welcome back! Your team collected 🪙 %s in %s"):format(Format.abbrev(coins), Format.time(seconds)), "success", 6)
	end)
end

return WorldClient
