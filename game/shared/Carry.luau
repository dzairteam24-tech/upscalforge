--!strict
-- An egg carried in a player's hands (from the Wild or the Heist): welded in front of their chest, so it moves
-- with them on every screen without lagging behind, and the player is marked Holding (EggHands raises their arms
-- to hold it). Released, it's anchored on the ground where it fell.

local Carry = {}

local IN_HANDS = CFrame.new(0, 0.1, -1.7) -- from the player's HumanoidRootPart

function Carry.hold(part: BasePart, player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	Carry.release(part, nil)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CFrame = root.CFrame * IN_HANDS
	local weld = Instance.new("WeldConstraint")
	weld.Name = "InHands"
	weld.Part0, weld.Part1 = root, part
	weld.Parent = part
	player:SetAttribute("Holding", true)
	return true
end

-- Lets go of it: on the ground at `at` (or where it is), and its last holder's hands are free again
function Carry.release(part: BasePart, at: Vector3?, holder: Player?)
	local weld = part:FindFirstChild("InHands")
	if weld then
		weld:Destroy()
	end
	part.Anchored = true
	if at then
		part.CFrame = CFrame.new(at)
	end
	if holder then
		holder:SetAttribute("Holding", nil)
	end
end

return Carry
