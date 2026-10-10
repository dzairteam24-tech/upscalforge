--!strict
-- The bat (Config/Gear, Logic/Gear): every player holds one (a tool), upgraded with coins at the Gear Shop.
-- Swinging it at a player who carries an egg (from the Wild, a raid or the Heist) counts a hit; enough hits in a
-- row knock the egg out of their hands (fewer with a better bat than theirs). Nobody carrying nothing is
-- touched, nor a new player, nor anyone in a Peaceful private server.
--
-- Traps (bought there too) are set down in the Wild; a player carrying an egg who steps on someone else's is
-- stuck for a moment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearConfig = require(Shared.Config.Gear)
local RaidConfig = require(Shared.Config.Raid)
local WildConfig = require(Shared.Config.Wild)
local Format = require(Shared.Logic.Format)
local Gear = require(Shared.Logic.Gear)
local Layout = require(Shared.Logic.Layout)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local HeistService = require(script.Parent.HeistService)
local IslandService = require(script.Parent.IslandService)
local RaidService = require(script.Parent.RaidService)
local WildService = require(script.Parent.WildService)

local GearService = {}

local PEACEFUL = game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0
local KNOCKED_GUARD = 4 -- seconds after being knocked (or picking an egg back up) before it counts again

type Combo = { hits: number, last: number }
local combos: { [Player]: Combo } = {} -- per target: the hits so far (each worth 1 / hits needed)
local lastSwing: { [Player]: number } = {}
local guardUntil: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function carrying(player: Player): boolean
	return player:GetAttribute("WildEgg") == true or RaidService.isCarrying(player) or HeistService.isCarrier(player)
end

local function knock(target: Player)
	if RaidService.isCarrying(target) then
		RaidService.knock(target)
	elseif HeistService.isCarrier(target) then
		HeistService.knock(target)
		IslandService.notify(target, "💥 Knocked out of your hands!", "error")
	else
		WildService.knock(target)
	end
	guardUntil[target] = os.clock() + KNOCKED_GUARD
end

local function swing(player: Player)
	local now = os.clock()
	if PEACEFUL or now - (lastSwing[player] or 0) < GearConfig.COOLDOWN then
		return
	end
	lastSwing[player] = now
	local data = DataService.get(player)
	local root = rootOf(player)
	if not data or not root then
		return
	end
	-- The nearest egg carrier in front of them
	local best: Player? = nil
	local bestDistance = GearConfig.RANGE
	for _, other in Players:GetPlayers() do
		local otherRoot = rootOf(other)
		if other ~= player and otherRoot and carrying(other) then
			local offset = otherRoot.Position - root.Position
			local distance = offset.Magnitude
			if distance <= bestDistance and (distance < 3 or root.CFrame.LookVector:Dot(offset.Unit) > 0.2) then
				best, bestDistance = other, distance
			end
		end
	end
	local target = best
	local targetData = if target then DataService.get(target) else nil
	if not target or not targetData then
		return
	end
	if os.time() - targetData.firstPlayed < RaidConfig.NEW_PLAYER_SAFE then
		IslandService.notify(player, ("%s is new here: leave them be"):format(target.DisplayName), "error")
		return
	end
	if now < (guardUntil[target] or 0) then
		return
	end
	local existing = combos[target]
	local combo: Combo = if existing and now - existing.last <= GearConfig.COMBO then existing else { hits = 0, last = now }
	combos[target] = combo
	local needed = Gear.hitsNeeded(data.bat, targetData.bat)
	combo.hits += 1 / needed
	combo.last = now
	local targetRoot = rootOf(target)
	if targetRoot then
		Net.event("Bump"):FireAllClients(targetRoot.Position, "Normal")
	end
	if combo.hits >= 0.999 then
		combos[target] = nil
		knock(target)
		IslandService.notify(player, ("💥 You knocked the egg out of %s's hands! Grab it!"):format(target.DisplayName), "success")
	else
		IslandService.notify(player, ("💥 Hit! %d / %d"):format(math.floor(combo.hits * needed + 0.5), needed), "info")
	end
end

-- Gives the player their bat (a fresh one, after an upgrade or a respawn)
local function giveBat(player: Player)
	local data = DataService.get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not backpack then
		return
	end
	local holders: { Instance } = { backpack }
	if player.Character then
		table.insert(holders, player.Character)
	end
	for _, holder in holders do
		local old = holder:FindFirstChild("Bat")
		if old then
			old:Destroy()
		end
	end
	local bat = Gear.bat(data.bat)
	local tool = Instance.new("Tool")
	tool.Name = "Bat"
	tool.ToolTip = bat.name
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -1.2, 0)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 3.6, 0.5)
	handle.Color = bat.color
	handle.Material = bat.material
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Cylinder
	head.Size = Vector3.new(1.6, 0.9, 0.9)
	head.Color = bat.color
	head.Material = bat.material
	head.CanCollide = false
	head.Massless = true
	head.CFrame = handle.CFrame * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90))
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = handle, head
	weld.Parent = head
	head.Parent = tool
	tool.Activated:Connect(function()
		-- (the default Animate script plays its slash for a "toolanim" value)
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash"
		anim.Parent = tool
		game:GetService("Debris"):AddItem(anim, 0.5)
		swing(player)
	end)
	tool.Parent = backpack
