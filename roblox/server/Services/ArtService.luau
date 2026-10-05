-- Loads the creatures' 3D models (Config/Art) into ReplicatedStorage.CreatureModels so every client can
-- clone them. Without them the game draws creatures with blocks, so a failed load is only a warning.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared.Config.Art)
local PetModel = require(Shared.PetModel)

local ArtService = {}

-- The saved model may be the imported model itself, or a model that has it inside.
local function findCreatures(root: Instance): Instance
	local named = root:FindFirstChild("CreatureModels", true)
	if named then
		return named
	end
	local children = root:GetChildren()
	if #children == 1 and not children[1]:IsA("BasePart") then
		return children[1]
	end
	return root
end

function ArtService.init()
	if ReplicatedStorage:FindFirstChild("CreatureModels") then
		return -- placed by hand in Studio
	end
	if Art.CREATURE_MODELS_ASSET_ID == 0 then
		return
	end
	task.spawn(function()
		local ok, result = pcall(function()
			return InsertService:LoadAsset(Art.CREATURE_MODELS_ASSET_ID)
		end)
		if not ok or not result then
			warn("[Art] Couldn't load the creature models:", result)
			return
		end
		local creatures = findCreatures(result)
		creatures.Name = "CreatureModels"
		-- Hide the source parts: they are only templates to clone
		for _, d in creatures:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		creatures.Parent = ReplicatedStorage
		if creatures ~= result then
			result:Destroy()
		end
		PetModel.reset()
		print("[Art] Creature models loaded")
	end)
end

return ArtService
