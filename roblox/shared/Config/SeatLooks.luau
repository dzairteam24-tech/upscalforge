--!strict
-- The floating seats' models as exported (written by art/blender/seats.py roblox; don't edit by hand): per
-- seat, in zone order, its reference part's box in the file (front +Z, studs), where the rider sits and the
-- seat's underside (above its bottom), and the color of each part role. SeatModel draws them; Cosmetics
-- makes a ride of each.

export type Look = {
	name: string,
	title: string,
	zone: number,
	model: { ref: string, center: Vector3, size: Vector3 },
	top: number,
	bottom: number,
	colors: { [string]: Color3 },
	glow: { [string]: boolean },
	light: Color3,
}

local looks: { Look } = {
	{
		name = "Cloud",
		title = "Cloud Seat",
		zone = 1,
		model = { ref = "body", center = Vector3.new(0.035, 0.934, -0.000), size = Vector3.new(3.488, 1.113, 2.954) },
		top = 0.969,
		bottom = 0.038,
		colors = {
			blush = Color3.fromRGB(255, 177, 202),
			body = Color3.fromRGB(251, 251, 255),
			earin = Color3.fromRGB(255, 194, 217),
			eye = Color3.fromRGB(52, 43, 52),
			mouth = Color3.fromRGB(81, 52, 52),
			shade = Color3.fromRGB(220, 222, 253),
			shine = Color3.fromRGB(255, 255, 255),
			star = Color3.fromRGB(255, 220, 90),
		},
		glow = { },
		light = Color3.fromRGB(255, 224, 243),
	},
	{
		name = "Blossom",
		title = "Blossom Seat",
		zone = 2,
		model = { ref = "petal", center = Vector3.new(0.000, 0.720, -0.000), size = Vector3.new(3.197, 1.222, 3.470) },
		top = 1.098,
		bottom = 0.000,
		colors = {
			blush = Color3.fromRGB(255, 177, 202),
			center = Color3.fromRGB(255, 230, 117),
			eye = Color3.fromRGB(52, 43, 52),
			leaf = Color3.fromRGB(148, 220, 128),
			mouth = Color3.fromRGB(81, 52, 52),
			petal = Color3.fromRGB(255, 172, 205),
			pollen = Color3.fromRGB(255, 189, 81),
			sepal = Color3.fromRGB(104, 177, 104),
			shine = Color3.fromRGB(255, 255, 255),
		},
		glow = { },
		light = Color3.fromRGB(255, 224, 243),
	},
}

return looks
