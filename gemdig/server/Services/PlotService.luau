--!strict
-- The plots: a platform for each player round the town, where their mine is. A player gets a free one when they
-- join; its sign carries their name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Layout = require(Shared.Logic.Layout)
local MineConfig = require(Shared.Config.Mine)

local PlotService = {}

local CELL = MineConfig.CELL
local GRASS = Color3.fromRGB(96, 168, 78)

local owners: { [number]: Player } = {} -- plot index -> player
local assigned: { [Player]: number } = {}
local signs: { [number]: TextLabel } = {}
local plotsFolder: Folder

local function slab(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(position)
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.Grass
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A plot: a frame of ground round the shaft (the first layer of the mine is cubes, the rest of the frame is
-- ground), and a sign
local function buildPlot(index: number)
	local folder = Instance.new("Folder")
	folder.Name = "Plot_" .. index
	folder.Parent = plotsFolder
	local center = Layout.plotCenter(index)
	local half = Layout.PLOT / 2
	local shaft = Layout.shaftSize()
	local ring = (Layout.PLOT - shaft) / 2
	local y = -CELL / 2
	-- (two long sides, then the two ends between them)
	slab(folder, "Ground", Vector3.new(Layout.PLOT, CELL, ring), center + Vector3.new(0, y, half - ring / 2), GRASS)
	slab(folder, "Ground", Vector3.new(Layout.PLOT, CELL, ring), center + Vector3.new(0, y, -half + ring / 2), GRASS)
	slab(folder, "Ground", Vector3.new(ring, CELL, shaft), center + Vector3.new(half - ring / 2, y, 0), GRASS)
	slab(folder, "Ground", Vector3.new(ring, CELL, shaft), center + Vector3.new(-half + ring / 2, y, 0), GRASS)
	-- the sign, on the side facing the town
	local spawn = Layout.plotSpawn(index)
	local post = slab(folder, "Sign", Vector3.new(0.6, 7, 0.6), Vector3.new(spawn.X, 3.5, spawn.Z) + (center - Vector3.new(spawn.X, 0, spawn.Z)).Unit * 3, Color3.fromRGB(110, 80, 50), Enum.Material.Wood)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 140
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 240, 180)
	label.TextStrokeTransparency = 0.3
	label.Text = "Free plot"
	label.Parent = gui
	gui.Parent = post
	signs[index] = label
end

function PlotService.index(player: Player): number?
	return assigned[player]
end

-- The player on this plot, if any
function PlotService.owner(index: number): Player?
	return owners[index]
end

function PlotService.assign(player: Player): number?
	if assigned[player] then
		return assigned[player]
	end
	for i = 1, Game.MAX_PLAYERS do
		if not owners[i] then
			owners[i] = player
			assigned[player] = i
			signs[i].Text = player.DisplayName .. "'s Mine"
			if typeof(player) == "Instance" then
				player:SetAttribute("Plot", i)
			end
			return i
		end
	end
	return nil
end

function PlotService.release(player: Player)
	local i = assigned[player]
	if i then
		owners[i] = nil
		assigned[player] = nil
		signs[i].Text = "Free plot"
	end
end

function PlotService.init()
	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace
	for i = 1, Game.MAX_PLAYERS do
		buildPlot(i)
	end
end

return PlotService
