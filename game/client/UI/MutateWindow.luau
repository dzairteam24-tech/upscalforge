--!strict
-- The Mutation Machine's window (Config/Mutate, Logic/Mutate). Locked until the player has enough speed (⚡): it
-- says how much more. Open, each creature (best first) with the mutation it would get next and the price. Over
-- the machine in town: 🔒 and the ⚡ it opens at, or OPEN.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local MutateConfig = require(Shared.Config.Mutate)
local Mutations = require(Shared.Config.Mutations)
local Earn = require(Shared.Logic.Earn)
local Format = require(Shared.Logic.Format)
local Mutate = require(Shared.Logic.Mutate)
local Snap = require(Shared.Logic.Snap)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local MutateWindow = {}

local LOCAL = Players.LocalPlayer

local function power(): number
	local value = LOCAL:GetAttribute("Speed")
	return if type(value) == "number" then value else 0
end

local function updateSign()
	local open = Mutate.open(power())
	for _, sign in CollectionService:GetTagged("MutateSign") do
		local status = sign:FindFirstChild("Status", true)
		if status and status:IsA("TextLabel") then
			status.Text = if open then "OPEN" else "🔒 Unlocks at ⚡ " .. Format.abbrev(MutateConfig.UNLOCK)
			status.TextColor3 = if open then Color3.fromRGB(110, 255, 110) else Color3.fromRGB(255, 120, 110)
		end
	end
end

function MutateWindow.mount(gui: Instance)
	local window, content = Theme.window(gui, "🧪 Mutation Machine", Vector2.new(760, 600), Color3.fromRGB(70, 200, 90))

	local function rebuild()
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local data = Store.data
		if not Mutate.open(power()) then
			local locked = Theme.card(content, Color3.fromRGB(50, 50, 65), { Size = UDim2.new(1, -8, 0, 200), LayoutOrder = 1 })
			Theme.text(locked, { Text = "🔒", Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 10) })
			Theme.bold(locked, { Text = "Locked", Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 92), MaxText = 36 })
			Theme.bold(locked, {
				Text = ("Unlocks at ⚡ %s speed (you have %s)"):format(Format.abbrev(MutateConfig.UNLOCK), Format.abbrev(math.floor(power()))),
				Size = UDim2.new(1, -16, 0, 30),
				Position = UDim2.fromOffset(8, 140),
				Font = Theme.font,
				TextColor3 = Color3.fromRGB(200, 200, 215),
				MaxText = 24,
			})
			return
		end
		Theme.text(content, { Text = "Raise a creature's mutation one step: Normal → Golden → Crystal → Lava → Neon", Size = UDim2.new(1, -8, 0, 24), TextColor3 = Theme.soft, LayoutOrder = 0 })
		if not data then
			return
		end
		local list = {}
		for id, creature in data.creatures do
			if Mutate.next(creature.m) then
				table.insert(list, { id = id, creature = creature })
			end
		end
		table.sort(list, function(a, b)
			return Earn.rate(a.creature) > Earn.rate(b.creature)
		end)
		local grid = Theme.grid(content, 1, 3, 230)
		for i, entry in list do
			local creature = entry.creature
			local nextMutation = Mutate.next(creature.m) :: string
			local species = Creatures.byId[creature.s]
			local card = Theme.card(grid, Theme.lighten(Theme.RARITY[if species then species.rarity else "Common"] or Theme.gray, 0.3), { LayoutOrder = i })
			local view = Theme.creatureView(card, { s = creature.s, m = creature.m })
			view.Size = UDim2.new(1, 0, 0, 96)
			view.Position = UDim2.fromOffset(0, 4)
			Theme.bold(card, { Text = Snap.name(creature), Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 100), MaxText = 22 })
			Theme.bold(card, { Text = "→ " .. nextMutation, Size = UDim2.new(1, -12, 0, 30), Position = UDim2.fromOffset(6, 128), TextColor3 = Mutations.byId[nextMutation].color, MaxText = 26 })
			local price = Mutate.price(creature)
			local mutate = Theme.button(card, "🪙 " .. Format.abbrev(price), if Store.coins() >= price then Theme.green else Theme.gray, function()
				Net.event("Mutate"):FireServer(entry.id)
			end)
			mutate.AnchorPoint = Vector2.new(0.5, 1)
			mutate.Position = UDim2.new(0.5, 0, 1, -8)
			mutate.Size = UDim2.new(1, -16, 0, 44)
		end
	end

	Windows.register("Mutate", window, rebuild)
	Store.Changed:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	LOCAL:GetAttributeChangedSignal("Speed"):Connect(updateSign)
	CollectionService:GetInstanceAddedSignal("MutateSign"):Connect(updateSign)
	updateSign()
end

return MutateWindow
