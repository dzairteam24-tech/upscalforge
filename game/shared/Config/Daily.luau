--!strict
-- Daily tasks: each day (UTC) everyone gets the same few tasks from this list (Logic/Daily). Done them all,
-- the player claims a free egg of the best tier they've hatched.

export type Task = { id: string, text: string, goal: number }

local LIST: { Task } = {
	{ id = "hatch", text = "Hatch %d eggs", goal = 3 },
	{ id = "buy", text = "Buy %d eggs at the Egg Shop", goal = 2 },
	{ id = "feed", text = "Feed your creatures at the trough", goal = 1 },
	{ id = "mother", text = "Feed the Mother Cube", goal = 1 },
	{ id = "wild", text = "Bring an egg home from the Wild", goal = 1 },
}

local byId: { [string]: Task } = {}
for _, task in LIST do
	byId[task.id] = task
end

return {
	LIST = LIST,
	byId = byId,
	PER_DAY = 3,
	REWARD_EGGS = 1,
}
