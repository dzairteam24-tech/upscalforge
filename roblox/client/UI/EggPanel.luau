-- Shows up next to an egg: price, odds for every creature, and hatch buttons (x1, x3, x8, auto).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local World1 = require(Shared.Config.World1)
local Products = require(Shared.Config.Products)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local AdButton = require(script.Parent.AdButton)
local Store = require(script.Parent.Parent.Store)
local PetCard = require(script.Parent.PetCard)
local Theme = require(script.Parent.Theme)

local EggPanel = {}

local LOCAL = Players.LocalPlayer

function EggPanel.mount(gui: ScreenGui)
	local panel = Theme.frame({
		Name = "EggPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(640, 220),
		BackgroundColor3 = Theme.bg,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	Theme.corner(panel, 16)
	Theme.stroke(panel, Theme.gold, 3)
	panel.Parent = gui

	local title = Theme.label({
		Text = "",
		Font = Theme.titleFont,
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 4),
		MaxTextSize = 24,
	})
	title.Parent = panel

	local odds = Theme.frame({ BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 38), Size = UDim2.new(1, -16, 0, 110) })
	local oddsLayout = Theme.list(odds, 8, true)
	oddsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	odds.Parent = panel

	local buttons = Theme.frame({ BackgroundTransparency = 1, Position = UDim2.new(0, 8, 1, -60), Size = UDim2.new(1, -16, 0, 50) })
	local buttonLayout = Theme.list(buttons, 8, true)
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttons.Parent = panel

	local zoneShown: number? = nil
	local autoHatch = false

	local function hatchButton(text: string, amount: number, color: Color3, order: number): TextButton
		local b = Theme.button({ Text = text, Size = UDim2.fromOffset(120, 48), BackgroundColor3 = color, LayoutOrder = order, MaxTextSize = 20 })
		b.Parent = buttons
		b.Activated:Connect(function()
			if zoneShown then
				Net.event("Hatch"):FireServer(zoneShown, amount)
			end
		end)
		return b
	end
	hatchButton("Hatch x1", 1, Theme.green, 1)
	local x3 = hatchButton("Hatch x3", 3, Theme.accent, 2)
	local x8 = hatchButton("Hatch x8", 8, Theme.purple, 3)
	local auto = Theme.button({ Text = "Auto: OFF", Size = UDim2.fromOffset(120, 48), BackgroundColor3 = Theme.card, LayoutOrder = 4, MaxTextSize = 20 })
	auto.Parent = buttons
	-- Rewarded video shortcuts next to the egg (shown only when a video can play)
	local adButtons: { [string]: TextButton } = {}
	for order, key in { "AdLuck", "AdEggs" } do
		local reward = Products.adByKey[key]
		if reward then
			local adButton = Theme.button({
				Text = "▶ " .. reward.label,
				Size = UDim2.fromOffset(150, 48),
				BackgroundColor3 = Theme.gold,
				LayoutOrder = 10 + order,
				Visible = false,
				MaxTextSize = 15,
			})
			adButton.Parent = buttons
			adButton.Activated:Connect(function()
				AdButton.watch(key)
			end)
			adButtons[key] = adButton
		end
	end
	task.spawn(function()
		while true do
			for key, adButton in adButtons do
				adButton.Visible = AdButton.available(key)
			end
			task.wait(2)
		end
	end)
	auto.Activated:Connect(function()
		autoHatch = not autoHatch
		auto.Text = if autoHatch then "Auto: ON" else "Auto: OFF"
		auto.BackgroundColor3 = if autoHatch then Theme.green else Theme.card
	end)

	local function updateButtons()
		local data = Store.data
		x3.Visible = data ~= nil and (data.upgrades.Hatch3 or 0) > 0
		x8.Visible = data ~= nil and (data.upgrades.Hatch8 or 0) > 0
		auto.Visible = data ~= nil and (data.upgrades.AutoHatch or 0) > 0
	end

	local function show(zoneId: number)
		zoneShown = zoneId
		local zone = World1.zonesById[zoneId]
		title.Text = ("%s Egg · 🪙 %s"):format(zone.name, Format.abbrev(zone.eggPrice))
		for _, child in odds:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for order, speciesId in zone.species do
			local species = World1.species[speciesId]
			local cell = Theme.frame({ Size = UDim2.fromOffset(110, 110), BackgroundColor3 = Theme.card, LayoutOrder = order })
			Theme.corner(cell, 10)
			local iconHolder = Theme.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.72, 0) })
			iconHolder.Parent = cell
			PetCard.icon({ s = speciesId, v = "Normal", z = "Normal" }, iconHolder)
			local text = Theme.label({
				Text = ("%s · %s"):format(speciesId, Format.chance(species.chance)),
				Size = UDim2.new(1, -6, 0.26, 0),
				Position = UDim2.new(0, 3, 0.72, 0),
				MaxTextSize = 14,
			})
			text.Parent = cell
			cell.Parent = odds
		end
		updateButtons()
		panel.Visible = true
	end

	local function hide()
		zoneShown = nil
		panel.Visible = false
	end

	-- Watch distance to eggs
	task.spawn(function()
		while true do
			task.wait(0.3)
			local character = LOCAL.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local nearest: number? = nil
			if root then
				for _, egg in CollectionService:GetTagged("EggStand") do
					if egg:IsA("BasePart") and (egg.Position - root.Position).Magnitude <= Constants.EGG_RANGE then
						local zoneId = egg:GetAttribute("ZoneId")
						if type(zoneId) == "number" and Store.isUnlocked(zoneId) then
							nearest = zoneId
						end
					end
				end
			end
			if nearest and nearest ~= zoneShown then
				show(nearest)
			elseif not nearest and zoneShown then
				hide()
			end
		end
	end)

	-- Auto hatch while standing at an egg
	task.spawn(function()
		while true do
			task.wait(Constants.HATCH_COOLDOWN + 0.9)
			if autoHatch and zoneShown then
				local data = Store.data
				local amount = 1
				if data and (data.upgrades.Hatch8 or 0) > 0 then
					amount = 8
				elseif data and (data.upgrades.Hatch3 or 0) > 0 then
					amount = 3
				end
				Net.event("Hatch"):FireServer(zoneShown, amount)
			end
		end
	end)

	Store.DataChanged:Connect(updateButtons)
end

return EggPanel
