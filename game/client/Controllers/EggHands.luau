--!strict
-- Players carrying an egg (marked Holding: Shared/Carry) hold it up over their head in both hands, on every
-- screen: their shoulders and elbows set after the animations each frame (not while sitting on a seat), so the
-- arms stay up while they run. R15 and R6 bodies both.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local EggHands = {}

local ARMS = { -- joint -> its bend: arms straight up, a little apart, elbows bent in round the egg
	-- R15
	RightShoulder = CFrame.Angles(math.rad(168), 0, math.rad(-12)),
	LeftShoulder = CFrame.Angles(math.rad(168), 0, math.rad(12)),
	RightElbow = CFrame.Angles(math.rad(12), 0, math.rad(20)),
	LeftElbow = CFrame.Angles(math.rad(12), 0, math.rad(-20)),
	-- R6 (its shoulders turn round their Z axis)
	["Right Shoulder"] = CFrame.Angles(0, 0, math.rad(165)),
	["Left Shoulder"] = CFrame.Angles(0, 0, math.rad(-165)),
}

local jointCache: { [Model]: { [string]: Instance } } = setmetatable({}, { __mode = "k" }) :: any

local function joints(character: Model): { [string]: Instance }
	local cached = jointCache[character]
	if cached then
		return cached
	end
	local found: { [string]: Instance } = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and ARMS[d.Name] and not found[d.Name] then
			found[d.Name] = d
		end
	end
	if next(found) then -- (not before the body has its joints)
		jointCache[character] = found
	end
	return found
end

function EggHands.init()
	RunService.Stepped:Connect(function()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local seat = player:GetAttribute("RideSeat")
			if character and player:GetAttribute("Holding") == true and (seat == nil or seat == "") then
				for name, joint in joints(character) do
					(joint :: any).Transform = ARMS[name]
				end
			end
		end
	end)
end

return EggHands
