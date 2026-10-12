--!strict
-- Creatures in the hotbar, as in Steal an Egg: a hatched creature isn't set down by itself, it goes into the
-- player's inventory (a tool each). Held, it's carried up over their head; used in their own garden it's set
-- down in the pasture. To sell one they carry it to the Sell pad in the square, or sell it from the Sell stall
-- (SellService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mutations = require(Shared.Config.Mutations)
local SnapConfig = require(Shared.Config.Snap)
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)
local Layout = require(Shared.Logic.Layout)
local PetModel = require(Shared.PetModel)

local DataService = require(script.Parent.DataService)
local HeistService = require(script.Parent.HeistService)
local IslandService = require(script.Parent.IslandService)

type Data = DataService.Data
type Creature = DataService.Creature

local CarryService = {}

local HEAD_TOP = 2.7 -- (as Shared/Carry: over the head)

-- The creature a player has in their hands now (its tool equipped)
type Held = { id: string, model: Model }
local held: { [Player]: Held } = {}

local function rootOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function title(creature: Creature): string
	local mutation = if creature.m ~= "Normal" then creature.m .. " " else ""
	local grade = if creature.g then creature.g .. " " else ""
	return grade .. mutation .. creature.s
end

local function build(creature: Creature): PetModel.Built
	local grade = if creature.g then SnapConfig.byId[creature.g] else nil
	local built = PetModel.build({ s = creature.s, v = creature.m, z = if grade then grade.size else "Normal" })
	for _, p in built.parts do
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
	end
	return built
end

---------------------------------------------------------------------------------------------------------------
-- In the hands

local function letGo(player: Player)
	local holding = held[player]
	if holding then
		held[player] = nil
		holding.model:Destroy()
		if player:GetAttribute("WildEgg") ~= true and not HeistService.isCarrier(player) then -- (an egg went up instead)
			player:SetAttribute("Holding", nil)
		end
		player:SetAttribute("CarryCreature", nil)
	end
end

local function lift(player: Player, id: string)
	letGo(player)
	local data = DataService.get(player)
	local root = rootOf(player)
	local creature = data and data.creatures[id]
	if not root or not creature or not player.Character then
		return
	end
	if player:GetAttribute("WildEgg") == true or HeistService.isCarrier(player) then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools() -- (their hands are full with an egg)
		end
		return
	end
	local built = build(creature)
	PetModel.place(built, root.CFrame * CFrame.new(0, HEAD_TOP + 0.15 + built.height / 2, 0))
	for _, p in built.parts do
		p.Anchored = false
		if p ~= built.body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = built.body, p
			weld.Parent = p
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Name = "InHands"
	weld.Part0, weld.Part1 = root, built.body
	weld.Parent = built.body
	built.model.Name = "CarriedCreature"
	built.model.Parent = player.Character
	held[player] = { id = id, model = built.model }
	player:SetAttribute("Holding", true) -- (EggHands raises their arms to it)
	player:SetAttribute("CarryCreature", id)
end

---------------------------------------------------------------------------------------------------------------
-- Selling, at the pad

local function onPad(player: Player): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	local flat = Vector3.new(root.CFrame.Position.X - Layout.SELL_SPOT.X, 0, root.CFrame.Position.Z - Layout.SELL_SPOT.Z)
	return flat.Magnitude <= Layout.SELL_RADIUS + 4
end

local function sell(player: Player)
	local holding = held[player]
	local data = DataService.get(player)
	if not holding or not data then
		return
	end
	local creature = data.creatures[holding.id]
	if not creature or table.find(data.placed, holding.id) then
		return
	end
	local price = Earn.sellPrice(creature)
	letGo(player)
	data.creatures[holding.id] = nil
	data.coins += price
	IslandService.fx("Steal", Layout.SELL_SPOT + Vector3.new(0, 3, 0), Color3.fromRGB(255, 210, 70))
	IslandService.push(player)
end

local function use(player: Player, id: string)
	local root = rootOf(player)
	if not root then
		return
	end
	if Layout.gardenAt(root.CFrame.Position) == IslandService.islandOf(player) then
		IslandService.place(player, id)
	elseif onPad(player) then
		sell(player)
	end
end

---------------------------------------------------------------------------------------------------------------
-- The tools

local function tools(player: Player, data: Data)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local have: { [string]: Tool } = {}
	local holders: { Instance } = { backpack }
	if player.Character then
		table.insert(holders, player.Character)
	end
	for _, holder in holders do
		for _, tool in holder:GetChildren() do
			local id = tool:GetAttribute("CreatureId")
			if tool:IsA("Tool") and type(id) == "string" then
				have[id] = tool
			end
		end
	end
	-- In the order they came (their ids count up)
	local ids: { string } = {}
	for id in data.creatures do
		if not table.find(data.placed, id) then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	for _, id in ids do
		local creature = data.creatures[id]
		local tool = have[id]
		have[id] = nil
		if not tool then
			local created = Instance.new("Tool")
			created:SetAttribute("CreatureId", id)
			created.RequiresHandle = false
			created.CanBeDropped = false
			created.Equipped:Connect(function()
				lift(player, id)
			end)
			created.Unequipped:Connect(function()
				local holding = held[player]
				if holding and holding.id == id then
					letGo(player)
				end
			end)
			created.Activated:Connect(function()
				use(player, id)
			end)
			created.Parent = backpack
			tool = created
		end
		local t = tool :: Tool
		local mutation = Mutations.byId[creature.m]
		t.Name = title(creature)
		t.ToolTip = ("%s🪙 %s/s · set it down in your garden, or sell it at the Sell pad"):format(if mutation and mutation.id ~= "Normal" then mutation.id .. " · " else "", Format.abbrev(Earn.rate(creature)))
	end
	for id, leftover in have do
		local holding = held[player]
		if holding and holding.id == id then
			letGo(player)
		end
		leftover:Destroy()
	end
end

---------------------------------------------------------------------------------------------------------------

-- The Sell pad in the square
local function sellPad()
	local pad = Instance.new("Part")
	pad.Name = "SellPad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.4, Layout.SELL_RADIUS * 2, Layout.SELL_RADIUS * 2)
	pad.CFrame = CFrame.new(Layout.SELL_SPOT + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Color = Color3.fromRGB(255, 200, 60)
	pad.Material = Enum.Material.SmoothPlastic
	pad.Anchored = true
	pad.CanCollide = false
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(260, 90)
	sign.StudsOffset = Vector3.new(0, 7, 0)
	sign.AlwaysOnTop = false
	sign.MaxDistance = 160
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 225, 90)
	label.TextStrokeTransparency = 0.2
	label.Text = "💰 SELL"
	label.Parent = sign
	sign.Parent = pad
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Sell what you hold"
	prompt.ObjectText = "💰 Sell"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = Layout.SELL_RADIUS + 4
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	prompt.Triggered:Connect(sell)
	local world = workspace:FindFirstChild("World")
	pad.Parent = world or workspace
end

function CarryService.init()
	IslandService.toolsChanged = function(player, data)
		task.defer(tools, player, data)
	end
	sellPad()
	Players.PlayerRemoving:Connect(function(player)
		letGo(player)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			-- (a held creature's tool can go with a respawn: then it's out of their hands)
			for player, holding in held do
				if not holding.model.Parent or not player.Character or holding.model.Parent ~= player.Character then
					letGo(player)
				end
			end
		end
	end)
end

return CarryService
