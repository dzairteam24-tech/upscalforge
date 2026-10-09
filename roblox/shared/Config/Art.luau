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
-- SEATS_ASSET_ID: the floating seats (import art/models/Seats.glb in Studio, Save to Roblox, paste its ID
-- here). The server loads it into ReplicatedStorage; until then seats are drawn as a plain cloud of balls.
--
-- PROPS_ASSET_ID: the map props (import art/models/Props.glb in Studio, Save to Roblox, paste its ID here).
-- The server loads it into ReplicatedStorage and PropService places them along the zones' edges in place of
-- the block trees. 0 = not uploaded yet: the block trees stay (or a props model put in ReplicatedStorage).

return {
	CREATURE_MODELS_ASSET_ID = 91371129157419,
	MAP_ART_ASSET_ID = 0,
	SEATS_ASSET_ID = 139829960209417,
	PROPS_ASSET_ID = 0,
}
