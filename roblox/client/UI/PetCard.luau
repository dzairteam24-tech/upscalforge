-- A creature card: 3D icon, name, power and badges. Used by the pets, trade and hatch windows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Variants = require(Shared.Config.Variants)
local Format = require(Shared.Logic.Format)
local PetMath = require(Shared.Logic.PetMath)
local PetModel = require(Shared.PetModel)
local Theme = require(script.Parent.Theme)

local PetCard = {}

function PetCard.icon(pet: { s: string, v: string, z: string, st: string? }, parent: Instance): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	local built = PetModel.build(pet)
	PetModel.place(built, CFrame.Angles(0, math.rad(-20), 0))
	built.model.Parent = viewport
	local camera = Instance.new("Camera")
	local distance = built.height * 2.3
	camera.CFrame = CFrame.lookAt(Vector3.new(0, built.height * 0.25, -distance), Vector3.new(0, built.height * 0.1, 0))
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = parent
	return viewport
end

function PetCard.title(pet: { s: string, v: string, z: string }): string
	local words = {}
	if pet.z ~= "Normal" then
		table.insert(words, pet.z)
	end
	if pet.v ~= "Normal" then
		table.insert(words, pet.v)
	end
	table.insert(words, pet.s)
	return table.concat(words, " ")
end

export type CardOptions = {
	equipped: boolean?,
	selected: boolean?,
	showPower: boolean?,
}

function PetCard.create(
	pet: { s: string, v: string, z: string, lk: boolean?, ex: boolean?, st: string? },
	options: CardOptions?
): TextButton
	local opts = options or {}
	local variant = Variants.byId[pet.v]
	local card = Instance.new("TextButton")
	card.Text = ""
	card.AutoButtonColor = true
	card.BackgroundColor3 = if opts.selected then Color3.fromRGB(70, 90, 140) else Theme.card
	card.BorderSizePixel = 0
	Theme.corner(card, 10)
	Theme.stroke(card, if variant then variant.color else Theme.muted, if pet.z ~= "Normal" then 3 else 2)

	local iconHolder = Instance.new("Frame")
	iconHolder.BackgroundTransparency = 1
	iconHolder.Size = UDim2.fromScale(1, 0.7)
	iconHolder.Parent = card
	PetCard.icon(pet, iconHolder)

	local name = Theme.label({
		Text = PetCard.title(pet),
		Size = UDim2.new(1, -6, 0.15, 0),
		Position = UDim2.new(0, 3, 0.68, 0),
		MaxTextSize = 14,
	})
	name.Parent = card

	if opts.showPower ~= false then
		local power = Theme.label({
			Text = "⚡ " .. Format.abbrev(PetMath.basePower(pet)),
			TextColor3 = Theme.gold,
			Size = UDim2.new(1, -6, 0.15, 0),
			Position = UDim2.new(0, 3, 0.84, 0),
			MaxTextSize = 14,
		})
		power.Parent = card
	end

	local badges = {}
	if opts.equipped then
		table.insert(badges, "✅")
	end
	if pet.lk then
		table.insert(badges, "🔒")
	end
	if pet.ex then
		table.insert(badges, "🧭")
	end
	local sticker = if pet.st then Items.byId[pet.st] else nil
	if sticker and sticker.icon then
		table.insert(badges, sticker.icon)
	end
	if pet.z == "Titan" then
		table.insert(badges, "👑")
	elseif pet.z == "Big" then
		table.insert(badges, "🟠")
	end
	if #badges > 0 then
		local badge = Theme.label({
			Text = table.concat(badges, ""),
			Size = UDim2.new(1, -6, 0.2, 0),
			Position = UDim2.fromOffset(3, 2),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 16,
		})
		badge.Parent = card
	end
	return card
end

return PetCard
