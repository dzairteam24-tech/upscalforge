--!strict
-- Daily tasks (Config/Daily): which ones are on each day, the same in every server.

local DailyConfig = require(script.Parent.Parent.Config.Daily)
local Hash = require(script.Parent.Hash)

local Daily = {}

export type State = { day: number, progress: { [string]: number }, claimed: boolean }

function Daily.day(t: number): number
	return t // 86400
end

-- The tasks of a day (PER_DAY different ones)
function Daily.tasks(day: number): { string }
	local pool = {}
	for _, task in DailyConfig.LIST do
		table.insert(pool, task.id)
	end
	local picked = {}
	for i = 1, math.min(DailyConfig.PER_DAY, #pool) do
		local at = 1 + math.floor(Hash.unit(day, i, 77) * #pool)
		table.insert(picked, table.remove(pool, at) :: string)
	end
	return picked
end

-- Brings a player's state to day `day` (a new day starts fresh)
function Daily.today(state: State, day: number)
	if state.day ~= day then
		state.day = day
		state.progress = {}
		state.claimed = false
	end
end

-- Whether every task of the day is done
function Daily.done(state: State): boolean
	for _, id in Daily.tasks(state.day) do
		if (state.progress[id] or 0) < DailyConfig.byId[id].goal then
			return false
		end
	end
	return true
end

return Daily
