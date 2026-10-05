-- Event window: what's running, time left, the bonus, your tokens and the event shop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local EventConfig = require(Shared.Config.Events)
local Items = require(Shared.Config.Items)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local EventPanel = {}

-- The running event (the server announces it, so a Studio test event shows too).
function EventPanel.current(): EventConfig.Event?
	local id = ReplicatedStorage:GetAttribute("EventId")
	return if type(id) == "string" and id ~= "" then EventConfig.byId[id] else nil
end

function EventPanel.tokens(): number
	local event = EventPanel.current()
	local data = Store.data
	local state = event and data and data.events and data.events[event.id]
	return if state then state.tokens else 0
end

local function offerText(offer: EventConfig.Offer): (string, string)
	if offer.title then
		local title = Cosmetics.titleById[offer.title]
		return "🏷️ Title: " .. (if title then title.text else offer.title), "Shows above your head"
	elseif offer.trail then
		local trail = Cosmetics.trailById[offer.trail]
		return "✨ " .. (if trail then trail.name else offer.trail), "A trail behind you"
	elseif offer.ride then
		local ride = Cosmetics.rideById[offer.ride]
		return "🛹 " .. (if ride then ride.name else offer.ride), "A ride (+25% speed, like every ride)"
	end
	local item = offer.itemId and Items.byId[offer.itemId]
	return (if item then (item.icon or "🎁") .. " " .. item.name else "?"), if item then item.description else ""
end

function EventPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Event", function()
		Windows.close("Event")
	end)
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	Theme.list(scroll, 8)
	scroll.Parent = content

	local function rebuild()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local event = EventPanel.current()
		local data = Store.data
		if not event or not data then
			local none = Theme.label({ Text = "No event right now. Check back soon!", Size = UDim2.new(1, -12, 0, 40), MaxTextSize = 18 })
			none.Parent = scroll
			return
		end
		local state = data.events and data.events[event.id] or { tokens = 0, bought = {} }
		local left = math.max(0, event.ends - workspace:GetServerTimeNow())
		local days = math.floor(left / 86400)
		local header = Theme.label({
			Text = ("%s %s · %s left · %s %s"):format(
				event.tokenIcon,
				event.name,
				if days > 0 then ("%dd %s"):format(days, Format.time(left % 86400)) else Format.time(left),
				event.tokenIcon,
				Format.abbrev(state.tokens)
			),
			Font = Theme.titleFont,
			TextColor3 = event.color,
			Size = UDim2.new(1, -12, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
			MaxTextSize = 20,
		})
		header.Parent = scroll
		local info = Theme.label({
			Text = ("Break sources to collect %s (vaults, Bigs and guardians give the most).%s"):format(
				event.token,
				if event.bonus then (" Bonus: %s x%g for everyone!"):format(event.bonus.stat, event.bonus.mult) else ""
			),
			Font = Enum.Font.Gotham,
			TextColor3 = Theme.muted,
			Size = UDim2.new(1, -12, 0, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
			MaxTextSize = 15,
		})
		info.Parent = scroll
		for i, offer in event.shop do
			local title, subtitle = offerText(offer)
			local owned = offer.once and state.bought[offer.id] == true
			local row = Theme.frame({ Size = UDim2.new(1, -12, 0, 60), BackgroundColor3 = Theme.card, LayoutOrder = 10 + i })
			Theme.corner(row, 10)
			local t = Theme.label({
				Text = title,
				Font = Theme.titleFont,
				Size = UDim2.new(0.68, 0, 0.5, 0),
				Position = UDim2.fromOffset(12, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 18,
			})
			t.Parent = row
			local st = Theme.label({
				Text = subtitle,
				Font = Enum.Font.Gotham,
				TextColor3 = Theme.muted,
				Size = UDim2.new(0.68, 0, 0.4, 0),
				Position = UDim2.new(0, 12, 0.52, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 14,
			})
			st.Parent = row
			local canBuy = not owned and state.tokens >= offer.price
			local b = Theme.button({
				Text = if owned then "Owned" else ("%s %s"):format(event.tokenIcon, Format.abbrev(offer.price)),
				Size = UDim2.new(0.28, 0, 1, -16),
				Position = UDim2.new(0.7, 0, 0, 8),
				BackgroundColor3 = if canBuy then Theme.green else Theme.card,
				MaxTextSize = 18,
			})
			b.Activated:Connect(function()
				if canBuy then
					Net.event("EventBuy"):FireServer(offer.id)
				end
			end)
			b.Parent = row
			row.Parent = scroll
		end
	end

	Store.DataChanged:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal("EventId"):Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	Windows.register("Event", window, rebuild)
end

return EventPanel
