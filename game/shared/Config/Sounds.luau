--!strict
-- The game's sounds. These are sounds that ship with Roblox itself (rbxasset://), so they always play; for better
-- ones, upload sounds (or pick Roblox's own from the Creator Store) and paste their ids here as "rbxassetid://123".
-- `pitch` shifts one sound into another (a ping played higher is a coin), `volume` 0..1.

export type Sound = { id: string, pitch: number, volume: number }

local function s(id: string, pitch: number, volume: number): Sound
	return { id = id, pitch = pitch, volume = volume }
end

local PING = "rbxasset://sounds/electronicpingshort.wav"

return {
	Click = s("rbxasset://sounds/button.wav", 1.2, 0.35), -- any button
	Success = s(PING, 1.25, 0.4), -- a good message
	Error = s("rbxasset://sounds/button.wav", 0.6, 0.5), -- a refusal
	Rare = s(PING, 0.9, 0.6), -- a rare message
	Coins = s(PING, 1.7, 0.35), -- something bought
	Hatch = s(PING, 1, 0.8), -- an egg hatching (Reveal), with Chime after it
	Chime = s(PING, 1.5, 0.6),
	SetEgg = s("rbxasset://sounds/impact_water.mp3", 1.6, 0.5), -- an egg down on the grass
	Steal = s("rbxasset://sounds/unsheath.wav", 1.3, 0.6), -- an egg grabbed from a nest
	Home = s(PING, 1.2, 0.7), -- an egg brought home
	Hit = s("rbxasset://sounds/swordslash.wav", 1, 0.7), -- a bat hit
	Swing = s("rbxasset://sounds/swordlunge.wav", 1.2, 0.5), -- a bat swung
	Heart = s("rbxasset://sounds/button.wav", 0.35, 0.7), -- a heartbeat while a guardian chases the player
	Escape = s(PING, 1.4, 0.7), -- got away from a guardian
	Knock = s("rbxasset://sounds/swordslash.wav", 0.7, 1), -- the hit that knocks something loose
}
