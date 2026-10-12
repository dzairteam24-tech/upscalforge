--!strict
-- An egg carried by a player (from the Wild or the Heist): held up over their head in both hands, like the big
-- stealing games do (in front of the chest it went into the body, and hid where they were running). It's welded
-- to them, so it moves with them on every screen without lagging behind; the player is marked Holding
-- (EggHands raises their arms to it) and can't hold a tool meanwhile (hands full: keepHandsFree). Released, it's
-- anchored on the ground where it fell.

local Carry = {}

local HEAD_TOP = 2.7 -- studs above the HumanoidRootPart's middle to just over the head
local LIFT = 0.15 -- gap between the head and the egg

-- How tall a part is drawn (a sphere mesh can stretch it)
local function height(part: BasePart): number
	local tall = part:GetAttribute("EggTall") -- (an egg drawn in layers, Shared/EggModel: its mesh draws nothing)
	if type(tall) == "number" then
		return part.Size.Y * tall
	end
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	return part.Size.Y * (if mesh then mesh.Scale.Y else 1)
end

-- Where the egg sits, from the root
function Carry.offset(part: BasePart): CFrame
	return CFrame.new(0, HEAD_TOP + LIFT + height(part) / 2, 0)
end

-- Puts away whatever tool the player holds (their hands are full)
function Carry.keepHandsFree(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and character:FindFirstChildOfClass("Tool") then
		humanoid:UnequipTools()
	end
end

function Carry.hold(part: BasePart, player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	Carry.release(part, nil)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CFrame = root.CFrame * Carry.offset(part)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "InHands"
	weld.Part0, weld.Part1 = root, part
	weld.Parent = part
	player:SetAttribute("Holding", true)
	Carry.keepHandsFree(player)
	return true
end

-- Lets go of it: on the ground at `at` (or where it is), and its last holder's hands are free again
function Carry.release(part: BasePart, at: Vector3?, holder: Player?)
	local weld = part:FindFirstChild("InHands")
	if weld then
		weld:Destroy()
	end
	part.Anchored = true
	part.CanQuery = true
	if at then
		part.CFrame = CFrame.new(at)
	end
	if holder then
		holder:SetAttribute("Holding", nil)
	end
end

return Carry
