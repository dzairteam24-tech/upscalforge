--!strict
-- The Fuse Machine's window (Config/Snap, Logic/Snap), as in Steal an Egg: three matching creatures fuse into one
-- that earns far more (three of a creature with the same mutation: a Mega; three Megas: a Rainbow). Each kind
-- the player has shows how many of three, with FUSE once there are enough. Over the machine in town, the player's
-- best: "2/3", or "READY!".

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local SnapConfig = require(Shared.Config.Snap)
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)
local Snap = require(Shared.Logic.Snap)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local FuseWindow = {}

type Kind = { id: string, creature: Snap.Creature, count: number, made: Snap.Creature? }

-- The player's creatures in kinds that could fuse (the same creature, mutation and grade; Rainbows don't fuse)
local function kinds(): { Kind }
	local data = Store.data
	if not data then
		return {}
	end
	local byKey: { [string]: Kind } = {}
	for id, creature in data.creatures do
		if Snap.next(creature.g) then
			local key = if creature.g then creature.s .. "|" .. creature.g else creature.s .. "|" .. creature.m
			local kind = byKey[key]
			if not kind then
				kind = { id = id, creature = creature, count = 0, made = nil }
				byKey[key] = kind
			end
			kind.count += 1
		end
	end
	local list = {}
	for _, kind in byKey do
		local _, made = Snap.find(data.creatures, data.placed, kind.id)
		kind.made = made
		table.insert(list, kind)
	end
	table.sort(list, function(a, b)
		if (a.made ~= nil) ~= (b.made ~= nil) then
			return a.made ~= nil
		end
		return Earn.rate(a.creature) > Earn.rate(b.creature)
	end)
	return list
end

-- The sign over the machine: this player's best progress
local function updateSign()
	local best = 0
	for _, kind in kinds() do
		best = math.max(best, kind.count)
	end
	for _, sign in CollectionService:GetTagged("FuseSign") do
		local status = sign:FindFirstChild("Status", true)
		if status and status:IsA("TextLabel") then
			status.Text = if best >= SnapConfig.NEED then "READY!" else ("%d/%d"):format(best, SnapConfig.NEED)
			status.TextColor3 = if best >= SnapConfig.NEED then Color3.fromRGB(110, 255, 110) else Color3.new(1, 1, 1)
		end
	end
end

function FuseWindow.mount(gui: Instance)
	local window, content = Theme.window(gui, "⚙️ Fuse Machine", Vector2.new(760, 600), Theme.blue)

	local function rebuild()
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		Theme.text(content, {
			Text = ("Fuse %d of the same creature into one that earns far more: %d matching make a Mega (×%d), %d Megas a Rainbow (×%d)"):format(SnapConfig.NEED, SnapConfig.NEED, SnapConfig.byId.Mega.mult, SnapConfig.NEED, SnapConfig.byId.Rainbow.mult),
			Size = UDim2.new(1, -8, 0, 44),
			TextColor3 = Theme.soft,
			TextWrapped = true,
			LayoutOrder = 0,
		})
		local list = kinds()
		if #list == 0 then
			Theme.bold(content, { Text = "No creatures to fuse yet", Size = UDim2.new(1, -8, 0, 60), LayoutOrder = 1, MaxText = 30 })
			return
		end
		local grid = Theme.grid(content, 1, 3, 230)
		for i, kind in list do
			local species = Creatures.byId[kind.creature.s]
			local rarity = if species then species.rarity else "Common"
			local card = Theme.card(grid, Theme.lighten(Theme.RARITY[rarity] or Theme.gray, 0.3), { LayoutOrder = i })
			local view = Theme.creatureView(card, { s = kind.creature.s, m = kind.creature.m })
			view.Size = UDim2.new(1, 0, 0, 100)
			view.Position = UDim2.fromOffset(0, 4)
			Theme.bold(card, { Text = Snap.name(kind.creature), Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 104), MaxText = 22 })
			local ready = kind.made ~= nil
			Theme.bold(card, {
				Text = if ready and kind.made then ("→ %s · 🪙 %s/s"):format(Snap.name(kind.made), Format.abbrev(Earn.rate(kind.made))) else ("%d/%d"):format(kind.count, SnapConfig.NEED),
				Size = UDim2.new(1, -12, 0, 40),
				Position = UDim2.fromOffset(6, 132),
				TextColor3 = if ready then Color3.fromRGB(110, 255, 110) else Color3.new(1, 1, 1),
				TextWrapped = true,
				MaxText = 22,
			})
			local fuse = Theme.button(card, if ready then "FUSE!" else ("%d/%d"):format(kind.count, SnapConfig.NEED), if ready then Theme.green else Theme.gray, function()
				if ready then
					Net.event("Snap"):FireServer(kind.id)
				end
			end)
			fuse.AnchorPoint = Vector2.new(0.5, 1)
			fuse.Position = UDim2.new(0.5, 0, 1, -8)
			fuse.Size = UDim2.new(1, -16, 0, 40)
		end
	end

	Windows.register("Fuse", window, rebuild)
	Store.Changed:Connect(function()
		updateSign()
		if window.Visible then
			rebuild()
		end
	end)
	CollectionService:GetInstanceAddedSignal("FuseSign"):Connect(updateSign)
	updateSign()
end

return FuseWindow
