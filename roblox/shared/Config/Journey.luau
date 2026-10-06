--!strict
-- The Journey: Professor Cubo's long quest line through all of Green Valley. One step at a time; each step
-- is claimed in the Quests window (or by talking to the Professor in the town).
-- `event` is a progress event (see GameService.progress). "max" events count the best value reached
-- (zone number, combo), the others add up from when the step starts.

local Progression = require(script.Parent.Progression)

export type Step = {
	event: string,
	goal: number,
	text: string,
	say: string, -- what the Professor says
	reward: Progression.Reward,
	max: boolean?,
}

local steps: { Step } = {
	{ event = "Break", goal = 20, text = "Break 20 coin sources", say = "Welcome to Green Valley! Let's start easy: break some coin sources.", reward = { gems = 10 } },
	{ event = "Hatch", goal = 5, text = "Hatch 5 eggs", say = "Coins buy eggs, and eggs give friends. Hatch a few!", reward = { gems = 10, items = { { id = "Elixir_Coins_2", amount = 1 } } } },
	{ event = "Zone", goal = 2, max = true, text = "Open the Flower Field", say = "The Flower Field is just past the gate. Can you open it? Here's a board to get around faster!", reward = { gems = 20, ride = "Starter" } },
	{ event = "Combo", goal = 10, max = true, text = "Reach a 10 combo", say = "Tap fast and keep breaking: combos give more coins.", reward = { gems = 15 } },
	{ event = "Big", goal = 1, text = "Defeat a Big creature", say = "Sometimes a Big creature shows up in a zone. Beat one!", reward = { gems = 20, tickets = 1 } },
	{ event = "Restore", goal = 1, text = "Fully restore a zone", say = "Collecting coins in a zone restores it. Bring one back to 100%.", reward = { gems = 25 } },
	{ event = "Hatch", goal = 50, text = "Hatch 50 eggs", say = "A big team is a strong team. Keep hatching!", reward = { gems = 25, items = { { id = "Elixir_Luck_2", amount = 1 } } } },
	{ event = "Zone", goal = 3, max = true, text = "Reach the Forest", say = "The Forest is full of foxes and owls. Off you go!", reward = { gems = 30 } },
	{ event = "Golden", goal = 1, text = "Hatch a Golden creature", say = "Golden creatures are twice as strong. Find one!", reward = { gems = 30, tickets = 2 } },
	{ event = "Guardian", goal = 1, text = "Defeat a zone guardian", say = "Restored zones call their guardian. Show it who's boss.", reward = { gems = 40 } },
	{ event = "Fuse", goal = 1, text = "Fuse creatures at the Fusion booth", say = "Too many of the same? Fuse them into a better variant.", reward = { gems = 30 } },
	{ event = "Zone", goal = 4, max = true, text = "Reach the Beach", say = "Sun, sand and crabs. The Beach is waiting!", reward = { gems = 40 } },
	{ event = "Expedition", goal = 3, text = "Send 3 trips", say = "Creatures that don't fit in your team can go on trips.", reward = { gems = 40, items = { { id = "Key_Zone", amount = 1 } } } },
	{ event = "BigCatch", goal = 1, text = "Catch a Big creature", say = "Beat a Big and it might join you. Keep trying!", reward = { gems = 50, tickets = 2 } },
	{ event = "Zone", goal = 5, max = true, text = "Reach the Mushroom Cave", say = "The cave glows in the dark. Bring a strong team.", reward = { gems = 50 } },
	{ event = "Hatch", goal = 300, text = "Hatch 300 eggs", say = "Every egg is a chance at something rare.", reward = { gems = 60, items = { { id = "Elixir_Luck_2", amount = 2 } } } },
	{ event = "Boss", goal = 1, text = "Defeat a World Boss", say = "Every hour a boss lands in the town. Fight it with everyone!", reward = { gems = 80, tickets = 3 } },
	{ event = "Zone", goal = 6, max = true, text = "Reach the Desert", say = "The Desert hides a Sphinx. Careful in the heat!", reward = { gems = 70 } },
	{ event = "Trade", goal = 1, text = "Trade or sell at the Plaza", say = "Other players might have what you need. Try a trade!", reward = { gems = 60 } },
	{ event = "Restore", goal = 3, text = "Fully restore 3 zones", say = "The valley is coming back to life thanks to you.", reward = { gems = 90 } },
	{ event = "Zone", goal = 7, max = true, text = "Reach Snow Peak", say = "Snow Peak is cold, but the Yeti is warm-hearted. Mostly.", reward = { gems = 90 } },
	{ event = "Guardian", goal = 5, text = "Defeat 5 guardians", say = "Guardians may join you as Titans. Keep at it!", reward = { gems = 110, items = { { id = "Key_Golden", amount = 1 } } } },
	{ event = "Zone", goal = 8, max = true, text = "Reach the Volcano", say = "The Volcano is hot and full of imps. Go!", reward = { gems = 120 } },
	{ event = "Rift", goal = 100, text = "Break 100 sources in a Pixel Rift", say = "When a Pixel Rift opens, coins rain. Don't miss it!", reward = { gems = 120, tickets = 4 } },
	{ event = "Zone", goal = 9, max = true, text = "Reach the Frozen Lake", say = "Almost there! The Frozen Lake shines like glass.", reward = { gems = 150 } },
	{ event = "Hatch", goal = 2000, text = "Hatch 2,000 eggs", say = "Legends say the rarest creatures need patience.", reward = { gems = 180, items = { { id = "Key_Golden", amount = 1 } } } },
	{ event = "Zone", goal = 10, max = true, text = "Reach the Pixel Zone", say = "The Pixel Zone! The Legendary Egg is there.", reward = { gems = 220 } },
	{ event = "Boss", goal = 10, text = "Defeat 10 World Bosses", say = "The valley's bosses fear your team now.", reward = { gems = 250, tickets = 6 } },
	{ event = "Reload", goal = 1, max = true, text = "Reload once", say = "A Reload makes you stronger for good. Ready for a fresh start?", reward = { gems = 300 } },
	{ event = "Titan", goal = 1, text = "Get a Titan creature", say = "The last step: a Titan. Tame a guardian or hatch one. You can do it!", reward = { gems = 1000, title = "J_Hero", items = { { id = "Key_Golden", amount = 3 } } } },
}

return {
	steps = steps,
	NPC_NAME = "Professor Cubo",
}
