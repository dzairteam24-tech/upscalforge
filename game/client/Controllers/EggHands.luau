--!strict
-- Players carrying an egg (marked Holding: Shared/Carry) hold it with both arms out in front of them, on every
-- screen: their shoulders and elbows bent after the animations each frame (not while sitting on a seat).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local EggHands = {}

local ARMS = { -- joint -> its bend: arms forward, a little inward, elbows slightly bent
	RightShoulder = CFrame.Angles(math.rad(80), 0, math.rad(18)),
	LeftShoulder = CFrame.Angles(math.rad(80), 0, math.rad(-18)),
	RightElbow = CFrame.Angles(math.rad(15), 0, 0),
	LeftElbow = CFrame.Angles(math.rad(15), 0, 0),
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
	jointCache[character] = found
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
