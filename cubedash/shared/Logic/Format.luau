--!strict
-- Numbers for the screen: 950, 12.4K, 3.4M, 1.2B...

local Format = {}

local UNITS = { "K", "M", "B", "T", "Qa", "Qi" }

function Format.short(n: number): string
	n = math.floor(n)
	if math.abs(n) < 1000 then
		return tostring(n)
	end
	local unit = 0
	local value = n
	while math.abs(value) >= 1000 and unit < #UNITS do
		value /= 1000
		unit += 1
	end
	local text = if math.abs(value) >= 100 then string.format("%d", math.floor(value)) else string.format("%.1f", math.floor(value * 10) / 10)
	text = string.gsub(text, "%.0$", "")
	return text .. UNITS[unit]
end

-- 12,450
function Format.comma(n: number): string
	local s = tostring(math.floor(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^(-?),", "%1"))
end

-- 4:05
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Format
