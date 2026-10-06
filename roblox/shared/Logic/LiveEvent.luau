--!strict
-- Live Event rules that don't need Roblox: who may start one, reading the chat command, and the bonus.

local Config = require(script.Parent.Parent.Config.LiveEvent)

export type Live = { stat: string, mult: number, ends: number } -- ends: unix time

export type Command = { stop: boolean, stat: string?, mult: number?, minutes: number? }

local LiveEvent = {}

function LiveEvent.isAdmin(userId: number, creatorId: number, isStudio: boolean): boolean
	if isStudio or (creatorId > 0 and userId == creatorId) then
		return true
	end
	return table.find(Config.ADMINS, userId) ~= nil
end

-- "/live luck 3 30" -> Luck x3 for 30 minutes. "/live stop" ends it. Returns nil and a reason when wrong.
function LiveEvent.parse(text: string): (Command?, string?)
	local words = string.split(string.lower(string.match(text, "^%s*(.-)%s*$") or ""), " ")
	local parts = {}
	for _, word in words do
		if word ~= "" then
			table.insert(parts, word)
		end
	end
	if parts[1] == "/live" then
		table.remove(parts, 1)
	end
	if parts[1] == "stop" then
		return { stop = true }, nil
	end
	local stat: string? = nil
	for name in Config.STATS do
		if string.lower(name) == parts[1] then
			stat = name
		end
	end
	if not stat then
		return nil, "Use: /live luck|coins|gem|pixel <mult> [minutes], or /live stop"
	end
	local mult = tonumber(parts[2])
	if not mult or mult <= 1 then
		return nil, "The multiplier must be more than 1"
	end
	local minutes = tonumber(parts[3]) or Config.DEFAULT_MINUTES
	if minutes <= 0 then
		return nil, "Minutes must be more than 0"
	end
	return {
		stop = false,
		stat = stat,
		mult = math.min(mult, Config.STATS[stat :: string]),
		minutes = math.min(minutes, Config.MAX_MINUTES),
	}, nil
end

-- The multiplier for a stat right now (1 when no event is running).
function LiveEvent.bonus(live: Live?, stat: string, now: number): number
	if live and live.stat == stat and now < live.ends then
		return live.mult
	end
	return 1
end

-- Checks data that came from another server before trusting it.
function LiveEvent.valid(value: any): boolean
	if type(value) ~= "table" or type(value.stat) ~= "string" then
		return false
	end
	local cap = Config.STATS[value.stat]
	return cap ~= nil and type(value.mult) == "number" and value.mult > 1 and value.mult <= cap and type(value.ends) == "number"
end

return LiveEvent
