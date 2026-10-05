--!strict
-- 3D art settings.
--
-- CREATURE_MODELS_ASSET_ID: the Roblox model that holds every creature's 3D parts (import
-- art/models/Cubelings_Roblox.glb in Studio, right-click the model > Save to Roblox, paste its ID here).
-- The server loads it at start into ReplicatedStorage.CreatureModels. 0 = not uploaded yet: creatures are
-- drawn with blocks, or with a CreatureModels folder you put in ReplicatedStorage yourself.

return {
	CREATURE_MODELS_ASSET_ID = 0,
}
