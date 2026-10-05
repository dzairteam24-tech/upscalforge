-- Shows what came out of the eggs, with a bigger celebration for rare results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local World1 = require(Shared.Config.World1)
local Variants = require(Shared.Config.Variants)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Notify = require(script.Parent.Notify)
local PetCard = require(script.Parent.PetCard)
local Theme = require(script.Parent.Theme)

local HatchPopup = {}

local rng = Random.new()

-- Hatch effect (cosmetic, bought in the shop): plays behind the cards. Odds are never touched.
local function playEffect(layer: Frame, fx: Cosmetics.HatchFx)
	for _, child in layer:GetChildren() do
		child:Destroy()
	end
	local fewer = Store.lowEnd()
	if fx.style == "rays" then
		local rays = Instance.new("Frame")
		rays.BackgroundTransparency = 1
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.5)
		rays.Size = UDim2.fromOffset(520, 520)
		rays.Parent = layer
		local count = if fewer then 6 else 12
		for i = 1, count do
			local ray = Instance.new("Frame")
			ray.BorderSizePixel = 0
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Position = UDim2.fromScale(0.5, 0.5)
			ray.Size = UDim2.new(0, 34, 1, 0)
			ray.Rotation = (i - 1) * 180 / count
			ray.BackgroundColor3 = fx.colors[(i - 1) % #fx.colors + 1]
			ray.BackgroundTransparency = 0.55
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			fade.Parent = ray
			ray.Parent = rays
		end
		TweenService:Create(rays, TweenInfo.new(2.5, Enum.EasingStyle.Linear), { Rotation = 90 }):Play()
	else -- confetti
		local count = if fewer then 20 else 50
		for _ = 1, count do
			local bit = Instance.new("Frame")
			bit.BorderSizePixel = 0
			bit.AnchorPoint = Vector2.new(0.5, 0.5)
			bit.Position = UDim2.new(0.5, 0, 0.5, 0)
			local size = rng:NextInteger(6, 12)
			bit.Size = UDim2.fromOffset(size, size)
			bit.Rotation = rng:NextInteger(0, 90)
			bit.BackgroundColor3 = fx.colors[rng:NextInteger(1, #fx.colors)]
			bit.Parent = layer
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(140, 340)
			local goal = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance * 0.6 + 60)
			TweenService:Create(bit, TweenInfo.new(rng:NextNumber(0.9, 1.6), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = goal,
				Rotation = bit.Rotation + rng:NextInteger(180, 540),
				BackgroundTransparency = 1,
			}):Play()
		end
	end
end

function HatchPopup.mount(gui: ScreenGui)
	local holder = Theme.frame({
		Name = "Hatch",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(600, 160),
		BackgroundTransparency = 1,
		Visible = false,
	})
	holder.ZIndex = 2
	local fxLayer = Theme.frame({
		Name = "HatchFx",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(600, 160),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Visible = false,
	})
	fxLayer.Parent = gui
	local layout = Theme.list(holder, 10, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	holder.Parent = gui

	local token = 0
	Net.event("HatchResult").OnClientEvent:Connect(function(results: { { [string]: any } }, _free: boolean)
		token += 1
		local myToken = token
		for _, child in holder:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local best = 1
		local bestPet = results[1]
		for i, pet in results do
			if i > 8 then
				break
			end
			local card = PetCard.create(pet :: any)
			card.Size = UDim2.fromOffset(100, 0)
			card.LayoutOrder = i
			if pet.deleted then
				card.BackgroundTransparency = 0.6
				local gone = Theme.label({
					Text = "🗑️ Auto-deleted",
					TextColor3 = Theme.muted,
					Size = UDim2.new(1, 0, 0.2, 0),
					Position = UDim2.fromScale(0, 0.4),
					MaxTextSize = 13,
				})
				gone.Parent = card
			end
			card.Parent = holder
			TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(100, 130) }):Play()
			local variant = Variants.byId[pet.v]
			if variant then
				local species = World1.species[pet.s]
				local legendary = species ~= nil and species.legendary
				local score = variant.order + (if pet.z == "Titan" then 10 elseif pet.z == "Big" then 5 else 0) + (if legendary then 9 else 0)
				if score > best then
					best = score
					bestPet = pet
				end
			end
		end
		holder.Visible = true
		local data = Store.data
		local fx = if data and data.equippedHatchFx then Cosmetics.hatchFxById[data.equippedHatchFx] else nil
		fxLayer.Visible = fx ~= nil
		if fx then
			playEffect(fxLayer, fx)
		end
		if best >= 10 then
			Notify.show("👑 INCREDIBLE! " .. PetCard.title(bestPet :: any), "rare", 5)
		elseif best >= 4 then
			Notify.show("✨ Rare hatch!", "rare")
		end
		task.delay(2.5, function()
			if token == myToken then
				holder.Visible = false
				fxLayer.Visible = false
			end
		end)
	end)
end

return HatchPopup
