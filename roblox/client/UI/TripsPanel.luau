-- Trips (expeditions): pick creatures that aren't on the team, send them away, claim what they bring back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Expeditions = require(Shared.Config.Expeditions)
local Items = require(Shared.Config.Items)
local Variants = require(Shared.Config.Variants)
local Expedition = require(Shared.Logic.Expedition)
local Format = require(Shared.Logic.Format)
local PetMath = require(Shared.Logic.PetMath)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local AdButton = require(script.Parent.AdButton)
local PetCard = require(script.Parent.PetCard)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local TripsPanel = {}

local chosenKind: string? = nil
local picked: { string } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- True when a trip is back and waiting to be claimed (for the menu dot).
function TripsPanel.hasReady(): boolean
	local data = Store.data
	if not data or not data.expeditions then
		return false
	end
	local t = now()
	for _, trip in data.expeditions do
		if t >= trip.ends then
			return true
		end
	end
	return false
end

local function rewardText(kind: Expeditions.ExpeditionKind): string
	local parts = { "🪙 Coins" }
	if kind.elixirs > 0 then
		table.insert(parts, ("🧪 %d elixir%s %s–%s"):format(
			kind.elixirs,
			if kind.elixirs > 1 then "s" else "",
			Items.ROMAN[kind.elixirTiers[1]],
			Items.ROMAN[kind.elixirTiers[2]]
		))
	end
	if kind.cartridgeChance > 0 then
		table.insert(parts, ("🃏 %d%% Boost Card %s–%s"):format(
			math.floor(kind.cartridgeChance * 100),
			Items.ROMAN[kind.cartridgeTiers[1]],
			Items.ROMAN[kind.cartridgeTiers[2]]
		))
	end
	if #kind.keyHalves > 0 then
		table.insert(parts, "🗝️ key halves")
	end
	if kind.stickerChance > 0 then
		table.insert(parts, ("⭐ %d%% sticker"):format(math.floor(kind.stickerChance * 100)))
	end
	if kind.gadgetChance > 0 then
		table.insert(parts, ("💣 %d%% gadget"):format(math.floor(kind.gadgetChance * 100)))
	end
	if kind.gemsPerZone > 0 then
		table.insert(parts, "💎 gems")
	end
	return table.concat(parts, " · ")
end

-- Creatures that can travel: not on the team and not already away.
local function available(data: { [string]: any }): { string }
	local ids = {}
	for petId, pet in data.pets do
		if not pet.ex and not table.find(data.equipped, petId) then
			table.insert(ids, petId)
		end
	end
	return PetMath.rankIds(data.pets, ids)
end

