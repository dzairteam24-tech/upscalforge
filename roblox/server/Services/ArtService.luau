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

-- Designed map pieces (Config/Art MAP_ART_ASSET_ID), built in Studio at their real place on the map.
-- A child named "Zone_<id>" takes the place of that zone's block decorations.
local function loadMapArt()
	if workspace:FindFirstChild("MapArt") or Art.MAP_ART_ASSET_ID == 0 then
		return
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(Art.MAP_ART_ASSET_ID)
	end)
	if not ok or not result then
		warn("[Art] Couldn't load the map art:", result)
		return
	end
	-- LoadAsset wraps the saved model in another one: unwrap it (the saved model should be named MapArt)
	local art: Instance = result:FindFirstChild("MapArt", true) or result
	local children = art:GetChildren()
	if art == result and #children == 1 and children[1]:IsA("Model") and not string.match(children[1].Name, "^Zone_%d+$") then
		art = children[1]
	end
	art.Name = "MapArt"
	for _, d in art:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local world = workspace:WaitForChild("World")
	for _, child in art:GetChildren() do
		local zone = world:FindFirstChild(child.Name)
		if zone and string.match(child.Name, "^Zone_%d+$") then
			for _, piece in zone:GetChildren() do
				if piece.Name == "Decor" then
					piece:Destroy()
				end
			end
		end
	end
	art.Parent = workspace
	if art ~= result then
		result:Destroy()
	end
	print("[Art] Map art loaded")
end

-- A Cubeling Ride model (Config/Art SADDLE_ASSET_ID, PONY_ASSET_ID) into ReplicatedStorage.<name> (RideModel)
local function loadRideArt(name: string, id: number)
	-- (added last, so it wins over a model placed by hand: RideModel uses the newest)
	if id == 0 then
		return
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok or not result then
		warn("[Art] Couldn't load " .. name .. ":", result)
		return
	end
	local model: Instance = result:FindFirstChild(name, true) or result
	model.Name = name
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	model.Parent = ReplicatedStorage
	if model ~= result then
		result:Destroy()
	end
	print("[Art] " .. name .. " loaded")
end

function ArtService.init()
	task.spawn(loadMapArt)
	task.spawn(loadRideArt, "SaddleModel", Art.SADDLE_ASSET_ID)
	task.spawn(loadRideArt, "PonyModel", Art.PONY_ASSET_ID)
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
