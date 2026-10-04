--!strict
-- Short number formatting for the UI: 1.5K, 20M, 3.1B, then e-notation for very large numbers.

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local Format = {}

function Format.abbrev(value: number): string
	if value ~= value then
		return "0"
	end
	local negative = value < 0
	local n = math.abs(value)
	local text: string
	if n < 1000 then
		text = tostring(math.floor(n))
	else
		local tier = math.floor(math.log10(n) / 3)
		if tier <= #SUFFIXES then
			local scaled = n / 10 ^ (tier * 3)
			local digits = if scaled < 10 then 2 elseif scaled < 100 then 1 else 0
			local factor = 10 ^ digits
			scaled = math.floor(scaled * factor) / factor
			text = string.format("%." .. digits .. "f", scaled):gsub("%.?0+$", "") .. SUFFIXES[tier]
		else
			local exponent = math.floor(math.log10(n))
			local mantissa = math.floor(n / 10 ^ exponent * 100) / 100
			text = string.format("%.2fe%d", mantissa, exponent)
		end
	end
	return if negative then "-" .. text else text
end

-- Multipliers: "x1.5", "x3.38", then "x1.2K" for big ones.
function Format.mult(value: number): string
	if value < 1000 then
		return "x" .. string.format("%.2f", value):gsub("%.?0+$", "")
	end
	return "x" .. Format.abbrev(value)
end

function Format.time(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm %ds", m, s % 60)
end

function Format.chance(probability: number): string
	if probability >= 0.01 then
		return string.format("%g%%", math.floor(probability * 10000 + 0.5) / 100)
	end
	return "1 in " .. Format.abbrev(math.floor(1 / probability + 0.5))
end

return Format
