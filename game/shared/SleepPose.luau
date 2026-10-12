--!strict
-- How a creature (PetModel) sleeps: each animal its own way (Config/Wild SLEEP_POSES), not just lying down. Used
-- for the Wild's guardians, asleep by their nests (WildService), with their eyes shut and breathing slowly.
--   side: rolled over on its side      back: on its back, feet up
--   loaf: lying with its legs tucked under (it sinks into itself)
--   curl: curled up, head down         sit: sitting low, as on a nest
-- (cube creatures: a pose is the whole body turned or squashed, the eyes shut to thin lines)

local SleepPose = {}

-- The sizes of a built creature's parts as made (a pose squashes them; waking puts them back)
function SleepPose.sizes(parts: { BasePart }): { Vector3 }
	local sizes = {}
	for i, p in parts do
		sizes[i] = p.Size
	end
	return sizes
end

-- Lays a built creature down asleep: base is the spot on the ground it sleeps on, facing the way it faces; breath
-- (-1 to 1, slowly back and forth) lifts and fills it a little
function SleepPose.place(built: any, base: CFrame, pose: string, breath: number, sizes: { Vector3 })
	local squash = 1
	local turn: CFrame
	if pose == "back" then
		turn = CFrame.Angles(0, 0, math.pi)
	elseif pose == "loaf" then
		squash = 0.7 + breath * 0.03
		turn = CFrame.identity
	elseif pose == "curl" then
		turn = CFrame.Angles(math.rad(-28), math.rad(25), math.rad(12))
	elseif pose == "sit" then
		squash = 0.82 + breath * 0.03
		turn = CFrame.Angles(math.rad(8), 0, 0)
	else -- "side"
		turn = CFrame.Angles(0, 0, math.rad(90))
	end
	-- (posed round the spot first, then set down so its lowest point just touches the ground, breathing)
	local frame = base * turn
	local lowest = math.huge
	for i, p in built.parts do
		local offset = built.offsets[i]
		local size = sizes[i] or p.Size
		local shut = p.Name == "Eye" or p.Name == "Shine" -- (eyes shut: thin lines)
		p.Size = Vector3.new(size.X, size.Y * squash * (if shut then 0.15 else 1), size.Z)
		p.CFrame = frame * CFrame.new(offset.X, offset.Y * squash, offset.Z) * offset.Rotation
		if p.Transparency < 1 then
			local half = p.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						lowest = math.min(lowest, (p.CFrame * Vector3.new(half.X * x, half.Y * y, half.Z * z)).Y)
					end
				end
			end
		end
	end
	local lift = base.Position.Y - lowest + (if pose == "back" or pose == "side" or pose == "curl" then math.max(0, breath) * 0.06 * built.height else 0)
	for _, p in built.parts do
		p.CFrame += Vector3.new(0, lift, 0)
	end
end

-- Awake again: its parts back to their sizes (then it's placed standing, PetModel.place)
function SleepPose.wake(built: any, sizes: { Vector3 })
	for i, p in built.parts do
		if sizes[i] then
			p.Size = sizes[i]
		end
	end
end

return SleepPose
