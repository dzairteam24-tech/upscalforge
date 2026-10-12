--!strict
-- The hatch reveal: the screen dims, light rays turn in the rarity's color behind the new creature in 3D,
-- with its name, rarity, mutation and what it earns. A tap (or a few seconds) closes it; hatches that come
-- together are shown one after another.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local EggSizes = require(Shared.Config.EggSizes)
local Mutations = require(Shared.Config.Mutations)
local SnapConfig = require(Shared.Config.Snap)
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)

local Effects = require(script.Parent.Parent.Effects)
local Theme = require(script.Parent.Theme)

local Reveal = {}

local SHOW_FOR = 4

type Item = { species: string, mutation: string, grade: string?, size: string? }
local queue: { Item } = {}
local holder: Frame? = nil
local busy = false

local function present(item: Item)
	local root = holder
	if not root then
		return
	end
	local species = Creatures.byId[item.species]
	local rarity = if species then species.rarity else "Common"
	local color = Theme.RARITY[rarity] or Theme.gray
	local mutation = Mutations.byId[item.mutation] or Mutations.byId.Normal
	local grade = if item.grade then SnapConfig.byId[item.grade] else nil
	local size = if item.size then EggSizes.byId[item.size] else nil -- (from a small, big or huge egg)
	local sizeName = if size and size.id ~= "Normal" then size.id else nil

	local screen = Instance.new("TextButton") -- (a tap anywhere closes it)
	screen.Name = "Reveal"
	screen.Text = ""
	screen.AutoButtonColor = false
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = Color3.new(0, 0, 0)
	screen.BackgroundTransparency = 1
	screen.ZIndex = 20
	TweenService:Create(screen, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()

	-- The rays, turning
	local rays = Instance.new("Frame")
	rays.BackgroundTransparency = 1
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.45)
	rays.Size = UDim2.fromOffset(10, 10)
	rays.ZIndex = 21
	for i = 1, 9 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromOffset(900, 46)
		ray.Rotation = i * 20
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = color
		ray.ZIndex = 21
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
		ray.Parent = rays
	end
	rays.Parent = screen
	TweenService:Create(rays, TweenInfo.new(SHOW_FOR + 1, Enum.EasingStyle.Linear), { Rotation = 120 }):Play()

	-- The creature
	local card = Instance.new("Frame")
	card.BackgroundTransparency = 1
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.47)
	card.Size = UDim2.fromOffset(420, 430)
	card.ZIndex = 22
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = card
	local title = Theme.bold(card, { Text = if grade then "FUSED!" elseif sizeName == "Huge" then "⭐ HUGE HATCH!" elseif sizeName == "Big" then "BIG HATCH!" else "HATCHED!", Size = UDim2.new(1, 0, 0, 56), TextColor3 = Theme.gold, MaxText = 52 })
	title.ZIndex = 23
	local view = Theme.creatureView(card, { s = item.species, m = item.mutation, size = if grade then grade.size elseif size then size.creature else nil })
	view.Size = UDim2.fromOffset(300, 240)
	view.Position = UDim2.fromOffset(60, 56)
	view.ZIndex = 23
	local name = Theme.bold(card, { Text = (if grade then grade.id .. " " else "") .. (if sizeName then sizeName .. " " else "") .. item.species, Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 296), MaxText = 46 })
	name.ZIndex = 23
	local line = rarity
	if mutation.id ~= "Normal" then
		line = mutation.id .. " · " .. rarity
	end
	local tag = Theme.bold(card, { Text = line, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 346), TextColor3 = if mutation.id ~= "Normal" then mutation.color else color, MaxText = 32 })
	tag.ZIndex = 23
	local rate = Earn.rate({ s = item.species, m = item.mutation, g = item.grade, w = item.size } :: any)
	local earns = Theme.bold(card, { Text = ("🪙 %s / second"):format(Format.abbrev(rate)), Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 384), TextColor3 = Color3.fromRGB(255, 230, 120), MaxText = 28 })
	earns.ZIndex = 23
	card.Parent = screen
	screen.Parent = root
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Effects.sound("Hatch")
	task.delay(0.2, Effects.sound, "Chime")
	if sizeName == "Huge" or sizeName == "Big" then
		task.delay(0.4, Effects.sound, "Rare") -- (a bigger fanfare for a bigger creature)
	end

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0 }):Play()
		TweenService:Create(screen, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		task.wait(0.25)
		screen:Destroy()
	end
	screen.Activated:Connect(function()
		task.spawn(close)
	end)
	local started = os.clock()
	while not closed and os.clock() - started < SHOW_FOR do
		task.wait(0.1)
	end
	close()
end

local function run()
	if busy then
		return
	end
	busy = true
	while #queue > 0 do
		present(table.remove(queue, 1) :: Item)
	end
	busy = false
end

-- A new creature to show: its species and mutation, its snap grade (Mega, Rainbow) when it was snapped, and the
-- size of the egg it hatched from (Config/EggSizes)
function Reveal.show(species: string, mutation: string, grade: string?, size: string?)
	table.insert(queue, { species = species, mutation = mutation, grade = grade, size = size })
	task.spawn(run)
end

function Reveal.mount(gui: Instance)
	holder = gui :: Frame
end

return Reveal
