# Meshy prop sheets (6 props each, split into separate props when they're brought into the game)

| File | Props (in order) | Status |
|------|------------------|--------|
| props_meadow.glb | Tree, Bush, Fence, Flowers, MossRock, BigFlower | good (tree trunk a bit orange) |
| props_forest.glb | Tulip (open), Beehive, Pine, Log, Stump, Fern | good |
| props_beach.glb | Umbrella, Seashell (pearl), PalmTree, Rowboat, SandCastle, Starfish | good |
| props_cave.glb | GiantMushroom, GlowShrooms, CrystalCluster, CaveBoulder, Stalagmite, RedMushroom | good; pairs touch, so the split joins them in 3 (split them apart) |
| props_desert.glb | Pyramid, BarrelCactus, Cactus, BrokenColumn, SandRock, Skull | good |
| props_snow.glb | SnowyPine, Cabin, Snowman, SnowRock, SnowPile, Sled | good |
| props_volcano.glb | LavaRock, LavaPool, BurntTree, SteamVent, MiniVolcano, EmberRocks | good |
| props_ice.glb | IceCrystals, IceBlock, SnowBank, FrozenTree, IcePillar, IceShards | good |
| props_pixel.glb | NeonCube, ArcadeScreen, PixelHeart, PixelTree, PixelFlower, GridPillar | only ArcadeScreen and PixelHeart are usable: Meshy broke up the small cubes of the others (redo them) |
| props_town.glb | Archway, Hedge, FlowerPlanter, StreetLamp, Bench, CatFountain | good (the town's decor) |
| building_cottage.glb | the town building (blank plaque on the roof) | good: art/blender/buildings.py makes six roof colors (art/models/Buildings.glb); the logos for the plaques are yours to design |

To redo later: props_cave (its props overlap in the file: GiantMushroom, GlowShrooms and CrystalCluster come out broken, so Decor.glb has only Stalagmite, CaveBoulder and RedMushroom). Generate it again with more space between the six.

## The style for every new design (ChatGPT image, then Meshy Image to 3D)

Elegant and minimal: very simple clean silhouettes, smooth rounded forms, ONE signature element per object, no
clutter (no crates, boxes, gifts, signs, lanterns, flags, bushes, small decorations, text), one cohesive soft
pastel palette with small gold accents, smooth matte plastic look, 3/4 view from slightly above, plain white
background. Meshy: Smart Topology, poly count 15000, Texture on, Pose off, export GLB.
