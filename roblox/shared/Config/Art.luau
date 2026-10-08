--!strict
-- 3D art settings.
--
-- CREATURE_MODELS_ASSET_ID: the Roblox model that holds every creature's 3D parts (import
-- art/models/Cubelings_Roblox.glb in Studio, right-click the model > Save to Roblox, paste its ID here).
-- The server loads it at start into ReplicatedStorage.CreatureModels. 0 = not uploaded yet: creatures are
-- drawn with blocks, or with a CreatureModels folder you put in ReplicatedStorage yourself.

--
-- MAP_ART_ASSET_ID: the Roblox model that holds the designed map pieces (docs/map-art.md). Build them in
-- Studio at their real place on the map, inside one model, right-click > Save to Roblox, paste its ID here.
-- The server loads it into Workspace.MapArt. A child named "Zone_3" replaces zone 3's block trees.
-- 0 = none yet: the map keeps its block decorations.
--
-- SADDLE_ASSET_ID, PONY_ASSET_ID: the Cubeling Ride's saddle and pony body (import art/models/Saddle.glb and
-- art/models/Pony.glb in Studio, right-click each model > Save to Roblox, paste their IDs here). The server
-- loads them into ReplicatedStorage. 0 = not uploaded yet: rides use a saddle/pony model put directly in
-- ReplicatedStorage by hand (any name: RideModel finds them by their Saddle__/Pony__ parts, the newest
-- winning), or else the saddle made of parts and the reshaped creature.

return {
	CREATURE_MODELS_ASSET_ID = 91371129157419,
	MAP_ART_ASSET_ID = 0,
	SADDLE_ASSET_ID = 98611574786833,
	PONY_ASSET_ID = 83201461968098,
}
