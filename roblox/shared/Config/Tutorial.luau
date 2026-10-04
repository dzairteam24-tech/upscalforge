--!strict
-- First-time guide: three steps with an arrow to the target, then a small reward.

export type Step = {
	event: string, -- progress event that completes the step
	text: string,
	target: string, -- "Breakable" | "Egg" | "Gate"
}

local steps: { Step } = {
	{ event = "Break", text = "Tap a coin pile to break it. Your creatures help you!", target = "Breakable" },
	{ event = "Hatch", text = "Collect coins, then walk to the egg and hatch a new creature", target = "Egg" },
	{ event = "Zone", text = "Keep collecting and unlock the next zone at a gate", target = "Gate" },
}

return {
	steps = steps,
	REWARD_GEMS = 25,
	REWARD_ITEM = "Elixir_Coins_2",
}
