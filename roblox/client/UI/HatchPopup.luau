-- Shows what came out of the eggs, with a bigger celebration for rare results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Variants = require(Shared.Config.Variants)
local Net = require(Shared.Net)

local Notify = require(script.Parent.Notify)
local PetCard = require(script.Parent.PetCard)
local Theme = require(script.Parent.Theme)

local HatchPopup = {}

function HatchPopup.mount(gui: ScreenGui)
	local holder = Theme.frame({
		Name = "Hatch",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(600, 160),
		BackgroundTransparency = 1,
		Visible = false,
	})
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
			card.Parent = holder
			TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(100, 130) }):Play()
			local variant = Variants.byId[pet.v]
			if variant then
				local score = variant.order + (if pet.z == "Titan" then 10 elseif pet.z == "Big" then 5 else 0)
				if score > best then
					best = score
					bestPet = pet
				end
			end
		end
		holder.Visible = true
		if best >= 10 then
			Notify.show("👑 INCREDIBLE! " .. PetCard.title(bestPet :: any), "rare", 5)
		elseif best >= 4 then
			Notify.show("✨ Rare hatch!", "rare")
		end
		task.delay(2.5, function()
			if token == myToken then
				holder.Visible = false
			end
		end)
	end)
end

return HatchPopup
