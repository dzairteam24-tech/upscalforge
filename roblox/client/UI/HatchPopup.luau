-- The hatch show: the egg pops up in the middle of the screen, shakes harder and harder, cracks, bursts in a
-- flash, and the creature jumps out in front of spinning rays coloured by its rarity, with its name, its
-- odds ("1 in 50K") and "NEW!" the first time. Rare results take longer and get louder; Titans and
-- Legendaries get the full treatment (slow motion, confetti, a big banner). Auto hatch uses a quick version,
-- but never for anything rare. Timings follow the top pet games (see docs/hatching.md).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local Sizes = require(Shared.Config.Sizes)
local Variants = require(Shared.Config.Variants)
local World1 = require(Shared.Config.World1)
local Format = require(Shared.Logic.Format)
local PetModel = require(Shared.PetModel)
local Net = require(Shared.Net)

local SoundClient = require(script.Parent.Parent.Controllers.SoundClient)
local Store = require(script.Parent.Parent.Store)
local PetCard = require(script.Parent.PetCard)
local Theme = require(script.Parent.Theme)

local HatchPopup = {}

local rng = Random.new()

-- Rarity looks: colour of the rays and banner, how long the show is, how many shakes.
type Tier = { level: number, label: string, colors: { Color3 } }

local VARIANT_COLORS: { [string]: Color3 } = {
	Normal = Color3.fromRGB(120, 200, 255),
	Golden = Color3.fromRGB(255, 205, 60),
	Crystal = Color3.fromRGB(130, 230, 255),
	Lava = Color3.fromRGB(255, 110, 40),
	Neon = Color3.fromRGB(60, 255, 150),
	Pixel = Color3.fromRGB(190, 120, 255),
}
local RAINBOW = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(90, 230, 120),
	Color3.fromRGB(80, 180, 255),
	Color3.fromRGB(190, 110, 255),
}

-- level 0: plain hatch, 1: rare (any variant, Big), 2: epic (Pixel, Titan, Legendary)
local function tierOf(pet: { [string]: any }): Tier
	local species = World1.species[pet.s]
	if species and species.legendary then
		return { level = 2, label = "LEGENDARY!", colors = RAINBOW }
	end
	if pet.z == "Titan" then
		return { level = 2, label = "TITAN!", colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 210, 70) } }
	end
	if pet.v == "Pixel" then
		return { level = 2, label = "PIXEL!", colors = { VARIANT_COLORS.Pixel, Color3.fromRGB(255, 110, 210) } }
	end
	if pet.z == "Big" then
		return { level = 1, label = "BIG!", colors = { Color3.fromRGB(255, 150, 60), VARIANT_COLORS[pet.v] or VARIANT_COLORS.Normal } }
	end
	if pet.v ~= "Normal" then
		return { level = 1, label = string.upper(pet.v) .. "!", colors = { VARIANT_COLORS[pet.v] or VARIANT_COLORS.Normal } }
	end
	return { level = 0, label = "", colors = { VARIANT_COLORS.Normal } }
end

-- Base odds of exactly this result from its egg (luck not counted), as text.
local function oddsText(pet: { [string]: any }, fromEgg: boolean): string?
	local species = World1.species[pet.s]
	if not species or not fromEgg then
		return nil
	end
	local chance = species.chance
	local variant = Variants.byId[pet.v]
	if variant and variant.chance > 0 then
		chance *= variant.chance
	end
	local size = Sizes.byId[pet.z]
	if size and size.chance > 0 then
		chance *= size.chance
	end
	return Format.chance(chance)
end

local function backOut(t: number): number
	local c1, c3 = 1.70158, 2.70158
	local x = math.clamp(t, 0, 1) - 1
	return 1 + c3 * x * x * x + c1 * x * x
end

