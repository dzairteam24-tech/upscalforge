--!strict
-- The town in the middle: the ground, roads out to every plot, the Sell stand and the Shop stand (touch their
-- prompts), and where players spawn.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Layout = require(Shared.Logic.Layout)

local TownService = {}

local actions: { [ProximityPrompt]: (Player) -> () } = {} -- what each stand's prompt does

local CELL = require(Shared.Config.Mine).CELL

local function slab(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A stand with a sign over it and a prompt on it
local function stand(parent: Instance, name: string, position: Vector3, color: Color3, title: string, action: string, triggered: (Player) -> ())
	local base = slab(parent, name, Vector3.new(10, 8, 10), CFrame.new(position + Vector3.new(0, 4, 0)), color, Enum.Material.SmoothPlastic)
	local roof = slab(parent, name .. "Roof", Vector3.new(13, 1, 13), CFrame.new(position + Vector3.new(0, 14, 0)), color:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.SmoothPlastic)
	for _, corner in { Vector3.new(-6, 0, -6), Vector3.new(6, 0, -6), Vector3.new(-6, 0, 6), Vector3.new(6, 0, 6) } do
		slab(parent, name .. "Post", Vector3.new(1, 10, 1), CFrame.new(position + corner + Vector3.new(0, 9, 0)), Color3.fromRGB(90, 70, 50), Enum.Material.Wood)
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 56)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
	gui.MaxDistance = 200
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = title
	label.Parent = gui
	gui.Parent = roof
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	actions[prompt] = triggered
end

-- `onSell(player)` and `onShop(player)` run when a prompt is used
function TownService.init(onSell: (Player) -> (), onShop: (Player) -> ())
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		local action = actions[prompt]
		if action then
			action(player)
		end
	end)
	local folder = Instance.new("Folder")
	folder.Name = "Town"
	folder.Parent = workspace
	slab(folder, "Ground", Vector3.new(Layout.HUB, CELL, Layout.HUB), CFrame.new(0, -CELL / 2, 0), Color3.fromRGB(150, 150, 158), Enum.Material.Cobblestone)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = folder
	stand(folder, "SellStand", Vector3.new(-20, 0, -20), Color3.fromRGB(70, 170, 90), "SELL GEMS", "Sell all gems", onSell)
	stand(folder, "ShopStand", Vector3.new(20, 0, -20), Color3.fromRGB(230, 150, 50), "SHOP", "Open shop", onShop)
	-- roads to the plots
	local roadStart = Layout.HUB / 2
	for i = 1, Game.MAX_PLAYERS do
		local center = Layout.plotCenter(i)
		local direction = center.Unit
		local plotEdge = Layout.PLOT / 2
		local from = direction * roadStart
		local to = direction * (center.Magnitude - plotEdge)
		local mid = (from + to) / 2
		slab(folder, "Road", Vector3.new(14, CELL, (to - from).Magnitude), CFrame.lookAt(mid + Vector3.new(0, -CELL / 2, 0), to + Vector3.new(0, -CELL / 2, 0)), Color3.fromRGB(176, 150, 110), Enum.Material.Sand)
	end
end

return TownService
