--!strict
-- Each farmer's tractor, for the long roads between the farms and the town. It's a brick model on a flat sliding
-- base: the driver's phone steers it (it owns its physics while they drive), so it never tips or gets stuck. Only
-- its farmer can drive it; "call" brings it to them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.Logic.Layout)
local Net = require(Shared.Net)

local TractorService = {}

local rgb = Color3.fromRGB
local GREEN = rgb(75, 151, 75)
local YELLOW = rgb(245, 205, 48)
local BLACK = rgb(27, 42, 53)
local GRAY = rgb(99, 95, 98)

local tractors: { [Player]: Model } = {}

-- The tractor: everything welded to its base, which carries the movers
function TractorService.build(at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Tractor"
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(6, 1.2, 10)
	base.Color = BLACK
	base.Material = Enum.Material.Plastic
	base.TopSurface = Enum.SurfaceType.Studs
	base.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0, 100, 100) -- (slides on the ground, no bounce)
	base.CFrame = at * CFrame.new(0, 1.2, 0)
	base.Parent = model
	model.PrimaryPart = base
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.Plastic
		p.TopSurface = Enum.SurfaceType.Studs
		p.CanCollide = false
		p.Massless = true
		if shape then
			p.Shape = shape
		end
		p.CFrame = base.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = base
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
		return p
	end
	piece("Hood", Vector3.new(4, 2.6, 5), CFrame.new(0, 1.9, -2.2), GREEN)
	piece("Grill", Vector3.new(3.6, 2, 0.4), CFrame.new(0, 1.8, -4.8), GRAY)
	piece("Body", Vector3.new(5, 1.4, 4.6), CFrame.new(0, 1.3, 2.4), GREEN)
	piece("Fender", Vector3.new(6.6, 0.5, 3.6), CFrame.new(0, 3.3, 3), GREEN)
	piece("Exhaust", Vector3.new(3, 0.6, 0.6), CFrame.new(1.4, 4.5, -3.2) * CFrame.Angles(0, 0, math.pi / 2), GRAY, Enum.PartType.Cylinder)
	piece("SteeringWheel", Vector3.new(0.4, 2.2, 2.2), CFrame.new(-2.2, 2.6, 1.2) * CFrame.Angles(math.rad(-30), 0, 0), BLACK, Enum.PartType.Cylinder)
	for _, side in { -1, 1 } do
		-- (the base rests 0.6 above the ground; the wheels reach down to it)
		piece("BigWheel", Vector3.new(1.6, 5, 5), CFrame.new(side * 3.6, 1.9, 3), BLACK, Enum.PartType.Cylinder)
		piece("BigHub", Vector3.new(1.7, 2.4, 2.4), CFrame.new(side * 3.6, 1.9, 3), YELLOW, Enum.PartType.Cylinder)
		piece("SmallWheel", Vector3.new(1.2, 2.8, 2.8), CFrame.new(side * 2.6, 0.8, -3.4), BLACK, Enum.PartType.Cylinder)
		piece("SmallHub", Vector3.new(1.3, 1.2, 1.2), CFrame.new(side * 2.6, 0.8, -3.4), YELLOW, Enum.PartType.Cylinder)
		piece("Light", Vector3.new(0.8, 0.8, 0.3), CFrame.new(side * 1.2, 2.6, -4.85), rgb(253, 234, 141)).Material = Enum.Material.Neon
	end
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2.4, 0.6, 2.4)
	seat.Color = YELLOW
	seat.Material = Enum.Material.Plastic
	seat.CanCollide = false
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- (the driver's phone moves it, not the seat)
	seat.Torque = 0
	seat.CFrame = base.CFrame * CFrame.new(0, 2.4, 2.6)
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = base
	seatWeld.Part1 = seat
	seatWeld.Parent = seat
	seat.Parent = model
	piece("SeatBack", Vector3.new(2.4, 2, 0.5), CFrame.new(0, 3.6, 3.9), YELLOW)
	-- the movers: a velocity along the ground (up and down left to gravity), and a turn that also keeps it upright
	local attachment = Instance.new("Attachment")
	attachment.Name = "Mover"
	attachment.Parent = base
	local move = Instance.new("LinearVelocity")
	move.Name = "Move"
	move.Attachment0 = attachment
	move.RelativeTo = Enum.ActuatorRelativeTo.World
	move.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	move.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	move.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	move.PlaneVelocity = Vector2.new(0, 0)
	move.MaxForce = 1e6
	move.Parent = base
	local turn = Instance.new("AngularVelocity")
	turn.Name = "Turn"
	turn.Attachment0 = attachment
	turn.RelativeTo = Enum.ActuatorRelativeTo.World
	turn.AngularVelocity = Vector3.zero
	turn.MaxTorque = 1e7
	turn.Parent = base
	return model
end

local function stop(model: Model)
	local base = model.PrimaryPart
	local move = base and base:FindFirstChild("Move") :: LinearVelocity?
	local turn = base and base:FindFirstChild("Turn") :: AngularVelocity?
	if move then
		move.PlaneVelocity = Vector2.new(0, 0)
	end
	if turn then
		turn.AngularVelocity = Vector3.zero
	end
end

-- Gives a farmer their tractor, by their farm's gate
function TractorService.give(player: Player, farm: number): Model
	TractorService.remove(player)
	local model = TractorService.build(Layout.tractor(farm))
	model:SetAttribute("Owner", player.UserId)
	model.Name = "Tractor_" .. player.UserId
	local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		local base = model.PrimaryPart :: BasePart
		if not occupant then
			stop(model)
			pcall(function()
				base:SetNetworkOwnershipAuto()
			end)
			return
		end
		local driver = Players:GetPlayerFromCharacter(occupant.Parent)
		if driver ~= player then
			-- (only its farmer drives it)
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
			occupant.Sit = false
			if driver then
				Net.event("Notify"):FireClient(driver, "That's someone else's tractor", "bad")
			end
			return
		end
		pcall(function()
			base:SetNetworkOwner(player)
		end)
	end)
	model.Parent = workspace
	tractors[player] = model
	return model
end

function TractorService.remove(player: Player)
	local model = tractors[player]
	if model then
		model:Destroy()
		tractors[player] = nil
	end
end

function TractorService.of(player: Player): Model?
	return tractors[player]
end

-- Brings their tractor to them (when nobody's in it)
function TractorService.call(player: Player): boolean
	local model = tractors[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not model or not root or not root:IsA("BasePart") then
		return false
	end
	local seat = model:FindFirstChild("DriverSeat") :: VehicleSeat?
	if seat and seat.Occupant then
		return false
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	local at = root.CFrame.Position + root.CFrame.RightVector * 8
	stop(model)
	model:PivotTo(CFrame.lookAt(Vector3.new(at.X, 1.2, at.Z), Vector3.new(at.X, 1.2, at.Z) + flat.Unit))
	return true
end

-- `farmOf(player)` (FarmService)
function TractorService.init(farmOf: (Player) -> number?, onLoaded: ((Player, any) -> ()) -> (), onLeaving: ((Player) -> ()) -> ())
	Net.event("CallTractor").OnServerEvent:Connect(TractorService.call)
	onLoaded(function(player)
		local farm = farmOf(player)
		if farm then
			TractorService.give(player, farm)
		end
	end)
	onLeaving(TractorService.remove)
end

return TractorService
