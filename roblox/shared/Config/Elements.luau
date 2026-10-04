--!strict
-- Zone elements. A variant is x2 stronger in the element listed as its `strongIn`.

export type Element = {
	id: string,
	label: string,
	color: Color3,
}

local list: { Element } = {
	{ id = "Neutral", label = "Neutral", color = Color3.fromRGB(138, 148, 166) },
	{ id = "Fire", label = "Fire", color = Color3.fromRGB(240, 100, 45) },
	{ id = "Ice", label = "Ice", color = Color3.fromRGB(79, 179, 232) },
	{ id = "Dark", label = "Dark", color = Color3.fromRGB(107, 78, 154) },
	{ id = "Pixel", label = "Pixel", color = Color3.fromRGB(142, 91, 217) },
	{ id = "Treasure", label = "Treasure", color = Color3.fromRGB(232, 181, 58) },
}

local byId: { [string]: Element } = {}
for _, element in list do
	byId[element.id] = element
end

return {
	list = list,
	byId = byId,
}
