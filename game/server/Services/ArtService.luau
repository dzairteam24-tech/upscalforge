--!strict
-- Loads the 3D art (Config/Art) from Roblox into ReplicatedStorage: the creatures (for PetModel), the seats,
-- the decor props and the town. A model that fails to load is only a warning: the game draws stand-ins.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared.Config.Art)
local PetModel = require(Shared.PetModel)

local ArtService = {}

-- Loads a saved model into ReplicatedStorage.<name> (unless one was placed there by hand) and returns it
local function load(name: string, id: number): Instance?
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	if id == 0 then
		return nil
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok or not result then
		warn("[Art] Couldn't load " .. name .. ":", result)
		return nil
	end
	-- LoadAsset wraps the saved model in another one
	local model: Instance = result
	local children = result:GetChildren()
	if #children == 1 and not children[1]:IsA("BasePart") then
		model = children[1]
	end
	model.Name = name
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model.Parent = ReplicatedStorage
	if model ~= result then
		result:Destroy()
	end
	print("[Art] " .. name .. " loaded")
	return model
end

-- Starts every load; `onLoaded(name, model)` is called as each arrives
function ArtService.init(onLoaded: (string, Instance) -> ())
	local models: { [string]: number } = {
		CreatureModels = Art.CREATURE_MODELS_ASSET_ID,
		SeatsModel = Art.SEATS_ASSET_ID,
		PropsModel = Art.PROPS_ASSET_ID,
		TownModel = Art.TOWN_ASSET_ID,
	}
	for name, id in models do
		task.spawn(function()
			local model = load(name, id)
			if model then
				if name == "CreatureModels" then
					PetModel.reset()
				end
				onLoaded(name, model)
			end
		end)
	end
end

return ArtService
