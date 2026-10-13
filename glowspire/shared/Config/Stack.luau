--!strict
-- The stacking loop's numbers, in one place so feel can be tuned without touching code. Distances are in
-- hundredths of a stud, times in milliseconds: the simulation is whole numbers only, so the server replays a run
-- exactly as the phone played it.
--
-- Three feel presets (Week 0): the founder plays all three and says which feels best.

export type Preset = {
	name: string,
	start: number, -- the first block's width and depth
	span: number, -- how far a block slides either side of the tower before turning back
	speed: number, -- slide speed at layer 0 (units per second)...
	perLayer: number, -- ...plus this much per layer...
	maxSpeed: number, -- ...up to this
	perfectMs: number, -- a tap this close (in time) to dead center snaps exactly...
	shrinkEvery: number, -- ...a millisecond less every this many layers...
	perfectMinMs: number, -- ...down to this
	easyLayers: number, -- the first blocks: a much wider perfect window, so a first try can't fail
	easyFactor: number,
	regrowEvery: number, -- this many perfects in a row grow the block back...
	regrow: number, -- ...by this much (never past `start`)
}

local PRESETS: { [string]: Preset } = {
	A = { name = "A: steady", start = 700, span = 1100, speed = 700, perLayer = 6, maxSpeed = 1600, perfectMs = 70, shrinkEvery = 2, perfectMinMs = 24, easyLayers = 3, easyFactor = 4, regrowEvery = 5, regrow = 60 },
	B = { name = "B: fast", start = 700, span = 1100, speed = 950, perLayer = 8, maxSpeed = 1900, perfectMs = 55, shrinkEvery = 2, perfectMinMs = 18, easyLayers = 3, easyFactor = 4, regrowEvery = 5, regrow = 60 },
	C = { name = "C: gentle", start = 800, span = 1100, speed = 600, perLayer = 5, maxSpeed = 1300, perfectMs = 90, shrinkEvery = 2, perfectMinMs = 30, easyLayers = 3, easyFactor = 4, regrowEvery = 5, regrow = 80 },
}

return {
	PRESETS = PRESETS,
	DEFAULT = "A",
	-- A run of at least this many layers becomes a Spire; its tier comes from its layers (Dim..Celestial)
	TIERS = {
		{ name = "Dim", layers = 10 },
		{ name = "Glow", layers = 20 },
		{ name = "Bright", layers = 35 },
		{ name = "Radiant", layers = 55 },
		{ name = "Prismatic", layers = 80 },
		{ name = "Celestial", layers = 120 },
	},
	MAX_TAPS = 1500, -- (a run sent to the server can't be longer)
	MAX_TAP_MS = 120000, -- (nor can one block wait longer than this)
	LAYER_HEIGHT = 0.8, -- studs (drawing only)
}