-- Strongest pick, or a same-element group when the +50% makes it better.
local function autoPick(data: { [string]: any }, count: number): { string }
	local ranked = available(data)
	local best: { string } = {}
	local bestScore = 0
	for i = 1, math.min(count, #ranked) do
		table.insert(best, ranked[i])
		bestScore += PetMath.basePower(data.pets[ranked[i]])
	end
	if #best < count then
		return best
	end
	local groups: { [string]: { string } } = {}
	for _, petId in ranked do
		local pet = data.pets[petId]
		local variant = Variants.byId[pet.v]
		if variant and variant.strongIn then
			groups[pet.v] = groups[pet.v] or {}
			table.insert(groups[pet.v], petId)
		end
	end
	for _, group in groups do
		if #group >= count then
			local score = 0
			for i = 1, count do
				score += PetMath.basePower(data.pets[group[i]])
			end
			score *= Expeditions.ELEMENT_BONUS
			if score > bestScore then
				bestScore = score
				best = table.move(group, 1, count, 1, {})
			end
		end
	end
	return best
end

function TripsPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Trips", function()
		Windows.close("Trips")
	end)

	-- Left: active trips and trip kinds
	local left = Instance.new("ScrollingFrame")
	left.BackgroundTransparency = 1
	left.BorderSizePixel = 0
	left.Size = UDim2.new(0.42, 0, 1, 0)
	left.ScrollBarThickness = 6
	left.AutomaticCanvasSize = Enum.AutomaticSize.Y
	left.CanvasSize = UDim2.new()
	Theme.list(left, 8)
	left.Parent = content

	-- Right: creature picker
	local right = Theme.frame({ Position = UDim2.new(0.44, 0, 0, 0), Size = UDim2.new(0.56, 0, 1, 0) })
	Theme.corner(right, 12)
	right.Parent = content
	local pickTitle = Theme.label({
		Text = "",
		Font = Theme.titleFont,
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
	})
	pickTitle.Parent = right
	local pickScroll = Instance.new("ScrollingFrame")
	pickScroll.BackgroundTransparency = 1
	pickScroll.BorderSizePixel = 0
	pickScroll.Position = UDim2.fromOffset(8, 40)
	pickScroll.Size = UDim2.new(1, -16, 1, -130)
	pickScroll.ScrollBarThickness = 6
	pickScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pickScroll.CanvasSize = UDim2.new()
	local pickGrid = Instance.new("UIGridLayout")
	pickGrid.CellSize = UDim2.fromOffset(84, 104)
	pickGrid.CellPadding = UDim2.fromOffset(6, 6)
	pickGrid.SortOrder = Enum.SortOrder.LayoutOrder
	pickGrid.Parent = pickScroll
	pickScroll.Parent = right
	local preview = Theme.label({
		Text = "",
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.muted,
		Position = UDim2.new(0, 8, 1, -86),
		Size = UDim2.new(1, -16, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
	})
	preview.Parent = right
	local autoButton = Theme.button({
		Text = "Auto pick",
		Position = UDim2.new(0, 8, 1, -50),
		Size = UDim2.new(0.4, -12, 0, 42),
		BackgroundColor3 = Theme.card,
		MaxTextSize = 18,
	})
	autoButton.Parent = right
	local sendButton = Theme.button({
		Text = "Send",
		Position = UDim2.new(0.4, 4, 1, -50),
		Size = UDim2.new(0.6, -12, 0, 42),
		BackgroundColor3 = Theme.green,
		MaxTextSize = 20,
	})
	sendButton.Parent = right

	local timers: { { label: TextLabel, claim: TextButton, double: TextButton, skip: TextButton, ends: number } } = {}

	local function updateTimers()
		local t = now()
		for _, timer in timers do
			local ready = t >= timer.ends
			timer.label.Text = if ready then "✅ Back home!" else "⏳ " .. Format.time(timer.ends - t)
			timer.claim.Visible = ready
			timer.double.Visible = ready and AdButton.offer("AdTripDouble", "TripDouble") ~= nil
			timer.skip.Visible = not ready and AdButton.offer("AdTripSkip", "TripSkip") ~= nil
			timer.double.Text = AdButton.label("AdTripDouble", "TripDouble", "x2")
			timer.skip.Text = AdButton.label("AdTripSkip", "TripSkip", "Finish now")
		end
	end

	local rebuild: () -> ()

	local function buildPicker(data: { [string]: any })
		Theme.clear(pickScroll)
		local kind = if chosenKind then Expeditions.byId[chosenKind] else nil
		right.Visible = kind ~= nil
		if not kind then
			return
		end
		-- Drop picks that can't travel any more
		local can = {}
		for _, petId in available(data) do
			can[petId] = true
		end
		local kept = {}
		for _, petId in picked do
			if can[petId] and #kept < kind.pets then
				table.insert(kept, petId)
			end
		end
		picked = kept

		pickTitle.Text = ("%s: pick %d creatures"):format(kind.name, kind.pets)
		local ids = available(data)
		for order, petId in ids do
			local pet = data.pets[petId]
			local card = PetCard.create(pet, { selected = table.find(picked, petId) ~= nil })
			card.LayoutOrder = order
			card.Activated:Connect(function()
				local index = table.find(picked, petId)
				if index then
					table.remove(picked, index)
				elseif #picked < kind.pets then
					table.insert(picked, petId)
				end
				rebuild()
			end)
			card.Parent = pickScroll
		end
		if #ids == 0 then
			local empty = Theme.label({
				Text = "Every creature is on your team or away. Hatch more, or unequip some.",
				Size = UDim2.new(1, 0, 0, 60),
				MaxTextSize = 16,
			})
			empty.Parent = pickScroll
		end

		local power = 0
		local pets = {}
		for _, petId in picked do
			power += PetMath.basePower(data.pets[petId])
			table.insert(pets, data.pets[petId])
		end
		local same = #picked == kind.pets and Expedition.sharedElement(pets)
		local coins = power * kind.duration * kind.coinFactor * (if same then Expeditions.ELEMENT_BONUS else 1) * (data.reloadMult or 1)
		preview.Text = ("≈ 🪙 %s%s"):format(Format.abbrev(coins), if same then (" · Same element +%d%%!"):format(math.floor((Expeditions.ELEMENT_BONUS - 1) * 100 + 0.5)) else "")
		preview.TextColor3 = if same then Theme.gold else Theme.muted
		sendButton.Text = ("Send (%d/%d)"):format(#picked, kind.pets)
		sendButton.BackgroundColor3 = if #picked == kind.pets then Theme.green else Theme.card
	end

	local function buildList(data: { [string]: any })
		Theme.clear(left)
		timers = {}
		local trips = data.expeditions or {}
		local slots: number = data.expeditionSlots or Expeditions.BASE_SLOTS
		local order = 0
		local function heading(text: string)
			order += 1
			local h = Theme.label({
				Text = text,
				Font = Theme.titleFont,
				Size = UDim2.new(1, -8, 0, 26),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = order,
				MaxTextSize = 20,
			})
			h.Parent = left
		end

		heading(("Away (%d/%d)"):format(#trips, slots))
		for index, trip in trips do
			local kind = Expeditions.byId[trip.kind]
			if not kind then
				continue
			end
			order += 1
			local card = Theme.frame({ Size = UDim2.new(1, -8, 0, 64), BackgroundColor3 = Theme.card, LayoutOrder = order })
			Theme.corner(card, 10)
			Theme.stroke(card, kind.color, 2)
			local name = Theme.label({
				Text = ("%s · %d creatures%s"):format(kind.name, #trip.pets, if trip.element then (" · +%d%%"):format(math.floor((Expeditions.ELEMENT_BONUS - 1) * 100 + 0.5)) else ""),
				Position = UDim2.fromOffset(10, 6),
				Size = UDim2.new(0.62, -10, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 16,
			})
			name.Parent = card
			local timeLabel = Theme.label({
				Text = "",
				TextColor3 = Theme.muted,
				Position = UDim2.fromOffset(10, 34),
				Size = UDim2.new(0.62, -10, 0, 22),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 15,
			})
			timeLabel.Parent = card
			local claim = Theme.button({
				Text = "Claim",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.new(0.2, 0, 0, 42),
				BackgroundColor3 = Theme.gold,
				Visible = false,
				MaxTextSize = 18,
			})
			claim.Parent = card
			claim.Activated:Connect(function()
				Net.event("ClaimExpedition"):FireServer(index, trip.started)
			end)
			local double = Theme.button({
				Text = "▶ x2",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(0.8, -14, 0.5, 0),
				Size = UDim2.new(0.16, 0, 0, 42),
				BackgroundColor3 = Theme.purple,
				Visible = false,
				MaxTextSize = 18,
			})
			double.Parent = card
			double.Activated:Connect(function()
				AdButton.take("AdTripDouble", "TripDouble", trip.started)
			end)
			local skip = Theme.button({
				Text = "▶ Finish now",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.new(0.34, 0, 0, 42),
				BackgroundColor3 = Theme.purple,
				Visible = false,
				MaxTextSize = 16,
			})
			skip.Parent = card
			skip.Activated:Connect(function()
				AdButton.take("AdTripSkip", "TripSkip", trip.started)
			end)
			card.Parent = left
			table.insert(timers, { label = timeLabel, claim = claim, double = double, skip = skip, ends = trip.ends })
		end
		if #trips == 0 then
			order += 1
			local none = Theme.label({
				Text = "No creatures away. Old and weak creatures still bring back loot!",
				Font = Enum.Font.Gotham,
				TextColor3 = Theme.muted,
				Size = UDim2.new(1, -8, 0, 40),
				LayoutOrder = order,
				MaxTextSize = 15,
			})
			none.Parent = left
		end

		heading("New trip")
		for _, kind in Expeditions.list do
			order += 1
			local chosen = kind.id == chosenKind
			local card = Instance.new("TextButton")
			card.Text = ""
			card.AutoButtonColor = true
			card.BackgroundColor3 = if chosen then Color3.fromRGB(70, 90, 140) else Theme.card
			card.BorderSizePixel = 0
			card.Size = UDim2.new(1, -8, 0, 78)
			card.LayoutOrder = order
			Theme.corner(card, 10)
			Theme.stroke(card, kind.color, 2)
			local name = Theme.label({
				Text = ("%s · %s · %d creatures"):format(kind.name, Format.time(kind.duration), kind.pets),
				Position = UDim2.fromOffset(10, 6),
				Size = UDim2.new(1, -20, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = kind.color,
				MaxTextSize = 17,
			})
			name.Parent = card
			local rewards = Theme.label({
				Text = rewardText(kind),
				Font = Enum.Font.Gotham,
				TextColor3 = Theme.muted,
				Position = UDim2.fromOffset(10, 32),
				Size = UDim2.new(1, -20, 0, 38),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				MaxTextSize = 14,
			})
			rewards.Parent = card
			card.Activated:Connect(function()
				if chosenKind ~= kind.id then
					chosenKind = kind.id
					picked = {}
				end
				rebuild()
			end)
			card.Parent = left
		end
	end

	rebuild = function()
		local data = Store.data
		if not data then
			return
		end
		buildList(data)
		buildPicker(data)
		updateTimers()
	end

	autoButton.Activated:Connect(function()
		local data = Store.data
		local kind = if chosenKind then Expeditions.byId[chosenKind] else nil
		if data and kind then
			picked = autoPick(data, kind.pets)
			rebuild()
		end
	end)
	sendButton.Activated:Connect(function()
		local kind = if chosenKind then Expeditions.byId[chosenKind] else nil
		if kind and #picked == kind.pets then
			Net.event("StartExpedition"):FireServer(kind.id, picked)
			picked = {}
		end
	end)

	Store.DataChanged:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if window.Visible then
				updateTimers()
			end
		end
	end)
	Windows.register("Trips", window, rebuild)
end

return TripsPanel
