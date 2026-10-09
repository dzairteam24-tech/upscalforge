-- Trading: pick a player, send a request, build offers, Ready (locked 3s after changes), then Confirm.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progress = require(Shared.Logic.Progress)
local Constants = require(Shared.Config.Constants)
local Cosmetics = require(Shared.Config.Cosmetics)
local PetMath = require(Shared.Logic.PetMath)
local TradeLogic = require(Shared.Logic.TradeLogic)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Notify = require(script.Parent.Notify)
local PetCard = require(script.Parent.PetCard)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local TradePanel = {}

local LOCAL = Players.LocalPlayer

local state: { [string]: any }? = nil
local stateReceivedAt = 0

-- A floating seat in a trade: a card with its name, in the seat's colors
local function seatCard(rideId: string, selected: boolean?): TextButton
	local ride = Cosmetics.rideById[rideId]
	local card = Instance.new("TextButton")
	card.Text = ""
	card.AutoButtonColor = true
	card.BackgroundColor3 = if selected then Color3.fromRGB(70, 90, 140) else Theme.card
	card.BorderSizePixel = 0
	Theme.corner(card, 10)
	Theme.stroke(card, if ride then ride.glow else Theme.muted, 3)
	local icon = Theme.label({
		Text = "🪑",
		Size = UDim2.new(1, 0, 0.55, 0),
		BackgroundTransparency = 1,
		MaxTextSize = 34,
	})
	icon.Parent = card
	local name = Theme.label({
		Text = if ride then ride.name else rideId,
		Size = UDim2.new(1, -6, 0.4, 0),
		Position = UDim2.new(0, 3, 0.56, 0),
		TextColor3 = if ride then ride.color else Theme.text,
		MaxTextSize = 14,
	})
	name.Parent = card
	return card
end

-- A traded item's card: a creature, or a seat ({ ride = id })
local function itemCard(item: { [string]: any }, selected: boolean?): TextButton
	if item.ride then
		return seatCard(item.ride, selected)
	end
	return PetCard.create(item :: any, { selected = selected })
end

local function itemTitle(item: { [string]: any }): string
	if item.ride then
		local ride = Cosmetics.rideById[item.ride]
		return "🪑 " .. (if ride then ride.name else item.ride)
	end
	return PetCard.title(item :: any)
end

local function scrollGrid(parent: Instance, props: { [string]: any }, cell: UDim2): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundColor3 = Theme.panel
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
	scroll.CanvasSize = UDim2.new()
	for k, v in props do
		(scroll :: any)[k] = v
	end
	Theme.corner(scroll, 10)
	Theme.padding(scroll, 6)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = cell
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	scroll.Parent = parent
	return scroll
end

function TradePanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Trade", function()
		if state then
			Net.event("TradeCancel"):FireServer()
		end
		Windows.close("Trade")
	end)

	-- Player list view ---------------------------------------------------------------------------------------
	local listView = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	listView.Parent = content
	local allowToggle = Theme.button({
		Text = "Trade requests: ON",
		Size = UDim2.new(0.5, 0, 0, 38),
		BackgroundColor3 = Theme.green,
		MaxTextSize = 18,
	})
	allowToggle.Parent = listView
	local playerList = Instance.new("ScrollingFrame")
	playerList.BackgroundTransparency = 1
	playerList.BorderSizePixel = 0
	playerList.Position = UDim2.fromOffset(0, 46)
	playerList.Size = UDim2.new(1, 0, 1, -46)
	playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	playerList.CanvasSize = UDim2.new()
	playerList.ScrollBarThickness = 6
	Theme.list(playerList, 6)
	playerList.Parent = listView

	-- Trade view ---------------------------------------------------------------------------------------------
	local tradeView = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false })
	tradeView.Parent = content
	local status = Theme.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
	})
	status.Parent = tradeView
	local mineLabel = Theme.label({ Text = "You give", Size = UDim2.new(0.49, 0, 0, 22), Position = UDim2.fromOffset(0, 30), MaxTextSize = 16 })
	mineLabel.Parent = tradeView
	local theirsLabel = Theme.label({
		Text = "You get",
		Size = UDim2.new(0.49, 0, 0, 22),
		Position = UDim2.new(0.51, 0, 0, 30),
		MaxTextSize = 16,
	})
	theirsLabel.Parent = tradeView
	local mineGrid = scrollGrid(tradeView, {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(0.49, 0, 0.42, -54),
	}, UDim2.fromOffset(72, 90))
	local theirsGrid = scrollGrid(tradeView, {
		Position = UDim2.new(0.51, 0, 0, 54),
		Size = UDim2.new(0.49, 0, 0.42, -54),
	}, UDim2.fromOffset(72, 90))
	local pickerLabel = Theme.label({
		Text = "Your creatures (tap to add or remove)",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0.42, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
	})
	pickerLabel.Parent = tradeView
	local picker = scrollGrid(tradeView, {
		Position = UDim2.new(0, 0, 0.42, 30),
		Size = UDim2.new(1, 0, 0.42, -30),
	}, UDim2.fromOffset(72, 90))
	local readyButton = Theme.button({
		Text = "Ready",
		Size = UDim2.new(0.48, 0, 0.12, 0),
		Position = UDim2.new(0, 0, 0.87, 0),
		BackgroundColor3 = Theme.green,
	})
	readyButton.Parent = tradeView
	local cancelButton = Theme.button({
		Text = "Cancel",
		Size = UDim2.new(0.48, 0, 0.12, 0),
		Position = UDim2.new(0.52, 0, 0.87, 0),
		BackgroundColor3 = Theme.red,
	})
	cancelButton.Parent = tradeView

	-- Confirm overlay
	local confirm = Theme.frame({
		BackgroundColor3 = Theme.bg,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 5,
		Active = true, -- blocks taps on the offer underneath while confirming
	})
	Theme.corner(confirm, 12)
	confirm.Parent = tradeView
	local summary = Theme.label({
		Text = "",
		Size = UDim2.new(1, -24, 0.7, 0),
		Position = UDim2.fromOffset(12, 12),
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 6,
		MaxTextSize = 20,
	})
	summary.Parent = confirm
	local confirmButton = Theme.button({
		Text = "Confirm trade",
		Size = UDim2.new(0.48, 0, 0.14, 0),
		Position = UDim2.new(0, 0, 0.84, 0),
		BackgroundColor3 = Theme.green,
		ZIndex = 6,
	})
	confirmButton.Parent = confirm
	local backButton = Theme.button({
		Text = "Cancel",
		Size = UDim2.new(0.48, 0, 0.14, 0),
		Position = UDim2.new(0.52, 0, 0.84, 0),
		BackgroundColor3 = Theme.red,
		ZIndex = 6,
	})
	backButton.Parent = confirm

	-- Incoming request popup
	local incoming = Theme.frame({
		Name = "TradeRequest",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(360, 110),
		BackgroundColor3 = Theme.bg,
		Visible = false,
	})
	Theme.corner(incoming, 14)
	Theme.stroke(incoming, Theme.purple, 3)
	incoming.Parent = gui
	local incomingText = Theme.label({ Text = "", Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(8, 6), MaxTextSize = 20 })
	incomingText.Parent = incoming
	local acceptButton = Theme.button({
		Text = "Accept",
		Size = UDim2.new(0.45, 0, 0, 44),
		Position = UDim2.new(0.03, 0, 0, 56),
		BackgroundColor3 = Theme.green,
	})
	acceptButton.Parent = incoming
	local declineButton = Theme.button({
		Text = "Decline",
		Size = UDim2.new(0.45, 0, 0, 44),
		Position = UDim2.new(0.52, 0, 0, 56),
		BackgroundColor3 = Theme.red,
	})
	declineButton.Parent = incoming
	local incomingFrom: number? = nil

	local function myOfferIds(): { string }
		local ids = {}
		if state then
			for petId in state.mine do
				table.insert(ids, petId)
			end
		end
		return ids
	end

	local function rebuildPlayers()
		Theme.clear(playerList)
		local data = Store.data
		local allow = data == nil or data.settings.allowTrades
		allowToggle.Text = if allow then "Trade requests: ON" else "Trade requests: OFF"
		allowToggle.BackgroundColor3 = if allow then Theme.green else Theme.card
		local others = 0
		for _, player in Players:GetPlayers() do
			if player ~= LOCAL then
				others += 1
				local row = Theme.frame({ Size = UDim2.new(1, -10, 0, 52), BackgroundColor3 = Theme.card })
				Theme.corner(row, 10)
				local name = Theme.label({
					Text = player.DisplayName,
					Size = UDim2.new(0.65, 0, 1, -8),
					Position = UDim2.fromOffset(12, 4),
					TextXAlignment = Enum.TextXAlignment.Left,
					MaxTextSize = 20,
				})
				name.Parent = row
				name.Size = UDim2.new(0.45, 0, 1, -8)
				local b = Theme.button({
					Text = "Trade",
					Size = UDim2.new(0.25, 0, 1, -12),
					Position = UDim2.new(0.73, 0, 0, 6),
					BackgroundColor3 = Theme.purple,
				})
				b.Activated:Connect(function()
					Net.event("TradeRequest"):FireServer(player.UserId)
				end)
				b.Parent = row
				-- Daily gift for friends (the server checks the friendship and the limits)
				local gifts = data and (data :: any).gifts
				local sentToday = gifts ~= nil and gifts.day == Progress.day(os.time()) and gifts.sent
				local gift = Theme.button({
					Text = if sentToday then "🎁 Sent" else "🎁 Gift",
					Size = UDim2.new(0.22, 0, 1, -12),
					Position = UDim2.new(0.49, 0, 0, 6),
					BackgroundColor3 = if sentToday then Theme.panel else Theme.gold,
					MaxTextSize = 16,
				})
				gift.Activated:Connect(function()
					if not sentToday then
						Net.event("SendGift"):FireServer(player.UserId)
					end
				end)
				gift.Parent = row
				row.Parent = playerList
			end
		end
		if others == 0 then
			local empty = Theme.label({ Text = "No other players in this server yet.", Size = UDim2.new(1, 0, 0, 40), MaxTextSize = 18 })
			empty.Parent = playerList
		end
	end

	local function rebuildTrade()
		local s = state
		listView.Visible = s == nil
		tradeView.Visible = s ~= nil
		if not s then
			return
		end
		Theme.clear(mineGrid)
		Theme.clear(theirsGrid)
		Theme.clear(picker)
		local mine = s.mine :: { [string]: any }
		for petId, pet in mine do
			local card = itemCard(pet)
			card.Activated:Connect(function()
				local ids = myOfferIds()
				table.remove(ids, table.find(ids, petId) :: number)
				Net.event("TradeOffer"):FireServer(ids)
			end)
			card.Parent = mineGrid
		end
		for _, pet in s.theirs :: { [string]: any } do
			itemCard(pet).Parent = theirsGrid
		end
		local data = Store.data
		if data then
			local ids = {}
			for petId, pet in data.pets do
				if not pet.lk then
					table.insert(ids, petId)
				end
			end
			for order, petId in PetMath.rankIds(data.pets, ids) do
				local card = PetCard.create(data.pets[petId], { selected = mine[petId] ~= nil })
				card.LayoutOrder = order
				card.Activated:Connect(function()
					local offer = myOfferIds()
					local index = table.find(offer, petId)
					if index then
						table.remove(offer, index)
					else
						table.insert(offer, petId)
					end
					Net.event("TradeOffer"):FireServer(offer)
				end)
				card.Parent = picker
			end
			-- Seats you can trade (not the free Cloud), after the creatures
			local order = 100000
			for _, ride in Cosmetics.rides do
				if ride.tradeable and data.rides and data.rides[ride.id] then
					local item = TradeLogic.rideItem(ride.id)
					local card = seatCard(ride.id, mine[item] ~= nil)
					order += 1
					card.LayoutOrder = order
					card.Activated:Connect(function()
						local offer = myOfferIds()
						local index = table.find(offer, item)
						if index then
							table.remove(offer, index)
						else
							table.insert(offer, item)
						end
						Net.event("TradeOffer"):FireServer(offer)
					end)
					card.Parent = picker
				end
			end
		end

		-- Totals for each side, and a warning when you give much rarer creatures than you get
		local function listOf(map: { [string]: any }): { any }
			local out = {}
			for _, pet in map do
				if not pet.ride then
					table.insert(out, pet)
				end
			end
			return out
		end
		local function seats(map: { [string]: any }): number
			local n = 0
			for _, item in map do
				if item.ride then
					n += 1
				end
			end
			return n
		end
		local function worthText(worth: TradeLogic.Worth): string
			local parts = { tostring(worth.count) }
			if worth.titans > 0 then
				table.insert(parts, "👑" .. worth.titans)
			end
			if worth.bigs > 0 then
				table.insert(parts, "⭐" .. worth.bigs)
			end
			if worth.rare > 0 then
				table.insert(parts, "💎" .. worth.rare)
			end
			return table.concat(parts, " · ")
		end
		local give = TradeLogic.worth(listOf(s.mine))
		local get = TradeLogic.worth(listOf(s.theirs))
		local unfair = TradeLogic.lopsided(give, get)
		local function seatText(n: number): string
			return if n > 0 then (" · 🪑" .. n) else ""
		end
		mineLabel.Text = "You give: " .. worthText(give) .. seatText(seats(s.mine))
		theirsLabel.Text = "You get: " .. worthText(get) .. seatText(seats(s.theirs))
		mineLabel.TextColor3 = if unfair then Theme.red else Theme.text

		local function names(list: { [string]: any }): string
			local out = {}
			for _, pet in list do
				table.insert(out, itemTitle(pet))
			end
			return if #out == 0 then "nothing" else table.concat(out, ", ")
		end
		confirm.Visible = s.stage == "Confirm"
		summary.Text = ("Trading with %s\n\nYou GIVE: %s\n\nYou GET: %s\n\n%s"):format(
			s.otherName,
			names(s.mine),
			names(s.theirs),
			if unfair
				then "⚠️ You're giving much rarer creatures than you get. Trades can't be undone!"
				else "Check carefully. Trades can't be undone."
		)
		confirmButton.Text = if s.myConfirmed then "Waiting..." else "Confirm trade"
	end

	-- Live status and Ready countdown
	RunService.Heartbeat:Connect(function()
		local s = state
		if not s then
			return
		end
		local left = math.max(0, s.lockLeft - (os.clock() - stateReceivedAt))
		local theirs = if s.theirReady then "✅ ready" else "choosing..."
		status.Text = ("Trading with %s · they are %s"):format(s.otherName, theirs)
		if s.myReady then
			readyButton.Text = "Waiting..."
			readyButton.BackgroundColor3 = Theme.card
		elseif left > 0 then
			readyButton.Text = ("Ready (%d)"):format(math.ceil(left))
			readyButton.BackgroundColor3 = Theme.card
		else
			readyButton.Text = "Ready"
			readyButton.BackgroundColor3 = Theme.green
		end
	end)

	allowToggle.Activated:Connect(function()
		local data = Store.data
		if data then
			Net.event("SetSetting"):FireServer("allowTrades", not data.settings.allowTrades)
		end
	end)
	readyButton.Activated:Connect(function()
		Net.event("TradeReady"):FireServer()
	end)
	cancelButton.Activated:Connect(function()
		Net.event("TradeCancel"):FireServer()
	end)
	backButton.Activated:Connect(function()
		Net.event("TradeCancel"):FireServer()
	end)
	confirmButton.Activated:Connect(function()
		Net.event("TradeConfirm"):FireServer()
	end)
	acceptButton.Activated:Connect(function()
		if incomingFrom then
			Net.event("TradeRespond"):FireServer(incomingFrom, true)
		end
		incoming.Visible = false
		incomingFrom = nil
	end)
	declineButton.Activated:Connect(function()
		if incomingFrom then
			Net.event("TradeRespond"):FireServer(incomingFrom, false)
		end
		incoming.Visible = false
		incomingFrom = nil
	end)

	Net.event("TradeIncoming").OnClientEvent:Connect(function(fromUserId: number, fromName: string)
		incomingFrom = fromUserId
		incomingText.Text = fromName .. " wants to trade with you"
		incoming.Visible = true
		task.delay(Constants.TRADE_REQUEST_TIMEOUT, function()
			if incomingFrom == fromUserId then
				incoming.Visible = false
				incomingFrom = nil
			end
		end)
	end)
	Net.event("TradeState").OnClientEvent:Connect(function(newState)
		state = newState
		stateReceivedAt = os.clock()
		if not Windows.isOpen("Trade") then
			Windows.open("Trade")
		end
		rebuildTrade()
	end)
	Net.event("TradeClosed").OnClientEvent:Connect(function(reason: string)
		state = nil
		Notify.show(reason, if reason == "Trade complete" then "success" else "info")
		rebuildTrade()
		rebuildPlayers()
	end)

	Players.PlayerAdded:Connect(rebuildPlayers)
	Players.PlayerRemoving:Connect(function()
		task.defer(rebuildPlayers)
	end)
	Store.DataChanged:Connect(function()
		if window.Visible then
			if state then
				rebuildTrade()
			else
				rebuildPlayers()
			end
		end
	end)
	Windows.register("Trade", window, function()
		rebuildPlayers()
		rebuildTrade()
	end)
end

return TradePanel
