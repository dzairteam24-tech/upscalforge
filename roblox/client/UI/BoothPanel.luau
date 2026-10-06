-- Trading Plaza booth window.
--   Your booth: put creatures up for sale (price in gems) or take them down, close the booth.
--   Someone else's booth: see what's for sale and buy.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Format = require(Shared.Logic.Format)
local PetMath = require(Shared.Logic.PetMath)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local PetCard = require(script.Parent.PetCard)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local BoothPanel = {}

local LOCAL = Players.LocalPlayer
local currentBooth: number? = nil
local pickedPet: string? = nil

local function boothPart(id: number): BasePart?
	for _, part in CollectionService:GetTagged("Booth") do
		if part:IsA("BasePart") and part:GetAttribute("BoothId") == id then
			return part
		end
	end
	return nil
end

local function listingsOf(part: BasePart): { { [string]: any } }
	local raw = part:GetAttribute("Listings")
	if type(raw) ~= "string" or raw == "" then
		return {}
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return if ok and type(decoded) == "table" then decoded else {}
end

-- Called by the world when a booth's prompt is used.
function BoothPanel.use(id: number)
	local part = boothPart(id)
	if not part then
		return
	end
	local owner = part:GetAttribute("Owner")
	if owner == 0 or owner == nil then
		Net.event("BoothClaim"):FireServer(id)
		return
	end
	currentBooth = id
	pickedPet = nil
	Windows.open("Booth")
end

