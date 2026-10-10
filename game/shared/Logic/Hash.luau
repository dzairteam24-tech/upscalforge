--!strict
-- A fixed shuffle of whole numbers into [0, 1): the same everywhere, so things that follow the clock (the
-- weather, the shop's stock) are the same in every server.

local Hash = {}

function Hash.unit(...: number): number
	local h = 2166136261
	for _, n in { ... } do
		h = (h * 16777619 + (n // 1) % 4294967296 + 97) % 4294967296
		h = (h * 2654435761) % 4294967296
	end
	return (h // 256) / 16777216
end

return Hash
