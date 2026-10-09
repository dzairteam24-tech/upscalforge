--!strict
-- First-time guide: three steps with an arrow to the target, then a small reward.

export type Step = {
	event: string, -- progress event that completes the step
	text: string,
	target: string, -- "Breakable" | "Egg" | "Gate"
}

local steps: { Step } = {
	{ event = "Hatch", text = "Walk to the Egg Garden and hatch a creature: your team earns coins for you", target = "Egg" },
	{ event = "Zone", text = "Save up and open the next egg's cage in the garden", target = "Gate" },
}

return {
	steps = steps,
	REWARD_GEMS = 25,
	REWARD_ITEM = "Elixir_Coins_2",
}
