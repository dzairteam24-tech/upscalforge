--!strict
-- Creatures in the hotbar, as in Steal an Egg: a hatched creature isn't set down by itself, it goes into the
-- player's inventory (a tool each, after the bat). Held, it's carried up over their head; used in their own
-- garden it's set down in the pasture. To sell one they carry it to the Sell pad in the square (the Safe Zone):
-- on the way anyone can knock it out of their hands with a bat (GearService) and grab it for themselves. Nobody
-- grabs it in time (or its owner leaves), it goes back to its owner's inventory.
--
-- A dropped creature stays in its owner's data until someone else grabs it, so leaving never loses it.

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
local DROP_TIME = 60 -- seconds a knocked-out creature waits on the ground before going home
local GRAB_RANGE = 10

-- The creature a player has in their hands now (its tool equipped)
type Held = { id: string, model: Model }
local held: { [Player]: Held } = {}
-- Creatures knocked out of their owner's hands, on the ground
type Dropped = { owner: Player, id: string, creature: Creature, model: Model, expires: number }
local dropped: { [string]: Dropped } = {} -- (by owner's UserId .. ":" .. id)

local function rootOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function key(owner: Player, id: string): string
	return owner.UserId .. ":" .. id
end

-- Whether one of the player's creatures is lying on the ground (not theirs to use until it's back)
function CarryService.isAway(player: Player, id: string): boolean
	return dropped[key(player, id)] ~= nil
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

-- Whether the player carries a creature where it can be knocked out of their hands (GearService): not in the
-- Safe Zone, not in their own garden
function CarryService.isCarrier(player: Player): boolean
	local root = rootOf(player)
	if not held[player] or not root then
		return false
	end
	return not Layout.inSafeZone(root.CFrame.Position) and Layout.gardenAt(root.CFrame.Position) ~= IslandService.islandOf(player)
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
		IslandService.notify(player, "Hold a creature from your inventory to sell it here", "info")
		return
	end
	local creature = data.creatures[holding.id]
	if not creature or table.find(data.placed, holding.id) or CarryService.isAway(player, holding.id) then
		return
	end
	local price = Earn.sellPrice(creature)
	letGo(player)
	data.creatures[holding.id] = nil
	data.coins += price
	IslandService.notify(player, ("Sold %s for 🪙 %s"):format(title(creature), Format.abbrev(price)), "success")
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
	else
		IslandService.notify(player, "Set it down in your garden, or sell it at the 💰 Sell pad in the square", "info")
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
		if not table.find(data.placed, id) and not CarryService.isAway(player, id) then
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
-- Knocked out of their hands, and grabbed

local function goHome(entry: Dropped)
	local k = key(entry.owner, entry.id)
	if dropped[k] ~= entry then
		return
	end
	dropped[k] = nil
	entry.model:Destroy()
	local data = DataService.get(entry.owner)
	if data and entry.owner.Parent then
		IslandService.notify(entry.owner, ("Your %s came back to your inventory"):format(entry.creature.s), "info")
		IslandService.push(entry.owner)
	end
end

local function grab(taker: Player, entry: Dropped)
	local k = key(entry.owner, entry.id)
	local root = rootOf(taker)
	if dropped[k] ~= entry or not root or (root.CFrame.Position - entry.model:GetPivot().Position).Magnitude > GRAB_RANGE + 4 then
		return
	end
	if taker == entry.owner then
		IslandService.notify(taker, ("Got your %s back! 🐾"):format(entry.creature.s), "success")
		goHome(entry)
		return
	end
	local ownerData = DataService.get(entry.owner)
	local takerData = DataService.get(taker)
	local creature = ownerData and ownerData.creatures[entry.id]
	if not ownerData or not takerData or not creature then
		goHome(entry)
		return
	end
	local count = 0
	for _ in takerData.creatures do
		count += 1
	end
	if count >= IslandService.storage(takerData) then
		IslandService.notify(taker, "Your storage is full: sell some creatures or grow your barn", "error")
		return
	end
	dropped[k] = nil
	entry.model:Destroy()
	ownerData.creatures[entry.id] = nil
	local at = table.find(ownerData.placed, entry.id)
	if at then
		table.remove(ownerData.placed, at)
	end
	local id = tostring(takerData.nextId)
	takerData.nextId += 1
	takerData.creatures[id] = { s = creature.s, m = creature.m, g = creature.g }
	IslandService.notify(taker, ("🐾 You stole %s's %s!"):format(entry.owner.DisplayName, title(creature)), "success")
	IslandService.notify(entry.owner, ("😱 %s stole your %s!"):format(taker.DisplayName, title(creature)), "error")
	IslandService.push(taker)
	IslandService.push(entry.owner)
	local tool = nil
	local backpack = taker:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:GetAttribute("CreatureId") == id then
				tool = child
			end
		end
	end
	local humanoid = taker.Character and taker.Character:FindFirstChildOfClass("Humanoid")
	if tool and tool:IsA("Tool") and humanoid then
		humanoid:EquipTool(tool) -- (straight into their hands: now they have to get it home)
	end
end

-- A bat knocked the creature out of the player's hands (GearService): it lies there, anyone can grab it
function CarryService.knock(player: Player)
	local holding = held[player]
	local root = rootOf(player)
	local data = DataService.get(player)
	local creature = holding and data and data.creatures[holding.id]
	if not holding or not root or not creature then
		return
	end
	local id = holding.id
	letGo(player)
	local built = build(creature)
	local at = Vector3.new(root.CFrame.Position.X, 0.3, root.CFrame.Position.Z)
	PetModel.place(built, CFrame.new(at) * root.CFrame.Rotation * CFrame.new(0, built.height / 2, 0))
	for _, p in built.parts do
		p.Anchored = true
	end
	built.model.Name = "DroppedCreature"
	local entry: Dropped = { owner = player, id = id, creature = { s = creature.s, m = creature.m, g = creature.g }, model = built.model, expires = os.clock() + DROP_TIME }
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = title(creature)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = GRAB_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = built.body
	prompt.Triggered:Connect(function(taker)
		grab(taker, entry)
	end)
	built.model.Parent = workspace
	dropped[key(player, id)] = entry
	IslandService.notify(player, ("💥 Your %s was knocked out of your hands! Grab it back!"):format(creature.s), "error")
	IslandService.push(player) -- (its tool goes away until it's back)
end

---------------------------------------------------------------------------------------------------------------

-- The Sell pad in the square, with the Safe Zone's sign
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
	label.Text = "💰 SELL\n🛡️ Safe Zone"
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
	-- (after the bat, which comes a moment later on each spawn: the creatures go after it in the hotbar)
	local function hasBat(player: Player): boolean
		local backpack = player:FindFirstChildOfClass("Backpack")
		return (backpack ~= nil and backpack:FindFirstChild("Bat") ~= nil) or (player.Character ~= nil and player.Character:FindFirstChild("Bat") ~= nil)
	end
	local function give(player: Player, data: Data, tries: number)
		if not player.Parent then
			return
		end
		if not hasBat(player) and tries < 10 then
			task.delay(0.3, give, player, data, tries + 1)
			return
		end
		tools(player, data)
	end
	IslandService.isAway = CarryService.isAway
	IslandService.toolsChanged = function(player, data)
		task.defer(give, player, data, 0)
	end
	sellPad()
	Players.PlayerRemoving:Connect(function(player)
		letGo(player)
		for _, entry in dropped do
			if entry.owner == player then
				goHome(entry)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, entry in dropped do
				if now >= entry.expires then
					goHome(entry)
				end
			end
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