local function grid(parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = position
	scroll.Size = size
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(92, 128)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	scroll.Parent = parent
	return scroll
end

-- A creature card with a price strip and a button under it.
local function saleCard(pet: { [string]: any }, price: number?, button: string?, color: Color3?, onPress: (() -> ())?): Frame
	local holder = Theme.frame({ BackgroundTransparency = 1 })
	local card = PetCard.create(pet :: any, { showPower = price == nil })
	card.Size = UDim2.new(1, 0, 0, 96)
	card.Parent = holder
	if price then
		local tag = Theme.label({
			Text = "💎 " .. Format.abbrev(price),
			TextColor3 = Color3.fromRGB(120, 220, 255),
			Position = UDim2.fromOffset(0, 72),
			Size = UDim2.new(1, 0, 0, 22),
			MaxTextSize = 15,
		})
		tag.Parent = card
	end
	if button then
		local b = Theme.button({
			Text = button,
			Position = UDim2.fromOffset(0, 100),
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = color or Theme.green,
			MaxTextSize = 14,
		})
		b.Parent = holder
		b.Activated:Connect(function()
			if onPress then
				onPress()
			end
		end)
	elseif onPress then
		card.Activated:Connect(onPress)
	end
	return holder
end

function BoothPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Booth", function()
		Windows.close("Booth")
	end)

	local header = Theme.label({
		Text = "",
		Font = Theme.titleFont,
		Size = UDim2.new(1, -150, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
	})
	header.Parent = content
	local closeBooth = Theme.button({
		Text = "Close booth",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(140, 32),
		BackgroundColor3 = Theme.red,
		MaxTextSize = 16,
	})
	closeBooth.Parent = content
	closeBooth.Activated:Connect(function()
		Net.event("BoothRelease"):FireServer()
		Windows.close("Booth")
	end)

	local forSale = grid(content, UDim2.fromOffset(0, 40), UDim2.new(1, 0, 0.45, -40))
	local mineTitle = Theme.label({
		Text = "Your creatures (tap one to sell it)",
		Font = Theme.titleFont,
		Position = UDim2.new(0, 0, 0.45, 4),
		Size = UDim2.new(0.62, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 17,
	})
	mineTitle.Parent = content
	local mine = grid(content, UDim2.new(0, 0, 0.45, 34), UDim2.new(0.62, 0, 0.55, -34))

	-- Price editor for the picked creature
	local editor = Theme.frame({ Position = UDim2.new(0.64, 0, 0.45, 4), Size = UDim2.new(0.36, 0, 0.55, -4) })
	Theme.corner(editor, 12)
	editor.Parent = content
	local editorTitle = Theme.label({
		Text = "",
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.fromOffset(6, 6),
		MaxTextSize = 16,
	})
	editorTitle.Parent = editor
	local priceBox = Instance.new("TextBox")
	priceBox.PlaceholderText = "Price in gems"
	priceBox.Text = ""
	priceBox.ClearTextOnFocus = false
	priceBox.Font = Theme.font
	priceBox.TextScaled = true
	priceBox.TextColor3 = Theme.text
	priceBox.BackgroundColor3 = Theme.card
	priceBox.Position = UDim2.new(0, 8, 0, 40)
	priceBox.Size = UDim2.new(1, -16, 0, 40)
	Theme.corner(priceBox, 8)
	priceBox.Parent = editor
	local listButton = Theme.button({
		Text = "Put up for sale",
		Position = UDim2.new(0, 8, 0, 88),
		Size = UDim2.new(1, -16, 0, 40),
		BackgroundColor3 = Theme.green,
		MaxTextSize = 16,
	})
	listButton.Parent = editor
	local note = Theme.label({
		Text = ("Buyers pay the price you set. A %d%% tax is taken from each sale."):format(math.floor(Constants.PLAZA_TAX * 100 + 0.5)),
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.muted,
		Position = UDim2.new(0, 8, 0, 134),
		Size = UDim2.new(1, -16, 0, 40),
		MaxTextSize = 13,
	})
	note.Parent = editor

	local function rebuild()
		Theme.clear(forSale)
		Theme.clear(mine)
		local id = currentBooth
		local part = if id then boothPart(id) else nil
		local data = Store.data
		if not id or not part or not data then
			return
		end
		local ownerId = part:GetAttribute("Owner")
		if ownerId == 0 then
			Windows.close("Booth")
			return
		end
		local own = ownerId == LOCAL.UserId
		local listings = listingsOf(part)
		header.Text = if own
			then ("🏪 Your booth · %d/%d for sale"):format(#listings, Constants.PLAZA_MAX_LISTINGS)
			else ("🏪 %s's booth · 💎 %s"):format(tostring(part:GetAttribute("OwnerName")), Format.abbrev(data.gems))
		closeBooth.Visible = own
		mineTitle.Visible = own
		mine.Visible = own
		editor.Visible = own

		local listed: { [string]: boolean } = {}
		for order, listing in listings do
			listed[listing.id] = true
			local card = if own
				then saleCard(listing, listing.price, "Take down", Theme.card, function()
					Net.event("BoothUnlist"):FireServer(listing.id)
				end)
				else saleCard(listing, listing.price, "Buy", Theme.green, function()
					Net.event("BoothBuy"):FireServer(id, listing.id, listing.price)
				end)
			card.LayoutOrder = order
			card.Parent = forSale
		end
		if #listings == 0 then
			local empty = Theme.label({ Text = if own then "Nothing for sale yet" else "Sold out!", Size = UDim2.fromOffset(200, 40), MaxTextSize = 16 })
			empty.Parent = forSale
		end
		if not own then
			return
		end

		-- Your creatures that can be sold: not locked, not on a trip, not already listed
		local ids = {}
		for petId, pet in data.pets do
			if not pet.lk and not pet.ex and not listed[petId] then
				table.insert(ids, petId)
			end
		end
		for order, petId in PetMath.rankIds(data.pets, ids) do
			local pet = data.pets[petId]
			local card = saleCard(pet, nil, nil, nil, function()
				pickedPet = petId
				rebuild()
			end)
			card.LayoutOrder = order
			card.Parent = mine
		end
		local picked = if pickedPet then data.pets[pickedPet] else nil
		editorTitle.Text = if picked then "Sell: " .. PetCard.title(picked) else "Pick a creature"
		listButton.Visible = picked ~= nil
		priceBox.Visible = picked ~= nil
	end

	listButton.Activated:Connect(function()
		local price = tonumber(priceBox.Text)
		if pickedPet and price and price >= 1 then
			Net.event("BoothList"):FireServer(pickedPet, math.floor(price))
			pickedPet = nil
			priceBox.Text = ""
		end
	end)

	-- Live updates while the window is open, and the prompt text each player sees
	local function bind(part: Instance)
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		local function changed()
			local owner = part:GetAttribute("Owner")
			if prompt then
				prompt.ActionText = if owner == 0 or owner == nil
					then "Claim booth"
					elseif owner == LOCAL.UserId then "Your booth"
					else "Shop"
			end
			if window.Visible and part:GetAttribute("BoothId") == currentBooth then
				rebuild()
			end
		end
		part:GetAttributeChangedSignal("Listings"):Connect(changed)
		part:GetAttributeChangedSignal("Owner"):Connect(changed)
		changed()
	end
	for _, part in CollectionService:GetTagged("Booth") do
		bind(part)
	end
	CollectionService:GetInstanceAddedSignal("Booth"):Connect(bind)
	Store.DataChanged:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	Windows.register("Booth", window, rebuild)
end

return BoothPanel
