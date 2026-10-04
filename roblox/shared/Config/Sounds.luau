--!strict
-- Sound effects and music. Swap these for audio from the Creator Store ("rbxassetid://123...").
-- The defaults are sounds that ship with the Roblox client, so the game makes noise out of the box.
-- An empty id plays nothing.

export type Sound = { id: string, volume: number, speed: number? }

local effects: { [string]: Sound } = {
	Coin = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.25, speed = 1.6 },
	Jackpot = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, speed = 0.8 },
	Hatch = { id = "rbxasset://sounds/swoosh.wav", volume = 0.5 },
	Rare = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, speed = 0.6 },
	Success = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.4, speed = 1.2 },
	Error = { id = "rbxasset://sounds/button.wav", volume = 0.4, speed = 0.7 },
	Click = { id = "rbxasset://sounds/button.wav", volume = 0.3 },
	Spin = { id = "rbxasset://sounds/button.wav", volume = 0.2, speed = 1.4 },
}

return {
	effects = effects,
	MUSIC = "", -- background music id; empty = no music
	MUSIC_VOLUME = 0.3,
	COIN_SOUNDS_PER_SECOND = 6,
}
