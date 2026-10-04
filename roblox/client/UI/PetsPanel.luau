-- Inventory window: team, storage, equip, lock, delete and fusion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Variants = require(Shared.Config.Variants)
local World1 = require(Shared.Config.World1)
local Format = require(Shared.Logic.Format)
local Inventory = require(Shared.Logic.Inventory)
local PetMath = require(Shared.Logic.PetMath)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local PetCard = require(script.Parent.PetCard)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local PetsPanel = {}

local selectedId: string? = nil
local deleteMode = false
local toDelete: { [string]: boolean? } = {}

function PetsPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Pets", function()
		Windows.close("Pets")
	end)

	-- Top bar
	local bar = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) })
	bar.Parent = content
	local counts = Theme.label({
		Text = "",
		Size = UDim2.new(0.4, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
	})
	counts.Parent = bar
	local equipBest = Theme.button({
		Text = "Equip Best",
		Size = UDim2.new(0.18, 0, 1, -4),
		Position = UDim2.new(0.4, 0, 0, 2),
		BackgroundColor3 = Theme.green,
		MaxTextSize = 18,
	})
	equipBest.Parent = bar
	local deleteToggle = Theme.button({
		Text = "Delete Mode",
		Size = UDim2.new(0.19, 0, 1, -4),
		Position = UDim2.new(0.6, 0, 0, 2),
		BackgroundColor3 = Theme.card,
		MaxTextSize = 18,
	})
	deleteToggle.Parent = bar
	local deleteConfirm = Theme.button({
		Text = "Delete (0)",
		Size = UDim2.new(0.19, 0, 1, -4),
		Position = UDim2.new(0.81, 0, 0, 2),
		BackgroundColor3 = Theme.red,
		Visible = false,
		MaxTextSize = 18,
	})
	deleteConfirm.Parent = bar

	-- Grid
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 48)
	scroll.Size = UDim2.new(0.64, 0, 1, -48)
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(96, 120)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	scroll.Parent = content

	-- Details
	local details = Theme.frame({
		Position = UDim2.new(0.66, 0, 0, 48),
		Size = UDim2.new(0.34, 0, 1, -48),
		BackgroundColor3 = Theme.panel,
	})
	Theme.corner(details, 12)
	details.Parent = content
	local detailsIcon = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.32, 0) })
	detailsIcon.Parent = details
	local detailsTitle = Theme.label({
		Text = "Pick a creature",
		Font = Theme.titleFont,
		Size = UDim2.new(1, -12, 0, 28),
		Position = UDim2.new(0, 6, 0.32, 0),
		MaxTextSize = 22,
	})
	detailsTitle.Parent = details
	local detailsText = Theme.label({
		Text = "",
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.muted,
		Size = UDim2.new(1, -12, 0.28, 0),
		Position = UDim2.new(0, 6, 0.32, 30),
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 15,
	})
	detailsText.Parent = details
	local buttons = Theme.frame({
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0.62, 30),
		Size = UDim2.new(1, -16, 0.38, -36),
	})
	local buttonGrid = Instance.new("UIGridLayout")
	buttonGrid.CellSize = UDim2.new(0.5, -4, 0.5, -4)
	buttonGrid.CellPadding = UDim2.fromOffset(8, 8)
	buttonGrid.Parent = buttons
	buttons.Parent = details
	local equipButton = Theme.button({ Text = "Equip", BackgroundColor3 = Theme.green, MaxTextSize = 18 })
	local lockButton = Theme.button({ Text = "Lock", BackgroundColor3 = Theme.card, MaxTextSize = 18 })
	local fuseButton = Theme.button({ Text = "Fuse", BackgroundColor3 = Theme.purple, MaxTextSize = 16 })
	local deleteButton = Theme.button({ Text = "Delete", BackgroundColor3 = Theme.red, MaxTextSize = 18 })
	for i, b in { equipButton, lockButton, fuseButton, deleteButton } do
		b.LayoutOrder = i
		b.Parent = buttons
	end

	local function refreshDetails()
		for _, child in detailsIcon:GetChildren() do
			child:Destroy()
		end
		local data = Store.data
		local pet = data and selectedId and data.pets[selectedId]
		buttons.Visible = pet ~= nil
		if not data or not pet or not selectedId then
			detailsTitle.Text = "Pick a creature"
			detailsText.Text = "Tap a card to see its power and skills."
			return
		end
		PetCard.icon(pet, detailsIcon)
		detailsTitle.Text = PetCard.title(pet)
		local species = World1.species[pet.s]
		local variant = Variants.byId[pet.v]
		local lines = {
			("⚡ %s coins per hit"):format(Format.abbrev(PetMath.basePower(pet))),
			variant and variant.description or "",
		}
		if species and pet.z == "Big" then
			table.insert(lines, "Big skill: " .. species.big.text)
		elseif species and pet.z == "Titan" then
			table.insert(lines, "Titan skill: " .. species.titan.text)
		end
		if species then
			table.insert(lines, ("From %s · %s chance"):format(World1.zonesById[species.zone].name, Format.chance(species.chance)))
		end
		detailsText.Text = table.concat(lines, "\n")

		if pet.ex then
			table.insert(lines, "🧭 Away on a trip. It comes back when you claim the trip.")
			detailsText.Text = table.concat(lines, "\n")
		end
		local equipped = table.find(data.equipped, selectedId) ~= nil
		equipButton.Text = if pet.ex then "On a trip" elseif equipped then "Unequip" else "Equip"
		equipButton.BackgroundColor3 = if pet.ex then Theme.card else Theme.green
		deleteButton.Visible = not pet.ex
		lockButton.Text = if pet.lk then "Unlock" else "Lock"
		local nextVariant = variant and variant.fuseInto
		if nextVariant and pet.z == "Normal" then
			local have = #Inventory.fusionMaterial(data :: any, pet.s, pet.v)
			fuseButton.Text = ("Fuse %d/%d → %s"):format(have, Constants.FUSION_COST, nextVariant)
			fuseButton.Visible = true
		else
			fuseButton.Visible = false
		end
	end

	local function rebuild()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local data = Store.data
		if not data then
			return
		end
		local ids = {}
		for petId in data.pets do
			table.insert(ids, petId)
		end
		local ranked = PetMath.rankIds(data.pets, ids)
		local equippedSet = {}
		for _, petId in data.equipped do
			equippedSet[petId] = true
		end
		local rank = {}
		for index, petId in ranked do
			rank[petId] = index
		end
		table.sort(ranked, function(a, b)
			if equippedSet[a] ~= equippedSet[b] then
				return equippedSet[a] == true
			end
			return rank[a] < rank[b]
		end)
		for order, petId in ranked do
			local pet = data.pets[petId]
			local card = PetCard.create(pet, {
				equipped = equippedSet[petId],
				selected = if deleteMode then toDelete[petId] == true else petId == selectedId,
			})
			card.LayoutOrder = order
			card.Activated:Connect(function()
				if deleteMode then
					if not pet.lk and not pet.ex then
						toDelete[petId] = if toDelete[petId] then nil else true
					end
					rebuild()
				else
					selectedId = petId
					rebuild()
					refreshDetails()
				end
			end)
			card.Parent = scroll
		end
		local n = 0
		for _ in toDelete do
			n += 1
		end
		deleteConfirm.Text = ("Delete (%d)"):format(n)
		counts.Text = ("Team %d/%d · Storage %d/%d"):format(#data.equipped, data.maxSlots, #ranked, data.capacity)
		refreshDetails()
	end

	equipBest.Activated:Connect(function()
		Net.event("EquipBest"):FireServer()
	end)
	deleteToggle.Activated:Connect(function()
		deleteMode = not deleteMode
		toDelete = {}
		deleteToggle.BackgroundColor3 = if deleteMode then Theme.red else Theme.card
		deleteConfirm.Visible = deleteMode
		rebuild()
	end)
	deleteConfirm.Activated:Connect(function()
		local ids = {}
		for petId in toDelete do
			table.insert(ids, petId)
		end
		if #ids > 0 then
			Net.event("DeletePets"):FireServer(ids)
		end
		toDelete = {}
	end)
	equipButton.Activated:Connect(function()
		local data = Store.data
		if not data or not selectedId then
			return
		end
		if data.pets[selectedId] and data.pets[selectedId].ex then
			return
		elseif table.find(data.equipped, selectedId) then
			Net.event("UnequipPet"):FireServer(selectedId)
		else
			Net.event("EquipPet"):FireServer(selectedId)
		end
	end)
	lockButton.Activated:Connect(function()
		local data = Store.data
		local pet = data and selectedId and data.pets[selectedId]
		if pet then
			Net.event("LockPet"):FireServer(selectedId, not pet.lk)
		end
	end)
	fuseButton.Activated:Connect(function()
		local data = Store.data
		local pet = data and selectedId and data.pets[selectedId]
		if pet then
			Net.event("FusePets"):FireServer(pet.s, pet.v)
		end
	end)
	deleteButton.Activated:Connect(function()
		if selectedId then
			Net.event("DeletePets"):FireServer({ selectedId })
			selectedId = nil
		end
	end)

	Store.DataChanged:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
	Windows.register("Pets", window, rebuild)
end

return PetsPanel
