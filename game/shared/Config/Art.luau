--!strict
-- The 3D art's Roblox models (art/models). Each is imported in Studio, saved to Roblox, and its id pasted
-- here; ArtService loads them into ReplicatedStorage when the server starts. 0 = not uploaded: the game
-- draws a plain stand-in instead.
--
-- CREATURE_MODELS_ASSET_ID: every creature's parts (art/models/Cubelings_Roblox.glb), for PetModel.
-- SEATS_ASSET_ID: the floating seats (art/models/Seats.glb), for SeatModel.
-- PROPS_ASSET_ID: the decor props (art/models/Decor.glb), placed round the islands (PropService).
-- TOWN_ASSET_ID: the town (art/models/Town.glb: the six buildings and the town's decor), for WorldService.

return {
	CREATURE_MODELS_ASSET_ID = 91371129157419,
	SEATS_ASSET_ID = 139829960209417,
	PROPS_ASSET_ID = 108089715600870,
	TOWN_ASSET_ID = 120341614662158,
}
