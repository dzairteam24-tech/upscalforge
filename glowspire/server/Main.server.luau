--!strict
-- Week 0 server: the stage (a dark plaza, the tower's base, labelled bot towers so the place doesn't look empty),
-- and the check of every finished run: the server replays the tap times itself and only trusts its own result.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Stack = require(Shared.Config.Stack)
local StackSim = require(Shared.Logic.StackSim)

local H = Stack.LAYER_HEIGHT

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = workspace
	return p
end

-- The plaza and the tower's base (its top at y = 0)
part("Plaza", Vector3.new(160, 2, 160), CFrame.new(0, -3, 0), Color3.fromRGB(18, 18, 30))
local start = Stack.PRESETS[Stack.DEFAULT].start / 100
part("Base", Vector3.new(start, 2, start), CFrame.new(0, -1, 0), Color3.fromRGB(60, 60, 90), Enum.Material.Neon)
local spawn = Instance.new("SpawnLocation")
spawn.Size = Vector3.new(6, 1, 6)
spawn.CFrame = CFrame.new(0, -1.5, 22)
spawn.Anchored = true
spawn.Transparency = 1
spawn.CanCollide = false
spawn.Neutral = true
spawn.Parent = workspace

-- Teacher Echoes: still towers of glowing slabs round the plaza, clearly labelled as bots (never shown as players)
local ECHOES = { 14, 22, 31, 9, 41, 18, 27, 12 }
for i, layers in ECHOES do
	local angle = (i - 1) / #ECHOES * 2 * math.pi
	local at = Vector3.new(math.cos(angle) * 40, 0, math.sin(angle) * 40)
	for l = 1, layers do
		local size = math.max(1, start - l * 0.08)
		part("Echo", Vector3.new(size, H, size), CFrame.new(at + Vector3.new(0, (l - 0.5) * H, 0)), Color3.fromHSV((l * 0.025) % 1, 0.6, 0.55), Enum.Material.Neon)
	end
	local top = part("EchoTop", Vector3.new(0.5, 0.5, 0.5), CFrame.new(at + Vector3.new(0, layers * H + 0.5, 0)), Color3.new(1, 1, 1))
	top.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 34)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.MaxDistance = 200
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(200, 200, 230)
	label.Text = "Teacher Echo (bot) " .. layers
	label.Parent = gui
	gui.Parent = top
end

-- The best verified run of each player this session (Week 0: nothing is saved)
local best: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player)
	best[player] = nil
end)

Net.event("Finish").OnServerEvent:Connect(function(player: Player, presetKey: any, taps: any)
	if type(presetKey) ~= "string" or not Stack.PRESETS[presetKey] or type(taps) ~= "table" or #taps > Stack.MAX_TAPS then
		return
	end
	local clean = {}
	for i = 1, #taps do
		local t = taps[i]
		if type(t) ~= "number" or t ~= t or t < 0 or t > Stack.MAX_TAP_MS then
			return
		end
		clean[i] = math.floor(t)
	end
	local run = StackSim.replay(presetKey, clean)
	local tier = if run.layer >= Stack.TIERS[1].layers then StackSim.tier(run.layer) else nil
	best[player] = math.max(best[player] or 0, run.layer)
	print(("[Glowspire] %s preset %s: %d layers, %d perfects, %s"):format(player.Name, presetKey, run.layer, run.perfects, tier or "no Spire"))
	Net.event("Result"):FireClient(player, run.layer, run.perfects, tier, best[player])
end)