---------------------------------------------------------------------------------------------------------------
-- 2D pieces (ParticleEmitters don't show in viewports, so rays, sparkles and confetti are GUI frames)

local function makeRays(parent: Instance, colors: { Color3 }, count: number): Frame
	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromScale(1.6, 1.6)
	rays.SizeConstraint = Enum.SizeConstraint.RelativeYY
	for i = 1, count do
		local ray = Instance.new("Frame")
		ray.BorderSizePixel = 0
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(0.09, 0, 1, 0)
		ray.Rotation = (i - 1) * 180 / count
		ray.BackgroundColor3 = colors[(i - 1) % #colors + 1]
		ray.BackgroundTransparency = 0.35
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.38, 0.2),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(0.62, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
		ray.Parent = rays
	end
	-- Soft glow in the middle
	local glow = Instance.new("Frame")
	glow.BorderSizePixel = 0
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(0.45, 0.45)
	glow.BackgroundColor3 = colors[1]:Lerp(Color3.new(1, 1, 1), 0.5)
	glow.BackgroundTransparency = 0.3
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = glow
	local fadeGlow = Instance.new("UIGradient")
	fadeGlow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fadeGlow.Parent = glow
	glow.Parent = rays
	rays.Parent = parent
	return rays
end

-- Four-point star sparkles that burst out from the middle and fade.
local function burstSparkles(parent: Instance, colors: { Color3 }, count: number)
	for _ = 1, count do
		local star = Instance.new("Frame")
		star.BorderSizePixel = 0
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(0.5, 0.5)
		local size = rng:NextInteger(10, 22)
		star.Size = UDim2.fromOffset(size, size)
		star.Rotation = 45
		star.BackgroundColor3 = colors[rng:NextInteger(1, #colors)]:Lerp(Color3.new(1, 1, 1), 0.4)
		star.ZIndex = 5
		star.Parent = parent
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0.25, 0.6)
		TweenService:Create(star, TweenInfo.new(rng:NextNumber(0.6, 1.1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5 + math.cos(angle) * distance, 0.5 + math.sin(angle) * distance),
			Rotation = 45 + rng:NextInteger(90, 270),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(4, 4),
		}):Play()
		task.delay(1.2, function()
			star:Destroy()
		end)
	end
end

-- Confetti raining down over the whole screen (Titans and Legendaries).
local function confetti(parent: Instance, colors: { Color3 }, count: number)
	for _ = 1, count do
		local bit = Instance.new("Frame")
		bit.BorderSizePixel = 0
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		bit.Position = UDim2.fromScale(rng:NextNumber(0, 1), rng:NextNumber(-0.3, -0.05))
		bit.Size = UDim2.fromOffset(rng:NextInteger(8, 14), rng:NextInteger(5, 9))
		bit.Rotation = rng:NextInteger(0, 180)
		bit.BackgroundColor3 = colors[rng:NextInteger(1, #colors)]
		bit.ZIndex = 9
		bit.Parent = parent
		local fall = rng:NextNumber(2.2, 3.6)
		TweenService:Create(bit, TweenInfo.new(fall, Enum.EasingStyle.Linear), {
			Position = UDim2.fromScale(bit.Position.X.Scale + rng:NextNumber(-0.15, 0.15), 1.1),
			Rotation = bit.Rotation + rng:NextInteger(360, 900),
		}):Play()
		task.delay(fall, function()
			bit:Destroy()
		end)
	end
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3, textSize: number): TextLabel
	local l = Theme.label({
		Text = text,
		Font = Theme.titleFont,
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = size,
		Position = position,
		MaxTextSize = textSize,
		ZIndex = 6,
	})
	Theme.stroke(l, Color3.fromRGB(30, 24, 70), 3)
	l.Parent = parent
	return l
end

---------------------------------------------------------------------------------------------------------------
-- One egg in its own viewport

type Shard = { part: BasePart, velocity: Vector3, spin: Vector3 }

type Slot = {
	frame: Frame,
	viewport: ViewportFrame,
	egg: Model?,
	eggMesh: SpecialMesh?,
	eggPart: BasePart?,
	cracks: { BasePart },
	built: PetModel.Built,
	pet: { [string]: any },
	tier: Tier,
	baseCFrame: CFrame,
	broken: boolean,
	shards: { Shard },
	rays: Frame?,
	revealAt: number,
}

local EGG_SIZE = 3.2

local function makeEgg(viewport: ViewportFrame, color: Color3, legendary: boolean): (Model, BasePart, SpecialMesh, { BasePart })
	local model = Instance.new("Model")
	model.Name = "Egg"
	local shell = Instance.new("Part")
	shell.Anchored = true
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.one * EGG_SIZE
	shell.Color = color
	shell.Material = if legendary then Enum.Material.Foil else Enum.Material.SmoothPlastic
	shell.Parent = model
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = shell
	-- Spots
	local spotColor = color:Lerp(Color3.new(1, 1, 1), 0.55)
	for i = 1, 6 do
		local spot = Instance.new("Part")
		spot.Anchored = true
		spot.Shape = Enum.PartType.Ball
		spot.Size = Vector3.one * (0.55 + (i % 3) * 0.15)
		spot.Color = spotColor
		spot.Material = Enum.Material.SmoothPlastic
		local a = i * 2.1
		local y = math.sin(i * 1.7) * 0.9
		local r = EGG_SIZE / 2 * math.sqrt(math.max(0.2, 1 - (y / (EGG_SIZE * 0.65)) ^ 2)) - 0.12
		spot.CFrame = CFrame.new(math.cos(a) * r, y, math.sin(a) * r)
		spot.Parent = model
	end
	-- Cracks, shown one by one as the egg shakes
	local cracks = {}
	for i = 1, 3 do
		local crack = Instance.new("Part")
		crack.Anchored = true
		crack.Size = Vector3.new(0.12, 0.9 + i * 0.25, 0.08)
		crack.Color = Color3.fromRGB(40, 30, 50)
		crack.Material = Enum.Material.SmoothPlastic
		crack.Transparency = 1
		crack.CFrame = CFrame.new((i - 2) * 0.55, 0.5 - i * 0.2, -EGG_SIZE / 2 + 0.05) * CFrame.Angles(0, 0, math.rad((i - 2) * 35 + 10))
		crack.Parent = model
		table.insert(cracks, crack)
	end
	model.PrimaryPart = shell
	model.Parent = viewport
	return model, shell, mesh, cracks
end

local function spawnShards(slot: Slot, count: number, color: Color3)
	for i = 1, count do
		local shard = Instance.new("Part")
		shard.Anchored = true
		shard.Size = Vector3.new(rng:NextNumber(0.35, 0.7), rng:NextNumber(0.3, 0.6), 0.14)
		shard.Color = if i % 3 == 0 then color:Lerp(Color3.new(1, 1, 1), 0.55) else color
		shard.Material = Enum.Material.SmoothPlastic
		local a = rng:NextNumber(0, math.pi * 2)
		local start = Vector3.new(math.cos(a) * 1.2, rng:NextNumber(-0.8, 1.2), math.sin(a) * 0.6 - 0.4)
		shard.CFrame = CFrame.new(start)
		shard.Parent = slot.viewport
		table.insert(slot.shards, {
			part = shard,
			velocity = Vector3.new(math.cos(a) * rng:NextNumber(5, 9), rng:NextNumber(5, 10), math.sin(a) * 3 - 4),
			spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8)),
		})
	end
end

---------------------------------------------------------------------------------------------------------------

function HatchPopup.mount(gui: ScreenGui)
	local overlay = Instance.new("TextButton") -- a button so a tap can skip the end of the show
	overlay.Name = "HatchShow"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.BorderSizePixel = 0
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 30
	overlay.Visible = false
	overlay.Parent = gui

	local stage = Instance.new("Frame") -- shaken as a whole for the screen shake
	stage.BackgroundTransparency = 1
	stage.Size = UDim2.fromScale(1, 1)
	stage.ZIndex = 30
	stage.Parent = overlay

	local flash = Instance.new("Frame")
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 40
	flash.Parent = overlay

	local running = 0 -- id of the show that's playing
	local skipFrom = math.huge
	local endAt = 0
	local started = 0

	overlay.Activated:Connect(function()
		local t = os.clock() - started
		if t >= skipFrom then
			endAt = math.min(endAt, t + 0.15)
		end
	end)

	local function clearStage()
		for _, child in stage:GetChildren() do
			child:Destroy()
		end
		for _, child in overlay:GetChildren() do
			if child:IsA("Frame") and child ~= stage and child ~= flash then
				child:Destroy()
			end
		end
	end

	local function play(results: { { [string]: any } }, eggId: number?)
		running += 1
		local myRun = running
		clearStage()

		local shown = {}
		for i = 1, math.min(8, #results) do
			table.insert(shown, results[i])
		end
		if #shown == 0 then
			return
		end

		-- How big a show: the best result decides
		local index = Store.data and (Store.data :: any).index or {}
		local bestLevel, best = -1, shown[1]
		local anyNew = false
		for _, pet in shown do
			local tier = tierOf(pet)
			if tier.level > bestLevel then
				bestLevel = tier.level
				best = pet
			end
			if not pet.deleted and index[pet.s .. "|" .. pet.v] ~= true then
				anyNew = true
			end
		end
		local fast = Players.LocalPlayer:GetAttribute("AutoHatching") == true and bestLevel == 0 and not anyNew
		local egg = if eggId then World1.eggs[eggId] else nil
		local zone = if egg then World1.zonesById[egg.zone] else nil
		local legendaryEgg = egg ~= nil and egg.fixedOdds == true
		local eggColor = if legendaryEgg then Color3.fromRGB(255, 200, 70) elseif zone then zone.color else Color3.fromRGB(240, 240, 245)

		-- Timeline (seconds)
		local shakes = if fast then 1 elseif bestLevel == 2 then 6 elseif bestLevel == 1 then 4 else 3
		local intro = if fast then 0.12 else 0.3
		local shakeLen, shakeGap = 0.22, 0.12
		local breakAt = if egg then intro + shakes * (shakeLen + shakeGap) + (if fast then 0 else 0.12) else 0.15
		local total = if fast then breakAt + 0.6 elseif bestLevel == 2 then breakAt + 4.4 elseif bestLevel == 1 then breakAt + 2.2 else breakAt + 1.3
		skipFrom = if bestLevel == 2 then breakAt + 1.2 elseif fast then 0 else breakAt + 0.3
		endAt = total
		started = os.clock()

		-- Layout: one big egg, a row of 3, or two rows of 4
		local count = #shown
		local cols = if count <= 3 then count else 4
		local rows = math.ceil(count / cols)
		local cell = if count == 1 then 0.46 elseif count <= 3 then 0.34 else 0.26 -- share of the screen height
		overlay.Visible = true
		overlay.Interactable = true
		TweenService:Create(overlay, TweenInfo.new(0.15), { BackgroundTransparency = if bestLevel == 2 then 0.3 elseif fast then 0.75 else 0.55 }):Play()

		local data = Store.data
		local fx = if data and (data :: any).equippedHatchFx then Cosmetics.hatchFxById[(data :: any).equippedHatchFx] else nil

		local slots: { Slot } = {}
		for i, pet in shown do
			local row = (i - 1) // cols
			local col = (i - 1) % cols
			local inRow = math.min(cols, count - row * cols)
			local frame = Instance.new("Frame")
			frame.BackgroundTransparency = 1
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
			frame.Size = UDim2.fromScale(cell, cell)
			local x = (col - (inRow - 1) / 2) * cell * 1.08
			local y = 0.45 + (row - (rows - 1) / 2) * cell * 1.15
			frame.Position = UDim2.new(0.5, 0, y, 0) + UDim2.new(0, 0, 0, 0)
			frame.Parent = stage
			-- Horizontal spacing in screen-height units, converted at runtime below
			frame:SetAttribute("OffsetX", x)

			local viewport = Instance.new("ViewportFrame")
			viewport.BackgroundTransparency = 1
			viewport.Size = UDim2.fromScale(1, 1)
			viewport.ZIndex = 3
			viewport.Ambient = Color3.fromRGB(190, 190, 205)
			viewport.LightColor = Color3.new(1, 1, 1)
			viewport.LightDirection = Vector3.new(-0.4, -1, 0.6)
			viewport.Parent = frame
			local camera = Instance.new("Camera")
			camera.FieldOfView = 32
			camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, -13), Vector3.new(0, 0.6, 0))
			camera.Parent = viewport
			viewport.CurrentCamera = camera

			local tier = tierOf(pet)
			local built = PetModel.build(pet :: any)
			-- Lay the parts out, then fit the creature in the frame whatever its size (Titans too)
			PetModel.place(built, CFrame.new())
			local fit = 3.4 / math.max(built.height, built.radius * 1.6)
			built.model:SetAttribute("Fit", fit)
			local baseCFrame = CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(0, 0, -13))
			-- Happy to be out: the open "D" mouth
			for p, anim in built.anims do
				if anim == "mouthO" then
					built.parts[p].Transparency = 0
				elseif anim == "mouthC" then
					built.parts[p].Transparency = 1
				end
			end
			if pet.deleted then
				for _, p in built.parts do
					if p.Transparency < 1 then
						p.Transparency = math.max(p.Transparency, 0.6)
					end
				end
			end
			local slot: Slot = {
				frame = frame,
				viewport = viewport,
				egg = nil,
				eggMesh = nil,
				eggPart = nil,
				cracks = {},
				built = built,
				pet = pet,
				tier = tier,
				baseCFrame = baseCFrame,
				broken = false,
				shards = {},
				rays = nil,
				revealAt = breakAt + (i - 1) * (if fast then 0.02 else 0.07),
			}
			if egg then
				local model, shell, mesh, cracks = makeEgg(viewport, eggColor, legendaryEgg)
				slot.egg, slot.eggPart, slot.eggMesh, slot.cracks = model, shell, mesh, cracks
				model:PivotTo(CFrame.new(0, -6, 0))
			end
			table.insert(slots, slot)
		end

		-- Text under the best result
		local bestSlot = slots[1]
		for _, slot in slots do
			if slot.pet == best then
				bestSlot = slot
			end
		end

		local last = os.clock()
		local localTime = 0
		local shakeOffset = Vector2.zero
		local shakeUntil = 0
		local shakePower = 0
		local connection: RBXScriptConnection? = nil
		local textShown = false

		local function revealText()
			textShown = true
			if fast then
				return
			end
			local holder = bestSlot.frame
			local name = PetCard.title(best :: any)
			label(holder, name, UDim2.new(2.2, 0, 0.13, 0), UDim2.fromScale(0.5, 1.02), Color3.new(1, 1, 1), 34)
			local tier = bestSlot.tier
			if tier.label ~= "" then
				local banner = label(holder, tier.label, UDim2.new(2.4, 0, 0.2, 0), UDim2.fromScale(0.5, -0.06), tier.colors[1], 64)
				banner.Rotation = -4
				if #tier.colors > 1 then
					local shimmer = Instance.new("UIGradient")
					local keys = {}
					for k, color in tier.colors do
						table.insert(keys, ColorSequenceKeypoint.new((k - 1) / math.max(1, #tier.colors - 1), color))
					end
					shimmer.Color = ColorSequence.new(keys)
					shimmer.Parent = banner
					banner.TextColor3 = Color3.new(1, 1, 1)
					TweenService:Create(shimmer, TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
				end
				local grow = Instance.new("UIScale")
				grow.Scale = 2.2
				grow.Parent = banner
				TweenService:Create(grow, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
			local odds = oddsText(best, egg ~= nil)
			if odds and (bestLevel > 0 or string.find(odds, "in")) then
				label(holder, odds, UDim2.new(1.6, 0, 0.1, 0), UDim2.fromScale(0.5, 1.13), Color3.fromRGB(255, 225, 120), 28)
			end
			if anyNew and not best.deleted and index[best.s .. "|" .. best.v] ~= true then
				local stamp = label(holder, "NEW!", UDim2.new(0.5, 0, 0.14, 0), UDim2.fromScale(0.95, 0.12), Color3.fromRGB(255, 90, 110), 40)
				stamp.Rotation = 12
				local grow = Instance.new("UIScale")
				grow.Scale = 1.8
				grow.Parent = stamp
				TweenService:Create(grow, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
			for _, slot in slots do
				if slot.pet.deleted then
					label(slot.frame, "🗑️", UDim2.new(0.4, 0, 0.18, 0), UDim2.fromScale(0.5, 0.9), Color3.new(1, 1, 1), 30)
				end
			end
		end

		local function breakEgg(slot: Slot)
			slot.broken = true
			if slot.egg then
				slot.egg:Destroy()
				slot.egg = nil
			end
			spawnShards(slot, if fast then 4 elseif slot.tier.level == 2 then 16 elseif slot.tier.level == 1 then 10 else 6, eggColor)
			slot.built.model.Parent = slot.viewport
			-- Rays behind every rare result, and behind the best one always (not in fast mode)
			if not fast and (slot == bestSlot or slot.tier.level > 0) then
				local colors = if fx and slot.tier.level == 0 then fx.colors else slot.tier.colors
				slot.rays = makeRays(slot.frame, colors, if Store.lowEnd() then 8 else 14)
				;(slot.rays :: Frame).ZIndex = 1
				burstSparkles(slot.frame, colors, if slot.tier.level == 2 then 16 elseif slot.tier.level == 1 then 10 else 6)
			end
		end

		local function finish()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			if running ~= myRun then
				return
			end
			overlay.Interactable = false
			TweenService:Create(overlay, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
			for _, slot in slots do
				TweenService:Create(slot.frame, TweenInfo.new(0.2), { Size = UDim2.fromScale(0, 0) }):Play()
			end
			task.delay(0.22, function()
				if running == myRun then
					overlay.Visible = false
					clearStage()
				end
			end)
		end

		local played = { shake = 0, broke = false, slowUntil = 0 }

		connection = RunService.RenderStepped:Connect(function()
			local now = os.clock()
			local dt = math.min(0.05, now - last)
			last = now
			-- Slow motion right after a Titan/Legendary breaks out
			local speed = if now < played.slowUntil then 0.35 else 1
			localTime += dt * speed
			local t = localTime
			if running ~= myRun then
				if connection then
					connection:Disconnect()
				end
				return
			end

			-- Frame positions (columns spaced in screen-height units)
			local screenH = math.max(1, gui.AbsoluteSize.Y)
			for _, slot in slots do
				local offsetX = (slot.frame:GetAttribute("OffsetX") or 0) :: number
				slot.frame.Position = UDim2.new(0.5, offsetX * screenH, slot.frame.Position.Y.Scale, 0)
			end

			-- Screen shake
			if now < shakeUntil then
				shakeOffset = Vector2.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * shakePower
			else
				shakeOffset = Vector2.zero
			end
			stage.Position = UDim2.fromOffset(shakeOffset.X, shakeOffset.Y)

			for i, slot in slots do
				-- Egg: rise, shake (harder each time), squash, break
				if slot.egg and slot.eggMesh and slot.eggPart then
					local egg = slot.egg :: Model
					local mesh = slot.eggMesh :: SpecialMesh
					local tilt = 0
					local lift = 0
					if t < intro then
						lift = (1 - backOut(t / intro)) * -6
					elseif t < slot.revealAt - (if fast then 0 else 0.12) then
						local k = (t - intro) / (shakeLen + shakeGap)
						local n = math.floor(k)
						local u = (k - n) * (shakeLen + shakeGap)
						if u < shakeLen then
							local amp = 5 + (n / math.max(1, shakes - 1)) * (if bestLevel == 2 then 17 else 9)
							tilt = math.sin(u / shakeLen * math.pi * 4) * amp
							if i == 1 and played.shake <= n then
								played.shake = n + 1
								SoundClient.play("Tick")
							end
						end
						for c, crack in slot.cracks do
							crack.Transparency = if n >= c then 0 else 1
						end
						-- The tell: on the last shakes a rare egg starts glowing in its rarity colour
						if slot.tier.level > 0 and n >= shakes - 2 then
							slot.eggPart.Color = eggColor:Lerp(slot.tier.colors[1], 0.6)
							slot.eggPart.Material = Enum.Material.Neon
						end
						mesh.Scale = Vector3.new(1, 1.3, 1)
					else
						-- Squash just before the pop
						mesh.Scale = Vector3.new(1.14, 1.3 * 0.86, 1.14)
					end
					egg:PivotTo(CFrame.new(0, lift, 0) * CFrame.Angles(0, math.rad(15), math.rad(tilt)))
					if t >= slot.revealAt then
						breakEgg(slot)
						if not played.broke then
							played.broke = true
							SoundClient.play(if bestLevel > 0 then "Rare" else "Hatch")
							if not fast then
								flash.BackgroundTransparency = if bestLevel == 2 then 0 else 0.25
								TweenService:Create(flash, TweenInfo.new(if bestLevel == 2 then 0.45 else 0.25), { BackgroundTransparency = 1 }):Play()
								shakeUntil = now + (if bestLevel == 2 then 0.35 else 0.15)
								shakePower = if bestLevel == 2 then 12 else 5
							end
							if bestLevel == 2 then
								played.slowUntil = now + 0.6
								confetti(overlay, if best and tierOf(best).colors then tierOf(best).colors else RAINBOW, if Store.lowEnd() then 30 else 70)
							elseif fx and not fast then
								confetti(overlay, fx.colors, 25)
							end
						end
					end
				elseif not slot.broken and t >= slot.revealAt then
					breakEgg(slot)
				end

				-- Creature: pop with an overshoot, one full spin, then a slow turn
				if slot.broken then
					local u = (t - slot.revealAt) / (if fast then 0.22 else 0.4)
					local pop = backOut(u)
					local spinT = math.clamp((t - slot.revealAt) / 0.6, 0, 1)
					local spin = (1 - (1 - spinT) ^ 3) * math.pi * 2 + math.max(0, t - slot.revealAt - 0.6) * 0.6
					local bob = math.sin(t * 3 + i) * 0.08
					local cf = slot.baseCFrame * CFrame.new(0, bob, 0) * CFrame.Angles(0, spin, 0)
					local model = slot.built.model
					local fit = (model:GetAttribute("Fit") or 1) :: number
					if u <= 1.05 then
						model:ScaleTo(fit * math.max(0.05, pop))
					end
					model:PivotTo(cf)
				end

				-- Shell pieces fall with gravity
				for _, shard in slot.shards do
					shard.velocity += Vector3.new(0, -26, 0) * dt
					local cf = shard.part.CFrame
					shard.part.CFrame = (cf + shard.velocity * dt) * CFrame.Angles(shard.spin.X * dt, shard.spin.Y * dt, shard.spin.Z * dt)
					shard.part.Transparency = math.min(1, shard.part.Transparency + dt * 0.9)
				end

				if slot.rays then
					(slot.rays :: Frame).Rotation += dt * (if slot.tier.level == 2 then 50 else 28)
				end
			end

			if not textShown and t >= breakAt + 0.25 then
				revealText()
			end
			if t >= endAt then
				finish()
			end
		end)
	end

	Net.event("HatchResult").OnClientEvent:Connect(function(results: { { [string]: any } }, _free: boolean, eggId: number?)
		play(results, eggId)
	end)
end

return HatchPopup
