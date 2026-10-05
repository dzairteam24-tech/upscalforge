-- Global leaderboards on boards in the Hub: strongest team, most coins, most Titans, highest Rank.
-- Uses OrderedDataStores. Huge numbers are stored as log10 so they fit in an integer key.
-- In Studio without API access the boards show a short note instead.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Logic.Achievements)
local Effects = require(Shared.Logic.Effects)
local Format = require(Shared.Logic.Format)
local MapLayout = require(Shared.Logic.MapLayout)
local PetMath = require(Shared.Logic.PetMath)
local Types = require(Shared.Logic.Types)

local DataService = require(script.Parent.DataService)
local State = require(script.Parent.State)

type PlayerData = Types.PlayerData

local LeaderboardService = {}

type Board = {
	id: string,
	title: string,
	color: Color3,
	log: boolean, -- store log10 of the value (for numbers that grow without limit)
	value: (data: PlayerData) -> number,
	format: (value: number) -> string,
}

local BOARDS: { Board } = {
	{
		id = "Power",
		title = "⚡ Strongest Team",
		color = Color3.fromRGB(255, 140, 90),
		log = true,
		value = function(data)
			return (PetMath.teamPower(data.pets, data.equipped, "Neutral", Effects.collect(data.pets, data.equipped)))
		end,
		format = function(v)
			return Format.abbrev(v) .. "/s"
		end,
	},
	{
		id = "Coins",
		title = "🪙 Most Coins",
		color = Color3.fromRGB(245, 197, 66),
		log = true,
		value = function(data)
			return data.stats.boardCoins or data.stats.coinsEarned or 0
		end,
		format = Format.abbrev,
	},
	{
		id = "Titans",
		title = "👑 Most Titans",
		color = Color3.fromRGB(255, 120, 200),
		log = false,
		value = function(data)
			return data.stats.titans or 0
		end,
		format = function(v)
			return tostring(math.floor(v))
		end,
	},
	{
		id = "Rank",
		title = "⭐ Highest Rank",
		color = Color3.fromRGB(255, 225, 120),
		log = false,
		value = function(data)
			return Achievements.stars(data.achievements)
		end,
		format = function(v)
			return ("Rank %d"):format(Achievements.rank(v))
		end,
	},
}

local ROWS = 10
local WRITE_INTERVAL = 120
local READ_INTERVAL = 120
local LOG_SCALE = 1e6

local stores: { [string]: OrderedDataStore } = {}
local available = true
local labels: { [string]: { TextLabel } } = {}
local status: { [string]: TextLabel } = {}
local names: { [number]: string } = {}

local function encode(board: Board, value: number): number
	if board.log then
		return math.floor(math.log10(math.max(1, value)) * LOG_SCALE)
	end
	return math.floor(value)
end

local function decode(board: Board, stored: number): number
	return if board.log then 10 ^ (stored / LOG_SCALE) else stored
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else "Player"
	names[userId] = result
	return result
end

local function buildBoard(board: Board, position: Vector3, folder: Folder)
	local panel = Instance.new("Part")
	panel.Name = "Leaderboard_" .. board.id
	panel.Anchored = true
	panel.Size = Vector3.new(24, 20, 1)
	panel.CFrame = CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
	panel.Color = Color3.fromRGB(36, 44, 68)
	panel.Material = Enum.Material.SmoothPlastic
	local frame = Instance.new("Part")
	frame.Name = "Frame"
	frame.Anchored = true
	frame.Size = Vector3.new(25, 21, 0.8)
	frame.CFrame = panel.CFrame * CFrame.new(0, 0, 0.3)
	frame.Color = board.color
	frame.Parent = panel
	for _, x in { -10, 10 } do
		local leg = Instance.new("Part")
		leg.Anchored = true
		leg.Size = Vector3.new(1.2, position.Y, 1.2)
		leg.CFrame = CFrame.new(position.X + x, position.Y / 2, position.Z + 0.5)
		leg.Color = Color3.fromRGB(60, 64, 80)
		leg.Parent = panel
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.13, 0)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = board.color
	title.Text = board.title
	title.Parent = gui
	local rows = {}
	for i = 1, ROWS do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = if i % 2 == 0 then 1 else 0.85
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.BorderSizePixel = 0
		row.Position = UDim2.new(0.03, 0, 0.14 + (i - 1) * 0.078, 0)
		row.Size = UDim2.new(0.94, 0, 0.074, 0)
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i == 1
			then Color3.fromRGB(255, 215, 90)
			elseif i == 2 then Color3.fromRGB(220, 225, 235)
			elseif i == 3 then Color3.fromRGB(230, 160, 100)
			else Color3.fromRGB(238, 241, 247)
		row.Text = ""
		row.Parent = gui
		table.insert(rows, row)
	end
	local note = Instance.new("TextLabel")
	note.BackgroundTransparency = 1
	note.Position = UDim2.new(0, 0, 0.93, 0)
	note.Size = UDim2.new(1, 0, 0.06, 0)
	note.Font = Enum.Font.Gotham
	note.TextScaled = true
	note.TextColor3 = Color3.fromRGB(169, 179, 201)
	note.Text = "Loading..."
	note.Parent = gui
	gui.Parent = panel
	panel.Parent = folder
	labels[board.id] = rows
	status[board.id] = note
end

local function showUnavailable()
	for _, board in BOARDS do
		status[board.id].Text = "Leaderboards turn on when the game is published"
	end
end

local function writeAll()
	for player in State.all() do
		local data = DataService.get(player)
		if not data then
			continue
		end
		for _, board in BOARDS do
			local value = encode(board, board.value(data))
			if value > 0 then
				local ok, err = pcall(function()
					stores[board.id]:SetAsync(tostring(player.UserId), value)
				end)
				if not ok then
					warn("[Leaderboard] write failed", board.id, err)
				end
			end
		end
	end
end

local function readAll()
	for _, board in BOARDS do
		local ok, pages = pcall(function()
			return stores[board.id]:GetSortedAsync(false, ROWS)
		end)
		if not ok then
			status[board.id].Text = "Couldn't load right now"
			continue
		end
		local entries = (pages :: DataStorePages):GetCurrentPage()
		for i, row in labels[board.id] do
			local entry = entries[i]
			if entry then
				local userId = tonumber(entry.key) or 0
				row.Text = ("  #%d  %s   %s"):format(i, nameOf(userId), board.format(decode(board, entry.value)))
			else
				row.Text = ""
			end
		end
		status[board.id].Text = "Updates every 2 minutes"
	end
end

function LeaderboardService.init()
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	local center = MapLayout.center(0)
	for i, board in BOARDS do
		local x = (i - (#BOARDS + 1) / 2) * 28
		buildBoard(board, center + Vector3.new(x, 13, 55), folder)
	end
	folder.Parent = workspace

	for _, board in BOARDS do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore("Leaderboard_" .. board.id)
		end)
		if not ok then
			available = false
			break
		end
		stores[board.id] = store
	end
	if not available then
		showUnavailable()
		return
	end

	task.spawn(function()
		task.wait(15)
		local lastWrite, lastRead = -math.huge, -math.huge
		while true do
			local now = os.clock()
			if now - lastWrite >= WRITE_INTERVAL then
				lastWrite = now
				writeAll()
			end
			if now - lastRead >= READ_INTERVAL then
				lastRead = now
				local ok = pcall(readAll)
				if not ok then
					showUnavailable()
				end
			end
			task.wait(5)
		end
	end)
end

return LeaderboardService
