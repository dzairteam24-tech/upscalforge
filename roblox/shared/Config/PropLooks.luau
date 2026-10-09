--!strict
-- The map props' models as exported (written by art/blender/props.py roblox; don't edit by hand): per prop,
-- its size in studs (as modeled: Y up) and the zones it decorates. PropService places them.

export type Look = { name: string, size: Vector3, zones: { number } }

local looks: { Look } = {
	{ name = "Bush", size = Vector3.new(8.92, 6.00, 7.82), zones = { 1, 2 } },
	{ name = "Tree", size = Vector3.new(16.08, 16.00, 15.18), zones = { 1, 3 } },
	{ name = "Fence", size = Vector3.new(6.26, 5.00, 4.06), zones = { 1 } },
	{ name = "Flowers", size = Vector3.new(5.69, 4.00, 4.89), zones = { 1, 2 } },
	{ name = "MossRock", size = Vector3.new(7.19, 5.00, 7.26), zones = { 1 } },
	{ name = "Tulip", size = Vector3.new(6.67, 7.00, 5.24), zones = { 2 } },
	{ name = "BigFlower", size = Vector3.new(8.36, 8.00, 7.34), zones = { 2 } },
	{ name = "Beehive", size = Vector3.new(6.09, 9.00, 4.62), zones = { 2 } },
	{ name = "Stump", size = Vector3.new(9.97, 5.00, 10.57), zones = { 3 } },
	{ name = "Fern", size = Vector3.new(9.45, 5.00, 10.14), zones = { 3 } },
	{ name = "Pine", size = Vector3.new(18.62, 18.00, 18.00), zones = { 3 } },
	{ name = "Log", size = Vector3.new(8.21, 4.00, 5.97), zones = { 3 } },
}

return looks