end

---------------------------------------------------------------------------------------------------------------
-- Traps

type Trap = { owner: Player, part: Part, expires: number }
local traps: { Trap } = {}

local function trapsSetBy(player: Player): number
	local count = 0
	for _, trap in traps do
		count += if trap.owner == player then 1 else 0
	end
	return count
end

local giveTraps: (Player) -> ()

local function setTrap(player: Player)
	local data = DataService.get(player)
	local root = rootOf(player)
	if not data or not root or data.traps <= 0 then
		return
	end
	if not Layout.biomeAt(root.Position, #WildConfig.BIOMES) then
		IslandService.notify(player, "Traps go down in the Wild", "error")
		return
	end
	if trapsSetBy(player) >= GearConfig.TRAP_MAX_SET then
		IslandService.notify(player, ("You can only have %d traps down at once"):format(GearConfig.TRAP_MAX_SET), "error")
		return
	end
	data.traps -= 1
	local part = Instance.new("Part")
	part.Name = "Trap"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.3, 4, 4)
	part.CFrame = CFrame.new(root.Position.X, 0.45, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = Color3.fromRGB(120, 110, 100)
	part.Material = Enum.Material.Metal
	part.Transparency = 0.35 -- (easy to miss when running)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Parent = workspace
	table.insert(traps, { owner = player, part = part, expires = os.clock() + GearConfig.TRAP_TIME })
	IslandService.notify(player, ("🪤 Trap set! (%d left)"):format(data.traps), "success")
	giveTraps(player)
	IslandService.push(player)
end

-- The traps tool, while the player has some
function giveTraps(player: Player)
	local data = DataService.get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not backpack then
		return
	end
	local tool = backpack:FindFirstChild("Traps") or (player.Character and player.Character:FindFirstChild("Traps"))
	if data.traps <= 0 then
		if tool then
			tool:Destroy()
		end
		return
	end
	if not tool then
		local created = Instance.new("Tool")
		created.Name = "Traps"
		created.RequiresHandle = false
		created.CanBeDropped = false
		created.Activated:Connect(function()
			setTrap(player)
		end)
		created.Parent = backpack
		tool = created
	end
	if tool and tool:IsA("Tool") then
		tool.ToolTip = ("🪤 Trap ×%d: set it down in the Wild"):format(data.traps)
	end
end

local function buyTrap(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	if data.traps >= GearConfig.TRAP_MAX_HELD then
		IslandService.notify(player, ("You can carry %d traps at most"):format(GearConfig.TRAP_MAX_HELD), "error")
		return
	end
	if data.coins < GearConfig.TRAP_PRICE then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(GearConfig.TRAP_PRICE)), "error")
		return
	end
	data.coins -= GearConfig.TRAP_PRICE
	data.traps += 1
	giveTraps(player)
	IslandService.notify(player, ("🪤 Bought a trap (%d)"):format(data.traps), "success")
	IslandService.push(player)
end

-- Ten times a second: traps catch egg carriers stepping on them, and old ones go
local function checkTraps()
	local now = os.clock()
	for i = #traps, 1, -1 do
		local trap = traps[i]
		local sprung = false
		if not PEACEFUL then
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				local data = DataService.get(player)
				if player ~= trap.owner and root and data and carrying(player) and os.time() - data.firstPlayed >= RaidConfig.NEW_PLAYER_SAFE then
					local flat = Vector3.new(root.Position.X - trap.part.Position.X, 0, root.Position.Z - trap.part.Position.Z)
					if flat.Magnitude <= GearConfig.TRAP_RANGE then
						WildService.stick(player, GearConfig.TRAP_STUCK)
						Net.event("Bump"):FireAllClients(root.Position, "Trap")
						IslandService.notify(player, ("🪤 %s's trap got you!"):format(trap.owner.DisplayName), "error")
						if trap.owner.Parent then
							IslandService.notify(trap.owner, ("🪤 Your trap caught %s!"):format(player.DisplayName), "success")
						end
						sprung = true
						break
					end
				end
			end
		end
		if sprung or now >= trap.expires or not trap.owner.Parent then
			trap.part:Destroy()
			table.remove(traps, i)
		end
	end
end

local function upgradeBat(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local price = Gear.upgradePrice(data.bat)
	if not price then
		IslandService.notify(player, "You have the best bat", "error")
		return
	end
	if data.coins < price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(price)), "error")
		return
	end
	data.coins -= price
	data.bat += 1
	giveBat(player)
	IslandService.notify(player, ("New bat: %s! 🏏"):format(Gear.bat(data.bat).name), "success")
	IslandService.push(player)
end

function GearService.init()
	Net.event("UpgradeBat").OnServerEvent:Connect(upgradeBat)
	Net.event("BuyTrap").OnServerEvent:Connect(buyTrap)
	DataService.onLoaded(function(player)
		giveBat(player)
		giveTraps(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			giveBat(player)
			giveTraps(player)
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			checkTraps()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		combos[player] = nil
		lastSwing[player] = nil
		guardUntil[player] = nil
	end)
end

return GearService
