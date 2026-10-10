--!strict
-- The Net Shop's window: which wild creatures the player can catch on the carpet (and what opens the others),
-- and nets for catching them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared.Config.Creatures)
local HuntConfig = require(Shared.Config.Hunt)
local Format = require(Shared.Logic.Format)
local Hatch = require(Shared.Logic.Hatch)
local Hunt = require(Shared.Logic.Hunt)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local TripsWindow = {}

-- The furthest egg tier the player has hatched (as IslandService.bestTier)
local function bestTier(data: { [string]: any }): number
	local best = 1
	for _, creature in data.creatures do
		local species = Creatures.byId[creature.s]
		if species and species.tier <= 10 and species.tier > best then
			best = species.tier
		end
	end
	return best
end

function TripsWindow.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "🥅 Net Shop", Vector2.new(520, 560))

	local function row(order: number, height: number): Frame
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, -8, 0, height)
		frame.BackgroundColor3 = Theme.card
		frame.LayoutOrder = order
		Theme.round(frame, 12)
		frame.Parent = content
		return frame
	end

	local function rebuild()
		for _, child in content:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local data = Store.data
		if not data then
			return
		end
		local best = bestTier(data)
		local how = row(1, 48)
		Theme.text(how, {
			Text = "🌿 Wild creatures walk down the red carpet in the street: walk up and catch one!",
			Size = UDim2.new(1, -20, 1, -8),
			Position = UDim2.fromOffset(10, 4),
			TextColor3 = Theme.soft,
		})
		for i, zone in HuntConfig.ZONES do
			local frame = row(1 + i, 40)
			local egg = Hatch.egg(zone.need)
			local open = Hunt.unlocked(zone, best)
			Theme.text(frame, {
				Text = if open then ("✅ %s creatures"):format(zone.name) else ("🔒 %s creatures · hatch a %s creature"):format(zone.name, if egg then egg.name else ""),
				Size = UDim2.new(1, -20, 1, -8),
				Position = UDim2.fromOffset(10, 4),
				TextColor3 = if open then Theme.ink else Theme.soft,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		for i, net in HuntConfig.NETS do
			local frame = row(10 + i, 56)
			Theme.text(frame, {
				Text = ("%s %s · green ×%.1f"):format(net.icon, net.name, net.mult),
				Size = UDim2.new(0.6, -10, 0, 26),
				Position = UDim2.fromOffset(10, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			Theme.text(frame, {
				Text = if net.share == 0 then "Free, always" else ("You have %d · one per try"):format(data.nets[net.id] or 0),
				Size = UDim2.new(0.6, -10, 0, 20),
				Position = UDim2.fromOffset(10, 30),
				TextColor3 = Theme.soft,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			if net.share > 0 then
				local price = Hunt.netPrice(net, best)
				local buy = Theme.button(frame, "🪙 " .. Format.abbrev(price), if Store.coins() >= price then Theme.green else Theme.soft, function()
					Net.event("BuyNet"):FireServer(net.id)
				end)
				buy.Size = UDim2.new(0.36, 0, 0, 40)
				buy.Position = UDim2.new(0.62, 0, 0, 8)
			end
		end
	end
	Windows.register("Trips", window, rebuild)
	Store.Changed:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
end

return TripsWindow
