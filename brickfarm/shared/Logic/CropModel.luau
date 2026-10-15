--!strict
-- What a crop looks like at each stage, as a list of bricks (size, where its middle is above the tile's middle,
-- color, and whether it's the fruit). The phones build these; nothing needs drawing or animating by hand.

local Crops = require(script.Parent.Parent.Config.Crops)

export type Brick = { size: Vector3, at: Vector3, color: Color3, fruit: boolean, round: boolean? }

local CropModel = {}

CropModel.SCALE = 1.3 -- (the shapes below are drawn small; this makes them read well from a phone)

local STEM = Color3.fromRGB(39, 70, 45)

local function brick(list: { Brick }, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, fruit: boolean?, round: boolean?)
	table.insert(list, { size = Vector3.new(sx, sy, sz), at = Vector3.new(x, y, z), color = color, fruit = fruit == true, round = round })
end

-- A sprout: the same for every crop (two little leaves)
local function sprout(list: { Brick }, crop: Crops.Crop)
	brick(list, 0.3, 0.6, 0.3, 0, 0.3, 0, STEM)
	brick(list, 0.8, 0.25, 0.5, -0.4, 0.65, 0, crop.leaf)
	brick(list, 0.8, 0.25, 0.5, 0.4, 0.75, 0, crop.leaf)
end

local function root(list: { Brick }, crop: Crops.Crop, stage: number)
	local h = ({ 0, 1.4, 2, 2.4 })[stage]
	for i, a in { 0, 2.1, 4.2 } do
		local lean = 0.35
		brick(list, 0.35, h, 0.35, math.cos(a) * lean, h / 2 + 0.2, math.sin(a) * lean, crop.leaf)
		if stage >= 3 and i == 1 then
			brick(list, 0.7, 0.3, 0.7, 0, h + 0.2, 0, crop.leaf)
		end
	end
	if stage >= 3 then
		local s = if stage == 4 then 1.6 else 1.1
		brick(list, s, s * 0.5, s, 0, s * 0.25, 0, crop.fruit, true) -- (its top, out of the soil)
	end
end

local function bush(list: { Brick }, crop: Crops.Crop, stage: number)
	local s = ({ 0, 1.6, 2.4, 2.8 })[stage]
	brick(list, 0.4, 0.8, 0.4, 0, 0.4, 0, STEM)
	brick(list, s, s * 0.75, s, 0, 0.6 + s * 0.375, 0, crop.leaf)
	brick(list, s * 0.6, s * 0.35, s * 0.6, 0, 0.6 + s * 0.75 + s * 0.17, 0, crop.leaf)
	if stage >= 3 then
		local spots = { { 1, 0.45, 0 }, { -1, 0.6, 0.2 }, { 0, 0.35, 1 }, { 0.2, 0.8, -1 }, { -0.7, 0.3, -0.7 }, { 0.7, 0.75, 0.7 } }
		local n = if stage == 4 then #spots else 3
		local size = if stage == 4 then 0.75 else 0.45
		for i = 1, n do
			local spot = spots[i]
			brick(list, size, size, size, spot[1] * s / 2, 0.6 + spot[2] * s * 0.75, spot[3] * s / 2, if stage == 4 then crop.fruit else crop.leaf:Lerp(crop.fruit, 0.35), true)
		end
	end
end

local function stalk(list: { Brick }, crop: Crops.Crop, stage: number)
	local h = ({ 0, 2.2, 3.6, 5 })[stage]
	brick(list, 0.5, h, 0.5, 0, h / 2, 0, crop.leaf)
	for i = 1, stage do
		local y = h * i / (stage + 1)
		local side = if i % 2 == 0 then 1 else -1
		brick(list, 1.4, 0.25, 0.45, side * 0.9, y, 0, crop.leaf)
	end
	if stage == 4 then
		brick(list, 0.8, 1.8, 0.8, 0.6, h * 0.6, 0, crop.fruit, true)
		brick(list, 0.8, 1.6, 0.8, -0.6, h * 0.45, 0.2, crop.fruit, true)
		brick(list, 0.3, 0.6, 0.3, 0, h + 0.3, 0, crop.fruit:Lerp(Color3.new(1, 1, 1), 0.3))
	elseif stage == 3 then
		brick(list, 0.6, 1.1, 0.6, 0.55, h * 0.6, 0, crop.leaf:Lerp(crop.fruit, 0.4), true)
	end
end

local function vine(list: { Brick }, crop: Crops.Crop, stage: number)
	local spread = ({ 0, 2, 3, 3.4 })[stage]
	for _, offset in { { 1, 0.6 }, { -1, -0.4 }, { 0.3, -1 }, { -0.5, 1 } } do
		brick(list, 1.2, 0.3, 1.2, offset[1] * spread / 2, 0.25, offset[2] * spread / 2, crop.leaf)
	end
	if stage >= 3 then
		local s = if stage == 4 then 2.6 else 1.3
		brick(list, s, s * 0.8, s, 0.2, s * 0.4, 0.1, crop.fruit, true, true)
		brick(list, 0.3, 0.5, 0.3, 0.2, s * 0.8 + 0.25, 0.1, STEM)
	end
end

local function flower(list: { Brick }, crop: Crops.Crop, stage: number)
	local h = ({ 0, 2, 3.8, 5.2 })[stage]
	brick(list, 0.45, h, 0.45, 0, h / 2, 0, crop.leaf)
	brick(list, 1.3, 0.25, 0.6, 0.7, h * 0.4, 0, crop.leaf)
	brick(list, 1.3, 0.25, 0.6, -0.7, h * 0.6, 0, crop.leaf)
	if stage >= 3 then
		local head = if stage == 4 then 1.5 else 0.8
		brick(list, head, head, 0.5, 0, h + head / 2, -0.25, Color3.fromRGB(105, 64, 40), true)
		if stage == 4 then
			for i = 0, 7 do
				local a = i / 8 * math.pi * 2
				brick(list, 0.8, 0.8, 0.3, math.cos(a) * 1.25, h + 0.75 + math.sin(a) * 1.25, -0.2, crop.fruit, true)
			end
		end
	end
end

local SHAPES = { root = root, bush = bush, stalk = stalk, vine = vine, flower = flower }

-- The bricks of a crop at a stage (1..4)
function CropModel.bricks(key: string, stage: number): { Brick }
	local crop = Crops.byKey[key]
	local list: { Brick } = {}
	if not crop then
		return list
	end
	if stage <= 1 then
		sprout(list, crop)
	else
		SHAPES[crop.shape](list, crop, math.clamp(stage, 2, 4))
	end
	for _, b in list do
		b.size *= CropModel.SCALE
		b.at *= CropModel.SCALE
	end
	return list
end

return CropModel
