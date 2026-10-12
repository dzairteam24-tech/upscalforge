--!strict
-- Creatures in the hotbar, as in Steal an Egg: a hatched creature isn't set down by itself, it goes into the
-- player's inventory (a tool each) unless it's kept in the barn. Held, it's carried up over their head as a ball
-- (Shared/Ball) in its rarity's color (it can't be stolen: StealService); used in their own garden it's set down in
-- the pasture. They sell creatures at the Shop (ShopService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mutations = require(Shared.Config.Mutations)
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)
local Layout = require(Shared.Logic.Layout)
local Ball = require(Shared.Ball)

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
	local grade = (if creature.g then creature.g .. " " else "") .. (if creature.w then creature.w .. " " else "")
	return grade .. mutation .. creature.s
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
	local model, body = Ball.build(creature.s, root.CFrame * CFrame.new(0, HEAD_TOP + 0.2 + Ball.SIZE / 2, 0), false)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "InHands"
	weld.Part0, weld.Part1 = root, body
	weld.Parent = body
	model.Name = "CarriedCreature"
	model.Parent = player.Character
	held[player] = { id = id, model = model }
	player:SetAttribute("Holding", true) -- (EggHands raises their arms to it)
	player:SetAttribute("CarryCreature", id)
end

---------------------------------------------------------------------------------------------------------------
-- Using a creature: in their own garden it's set down in the pasture (selling is at the Shop: ShopService)

local function use(player: Player, id: string)
	local root = rootOf(player)
	if not root then
		return
	end
	if Layout.gardenAt(root.CFrame.Position) == IslandService.islandOf(player) then
		IslandService.place(player, id)
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
		if not table.find(data.placed, id) and not data.stored[id] then
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
		t.ToolTip = ("%s🪙 %s/s · set it down in your garden"):format(if mutation and mutation.id ~= "Normal" then mutation.id .. " · " else "", Format.abbrev(Earn.rate(creature)))
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

function CarryService.init()
	IslandService.toolsChanged = function(player, data)
		task.defer(tools, player, data)
	end
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
